import Foundation
@preconcurrency import DiskArbitration
import IOKit
import IOKit.storage

/// Errors surfaced by drive operations.
public enum DriveError: LocalizedError, Sendable {
    case mountFailed(String)
    case unmountFailed(String)
    case ejectFailed(String)
    case driveNotFound(String)
    case sessionUnavailable

    public var errorDescription: String? {
        switch self {
        case .mountFailed(let msg): return "Mount failed: \(msg)"
        case .unmountFailed(let msg): return "Unmount failed: \(msg)"
        case .ejectFailed(let msg): return "Eject failed: \(msg)"
        case .driveNotFound(let id): return "Drive not found: \(id)"
        case .sessionUnavailable: return "DiskArbitration session unavailable"
        }
    }
}

/// Live, observable list of drives the OS knows about, plus mount/unmount/eject.
///
/// All callbacks fire on the main queue and `drives` is mutated only on the main thread,
/// so SwiftUI can observe it directly via `@Published`.
@MainActor
public final class DriveManager: ObservableObject {

    @Published public private(set) var drives: [Drive] = []
    @Published public private(set) var lastError: String?
    @Published public private(set) var driverStatus: NTFSDriverStatus = .unknown

    private var session: DASession?
    private let detector = NTFSDetector()
    private let driverManager = NTFSDriverManager()

    public init() {}

    /// Detach the DiskArbitration session from its dispatch queue. Call this if you
    /// intend to drop a long-lived `DriveManager` before app termination.
    public func stop() {
        if let session {
            DASessionSetDispatchQueue(session, nil)
        }
        session = nil
    }

    // MARK: - Lifecycle

    public func start() {
        guard session == nil else { return }
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            lastError = "Failed to create DiskArbitration session"
            return
        }
        self.session = session

        let context = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskAppearedCallback(session, nil, { disk, context in
            guard let context else { return }
            let manager = Unmanaged<DriveManager>.fromOpaque(context).takeUnretainedValue()
            let drive = DriveManager.makeDrive(from: disk)
            DispatchQueue.main.async {
                manager.upsert(drive)
            }
        }, context)

        DARegisterDiskDisappearedCallback(session, nil, { disk, context in
            guard let context else { return }
            let manager = Unmanaged<DriveManager>.fromOpaque(context).takeUnretainedValue()
            guard let bsd = DADiskGetBSDName(disk) else { return }
            let bsdName = String(cString: bsd)
            DispatchQueue.main.async {
                manager.remove(bsdName: bsdName)
            }
        }, context)

        DARegisterDiskDescriptionChangedCallback(session, nil, nil, { disk, _, context in
            guard let context else { return }
            let manager = Unmanaged<DriveManager>.fromOpaque(context).takeUnretainedValue()
            let drive = DriveManager.makeDrive(from: disk)
            DispatchQueue.main.async {
                manager.upsert(drive)
            }
        }, context)

        DASessionSetDispatchQueue(session, DispatchQueue.main)
    }

    public func refresh() {
        // DiskArbitration doesn't expose an "iterate all disks" API, so we rebuild the
        // list by enumerating BSD nodes via IOKit and asking DA for each one.
        guard let session else { return }

        var rebuilt: [Drive] = []
        for bsdName in Self.allDiskBSDNames() {
            if let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) {
                rebuilt.append(Self.makeDrive(from: disk))
            }
        }
        drives = rebuilt
            .filter(DriveVisibilityFilter.isListed)
            .sorted { $0.bsdName < $1.bsdName }
    }

    // MARK: - Mutations

    private func upsert(_ drive: Drive) {
        guard DriveVisibilityFilter.isListed(drive) else {
            remove(bsdName: drive.bsdName)
            return
        }
        if let idx = drives.firstIndex(where: { $0.bsdName == drive.bsdName }) {
            drives[idx] = drive
        } else {
            drives.append(drive)
        }
        drives.sort { $0.bsdName < $1.bsdName }
    }

    private func remove(bsdName: String) {
        drives.removeAll { $0.bsdName == bsdName }
    }

    // MARK: - Actions

    public func mount(_ drive: Drive) async throws {
        guard let session else { throw DriveError.sessionUnavailable }
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, drive.bsdName) else {
            throw DriveError.driveNotFound(drive.bsdName)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let box = ContinuationBox(cont: cont)
            let ctx = Unmanaged.passRetained(box).toOpaque()
            DADiskMount(disk, nil, DADiskMountOptions(kDADiskMountOptionDefault), { _, dissenter, ctx in
                guard let ctx else { return }
                let box = Unmanaged<ContinuationBox>.fromOpaque(ctx).takeRetainedValue()
                if let dissenter {
                    let status = DADissenterGetStatus(dissenter)
                    let msg = (DADissenterGetStatusString(dissenter) as String?)
                        ?? "DADissenter status \(String(format: "0x%08X", status))"
                    box.cont.resume(throwing: DriveError.mountFailed(msg))
                } else {
                    box.cont.resume()
                }
            }, ctx)
        }
        refresh()
    }

    public func unmount(_ drive: Drive, force: Bool = false) async throws {
        guard let session else { throw DriveError.sessionUnavailable }
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, drive.bsdName) else {
            throw DriveError.driveNotFound(drive.bsdName)
        }
        let opts = DADiskUnmountOptions(force ? kDADiskUnmountOptionForce : kDADiskUnmountOptionDefault)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let box = ContinuationBox(cont: cont)
            let ctx = Unmanaged.passRetained(box).toOpaque()
            DADiskUnmount(disk, opts, { _, dissenter, ctx in
                guard let ctx else { return }
                let box = Unmanaged<ContinuationBox>.fromOpaque(ctx).takeRetainedValue()
                if let dissenter {
                    let status = DADissenterGetStatus(dissenter)
                    let msg = (DADissenterGetStatusString(dissenter) as String?)
                        ?? "DADissenter status \(String(format: "0x%08X", status))"
                    box.cont.resume(throwing: DriveError.unmountFailed(msg))
                } else {
                    box.cont.resume()
                }
            }, ctx)
        }
        await TransferPowerAssertion.shared.mountEnded()
        refresh()
    }

    public func eject(_ drive: Drive) async throws {
        guard let session else { throw DriveError.sessionUnavailable }
        guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, drive.bsdName) else {
            throw DriveError.driveNotFound(drive.bsdName)
        }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let box = ContinuationBox(cont: cont)
            let ctx = Unmanaged.passRetained(box).toOpaque()
            DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault), { _, dissenter, ctx in
                guard let ctx else { return }
                let box = Unmanaged<ContinuationBox>.fromOpaque(ctx).takeRetainedValue()
                if let dissenter {
                    let status = DADissenterGetStatus(dissenter)
                    let msg = (DADissenterGetStatusString(dissenter) as String?)
                        ?? "DADissenter status \(String(format: "0x%08X", status))"
                    box.cont.resume(throwing: DriveError.ejectFailed(msg))
                } else {
                    box.cont.resume()
                }
            }, ctx)
        }
        await TransferPowerAssertion.shared.mountEnded()
        refresh()
    }

    /// Probe a drive's NTFS status using both the reported FS string and (if necessary) the boot sector.
    public func ntfsStatus(_ drive: Drive) -> NTFSDetectionResult {
        detector.detect(drive)
    }

    // MARK: - NTFS Driver (ntfs-3g) integration

    /// Re-detect the NTFS driver stack (macFUSE + ntfs-3g) and update `driverStatus`.
    public func refreshDriverStatus() async {
        let status = await driverManager.detectStatus()
        self.driverStatus = status
    }

    /// Mount an NTFS volume read/write through ntfs-3g. Pops a system password prompt
    /// the first time it needs root.
    public func mountReadWrite(_ drive: Drive) async throws -> URL {
        guard isLikelyNTFS(drive) else { throw NTFSDriverError.driveNotNTFS }
        let mountPoint = try await driverManager.mount(drive: drive, options: .fast)
        await TransferPowerAssertion.shared.mountBegan(at: mountPoint.path)
        // Give DA a beat to notice the mount, then refresh.
        try? await Task.sleep(nanoseconds: 300_000_000)
        refresh()
        return mountPoint
    }

    /// Mount an NTFS volume read-only via ntfs-3g (still useful: macOS's built-in
    /// read-only NTFS support is sometimes flaky, ntfs-3g is more reliable).
    public func mountReadOnlyViaDriver(_ drive: Drive) async throws -> URL {
        guard isLikelyNTFS(drive) else { throw NTFSDriverError.driveNotNTFS }
        let mountPoint = try await driverManager.mount(drive: drive, options: .readOnly)
        await TransferPowerAssertion.shared.mountBegan(at: mountPoint.path)
        try? await Task.sleep(nanoseconds: 300_000_000)
        refresh()
        return mountPoint
    }

    /// Treat a drive as NTFS if either the OS already labels it so or the boot-sector probe matches.
    public func isLikelyNTFS(_ drive: Drive) -> Bool {
        if drive.isNTFS { return true }
        if case .confirmedFromBootSector = ntfsStatus(drive) { return true }
        return false
    }

    // MARK: - DiskArbitration → Drive mapping

    static func makeDrive(from disk: DADisk) -> Drive {
        let bsdName: String = {
            if let p = DADiskGetBSDName(disk) { return String(cString: p) }
            return "unknown"
        }()
        let descCF = DADiskCopyDescription(disk)
        let desc = (descCF as? [String: Any]) ?? [:]

        let isWholeDisk = (desc[kDADiskDescriptionMediaWholeKey as String] as? Bool) ?? false
        let mediaName = desc[kDADiskDescriptionMediaNameKey as String] as? String
        let volumeName = desc[kDADiskDescriptionVolumeNameKey as String] as? String
        let mediaContent = desc[kDADiskDescriptionMediaContentKey as String] as? String
        let fsRaw = desc[kDADiskDescriptionVolumeKindKey as String] as? String
        let mountURL = desc[kDADiskDescriptionVolumePathKey as String] as? URL

        let totalSize = (desc[kDADiskDescriptionMediaSizeKey as String] as? NSNumber)?.uint64Value ?? 0
        let blockSize = (desc[kDADiskDescriptionMediaBlockSizeKey as String] as? NSNumber)?.uint32Value ?? 512

        let isRemovable = (desc[kDADiskDescriptionMediaRemovableKey as String] as? Bool) ?? false
        let isEjectable = (desc[kDADiskDescriptionMediaEjectableKey as String] as? Bool) ?? false
        let isInternal = (desc[kDADiskDescriptionDeviceInternalKey as String] as? Bool) ?? false
        let isWritable = (desc[kDADiskDescriptionMediaWritableKey as String] as? Bool) ?? true

        let vendor = (desc[kDADiskDescriptionDeviceVendorKey as String] as? String)?
            .trimmingCharacters(in: .whitespaces)
        let model = (desc[kDADiskDescriptionDeviceModelKey as String] as? String)?
            .trimmingCharacters(in: .whitespaces)

        let busName = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String
        let bus = mapBus(busName, isInternal: isInternal)

        // Parent BSD name: derive from naming convention `diskNsM`.
        var parent: String? = nil
        if !isWholeDisk, let range = bsdName.range(of: #"^disk\d+"#, options: .regularExpression) {
            parent = String(bsdName[range])
        }

        let filesystem = Filesystem.fromIdentifier(fsRaw)

        return Drive(
            bsdName: bsdName,
            parentBSDName: parent,
            isWholeDisk: isWholeDisk,
            volumeName: volumeName,
            mediaName: mediaName,
            vendor: vendor,
            model: model,
            filesystem: filesystem,
            mountPoint: mountURL,
            totalSize: totalSize,
            blockSize: blockSize,
            isRemovable: isRemovable,
            isEjectable: isEjectable,
            isInternal: isInternal,
            isWritable: isWritable,
            bus: bus,
            mediaContent: mediaContent
        )
    }

    private static func mapBus(_ name: String?, isInternal: Bool) -> DriveBus {
        guard let name else { return isInternal ? .internalBus : .unknown }
        switch name.uppercased() {
        case "USB": return .usb
        case "THUNDERBOLT": return .thunderbolt
        case "SATA", "ATA", "ATAPI": return .sata
        case "NVME", "NVMEXPRESS", "PCI-EXPRESS", "APPLE FABRIC": return .nvme
        case "SD", "SECURE DIGITAL": return .sd
        case "FIREWIRE", "IEEE 1394": return .firewire
        case "VIRTUAL INTERFACE", "DISK IMAGE": return .virtual
        default:
            return isInternal ? .internalBus : .unknown
        }
    }

    // MARK: - IOKit enumeration

    /// Walk every IOMedia object in the IORegistry and collect BSD names like `disk0`,
    /// `disk0s1`, etc. This is how Disk Utility / `diskutil list` get their list.
    static func allDiskBSDNames() -> [String] {
        var bsdNames: [String] = []
        let matching = IOServiceMatching(kIOMediaClass)
        var iter: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter)
        guard kr == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }

        while case let svc = IOIteratorNext(iter), svc != 0 {
            defer { IOObjectRelease(svc) }
            if let name = IORegistryEntryCreateCFProperty(svc, kIOBSDNameKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String {
                bsdNames.append(name)
            }
        }
        return bsdNames
    }
}

/// Heap box used to bridge a Swift continuation through a C-style DiskArbitration callback.
private final class ContinuationBox: @unchecked Sendable {
    let cont: CheckedContinuation<Void, Error>
    init(cont: CheckedContinuation<Void, Error>) { self.cont = cont }
}

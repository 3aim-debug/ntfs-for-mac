import Foundation

/// Connection bus / transport reported by IOKit.
public enum DriveBus: String, Sendable, CaseIterable {
    case usb = "USB"
    case thunderbolt = "Thunderbolt"
    case sata = "SATA"
    case nvme = "NVMe"
    case sd = "SD"
    case firewire = "FireWire"
    case virtual = "Virtual"
    case internalBus = "Internal"
    case unknown = "Unknown"
}

/// A normalized, identity-stable representation of a disk or volume the OS knows about.
///
/// Both whole disks (e.g. `disk4`) and individual volumes/partitions (e.g. `disk4s1`) are
/// modeled as `Drive` values; whole disks have `isWholeDisk == true` and no `volumeName` /
/// `mountPoint`, while volumes carry their parent's identifier in `parentBSDName`.
public struct Drive: Identifiable, Hashable, Sendable {
    public var id: String { bsdName }

    public let bsdName: String
    public let parentBSDName: String?
    public let isWholeDisk: Bool

    public let volumeName: String?
    public let mediaName: String?
    public let vendor: String?
    public let model: String?

    public let filesystem: Filesystem
    public let mountPoint: URL?
    public let totalSize: UInt64
    public let blockSize: UInt32

    public let isRemovable: Bool
    public let isEjectable: Bool
    public let isInternal: Bool
    public let isWritable: Bool
    public let bus: DriveBus

    /// Partition/content type from DiskArbitration (e.g. `Microsoft Basic Data`, `Apple_APFS_Container`).
    public let mediaContent: String?

    /// APFS snapshot BSD names look like `disk3s1s1`.
    public var isAPFSSnapshot: Bool {
        bsdName.range(of: #"^disk\d+s\d+s\d+"#, options: .regularExpression) != nil
    }

    public init(
        bsdName: String,
        parentBSDName: String? = nil,
        isWholeDisk: Bool = false,
        volumeName: String? = nil,
        mediaName: String? = nil,
        vendor: String? = nil,
        model: String? = nil,
        filesystem: Filesystem = .unknown,
        mountPoint: URL? = nil,
        totalSize: UInt64 = 0,
        blockSize: UInt32 = 512,
        isRemovable: Bool = false,
        isEjectable: Bool = false,
        isInternal: Bool = false,
        isWritable: Bool = true,
        bus: DriveBus = .unknown,
        mediaContent: String? = nil
    ) {
        self.bsdName = bsdName
        self.parentBSDName = parentBSDName
        self.isWholeDisk = isWholeDisk
        self.volumeName = volumeName
        self.mediaName = mediaName
        self.vendor = vendor
        self.model = model
        self.filesystem = filesystem
        self.mountPoint = mountPoint
        self.totalSize = totalSize
        self.blockSize = blockSize
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isInternal = isInternal
        self.isWritable = isWritable
        self.bus = bus
        self.mediaContent = mediaContent
    }

    public var isMounted: Bool { mountPoint != nil }
    public var isNTFS: Bool { filesystem.kind == .ntfs }
    public var devicePath: String { "/dev/\(bsdName)" }
    public var rawDevicePath: String { "/dev/r\(bsdName)" }

    public var displayName: String {
        volumeName ?? mediaName ?? bsdName
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}

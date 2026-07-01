import Foundation

/// Detects NTFS volumes by reading the boot sector directly when the OS hasn't already
/// identified the filesystem. This is the typical scenario on stock macOS, which won't
/// always set a filesystem string for NTFS partitions if no NTFS driver is present.
///
/// Reading raw devices (`/dev/diskNsM`) requires either root privileges or that the user
/// has been granted "Full Disk Access" + the device's BSD node be readable by the user.
/// We fail soft: if we can't open the device, we just return `.indeterminate`.
public enum NTFSDetectionResult: Sendable, Equatable {
    /// Confirmed NTFS based on filesystem identifier reported by the OS.
    case confirmedFromIdentifier
    /// Confirmed NTFS based on the boot sector OEM ID + signature.
    case confirmedFromBootSector
    /// Definitely not NTFS (some other known filesystem detected).
    case notNTFS
    /// Couldn't determine (e.g. permission denied, unreadable device, whole-disk node).
    case indeterminate(reason: String)
}

public struct NTFSDetector: Sendable {

    public init() {}

    /// Quick, non-IO check: is the filesystem already reported as NTFS?
    public func isReportedAsNTFS(_ drive: Drive) -> Bool {
        drive.filesystem.kind == .ntfs
    }

    /// Full check: trusts the reported identifier first, then falls back to a boot-sector
    /// probe on the raw character device.
    public func detect(_ drive: Drive) -> NTFSDetectionResult {
        if drive.filesystem.kind == .ntfs {
            return .confirmedFromIdentifier
        }
        // Don't probe whole disks — they don't have a filesystem boot sector at offset 0
        // in any meaningful sense for partitioned media.
        if drive.isWholeDisk {
            return .indeterminate(reason: "whole-disk device; no partition boot sector to probe")
        }
        // If the OS already identified a non-NTFS filesystem, trust it.
        switch drive.filesystem.kind {
        case .apfs, .hfs, .exfat, .fat32, .ext, .udf, .iso9660:
            return .notNTFS
        case .ntfs, .unknown, .other:
            break
        }
        return probeBootSector(rawDevicePath: drive.rawDevicePath)
    }

    /// Read the first 512 bytes of the device and check for the NTFS signature.
    ///
    /// NTFS boot sector layout (relevant fields):
    ///   - bytes 0x00..0x02: jump instruction (0xEB 0x52 0x90 typically)
    ///   - bytes 0x03..0x0A: 8-byte OEM identifier — "NTFS    " (with 4 trailing spaces) for NTFS
    ///   - bytes 0x1FE..0x200: 0x55 0xAA boot sector signature
    private func probeBootSector(rawDevicePath: String) -> NTFSDetectionResult {
        let fd = open(rawDevicePath, O_RDONLY)
        if fd < 0 {
            let err = String(cString: strerror(errno))
            return .indeterminate(reason: "open(\(rawDevicePath)) failed: \(err)")
        }
        defer { close(fd) }

        var buffer = [UInt8](repeating: 0, count: 512)
        let bytesRead = buffer.withUnsafeMutableBytes { ptr -> Int in
            return read(fd, ptr.baseAddress, 512)
        }
        if bytesRead < 512 {
            let err = bytesRead < 0 ? String(cString: strerror(errno)) : "short read"
            return .indeterminate(reason: "read failed: \(err)")
        }

        // Boot signature 0x55 0xAA at offset 510.
        guard buffer[510] == 0x55, buffer[511] == 0xAA else {
            return .notNTFS
        }
        // OEM ID at offset 3, 8 bytes. NTFS = "NTFS    "
        let oemBytes = Array(buffer[3..<11])
        let oemString = String(bytes: oemBytes, encoding: .ascii) ?? ""
        if oemString == "NTFS    " {
            return .confirmedFromBootSector
        }
        return .notNTFS
    }
}

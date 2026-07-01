import Foundation

/// Known filesystems we want to special-case in the UI; everything else falls through `other`.
public struct Filesystem: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case apfs
        case hfs
        case ntfs
        case exfat
        case fat32
        case ext
        case udf
        case iso9660
        case unknown
        case other
    }

    public let kind: Kind
    /// Raw identifier as DiskArbitration / IOKit reported it (e.g. "ntfs", "apfs", "msdos").
    public let rawIdentifier: String?

    public init(kind: Kind, rawIdentifier: String? = nil) {
        self.kind = kind
        self.rawIdentifier = rawIdentifier
    }

    public static let unknown = Filesystem(kind: .unknown, rawIdentifier: nil)

    /// Map a DiskArbitration/IOKit filesystem identifier to a normalized `Kind`.
    public static func fromIdentifier(_ identifier: String?) -> Filesystem {
        guard let identifier, !identifier.isEmpty else {
            return .unknown
        }
        let normalized = identifier.lowercased()
        let kind: Kind
        switch normalized {
        case "apfs":
            kind = .apfs
        case "hfs", "hfs+", "hfsj", "hfsx", "case-sensitive hfs+":
            kind = .hfs
        case "ntfs":
            kind = .ntfs
        case "exfat":
            kind = .exfat
        case "msdos", "fat", "fat32", "vfat":
            kind = .fat32
        case "ext", "ext2", "ext3", "ext4":
            kind = .ext
        case "udf":
            kind = .udf
        case "cd9660", "iso9660":
            kind = .iso9660
        default:
            kind = .other
        }
        return Filesystem(kind: kind, rawIdentifier: identifier)
    }

    public var displayName: String {
        switch kind {
        case .apfs: return "APFS"
        case .hfs: return "HFS+"
        case .ntfs: return "NTFS"
        case .exfat: return "exFAT"
        case .fat32: return "FAT32"
        case .ext: return "ext"
        case .udf: return "UDF"
        case .iso9660: return "ISO 9660"
        case .unknown: return "Unknown"
        case .other: return rawIdentifier?.uppercased() ?? "Other"
        }
    }
}

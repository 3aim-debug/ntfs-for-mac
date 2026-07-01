import Foundation

/// Decides which disks appear in the sidebar — hides containers, recovery, snapshots, and other system junk.
enum DriveVisibilityFilter {

    /// User-facing volumes only (external data drives, NTFS, etc.).
    static func isListed(_ drive: Drive) -> Bool {
        if drive.isWholeDisk { return false }
        if drive.isAPFSSnapshot { return false }
        if isSystemVolumeName(drive) { return false }
        if isSystemMediaContent(drive.mediaContent) { return false }
        if isVirtualWithoutUserData(drive) { return false }
        if isTinyPlaceholder(drive) { return false }

        // Internal disks: only show NTFS (e.g. Boot Camp) — skip APFS/HFS system volumes.
        if drive.isInternal && !drive.isRemovable {
            return drive.isNTFS || isLikelyNTFSBootCamp(drive)
        }

        return hasRecognizedUserVolume(drive)
    }

    // MARK: - Rules

    private static func isSystemVolumeName(_ drive: Drive) -> Bool {
        let names = [drive.volumeName, drive.mediaName, drive.displayName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for name in names {
            let lower = name.lowercased()
            if systemVolumeNames.contains(lower) { return true }
            if lower.hasPrefix("com.apple.") { return true }
            if lower.hasSuffix(".hidden") { return true }
            if lower.contains("snapshot") { return true }
            if lower.contains("recovery container") { return true }
            if lower.contains("container disk") && !lower.contains("data") { return true }
        }
        return false
    }

    private static let systemVolumeNames: Set<String> = [
        "preboot",
        "recovery",
        "vm",
        "efi",
        "microsoft reserved",
        "no volume",
    ]

    private static func isSystemMediaContent(_ content: String?) -> Bool {
        guard let content, !content.isEmpty else { return false }
        let upper = content.uppercased()

        let blockedPrefixes = [
            "APPLE_APFS_ISC",
            "APPLE_APFS_RECOVERY",
            "APPLE_APFS_CONTAINER",
            "APFS_CONTAINER",
            "GUID_PARTITION",
            "FDISK_PARTITION",
            "APPLE_PARTITION",
            "EFI",
        ]
        for prefix in blockedPrefixes {
            if upper.hasPrefix(prefix.uppercased()) { return true }
        }

        if upper.contains("RECOVERY") && upper.contains("CONTAINER") { return true }
        if upper == "MICROSOFT RESERVED" { return true }

        return false
    }

    private static func isVirtualWithoutUserData(_ drive: Drive) -> Bool {
        guard drive.bus == .virtual else { return false }
        if drive.isNTFS || drive.filesystem.kind == .exfat || drive.filesystem.kind == .fat32 {
            return false
        }
        // iSCSI / virtual targets with no user filesystem.
        return true
    }

    private static func isTinyPlaceholder(_ drive: Drive) -> Bool {
        let minSize: UInt64 = 64 * 1024 * 1024 // 64 MiB
        guard drive.totalSize < minSize else { return false }
        guard drive.volumeName?.isEmpty ?? true else { return false }
        switch drive.filesystem.kind {
        case .ntfs, .exfat, .fat32, .hfs, .apfs, .ext:
            return false
        case .unknown, .other, .udf, .iso9660:
            return true
        }
    }

    private static func isLikelyNTFSBootCamp(_ drive: Drive) -> Bool {
        guard let content = drive.mediaContent?.uppercased() else { return false }
        return content.contains("MICROSOFT") && content.contains("DATA")
    }

    private static func hasRecognizedUserVolume(_ drive: Drive) -> Bool {
        switch drive.filesystem.kind {
        case .ntfs, .exfat, .fat32, .hfs, .apfs, .ext, .udf, .iso9660:
            return true
        case .unknown, .other:
            if drive.volumeName != nil && !(drive.volumeName?.isEmpty ?? true) {
                return true
            }
            if let content = drive.mediaContent?.uppercased(),
               content.contains("MICROSOFT BASIC DATA") || content.contains("LINUX") {
                return true
            }
            return false
        }
    }
}

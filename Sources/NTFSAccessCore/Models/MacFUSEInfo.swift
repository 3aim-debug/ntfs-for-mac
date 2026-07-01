import Foundation

/// Host macOS version helpers used for driver compatibility and install guidance.
public enum HostOSInfo: Sendable {
    public static var majorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// macOS 26 Tahoe and later use macFUSE's FSKit backend (no kext).
    public static var prefersFSKitBackend: Bool { majorVersion >= 26 }

    public static var isMacOS27OrLater: Bool { majorVersion >= 27 }

    public static var marketingName: String {
        switch majorVersion {
        case 27...: return "macOS \(majorVersion)"
        case 26: return "macOS 26"
        case 15: return "macOS 15 Sequoia"
        case 14: return "macOS 14 Sonoma"
        default: return "macOS \(majorVersion)"
        }
    }
}

/// macFUSE release metadata used for detection, compatibility checks, and install guidance.
public enum MacFUSEInfo: Sendable {
    /// Latest stable release (Homebrew `macfuse` cask).
    public static let recommendedStableVersion = "5.2.0"
    /// Latest developer pre-release (Homebrew `macfuse@dev` cask). Required for macOS 27.
    public static let recommendedDevVersion = "5.3.2"
    /// First macFUSE release with initial macOS 27 support.
    public static let minimumMacOS27Version = "5.3.1"
    /// Oldest macFUSE generation we consider usable on legacy macOS.
    public static let minimumLegacyVersion = "5.0.0"
    /// First macFUSE release with a usable FSKit backend on macOS 26.
    public static let minimumFSKitVersion = "5.1.0"

    public static let bundlePath = "/Library/Filesystems/macfuse.fs"
    public static let fuseConfigPath = "/etc/fuse.conf"
    public static let downloadURL = "https://github.com/macfuse/macfuse/releases"
    public static let homepageURL = "https://macfuse.github.io/"

    public static let brewInstallStable = "brew install --cask macfuse"
    public static let brewUpgradeStable = "brew upgrade --cask macfuse"
    public static let brewUninstallStable = "brew uninstall --cask macfuse"
    public static let brewInstallDev = "brew install --cask macfuse@dev"
    public static let brewUpgradeDev = "brew upgrade --cask macfuse@dev"

    public static let brewTrustNTFS3GFormula = "brew trust --formula gromgit/fuse/ntfs-3g-mac"

    public static var prefersFSKitBackend: Bool { HostOSInfo.prefersFSKitBackend }

    /// Version we recommend for the machine running this app.
    public static var recommendedVersionForHost: String {
        if HostOSInfo.isMacOS27OrLater { return recommendedDevVersion }
        if HostOSInfo.prefersFSKitBackend { return recommendedStableVersion }
        return recommendedStableVersion
    }

    /// Oldest macFUSE we allow mounts on for the current host OS.
    public static var minimumSupportedVersionForHost: String {
        if HostOSInfo.isMacOS27OrLater { return minimumMacOS27Version }
        if HostOSInfo.prefersFSKitBackend { return minimumFSKitVersion }
        return minimumLegacyVersion
    }

    /// Fresh install commands for the current host.
    public static var brewInstallCommandsForHost: [String] {
        if HostOSInfo.isMacOS27OrLater { return [brewInstallDev] }
        return [brewInstallStable]
    }

    /// Upgrade/migrate commands. On macOS 27, stable `macfuse` and `macfuse@dev` conflict in Homebrew —
    /// you must uninstall stable before installing the dev cask.
    public static var brewUpgradeCommandsForHost: [String] {
        if HostOSInfo.isMacOS27OrLater {
            return [brewUninstallStable, brewInstallDev]
        }
        return [brewUpgradeStable]
    }

    /// Install command appropriate for the current host (dev cask on macOS 27).
    public static var brewInstallForHost: String { brewInstallCommandsForHost[0] }

    /// Upgrade command appropriate for the current host (legacy single-line; prefer `brewUpgradeCommandsForHost`).
    public static var brewUpgradeForHost: String {
        brewUpgradeCommandsForHost.joined(separator: " && ")
    }

    public static var recommendedVersionLabel: String {
        if HostOSInfo.isMacOS27OrLater {
            return "\(recommendedDevVersion) (recommended on \(HostOSInfo.marketingName))"
        }
        if HostOSInfo.prefersFSKitBackend {
            return "\(recommendedStableVersion) (stable) · \(recommendedDevVersion) (dev, optional)"
        }
        return recommendedStableVersion
    }

    public static func isVersionSupported(_ version: String) -> Bool {
        isAtLeast(version, minimum: minimumSupportedVersionForHost)
    }

    public static func updateRecommended(installed: String) -> Bool {
        guard let cmp = compare(installed, recommendedVersionForHost) else { return false }
        return cmp == .orderedAscending
    }

    /// Compare dotted version strings (`5.2.0` vs `5.3.2`). Returns nil if either side can't be parsed.
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        let left = parse(lhs)
        let right = parse(rhs)
        guard let left, let right else { return nil }
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }

    public static func isAtLeast(_ version: String, minimum: String) -> Bool {
        guard let result = compare(version, minimum) else { return false }
        return result != .orderedAscending
    }

    private static func parse(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let n = Int(part) else { return nil }
            numbers.append(n)
        }
        return numbers
    }

    /// True when `/etc/fuse.conf` exists and enables `user_allow_other` (required for `allow_other`).
    public static var isAllowOtherConfigured: Bool {
        guard let data = FileManager.default.contents(atPath: fuseConfigPath),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return text.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#") && trimmed.hasPrefix("user_allow_other")
        }
    }
}

private func == (lhs: [Int], rhs: [Int]) -> Bool {
    let maxCount = max(lhs.count, rhs.count)
    for i in 0..<maxCount {
        let l = i < lhs.count ? lhs[i] : 0
        let r = i < rhs.count ? rhs[i] : 0
        if l != r { return false }
    }
    return true
}

private func < (lhs: [Int], rhs: [Int]) -> Bool {
    let maxCount = max(lhs.count, rhs.count)
    for i in 0..<maxCount {
        let l = i < lhs.count ? lhs[i] : 0
        let r = i < rhs.count ? rhs[i] : 0
        if l < r { return true }
        if l > r { return false }
    }
    return false
}

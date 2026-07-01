import Foundation

/// Builds ntfs-3g / FUSE `-o` option lists tuned for throughput on macOS.
public enum NTFSMountTuning {

    public enum Profile: Sendable {
        case balanced
        /// Default read/write profile — async I/O, 1 MiB chunks.
        case fast
        /// Alias of `.fast`.
        case maximumSpeed
        /// Stable throughput for long copies.
        case sustainedThroughput
        /// Read-only throughput.
        case maximumReadSpeed
    }

    public struct Context: Sendable {
        let drive: Drive
        let macFUSEVersion: String?
        let externalFUSE: Bool
        let readOnly: Bool
        let allowOther: Bool
        let preserveOwnership: Bool
        let profile: Profile
        let volumeName: String
    }

    private static let ntfsMaxRead = 1_048_576
    private static let macFUSEIOSizeBurst = 1_048_576
    /// Smaller chunks pipeline more evenly on USB HDDs — reduces post-burst taper.
    private static let macFUSEIOSizeSustained = 524_288
    private static let macFUSEDaemonTimeoutFast = 180
    private static let macFUSEDaemonTimeoutSustained = 120
    /// Batch mtime updates during long open-file writes (seconds).
    private static let mtimeDelaySeconds = 300

    public static func fuseOptions(for context: Context) -> [String] {
        switch context.profile {
        case .balanced:
            return balancedOptions(for: context)
        case .fast, .maximumSpeed:
            return fastOptions(for: context)
        case .sustainedThroughput:
            return performanceOptions(for: context, sustained: true)
        case .maximumReadSpeed:
            return performanceOptions(for: context, sustained: false)
        }
    }

    // MARK: - Profiles

    private static func fastOptions(for context: Context) -> [String] {
        let blockSize = storageBlockSize(for: context.drive)

        var options: [String] = [
            "local",
            "noatime",
            "big_writes",
            "max_read=\(ntfsMaxRead)",
            "streams_interface=none",
            "nocompression",
        ]

        if context.externalFUSE {
            options.append(contentsOf: [
                "iosize=\(macFUSEIOSizeBurst)",
                "blocksize=\(blockSize)",
                "nosyncwrites",
                "nosynconclose",
                "noappledouble",
                "noapplexattr",
                "negative_vncache",
                "daemon_timeout=\(macFUSEDaemonTimeoutFast)",
            ])
        }

        if shouldUseFSKitBackend(macFUSEVersion: context.macFUSEVersion, externalFUSE: context.externalFUSE) {
            options.append("backend=fskit")
        }

        appendCommon(&options, context: context)
        return options
    }

    private static func balancedOptions(for context: Context) -> [String] {
        var options: [String] = [
            "local",
            "auto_xattr",
            "noatime",
            "streams_interface=xattr",
        ]
        appendCommon(&options, context: context)
        return options
    }

    private static func performanceOptions(for context: Context, sustained: Bool) -> [String] {
        let blockSize = storageBlockSize(for: context.drive)
        let ioSize = sustained ? macFUSEIOSizeSustained : macFUSEIOSizeBurst

        var options: [String] = [
            "local",
            "noatime",
            "big_writes",
            "max_read=\(ntfsMaxRead)",
            "streams_interface=none",
            "nocompression",
        ]

        if sustained && !context.readOnly {
            options.append("delay_mtime=\(mtimeDelaySeconds)")
        }

        if context.externalFUSE {
            options.append(contentsOf: macFUSEPerformanceOptions(
                blockSize: blockSize,
                ioSize: ioSize,
                sustained: sustained
            ))
        }

        if shouldUseFSKitBackend(macFUSEVersion: context.macFUSEVersion, externalFUSE: context.externalFUSE) {
            options.append("backend=fskit")
        }

        appendCommon(&options, context: context)
        return options
    }

    private static func macFUSEPerformanceOptions(blockSize: Int, ioSize: Int, sustained: Bool) -> [String] {
        var options = [
            "iosize=\(ioSize)",
            "blocksize=\(blockSize)",
            "nosyncwrites",
            "noappledouble",
            "noapplexattr",
            "negative_vncache",
            "daemon_timeout=\(macFUSEDaemonTimeoutSustained)",
        ]
        if !sustained {
            options.append("nosynconclose")
        }
        return options
    }

    private static func storageBlockSize(for drive: Drive) -> Int {
        let bs = Int(drive.blockSize)
        if bs >= 4096 { return bs }
        if bs >= 512 { return bs }
        return 4096
    }

    private static func appendCommon(_ options: inout [String], context: Context) {
        if context.allowOther {
            options.append("allow_other")
        } else {
            // Drop ntfs-3g defaults (allow_other needs /etc/fuse.conf). Keep silent + nonempty.
            options.append("no_def_opts")
            options.append("silent")
            options.append("nonempty")
        }
        options.append(context.readOnly ? "ro" : "rw")

        if !context.preserveOwnership {
            options.append("uid=\(getuid())")
            options.append("gid=\(getgid())")
        }

        options.append("volname=\(context.volumeName)")
    }

    private static func shouldUseFSKitBackend(macFUSEVersion: String?, externalFUSE: Bool) -> Bool {
        guard !externalFUSE,
              HostOSInfo.prefersFSKitBackend,
              let macFUSEVersion,
              MacFUSEInfo.isAtLeast(macFUSEVersion, minimum: MacFUSEInfo.minimumFSKitVersion) else {
            return false
        }
        return true
    }
}

import Foundation

/// Parses `mount(8)` output for a mount point.
public enum NTFSMountDiagnostics: Sendable {

    public struct MountInfo: Sendable, Equatable {
        public let device: String
        public let mountPoint: String
        public let filesystem: String
        public let flags: [String]
        public let isSynchronous: Bool
        public let isAsynchronous: Bool
        public let isReadOnly: Bool

        public var isFUSE: Bool {
            let fs = filesystem.lowercased()
            return fs.contains("fuse") || fs.contains("macfuse")
        }

        public var flagsSummary: String { flags.joined(separator: ", ") }
    }

    public enum VerificationError: Error, Sendable, Equatable {
        case notInMountTable
        case notFUSE(filesystem: String)
        case notReadable
        case notWritable
    }

    public static func mountInfo(for path: String) async -> MountInfo? {
        let result = try? await ProcessRunner.run("/sbin/mount")
        guard let output = result?.stdout else { return nil }

        let normalized = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let line = output.split(separator: "\n").first(where: { $0.contains(" on \(normalized) ") }) else {
            return nil
        }
        return parse(line: String(line), mountPoint: normalized)
    }

    /// Confirms the path is a live macFUSE / ntfs-3g mount.
    ///
    /// Uses the mount table only. `FileManager` checks against FUSE mount points are
    /// unreliable on macOS (false negatives for exists/readable/writable on the root).
    public static func verifyFUSEMount(at path: String, requireWrite: Bool) async -> Result<MountInfo, VerificationError> {
        let normalized = path.hasSuffix("/") ? String(path.dropLast()) : path

        for attempt in 0..<10 {
            if let info = await mountInfo(for: normalized) {
                guard info.isFUSE else {
                    return .failure(.notFUSE(filesystem: info.filesystem))
                }
                if requireWrite && info.isReadOnly {
                    return .failure(.notWritable)
                }
                return .success(info)
            }
            if attempt < 9 {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        return .failure(.notInMountTable)
    }

    public static func parse(line: String, mountPoint: String) -> MountInfo? {
        guard let onRange = line.range(of: " on \(mountPoint) ("),
              let close = line[onRange.upperBound...].firstIndex(of: ")") else {
            return nil
        }
        let device = String(line[..<onRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let flagString = String(line[onRange.upperBound..<close])
        let flags = flagString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let fs = flags.first ?? "unknown"
        let readOnlyFlags: Set<String> = ["read-only", "rdonly", "ro"]
        let isReadOnly = flags.contains { readOnlyFlags.contains($0.lowercased()) }
        return MountInfo(
            device: device,
            mountPoint: mountPoint,
            filesystem: fs,
            flags: flags,
            isSynchronous: flags.contains("synchronous"),
            isAsynchronous: flags.contains("asynchronous"),
            isReadOnly: isReadOnly
        )
    }
}

import Foundation

/// Checks whether a mount point is visible to the app process (same user as Finder).
public enum VolumeAccessibility {
    public static func isAccessibleByCurrentUser(at path: String, retries: Int = 12) async -> Bool {
        let normalized = path.hasSuffix("/") ? String(path.dropLast()) : path

        for attempt in 0..<retries {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: normalized, isDirectory: &isDirectory),
               isDirectory.boolValue,
               (try? FileManager.default.contentsOfDirectory(atPath: normalized)) != nil {
                return true
            }
            if attempt < retries - 1 {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        return false
    }

    /// True when the mount table lists a FUSE volume at `path` but this user cannot open it.
    public static func isGhostFUSEMount(at path: String) async -> Bool {
        guard let info = await NTFSMountDiagnostics.mountInfo(for: path), info.isFUSE else {
            return false
        }
        return !(await isAccessibleByCurrentUser(at: path, retries: 1))
    }
}

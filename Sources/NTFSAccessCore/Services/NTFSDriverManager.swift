import Foundation

/// Status of the third-party NTFS driver stack on this machine.
public struct NTFSDriverStatus: Sendable, Equatable {
    public let macFUSEInstalled: Bool
    public let macFUSEVersion: String?
    public let macFUSEBundlePath: String?

    public let ntfs3gPath: String?
    public let ntfs3gVersion: String?
    /// True when `ntfs-3g --version` reports the external macFUSE library (not libfuse3 integrated).
    public let ntfs3gUsesExternalFUSE: Bool

    /// Installed macFUSE meets our minimum for this host OS.
    public var isMacFUSEVersionSupported: Bool {
        guard let macFUSEVersion else { return false }
        return MacFUSEInfo.isVersionSupported(macFUSEVersion)
    }

    /// Installed macFUSE is older than what we recommend on this Mac.
    public var macFUSEUpdateRecommended: Bool {
        guard let macFUSEVersion, macFUSEInstalled else { return false }
        return MacFUSEInfo.updateRecommended(installed: macFUSEVersion)
    }

    /// Both pieces are present, macFUSE is new enough, and we should be able to mount NTFS read/write.
    public var isReady: Bool {
        macFUSEInstalled && isMacFUSEVersionSupported && ntfs3gPath != nil
    }

    public static let unknown = NTFSDriverStatus(
        macFUSEInstalled: false,
        macFUSEVersion: nil,
        macFUSEBundlePath: nil,
        ntfs3gPath: nil,
        ntfs3gVersion: nil,
        ntfs3gUsesExternalFUSE: false
    )
}

public enum NTFSDriverError: LocalizedError, Sendable {
    case driverNotInstalled
    case ntfs3gMissing
    case mountFailed(String)
    case unmountFailed(String)
    case driveNotNTFS
    case invalidVolumeName
    case macFUSETooOld(installed: String, minimum: String)

    public var errorDescription: String? {
        switch self {
        case .driverNotInstalled:
            return "macFUSE is not installed. Install macFUSE \(MacFUSEInfo.recommendedVersionForHost) or newer on \(HostOSInfo.marketingName)."
        case .ntfs3gMissing:
            return "ntfs-3g binary not found. Install via Homebrew: brew install gromgit/fuse/ntfs-3g-mac"
        case .mountFailed(let msg): return Self.mountFailureDescription(msg)
        case .unmountFailed(let msg): return "Unmount failed: \(msg)"
        case .driveNotNTFS: return "This drive isn't an NTFS volume."
        case .invalidVolumeName: return "Invalid volume name."
        case .macFUSETooOld(let installed, let minimum):
            return "macFUSE \(installed) is too old for \(HostOSInfo.marketingName). Upgrade to macFUSE \(minimum) or newer (recommended: \(MacFUSEInfo.recommendedVersionForHost))."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .mountFailed(let msg):
            return Self.mountFailureRecoverySuggestion(msg)
        default:
            return nil
        }
    }

    private static func mountFailureDescription(_ msg: String) -> String {
        let lower = msg.lowercased()
        if lower.contains("unclean") || lower.contains("metadata kept in windows cache") {
            return "ntfs-3g mount failed: NTFS dirty flag set (Windows did not flush metadata — not the same as hiberfil.sys)."
        }
        if lower.contains("hibernation") || lower.contains("hiberfile") {
            return "ntfs-3g mount failed: Windows hibernation or fast startup is blocking read/write access."
        }
        if lower.contains("volume is busy") {
            return "ntfs-3g mount failed: The volume is in use by another process."
        }
        return "ntfs-3g mount failed: \(msg)"
    }

    private static func mountFailureRecoverySuggestion(_ msg: String) -> String? {
        let lower = msg.lowercased()
        if lower.contains("unclean") || lower.contains("metadata kept in windows cache") {
            return "Try Mount (Read/Write) again — the app runs ntfsfix to clear the dirty flag. If it persists, run chkdsk from Windows or disable Fast Startup."
        }
        if lower.contains("hibernation") || lower.contains("hiberfile") {
            return "Boot Windows and choose Shut down (not Restart), with Fast Startup disabled."
        }
        if lower.contains("probe failed") {
            return "Eject the drive, wait a few seconds, and try again."
        }
        if lower.contains("volume is busy") {
            return "Unmount or eject the drive in Finder, then try again."
        }
        if lower.contains("default_permissions") && lower.contains("defer_permissions") {
            return "Update \(AppInfo.displayName) to the latest build and remount."
        }
        if lower.contains("allow_other") || lower.contains("fuse.conf") || lower.contains("logged-in user") {
            return "Quit and reopen \(AppInfo.displayName), then mount again. The app writes user_allow_other to /etc/fuse.conf automatically."
        }
        if lower.contains("not visible to your user") {
            return "Unmount the drive (Volume Actions → Unmount), quit the app completely (Cmd+Q), reopen it, and mount again."
        }
        return nil
    }
}

/// Detects macFUSE + ntfs-3g and mounts NTFS volumes read/write.
///
/// Mount commands run via the system admin prompt (`do shell script with administrator privileges`).
public final class NTFSDriverManager: @unchecked Sendable {

    public init() {}

    // MARK: - Detection

    private static let macFUSEBundle = MacFUSEInfo.bundlePath

    /// Common Homebrew install locations for `ntfs-3g`. We check in priority order.
    private static let ntfs3gCandidates: [String] = [
        "/opt/homebrew/bin/ntfs-3g",
        "/opt/homebrew/sbin/ntfs-3g",
        "/usr/local/bin/ntfs-3g",
        "/usr/local/sbin/ntfs-3g",
        "/usr/local/Cellar/ntfs-3g-mac/current/bin/ntfs-3g"
    ]

    public func detectStatus() async -> NTFSDriverStatus {
        let fm = FileManager.default

        let bundleExists = fm.fileExists(atPath: Self.macFUSEBundle)
        let macFUSEVersion: String? = bundleExists
            ? Self.readBundleVersion(at: Self.macFUSEBundle)
            : nil

        let ntfs3gPath = Self.ntfs3gCandidates.first { fm.isExecutableFile(atPath: $0) }
        var ntfs3gVersion: String? = nil
        var ntfs3gUsesExternalFUSE = false
        if let path = ntfs3gPath {
            // ntfs-3g --version writes its banner to stderr.
            if let result = try? await ProcessRunner.run(path, arguments: ["--version"]) {
                let banner = result.combinedOutput
                ntfs3gVersion = Self.firstLine(of: banner)
                ntfs3gUsesExternalFUSE = banner.localizedCaseInsensitiveContains("external FUSE")
            }
        }

        return NTFSDriverStatus(
            macFUSEInstalled: bundleExists,
            macFUSEVersion: macFUSEVersion,
            macFUSEBundlePath: bundleExists ? Self.macFUSEBundle : nil,
            ntfs3gPath: ntfs3gPath,
            ntfs3gVersion: ntfs3gVersion,
            ntfs3gUsesExternalFUSE: ntfs3gUsesExternalFUSE
        )
    }

    private static func readBundleVersion(at bundlePath: String) -> String? {
        let plistPath = "\(bundlePath)/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String)
    }

    private static func firstLine(of text: String) -> String? {
        text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init)
    }

    // MARK: - Mount / Unmount

    public struct MountOptions: Sendable {
        public var readOnly: Bool
        public var allowOther: Bool
        public var preserveOwnership: Bool
        public var customMountPoint: URL?
        public var performanceProfile: NTFSMountTuning.Profile

        public init(
            readOnly: Bool = false,
            allowOther: Bool = MacFUSEInfo.isAllowOtherConfigured,
            preserveOwnership: Bool = false,
            customMountPoint: URL? = nil,
            performanceProfile: NTFSMountTuning.Profile = .fast
        ) {
            self.readOnly = readOnly
            self.allowOther = allowOther
            self.preserveOwnership = preserveOwnership
            self.customMountPoint = customMountPoint
            self.performanceProfile = performanceProfile
        }

        public static let fast = MountOptions(performanceProfile: .fast)
        public static let readOnly = MountOptions(
            readOnly: true,
            performanceProfile: .maximumReadSpeed
        )
        public static let `default` = MountOptions.fast
    }

    @discardableResult
    public func mount(
        drive: Drive,
        options: MountOptions = .default
    ) async throws -> URL {
        let status = await detectStatus()
        guard status.macFUSEInstalled else { throw NTFSDriverError.driverNotInstalled }
        if let version = status.macFUSEVersion, !MacFUSEInfo.isVersionSupported(version) {
            throw NTFSDriverError.macFUSETooOld(
                installed: version,
                minimum: MacFUSEInfo.minimumSupportedVersionForHost
            )
        }
        guard let ntfs3g = status.ntfs3gPath else { throw NTFSDriverError.ntfs3gMissing }
        guard !drive.isWholeDisk else {
            throw NTFSDriverError.mountFailed("Cannot mount a whole disk; pick a partition.")
        }

        var mountOptions = options
        // Privileged mounts configure /etc/fuse.conf and use allow_other so Finder can access the volume.
        mountOptions.allowOther = true

        let mountPoint = mountOptions.customMountPoint
            ?? URL(fileURLWithPath: "/Volumes/\(safeVolumeName(for: drive))")

        let safeMountPath = ProcessRunner.shellQuote(mountPoint.path)
        let safeNTFS3G = ProcessRunner.shellQuote(ntfs3g)
        let safeDevice = ProcessRunner.shellQuote(drive.devicePath)

        let volumeName = safeVolumeName(for: drive)
        let ntfsOptions = NTFSMountTuning.fuseOptions(for: NTFSMountTuning.Context(
            drive: drive,
            macFUSEVersion: status.macFUSEVersion,
            externalFUSE: status.ntfs3gUsesExternalFUSE,
            readOnly: mountOptions.readOnly,
            allowOther: mountOptions.allowOther,
            preserveOwnership: mountOptions.preserveOwnership,
            profile: mountOptions.readOnly ? .maximumReadSpeed : mountOptions.performanceProfile,
            volumeName: volumeName
        ))

        let fuseOptionString = ntfsOptions.joined(separator: ",")
        let quotedFuseOptions = ProcessRunner.shellQuote(fuseOptionString)
        let ownerUID = getuid()
        let ownerGID = getgid()
        let ntfsfix = NTFSVolumePreparer.companionTool(named: "ntfsfix", beside: ntfs3g)
        let ntfsfixStep = mountOptions.readOnly ? "" : NTFSVolumePreparer.ntfsfixStep(
            device: drive.devicePath,
            ntfsfix: ntfsfix
        )

        let composite = """
        /usr/bin/pkill -f 'ntfs-3g.*\(drive.bsdName)' 2>/dev/null || true; \
        /usr/sbin/diskutil unmount force \(safeDevice) >/dev/null 2>&1 || true; \
        /usr/sbin/diskutil unmount force \(safeMountPath) >/dev/null 2>&1 || true; \
        if /sbin/mount | /usr/bin/grep -Fq ' on \(mountPoint.path) '; then \
          /sbin/umount \(safeMountPath) >/dev/null 2>&1 || /usr/sbin/diskutil unmount force \(safeMountPath) >/dev/null 2>&1 || true; \
        fi; \
        if ! /sbin/mount | /usr/bin/grep -Fq ' on \(mountPoint.path) '; then /bin/rmdir \(safeMountPath) 2>/dev/null || true; fi; \
        FUSE_CONF=/etc/fuse.conf; \
        if [ ! -f "$FUSE_CONF" ]; then \
          /bin/printf '%s\\n' '# macFUSE configuration for \(AppInfo.displayName)' 'user_allow_other' > "$FUSE_CONF"; \
        elif ! /usr/bin/grep -qE '^[[:space:]]*user_allow_other' "$FUSE_CONF"; then \
          /bin/printf '\\n%s\\n' 'user_allow_other' >> "$FUSE_CONF"; \
        fi; \
        \(ntfsfixStep)\
        /bin/mkdir -p \(safeMountPath); \
        /usr/sbin/chown \(ownerUID):\(ownerGID) \(safeMountPath) 2>/dev/null || true; \
        ERROR_FILE=$(/usr/bin/mktemp /private/tmp/ntfs-formac-err.XXXXXX); \
        if \(safeNTFS3G) \(safeDevice) \(safeMountPath) -o \(quotedFuseOptions) 2>"$ERROR_FILE"; then \
          :; \
        elif [ "\(mountOptions.readOnly ? "1" : "0")" = "0" ]; then \
          \(ntfsfixStep)\
          if \(safeNTFS3G) \(safeDevice) \(safeMountPath) -o remove_hiberfile,recover,\(quotedFuseOptions) 2>"$ERROR_FILE"; then \
            :; \
          else \
            /bin/cat "$ERROR_FILE" >&2; /bin/rm -f "$ERROR_FILE"; exit 1; \
          fi; \
        else \
          /bin/cat "$ERROR_FILE" >&2; /bin/rm -f "$ERROR_FILE"; exit 1; \
        fi; \
        /bin/rm -f "$ERROR_FILE"; \
        MOUNT_LINE=""; \
        for _ in 1 2 3 4 5 6; do \
          MOUNT_LINE=$(/sbin/mount | /usr/bin/grep -F ' on \(mountPoint.path) ' || true); \
          if [ -n "$MOUNT_LINE" ]; then break; fi; \
          /bin/sleep 0.5; \
        done; \
        if [ -z "$MOUNT_LINE" ]; then \
          /usr/sbin/diskutil unmount force \(safeMountPath) >/dev/null 2>&1 || /bin/rmdir \(safeMountPath) 2>/dev/null || true; \
          /bin/echo 'Mount verification failed: \(mountPoint.path) is not in the mount table.' >&2; \
          exit 1; \
        fi; \
        if ! /usr/bin/printf '%s' "$MOUNT_LINE" | /usr/bin/grep -qi macfuse; then \
          /usr/sbin/diskutil unmount force \(safeMountPath) >/dev/null 2>&1 || true; \
          /bin/rmdir \(safeMountPath) 2>/dev/null || true; \
          /bin/echo 'Mount verification failed: \(mountPoint.path) is not a macFUSE volume.' >&2; \
          exit 1; \
        fi; \
        if [ "\(mountOptions.readOnly ? "1" : "0")" = "0" ] && /usr/bin/printf '%s' "$MOUNT_LINE" | /usr/bin/grep -qE '(^|, )read-only(,|$)'; then \
          /usr/sbin/diskutil unmount force \(safeMountPath) >/dev/null 2>&1 || true; \
          /bin/rmdir \(safeMountPath) 2>/dev/null || true; \
          /bin/echo 'Mount verification failed: \(mountPoint.path) is read-only.' >&2; \
          exit 1; \
        fi; \
        CONSOLE_USER=$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || true); \
        if [ -n "$CONSOLE_USER" ] && [ "$CONSOLE_USER" != "root" ]; then \
          if ! /usr/bin/sudo -u "$CONSOLE_USER" /bin/ls \(safeMountPath) >/dev/null 2>&1; then \
            /usr/sbin/diskutil unmount force \(safeMountPath) >/dev/null 2>&1 || true; \
            /bin/rmdir \(safeMountPath) 2>/dev/null || true; \
            /bin/echo 'Mount verification failed: \(mountPoint.path) is not accessible to the logged-in user (allow_other / fuse.conf).' >&2; \
            exit 1; \
          fi; \
          /usr/bin/sudo -u "$CONSOLE_USER" /usr/bin/open \(safeMountPath) >/dev/null 2>&1 || true; \
        elif ! /bin/ls \(safeMountPath) >/dev/null 2>&1; then \
          /usr/sbin/diskutil unmount force \(safeMountPath) >/dev/null 2>&1 || true; \
          /bin/rmdir \(safeMountPath) 2>/dev/null || true; \
          /bin/echo 'Mount verification failed: \(mountPoint.path) is not accessible.' >&2; \
          exit 1; \
        fi
        """

        let prompt = "\(AppInfo.displayName) wants to mount \(drive.displayName) as read/write."
        do {
            _ = try await ProcessRunner.runPrivileged(shellCommand: composite, prompt: prompt)
        } catch let ProcessRunnerError.appleScriptFailed(code, message) {
            throw NTFSDriverError.mountFailed("[\(code)] \(message)")
        }

        let verification = await NTFSMountDiagnostics.verifyFUSEMount(
            at: mountPoint.path,
            requireWrite: !mountOptions.readOnly
        )
        switch verification {
        case .success:
            if await VolumeAccessibility.isAccessibleByCurrentUser(at: mountPoint.path) {
                return mountPoint
            }
            throw NTFSDriverError.mountFailed(
                "Volume mounted in the kernel but /Volumes/\(volumeName) is not visible to your user. " +
                "Quit the app, reopen the latest build, then mount again — allow_other will be enabled automatically."
            )
        case .failure(let error):
            throw NTFSDriverError.mountFailed(Self.verificationErrorMessage(error, path: mountPoint.path))
        }
    }

    private static func verificationErrorMessage(_ error: NTFSMountDiagnostics.VerificationError, path: String) -> String {
        switch error {
        case .notInMountTable:
            return "Mount at \(path) did not appear in the mount table."
        case .notFUSE(let filesystem):
            return "Mount at \(path) is not macFUSE (found \(filesystem)). The volume may be mounted read-only by macOS instead."
        case .notReadable:
            return "Mount at \(path) exists but is not readable."
        case .notWritable:
            return "Mount at \(path) is read-only."
        }
    }

    /// Unmount a volume mounted by us (or anyone else). Uses `diskutil unmount` which
    /// does NOT require admin privileges for user-mounted volumes.
    public func unmount(drive: Drive, force: Bool = false) async throws {
        let args: [String] = force
            ? ["unmount", "force", drive.devicePath]
            : ["unmount", drive.devicePath]
        let result = try await ProcessRunner.run("/usr/sbin/diskutil", arguments: args)
        if !result.isSuccess {
            throw NTFSDriverError.unmountFailed(result.combinedOutput)
        }
    }

    // MARK: - Helpers

    /// Make a filesystem-safe volume name for use in `/Volumes/<name>`.
    private func safeVolumeName(for drive: Drive) -> String {
        let raw = drive.volumeName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? drive.mediaName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? "NTFS-\(drive.bsdName)"
        // Strip path separators and other characters that would break /Volumes mounting.
        let stripped = raw.unicodeScalars
            .filter { !"/\\:?\"<>|".unicodeScalars.contains($0) }
            .map(String.init)
            .joined()
        return stripped.isEmpty ? "NTFS-\(drive.bsdName)" : stripped
    }

    /// Returns true if `path` appears in the system mount table (not just an empty directory).
    public func isPathMounted(_ path: String) async -> Bool {
        let result = try? await ProcessRunner.run("/sbin/mount", arguments: [])
        guard let output = result?.stdout else { return false }
        return output.contains(" on \(path) ") || output.hasSuffix(" on \(path)\n")
    }

    /// Single-quote a string for safe inclusion in a /bin/sh command.
    /// Replaces `'` with `'\''`.
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

import SwiftUI
import AppKit
import NTFSAccessCore

struct DriveDetailView: View {
    let drive: Drive
    @Binding var showInstall: Bool
    @EnvironmentObject private var driveManager: DriveManager

    @State private var working = false
    @State private var actionError: String?
    @State private var actionInfo: String?
    @State private var lastMountPoint: URL?
    @State private var mountDiagnostics: NTFSMountDiagnostics.MountInfo?
    @State private var ntfsResult: NTFSDetectionResult?
    @State private var openInFinderAfterMount = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                headerCard

                CardSection(title: "Details", icon: "info.circle") {
                    detailsGrid
                }

                CardSection(title: "NTFS Detection", icon: "flag.fill", tint: isNTFS ? .orange : .secondary) {
                    ntfsResultView
                }

                if isNTFS {
                    CardSection(title: "Read / Write Mount", icon: "bolt.shield.fill", tint: .orange) {
                        ntfsActionsContent
                    }
                }

                if let mountDiagnostics {
                    CardSection(title: "Mount Performance", icon: "speedometer") {
                        mountDiagnosticsContent(mountDiagnostics)
                    }
                }

                CardSection(title: "Volume Actions", icon: "slider.horizontal.3") {
                    volumeActionsContent
                }

                if let info = actionInfo {
                    FeedbackBanner(
                        message: info,
                        style: .success,
                        actionTitle: lastMountPoint != nil ? "Reveal in Finder" : nil,
                        action: lastMountPoint.map { url in { NSWorkspace.shared.activateFileViewerSelecting([url]) } },
                        onDismiss: { actionInfo = nil }
                    )
                }

                if let error = actionError {
                    FeedbackBanner(
                        message: error,
                        style: .error,
                        onDismiss: { actionError = nil }
                    )
                }
            }
            .padding(20)
        }
        .task(id: drive.id) {
            ntfsResult = driveManager.ntfsStatus(drive)
            await refreshMountDiagnostics()
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: DriveIcon.symbol(for: drive))
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DriveIcon.color(for: drive, isNTFS: isNTFS))
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(drive.displayName)
                        .font(.title.weight(.semibold))
                    if isNTFS { NTFSBadge() }
                }
                Text(drive.isWholeDisk ? "Whole disk" : "Volume")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let model = drive.model {
                    Text([drive.vendor, model].compactMap { $0 }.joined(separator: " "))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            statusPill
        }
        .padding(AppTheme.cardPadding)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private var statusPill: some View {
        let (label, icon, color) = mountStatusDisplay
        return Label(label, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var mountStatusDisplay: (String, String, Color) {
        if let info = mountDiagnostics {
            if info.isFUSE {
                return info.isReadOnly
                    ? ("Mounted read-only (ntfs-3g)", "lock.fill", .orange)
                    : ("Mounted (ntfs-3g)", "checkmark.circle.fill", .green)
            }
            return ("Mounted (macOS)", "exclamationmark.circle.fill", .orange)
        }
        if drive.isMounted {
            return ("Listed as mounted", "questionmark.circle.fill", .orange)
        }
        return ("Not mounted", "circle", .secondary)
    }

    // MARK: - Details

    private var detailsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), alignment: .topLeading),
            GridItem(.flexible(), alignment: .topLeading)
        ], alignment: .leading, spacing: 12) {
            DetailInfoCell(label: "BSD Name", value: drive.bsdName)
            DetailInfoCell(label: "Device Path", value: drive.devicePath, monospaced: true)
            DetailInfoCell(label: "Filesystem", value: drive.filesystem.displayName)
            DetailInfoCell(label: "Mount Point", value: drive.mountPoint?.path ?? "—", monospaced: drive.mountPoint != nil)
            DetailInfoCell(label: "Size", value: drive.totalSize > 0 ? drive.formattedSize : "—")
            DetailInfoCell(label: "Block Size", value: "\(drive.blockSize) bytes")
            DetailInfoCell(label: "Bus", value: drive.bus.rawValue)
            DetailInfoCell(label: "Internal", value: drive.isInternal ? "Yes" : "No")
            DetailInfoCell(label: "Removable", value: drive.isRemovable ? "Yes" : "No")
            DetailInfoCell(label: "Ejectable", value: drive.isEjectable ? "Yes" : "No")
            DetailInfoCell(label: "Writable (media)", value: drive.isWritable ? "Yes" : "No")
            if let parent = drive.parentBSDName {
                DetailInfoCell(label: "Parent", value: parent, monospaced: true)
            }
            if let media = drive.mediaName {
                DetailInfoCell(label: "Media", value: media)
            }
        }
    }

    // MARK: - NTFS

    private var isNTFS: Bool {
        if drive.isNTFS { return true }
        switch ntfsResult {
        case .confirmedFromIdentifier, .confirmedFromBootSector: return true
        default: return false
        }
    }

    private var ntfsResultView: some View {
        let result = ntfsResult ?? driveManager.ntfsStatus(drive)
        let copy = ntfsStatusCopy(for: result)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: copy.icon)
                .font(.title2)
                .foregroundStyle(copy.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.title)
                    .font(.body.weight(.medium))
                Text(copy.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Re-check") {
                ntfsResult = driveManager.ntfsStatus(drive)
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }

    private func ntfsStatusCopy(for result: NTFSDetectionResult) -> (icon: String, color: Color, title: String, subtitle: String) {
        switch result {
        case .confirmedFromIdentifier:
            return ("flag.fill", .orange, "NTFS confirmed", "Reported as NTFS by the system.")
        case .confirmedFromBootSector:
            return ("flag.fill", .orange, "NTFS confirmed (boot sector)", "Boot sector signature matches NTFS.")
        case .notNTFS:
            let subtitle = drive.filesystem.kind == .unknown
                ? "Boot sector did not match NTFS."
                : "Detected as \(drive.filesystem.displayName)."
            return ("checkmark.seal.fill", .green, "Not NTFS", subtitle)
        case .indeterminate(let reason):
            return ("questionmark.circle.fill", .secondary, "Unknown", "\(reason). Grant Full Disk Access if detection fails.")
        }
    }

    private var driverReady: Bool { driveManager.driverStatus.isReady }

    private var ntfsActionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mounts this volume read/write through ntfs-3g. Async I/O, 1 MiB transfer size.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Open in Finder after mount", isOn: $openInFinderAfterMount)
                .font(.callout)

            HStack(spacing: 10) {
                if driverReady {
                    Button {
                        performMountRW()
                    } label: {
                        Label("Mount Read/Write", systemImage: "lock.open.rotation")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(working || drive.isWholeDisk)

                    Button {
                        performMountRO()
                    } label: {
                        Label("Mount Read-Only", systemImage: "lock")
                    }
                    .disabled(working || drive.isWholeDisk)
                } else {
                    Button {
                        showInstall = true
                    } label: {
                        Label("Install NTFS Driver…", systemImage: "shippingbox")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if working {
                    ProgressView()
                        .controlSize(.small)
                }

                if !driverReady {
                    Text(driverStatusHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()
            }
        }
    }

    private var driverStatusHint: String {
        if !driveManager.driverStatus.macFUSEInstalled { return "macFUSE not installed" }
        if driveManager.driverStatus.ntfs3gPath == nil { return "ntfs-3g not found" }
        return "Driver update required"
    }

    private func mountDiagnosticsContent(_ info: NTFSMountDiagnostics.MountInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(info.flagsSummary)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))

            if info.isSynchronous {
                Label(
                    "Synchronous I/O — unmount and remount with Read/Write for best speed.",
                    systemImage: "tortoise.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            } else if info.isReadOnly {
                Label(
                    "Read-only mount — unmount and try Mount Read/Write again.",
                    systemImage: "lock.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            } else {
                Label("Async I/O active (1 MiB chunks)", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Volume actions

    private var volumeActionsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Standard macOS volume controls. NTFS volumes mount read-only via macOS — use Read/Write Mount above for full access.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 140), spacing: 8)
            ], spacing: 8) {
                actionButton("Mount", icon: "arrow.down.to.line", disabled: working || drive.isMounted || drive.isWholeDisk) {
                    perform { try await driveManager.mount(drive) }
                }
                actionButton("Unmount", icon: "arrow.up.to.line", disabled: working || !drive.isMounted) {
                    perform { try await driveManager.unmount(drive) }
                }
                actionButton("Force Unmount", icon: "exclamationmark.arrow.triangle.2.circlepath", disabled: working || !drive.isMounted) {
                    perform { try await driveManager.unmount(drive, force: true) }
                }
                actionButton("Eject", icon: "eject", disabled: working || !drive.isEjectable) {
                    perform { try await driveManager.eject(drive) }
                }
            }
        }
    }

    private func actionButton(_ title: String, icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
    }

    // MARK: - Mount operations

    private func refreshMountDiagnostics() async {
        let path = drive.mountPoint?.path ?? lastMountPoint?.path
        guard let path else {
            mountDiagnostics = nil
            return
        }
        mountDiagnostics = await NTFSMountDiagnostics.mountInfo(for: path)
        if await VolumeAccessibility.isGhostFUSEMount(at: path) {
            actionError = """
            This volume is mounted but invisible in Finder (root-only FUSE mount).

            Unmount it, press Cmd+Q to quit the app completely, reopen it, then mount again.
            """
        }
    }

    private func performMountRW() {
        actionError = nil
        actionInfo = nil
        lastMountPoint = nil
        working = true
        Task {
            defer { working = false }
            do {
                let url = try await driveManager.mountReadWrite(drive)
                lastMountPoint = url
                mountDiagnostics = await NTFSMountDiagnostics.mountInfo(for: url.path)
                if mountDiagnostics?.isFUSE != true {
                    actionInfo = "Mount reported success but the volume is not visible as macFUSE. Try unmounting, then use Mount Read/Write again."
                } else if mountDiagnostics?.isSynchronous == true {
                    actionInfo = "Mounted at \(url.path), but I/O is still synchronous."
                } else if mountDiagnostics?.isReadOnly == true {
                    actionInfo = "Mounted at \(url.path), but read-only."
                } else if await VolumeAccessibility.isGhostFUSEMount(at: url.path) {
                    actionError = formatError(NTFSDriverError.mountFailed(
                        "Volume mounted in the kernel but \(url.path) is not visible to your user."
                    ))
                } else {
                    actionInfo = "Mounted read/write at \(url.path)"
                }
                driveManager.refresh()
                if openInFinderAfterMount, mountDiagnostics?.isFUSE == true, let url = lastMountPoint {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                ntfsResult = driveManager.ntfsStatus(drive)
            } catch {
                actionError = formatError(error)
            }
        }
    }

    private func performMountRO() {
        actionError = nil
        actionInfo = nil
        lastMountPoint = nil
        working = true
        Task {
            defer { working = false }
            do {
                let url = try await driveManager.mountReadOnlyViaDriver(drive)
                lastMountPoint = url
                mountDiagnostics = await NTFSMountDiagnostics.mountInfo(for: url.path)
                actionInfo = "Mounted read-only at \(url.path)"
                if openInFinderAfterMount, let url = lastMountPoint {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func perform(_ op: @escaping () async throws -> Void) {
        actionError = nil
        actionInfo = nil
        working = true
        Task {
            defer { working = false }
            do {
                try await op()
                ntfsResult = driveManager.ntfsStatus(drive)
                await refreshMountDiagnostics()
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func formatError(_ error: Error) -> String {
        if let recovery = (error as? LocalizedError)?.recoverySuggestion {
            return "\(error.localizedDescription)\n\n\(recovery)"
        }
        return error.localizedDescription
    }
}

import SwiftUI
import NTFSAccessCore

/// Sheet that walks the user through installing macFUSE + ntfs-3g via Homebrew.
struct InstallInstructionsView: View {
    @EnvironmentObject private var driveManager: DriveManager
    @Environment(\.dismiss) private var dismiss

    private var status: NTFSDriverStatus { driveManager.driverStatus }

    private var macFUSEInstallCommands: [String] {
        if status.macFUSEInstalled {
            if status.macFUSEUpdateRecommended {
                return MacFUSEInfo.brewUpgradeCommandsForHost
            }
            return []
        }
        return MacFUSEInfo.brewInstallCommandsForHost
    }

    private var macFUSEStepBody: String {
        if HostOSInfo.isMacOS27OrLater {
            return """
            On \(HostOSInfo.marketingName), install macFUSE \(MacFUSEInfo.recommendedDevVersion) via the `macfuse@dev` cask. macFUSE 5.3.1+ is the first release with official macOS 27 support. It uses Apple's FSKit backend — no Reduced Security or kernel extension is required.

            If you already have the stable `macfuse` cask (5.2.0), Homebrew cannot install `macfuse@dev` on top of it — you must uninstall stable first, then install dev. The commands below do that in order.
            """
        }
        if MacFUSEInfo.prefersFSKitBackend {
            return """
            Install macFUSE \(MacFUSEInfo.recommendedStableVersion) or newer. On \(HostOSInfo.marketingName), macFUSE uses Apple's FSKit backend — you do not need Reduced Security or a kernel extension.
            """
        }
        return """
        Install macFUSE \(MacFUSEInfo.recommendedStableVersion) or newer. macFUSE provides the hooks needed for FUSE filesystems (including ntfs-3g) on macOS.
        """
    }

    private var extensionApprovalBody: String {
        if MacFUSEInfo.prefersFSKitBackend {
            return """
            After installing macFUSE, open System Settings → Privacy & Security and allow the macFUSE file system extension if prompted. On \(HostOSInfo.marketingName) this uses the FSKit backend — no Recovery Mode or Reduced Security is required.
            """
        }
        return """
        After installing macFUSE, open System Settings → Privacy & Security and click "Allow" next to the Benjamin Fleischer system extension entry. On Apple Silicon you may also need to enable Reduced Security via Recovery Mode (one-time) when using the legacy kernel backend.
        """
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !homebrewLikelyInstalled {
                        homebrewCallout
                    }
                    statusSummary
                    step(
                        number: 1,
                        title: "Install macFUSE \(MacFUSEInfo.recommendedVersionForHost)+",
                        body: macFUSEStepBody,
                        commands: macFUSEInstallCommands,
                        installed: status.macFUSEInstalled && status.isMacFUSEVersionSupported && !status.macFUSEUpdateRecommended
                    )
                    if status.macFUSEInstalled && status.macFUSEUpdateRecommended,
                       let current = status.macFUSEVersion {
                        updateCallout(current: current)
                    }
                    step(
                        number: 2,
                        title: "Approve the system extension",
                        body: extensionApprovalBody,
                        commands: [],
                        installed: status.macFUSEInstalled && status.isMacFUSEVersionSupported
                    )
                    step(
                        number: 3,
                        title: "Install ntfs-3g",
                        body: "ntfs-3g is the actual NTFS read/write driver. The gromgit/fuse tap keeps an Apple-Silicon-friendly build current. If Homebrew asks you to trust the tap first, run the trust command below, then install.",
                        commands: [
                            "brew tap gromgit/fuse",
                            MacFUSEInfo.brewTrustNTFS3GFormula,
                            "brew install gromgit/fuse/ntfs-3g-mac"
                        ],
                        installed: status.ntfs3gPath != nil
                    )
                    step(
                        number: 4,
                        title: "Re-check from this app",
                        body: "Hit \"Re-check\" below — once both pieces are detected at supported versions, the banner turns green and you can mount NTFS drives read/write from the detail view.",
                        commands: [],
                        installed: status.isReady
                    )
                    if MacFUSEInfo.prefersFSKitBackend && !HostOSInfo.isMacOS27OrLater {
                        optionalDevReleaseNote
                    }
                }
                .padding(20)
            }

            Divider()
            footer
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 540, idealHeight: 620)
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Install NTFS Driver")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Required: macFUSE \(MacFUSEInfo.recommendedVersionForHost)+ and ntfs-3g on \(HostOSInfo.marketingName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var optionalDevReleaseNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Optional: macFUSE developer release")
                .font(.headline)
            Text("macFUSE \(MacFUSEInfo.recommendedDevVersion) (pre-release) adds performance improvements on macOS 26. Only install if you need bleeding-edge fixes.")
                .font(.callout)
                .foregroundStyle(.secondary)
            CommandBlock(command: MacFUSEInfo.brewInstallDev)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func updateCallout(current: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("macFUSE update available")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Installed: \(current) · Recommended: \(MacFUSEInfo.recommendedVersionForHost)+ on \(HostOSInfo.marketingName)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var homebrewLikelyInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew")
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew")
    }

    private var homebrewCallout: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("Homebrew required")
                    .font(.subheadline.weight(.semibold))
                Text("Install Homebrew from brew.sh first, then run the commands below in Terminal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Link("Install Homebrew", destination: URL(string: "https://brew.sh")!)
                    .font(.callout)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Status summary
    private var statusSummary: some View {
        HStack(spacing: 18) {
            statusPill(
                label: "macFUSE",
                installed: status.macFUSEInstalled && status.isMacFUSEVersionSupported,
                version: status.macFUSEVersion,
                warning: status.macFUSEUpdateRecommended ? "update available" : nil
            )
            statusPill(
                label: "ntfs-3g",
                installed: status.ntfs3gPath != nil,
                version: status.ntfs3gVersion,
                warning: nil
            )
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statusPill(label: String, installed: Bool, version: String?, warning: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: installed ? "checkmark.circle.fill" : (warning != nil ? "exclamationmark.circle.fill" : "xmark.circle.fill"))
                .foregroundStyle(installed ? .green : (warning != nil ? .orange : .red))
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.callout).fontWeight(.medium)
                if let warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(installed ? (version ?? "installed") : "not installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: Step row
    private func step(number: Int, title: String, body: String, commands: [String], installed: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(installed ? Color.green : Color.accentColor)
                    .frame(width: 26, height: 26)
                if installed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !commands.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(commands, id: \.self) { cmd in
                            CommandBlock(command: cmd)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    // MARK: Footer
    private var footer: some View {
        HStack(spacing: 10) {
            Link("Homebrew", destination: URL(string: "https://brew.sh")!)
                .font(.callout)
            Link("macFUSE releases", destination: URL(string: MacFUSEInfo.downloadURL)!)
                .font(.callout)
            Spacer()
            Button("Re-check") {
                Task { await driveManager.refreshDriverStatus() }
            }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct CommandBlock: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("$")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(command)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(command, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(copied ? "Copied" : "Copy to clipboard")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }
}

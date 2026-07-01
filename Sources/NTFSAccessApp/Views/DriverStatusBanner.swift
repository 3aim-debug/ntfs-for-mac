import SwiftUI
import NTFSAccessCore

/// Top-of-window banner showing macFUSE + ntfs-3g readiness.
struct DriverStatusBanner: View {
    @EnvironmentObject private var driveManager: DriveManager
    @Binding var showInstall: Bool
    @AppStorage("driverBannerCollapsed") private var collapsedWhenReady = false

    var body: some View {
        if isReady && collapsedWhenReady {
            collapsedBanner
        } else {
            expandedBanner
        }
    }

    private var isReady: Bool {
        status.isReady && !status.macFUSEUpdateRecommended
    }

    private var collapsedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
                .font(.caption)
            Text("NTFS driver ready")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Expand") { collapsedWhenReady = false }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color.green.opacity(0.06))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var expandedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            Spacer()

            if isReady {
                Button("Collapse") { collapsedWhenReady = true }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.caption)
                Button("Re-check") {
                    Task { await driveManager.refreshDriverStatus() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button(status.macFUSEInstalled ? "Update Driver…" : "Install Driver…") {
                    showInstall = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tint.opacity(0.07))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var status: NTFSDriverStatus { driveManager.driverStatus }

    private var tint: Color {
        if isReady { return .green }
        if status.macFUSEInstalled || status.ntfs3gPath != nil { return .orange }
        return .secondary
    }

    private var icon: String {
        if isReady { return "checkmark.shield.fill" }
        if status.macFUSEInstalled || status.ntfs3gPath != nil { return "exclamationmark.shield.fill" }
        return "shield"
    }

    private var title: String {
        if isReady { return "NTFS driver ready" }
        if status.macFUSEUpdateRecommended { return "macFUSE update recommended" }
        if !status.macFUSEInstalled && status.ntfs3gPath == nil { return "NTFS driver not installed" }
        if !status.macFUSEInstalled { return "macFUSE missing" }
        if status.macFUSEInstalled && !status.isMacFUSEVersionSupported { return "macFUSE version too old" }
        return "ntfs-3g not found"
    }

    private var subtitle: String {
        if isReady {
            let m = status.macFUSEVersion.map { "macFUSE \($0)" } ?? "macFUSE"
            let n = status.ntfs3gVersion ?? "ntfs-3g"
            return "\(m) · \(n) — select an NTFS volume and click Mount Read/Write"
        }
        if status.macFUSEUpdateRecommended, let current = status.macFUSEVersion {
            return "Installed \(current) · recommended \(MacFUSEInfo.recommendedVersionForHost)+ on \(HostOSInfo.marketingName)"
        }
        if status.macFUSEInstalled && !status.isMacFUSEVersionSupported, let current = status.macFUSEVersion {
            return "Upgrade macFUSE from \(current) to \(MacFUSEInfo.minimumSupportedVersionForHost)+"
        }
        return "Install macFUSE and ntfs-3g via Homebrew to enable read/write mounting."
    }
}

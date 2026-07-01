import SwiftUI
import NTFSAccessCore

struct ContentView: View {
    @EnvironmentObject private var driveManager: DriveManager
    @State private var selection: Drive.ID?
    @State private var filter: DriveFilter = .all
    @State private var showInstall = false

    var body: some View {
        VStack(spacing: 0) {
            DriverStatusBanner(showInstall: $showInstall)
            NavigationSplitView {
                DriveListView(
                    drives: filtered,
                    selection: $selection,
                    filter: $filter
                )
                .navigationSplitViewColumnWidth(
                    min: AppTheme.sidebarMinWidth,
                    ideal: AppTheme.sidebarIdealWidth
                )
            } detail: {
                if let id = selection, let drive = driveManager.drives.first(where: { $0.id == id }) {
                    DriveDetailView(drive: drive, showInstall: $showInstall)
                        .id(drive.id)
                } else {
                    EmptyDetailView(showInstall: $showInstall)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    driveManager.refresh()
                    Task { await driveManager.refreshDriverStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Re-scan drives and re-check NTFS driver")
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
        .sheet(isPresented: $showInstall) {
            InstallInstructionsView()
                .environmentObject(driveManager)
        }
    }

    private var filtered: [Drive] {
        switch filter {
        case .all:
            return driveManager.drives
        case .ntfsOnly:
            return driveManager.drives.filter { drive in
                if drive.isNTFS { return true }
                if case .confirmedFromBootSector = driveManager.ntfsStatus(drive) { return true }
                return false
            }
        case .mountedOnly:
            return driveManager.drives.filter { $0.isMounted }
        case .external:
            return driveManager.drives.filter { !$0.isInternal }
        }
    }
}

enum DriveFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case ntfsOnly = "NTFS"
    case mountedOnly = "Mounted"
    case external = "External"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .all: return "externaldrive"
        case .ntfsOnly: return "flag.fill"
        case .mountedOnly: return "checkmark.circle"
        case .external: return "cable.connector"
        }
    }
}

struct EmptyDetailView: View {
    @EnvironmentObject private var driveManager: DriveManager
    @Binding var showInstall: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 56))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text(AppInfo.displayName)
                    .font(.title.weight(.semibold))
                Text("Select a drive from the sidebar to view details, mount volumes, and enable NTFS read/write.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if !driveManager.driverStatus.isReady {
                Button {
                    showInstall = true
                } label: {
                    Label("Set Up NTFS Driver", systemImage: "shippingbox")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Label("Driver ready — pick an NTFS volume to mount read/write", systemImage: "checkmark.shield.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

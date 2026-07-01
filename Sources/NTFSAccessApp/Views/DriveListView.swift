import SwiftUI
import NTFSAccessCore

struct DriveListView: View {
    let drives: [Drive]
    @Binding var selection: Drive.ID?
    @Binding var filter: DriveFilter

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker("Filter", selection: $filter) {
                    ForEach(DriveFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Drive filter")

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Search drives", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.callout)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if visibleDrives.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(grouped, id: \.0) { parent, items in
                        Section(parent) {
                            ForEach(items) { drive in
                                DriveRow(drive: drive)
                                    .tag(drive.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var visibleDrives: [Drive] {
        guard !searchText.isEmpty else { return drives }
        let q = searchText.lowercased()
        return drives.filter {
            $0.displayName.lowercased().contains(q)
                || $0.bsdName.lowercased().contains(q)
                || ($0.volumeName?.lowercased().contains(q) ?? false)
                || ($0.model?.lowercased().contains(q) ?? false)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: filter == .ntfsOnly ? "flag.slash" : "externaldrive.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(emptySubtitle)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if !searchText.isEmpty { return "No matches" }
        switch filter {
        case .all: return "No drives found"
        case .ntfsOnly: return "No NTFS volumes"
        case .mountedOnly: return "Nothing mounted"
        case .external: return "No external drives"
        }
    }

    private var emptySubtitle: String {
        if !searchText.isEmpty { return "Try a different search term." }
        switch filter {
        case .all: return "Connect a drive or click Refresh."
        case .ntfsOnly: return "NTFS volumes appear here once detected."
        case .mountedOnly: return "Mount a volume to see it here."
        case .external: return "Plug in a USB or Thunderbolt drive."
        }
    }

    private var grouped: [(String, [Drive])] {
        let source = visibleDrives
        let parents = Set(source.compactMap { $0.parentBSDName })
            .union(source.filter { $0.isWholeDisk }.map { $0.bsdName })

        var result: [(String, [Drive])] = []
        for parent in parents.sorted() {
            let items = source
                .filter { $0.bsdName == parent || $0.parentBSDName == parent }
                .sorted { lhs, rhs in
                    if lhs.isWholeDisk != rhs.isWholeDisk { return lhs.isWholeDisk }
                    return lhs.bsdName < rhs.bsdName
                }
            if !items.isEmpty {
                result.append((sectionTitle(for: parent, items: items), items))
            }
        }

        let leftovers = source.filter { d in
            !d.isWholeDisk && (d.parentBSDName.map { !parents.contains($0) } ?? true)
        }
        if !leftovers.isEmpty {
            result.append(("Other", leftovers))
        }
        return result
    }

    private func sectionTitle(for parent: String, items: [Drive]) -> String {
        if parent == "Other" { return parent }
        let volumes = items.filter { !$0.isWholeDisk }
        if let model = volumes.compactMap(\.model).first {
            let vendor = volumes.compactMap(\.vendor).first
            let label = [vendor, model].compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !label.isEmpty { return label }
        }
        if let name = volumes.first(where: { $0.volumeName != nil })?.volumeName {
            return name
        }
        return parent
    }
}

private struct DriveRow: View {
    let drive: Drive
    @EnvironmentObject private var driveManager: DriveManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: DriveIcon.symbol(for: drive))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DriveIcon.color(for: drive, isNTFS: isNTFS))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(drive.displayName)
                        .font(.body)
                        .lineLimit(1)
                    if isNTFS {
                        NTFSBadge()
                    }
                }
                HStack(spacing: 6) {
                    Text(drive.bsdName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if drive.totalSize > 0 {
                        Text("•").foregroundStyle(.tertiary)
                        Text(drive.formattedSize)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if drive.isMounted {
                        Text("•").foregroundStyle(.tertiary)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption2)
                            .accessibilityLabel("Mounted")
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var isNTFS: Bool {
        if drive.isNTFS { return true }
        if case .confirmedFromBootSector = driveManager.ntfsStatus(drive) { return true }
        return false
    }
}

struct NTFSBadge: View {
    var body: some View {
        Text("NTFS")
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .foregroundStyle(.orange)
    }
}

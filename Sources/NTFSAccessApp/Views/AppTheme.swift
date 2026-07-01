import SwiftUI
import NTFSAccessCore

// Layout spacing used across views.

enum AppTheme {
    static let cardRadius: CGFloat = 10
    static let cardPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 16
    static let sidebarMinWidth: CGFloat = 300
    static let sidebarIdealWidth: CGFloat = 340
}

// MARK: - Card section

struct CardSection<Content: View>: View {
    let title: String
    var icon: String? = nil
    var tint: Color = .accentColor
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.headline)
                Spacer()
            }
            content()
        }
        .padding(AppTheme.cardPadding)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .strokeBorder(.quaternary.opacity(0.6), lineWidth: 0.5)
        )
    }
}

// MARK: - Feedback banner

struct FeedbackBanner: View {
    enum Style { case success, error }

    let message: String
    let style: Style
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: style == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(style == .success ? .green : .red)
                .font(.title3)

            Text(message)
                .font(.callout)
                .foregroundStyle(style == .success ? Color.primary : Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Dismiss")
                }
            }
        }
        .padding(12)
        .background(
            (style == .success ? Color.green : Color.red).opacity(0.08),
            in: RoundedRectangle(cornerRadius: AppTheme.cardRadius)
        )
    }
}

// MARK: - Drive icons

enum DriveIcon {
    static func symbol(for drive: Drive) -> String {
        if drive.isWholeDisk {
            return drive.isInternal ? "internaldrive.fill" : "externaldrive.fill"
        }
        switch drive.bus {
        case .usb:
            return "externaldrive.connected.to.line.below.fill"
        case .thunderbolt:
            return "bolt.fill"
        case .nvme, .sata, .internalBus:
            return "internaldrive.fill"
        default:
            return "externaldrive.fill"
        }
    }

    static func color(for drive: Drive, isNTFS: Bool) -> Color {
        if isNTFS { return .orange }
        if drive.isMounted { return .accentColor }
        return .secondary
    }
}

// MARK: - Detail info cell

struct DetailInfoCell: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .tracking(0.4)
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

import SwiftUI
import EddingsKit

struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: EISpacing.sectionGap) {
                settingsCard(title: "Data Sources") {
                    settingsRow(label: "SimpleFin", status: "Connected", statusColor: EIColor.emerald)
                    settingsRow(label: "Email (IMAP)", status: "Syncing", statusColor: EIColor.emerald)
                    settingsRow(label: "Slack", status: "Connected", statusColor: EIColor.emerald)
                    settingsRow(label: "Fathom (Meetings)", status: "Connected", statusColor: EIColor.emerald)
                    settingsRow(label: "VRAM Filesystem", status: "macOS only", statusColor: EIColor.textTertiary, isLast: true)
                }

                settingsCard(title: "Index Status") {
                    settingsRow(label: "Documents", status: "912,441", statusColor: EIColor.textPrimary)
                    settingsRow(label: "Email chunks", status: "282,103", statusColor: EIColor.textPrimary)
                    settingsRow(label: "Transcript chunks", status: "87,294", statusColor: EIColor.textPrimary)
                    settingsRow(label: "Slack messages", status: "13,512", statusColor: EIColor.textPrimary)
                    settingsRow(label: "Contacts", status: "847", statusColor: EIColor.textPrimary)
                    settingsRow(label: "Embeddings (512d)", status: "382,441", statusColor: EIColor.textPrimary, isLast: true)
                }

                settingsCard(title: "iCloud Sync") {
                    settingsRow(label: "Status", status: "Up to date", statusColor: EIColor.emerald)
                    settingsRow(label: "Last sync", status: "4 minutes ago", statusColor: EIColor.textPrimary)
                    settingsRow(label: "iCloud usage", status: "247 MB of 200 GB", statusColor: EIColor.textPrimary, isLast: true)
                }
            }
            .padding(EISpacing.detailPadding)
        }
        .background(EIColor.deep)
        .navigationTitle("Settings")
    }

    private func settingsCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(EITypography.bodyLarge())
                .foregroundStyle(EIColor.textPrimary)
                .padding(.bottom, 12)

            content()
        }
        .padding(EISpacing.cardPadding)
        .background(EIColor.card)
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: EIRadius.xl)
                .stroke(EIColor.border, lineWidth: 1)
        )
    }

    private func settingsRow(label: String, status: String, statusColor: Color, isLast: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(EITypography.body())
                    .foregroundStyle(EIColor.textSecondary)
                Spacer()
                Text(status)
                    .font(EITypography.body())
                    .foregroundStyle(statusColor)
            }
            .padding(.vertical, 8)

            if !isLast {
                Divider()
                    .background(EIColor.borderSubtle)
            }
        }
    }
}

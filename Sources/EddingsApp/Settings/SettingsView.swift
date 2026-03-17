import SwiftUI
import EddingsKit

struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var settingsVM

    var body: some View {
        ScrollView {
            VStack(spacing: EISpacing.sectionGap) {
                settingsCard(title: "Data Sources") {
                    ForEach(Array(settingsVM.syncSources.enumerated()), id: \.offset) { index, source in
                        VStack(spacing: 0) {
                            HStack {
                                Text(source.name)
                                    .font(EITypography.body())
                                    .foregroundStyle(EIColor.textSecondary)
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(source.status)
                                        .font(EITypography.body())
                                        .foregroundStyle(source.statusColor)
                                    Text(source.lastSync)
                                        .font(EITypography.caption())
                                        .foregroundStyle(EIColor.textTertiary)
                                }
                            }
                            .padding(.vertical, 8)
                            if index < settingsVM.syncSources.count - 1 {
                                Divider().background(EIColor.borderSubtle)
                            }
                        }
                    }
                }

                settingsCard(title: "Index Status") {
                    ForEach(Array(settingsVM.tableCounts.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 0) {
                            HStack {
                                Text(item.name)
                                    .font(EITypography.body())
                                    .foregroundStyle(EIColor.textSecondary)
                                Spacer()
                                Text(item.count.formatted())
                                    .font(EITypography.body())
                                    .foregroundStyle(EIColor.textPrimary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 8)
                            if index < settingsVM.tableCounts.count - 1 {
                                Divider().background(EIColor.borderSubtle)
                            }
                        }
                    }

                    Divider().background(EIColor.borderSubtle)
                    HStack {
                        Text("Embeddings (512d)")
                            .font(EITypography.body())
                            .foregroundStyle(EIColor.textSecondary)
                        Spacer()
                        Text(settingsVM.embeddingCount.formatted())
                            .font(EITypography.body())
                            .foregroundStyle(EIColor.textPrimary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 8)
                }

                #if os(macOS)
                settingsCard(title: "Database") {
                    HStack {
                        Text("Path")
                            .font(EITypography.body())
                            .foregroundStyle(EIColor.textSecondary)
                        Spacer()
                        Text(settingsVM.databasePath)
                            .font(EITypography.caption())
                            .foregroundStyle(EIColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 8)

                    Divider().background(EIColor.borderSubtle)

                    HStack {
                        Text("Size")
                            .font(EITypography.body())
                            .foregroundStyle(EIColor.textSecondary)
                        Spacer()
                        Text(settingsVM.databaseSize)
                            .font(EITypography.body())
                            .foregroundStyle(EIColor.textPrimary)
                    }
                    .padding(.vertical, 8)
                }
                #endif
            }
            .padding(EISpacing.detailPadding)
        }
        .background(EIColor.deep)
        .navigationTitle("Settings")
        .task { await settingsVM.load() }
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
}

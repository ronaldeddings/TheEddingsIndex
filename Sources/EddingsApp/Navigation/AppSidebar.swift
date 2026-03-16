import SwiftUI
import EddingsKit

struct AppSidebar: View {
    @Environment(EddingsEngine.self) private var engine

    var body: some View {
        @Bindable var engine = engine

        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: EISpacing.cardGap) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(EIColor.gold.gradient)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text("EI")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(EIColor.deep)
                            )
                        Text("The Eddings Index")
                            .font(EITypography.bodyLarge())
                            .foregroundStyle(EIColor.textPrimary)
                    }
                    .padding(.horizontal, EISpacing.sidebarPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }

                ForEach(EddingsEngine.SidebarSection.allCases) { section in
                    Button {
                        engine.selectedSection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.sfSymbol)
                                .frame(width: 18)
                                .foregroundStyle(engine.selectedSection == section ? EIColor.gold : EIColor.textTertiary)
                            Text(section.rawValue)
                                .font(EITypography.bodyLarge())
                                .foregroundStyle(engine.selectedSection == section ? EIColor.textPrimary : EIColor.textSecondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, EISpacing.sidebarPadding)
                        .background(
                            engine.selectedSection == section
                                ? EIColor.gold.opacity(0.10)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: EIRadius.sm))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }

                Spacer()
            }
            .frame(minWidth: EILayout.sidebarWidth)
            .background(EIColor.surface)
        } detail: {
            Group {
                switch engine.selectedSection {
                case .search:
                    SearchView()
                case .freedom:
                    FreedomDashboard()
                case .meetings:
                    MeetingList()
                case .people:
                    ContactList()
                case .settings:
                    SettingsView()
                }
            }
            .background(EIColor.deep)
        }
    }
}

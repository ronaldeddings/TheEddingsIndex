import SwiftUI
import EddingsKit

struct ContactList: View {
    @State private var searchText = ""
    @State private var selectedTab = "depth"

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("Relationships")
                    .font(EITypography.title())
                    .foregroundStyle(EIColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(EIColor.textTertiary)
                    TextField("Find a person or company...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(EITypography.bodySmall())
                }
                .padding(10)
                .background(EIColor.card)
                .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: EIRadius.md)
                        .stroke(EIColor.border, lineWidth: 1)
                )

                HStack(spacing: 4) {
                    ForEach(["depth", "recent", "fading", "companies"], id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab.capitalized)
                                .font(EITypography.caption())
                                .foregroundStyle(selectedTab == tab ? EIColor.textPrimary : EIColor.textTertiary)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(selectedTab == tab ? EIColor.elevated : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(EIColor.card)
                .clipShape(RoundedRectangle(cornerRadius: EIRadius.sm))
            }
            .padding(EISpacing.sidebarPadding)

            List {
                Section("Inner Circle") {
                    ContactRow(name: "Emily Humphrey", role: "COO, Hacker Valley Media", initials: "EH", depth: .high, emails: 127, meetings: 84, slack: 1247)
                    ContactRow(name: "Marcus Webb", role: "Content Lead, Hacker Valley", initials: "MW", depth: .high, emails: 45, meetings: 32, slack: 892)
                }
                Section("Growing") {
                    ContactRow(name: "Sarah Chen", role: "Head of Partnerships, Optro", initials: "SC", depth: .medium, emails: 18, meetings: 4, slack: 0)
                    ContactRow(name: "Jess Park", role: "DevRel Lead, Mozilla", initials: "JP", depth: .high, emails: 89, meetings: 26, slack: 45)
                }
                Section {
                    ContactRow(name: "Chris Cochran", role: "Co-host, Hacker Valley", initials: "CC", depth: .fading, emails: 67, meetings: 45, slack: 2100)
                } header: {
                    Text("Fading")
                        .foregroundStyle(EIColor.rose)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(EIColor.deep)
    }
}

struct ContactRow: View {
    let name: String
    let role: String
    let initials: String
    let depth: ContactDepth
    let emails: Int
    let meetings: Int
    let slack: Int

    enum ContactDepth {
        case high, medium, low, fading

        var color: Color {
            switch self {
            case .high: return EIColor.gold
            case .medium: return EIColor.indigo
            case .low: return EIColor.textTertiary
            case .fading: return EIColor.rose
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(depth.color.opacity(0.18))
                    .frame(width: 40, height: 40)
                if depth == .high {
                    Circle()
                        .stroke(depth.color.opacity(0.4), lineWidth: 2)
                        .frame(width: 44, height: 44)
                }
                Text(initials)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(depth.color)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textPrimary)
                Text(role)
                    .font(EITypography.caption())
                    .foregroundStyle(EIColor.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                if emails > 0 {
                    statChip("✉ \(emails)", color: EIColor.gold)
                }
                if meetings > 0 {
                    statChip("◉ \(meetings)", color: EIColor.violet)
                }
                if slack > 0 {
                    statChip("◈ \(slack > 999 ? "\(slack/1000)K" : "\(slack)")", color: EIColor.indigo)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(depth == .fading ? 0.7 : 1.0)
        .listRowBackground(Color.clear)
    }

    private func statChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(EITypography.micro())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

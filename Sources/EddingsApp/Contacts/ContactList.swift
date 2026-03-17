import SwiftUI
import EddingsKit

struct ContactList: View {
    @Environment(EddingsEngine.self) private var engine
    @State private var searchText = ""
    @State private var selectedTab = "depth"

    private var filteredContacts: [Contact] {
        let contacts = engine.contacts
        if searchText.isEmpty { return contacts }
        return contacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.email ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.role ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var innerCircle: [Contact] {
        filteredContacts.filter { totalInteractions($0) >= 100 }
    }

    private var growing: [Contact] {
        filteredContacts.filter { totalInteractions($0) >= 10 && totalInteractions($0) < 100 }
    }

    private var fading: [Contact] {
        filteredContacts.filter { totalInteractions($0) < 10 && totalInteractions($0) > 0 }
    }

    private func totalInteractions(_ c: Contact) -> Int {
        c.emailCount + c.meetingCount + c.slackCount
    }

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

            if engine.contacts.isEmpty {
                ContentUnavailableView("No Contacts", systemImage: "person.2", description: Text("Run ei-cli sync to import contacts"))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    if !innerCircle.isEmpty {
                        Section("Inner Circle") {
                            ForEach(innerCircle) { contact in
                                ContactRow(contact: contact, depth: .high)
                            }
                        }
                    }
                    if !growing.isEmpty {
                        Section("Growing") {
                            ForEach(growing) { contact in
                                ContactRow(contact: contact, depth: .medium)
                            }
                        }
                    }
                    if !fading.isEmpty {
                        Section {
                            ForEach(fading) { contact in
                                ContactRow(contact: contact, depth: .fading)
                            }
                        } header: {
                            Text("Fading")
                                .foregroundStyle(EIColor.rose)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(EIColor.deep)
        .onAppear { engine.loadContacts() }
    }
}

struct ContactRow: View {
    let contact: Contact
    let depth: ContactDepth

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

    private var initials: String {
        let parts = contact.name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))"
        }
        return String(contact.name.prefix(2)).uppercased()
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
                Text(contact.name)
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textPrimary)
                if let role = contact.role, !role.isEmpty {
                    Text(role)
                        .font(EITypography.caption())
                        .foregroundStyle(EIColor.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if contact.emailCount > 0 {
                    statChip("✉ \(contact.emailCount)", color: EIColor.gold)
                }
                if contact.meetingCount > 0 {
                    statChip("◉ \(contact.meetingCount)", color: EIColor.violet)
                }
                if contact.slackCount > 0 {
                    let display = contact.slackCount > 999 ? "\(contact.slackCount/1000)K" : "\(contact.slackCount)"
                    statChip("◈ \(display)", color: EIColor.indigo)
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

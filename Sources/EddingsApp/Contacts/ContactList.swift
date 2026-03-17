import SwiftUI
import EddingsKit

struct ContactContentList: View {
    @Environment(PeopleViewModel.self) private var peopleVM

    var body: some View {
        @Bindable var peopleVM = peopleVM

        VStack(spacing: 0) {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Relationships")
                        .font(EITypography.display())
                        .foregroundStyle(EIColor.textPrimary)
                    Text("\(peopleVM.scoredContacts.count) contacts across email, meetings, and Slack")
                        .font(EITypography.bodySmall())
                        .foregroundStyle(EIColor.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(EIColor.textTertiary)
                    TextField("Find a person or company...", text: $peopleVM.searchFilter)
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

                PillToggle(selection: $peopleVM.selectedTab)
            }
            .padding(EISpacing.sidebarPadding)

            if peopleVM.scoredContacts.isEmpty {
                ContentUnavailableView("No Contacts", systemImage: "person.2", description: Text("Run ei-cli sync to import contacts"))
                    .frame(maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { peopleVM.selectedContactId },
                    set: { id in Task { await peopleVM.selectContact(id) } }
                )) {
                    if peopleVM.selectedTab == .companies {
                        ForEach(peopleVM.companies) { company in
                            let companyContacts = peopleVM.filteredContacts.filter { $0.contact.companyId == company.id }
                            if !companyContacts.isEmpty {
                                Section(company.name) {
                                    ForEach(companyContacts, id: \.contact.id) { score in
                                        ContactRow(score: score)
                                            .tag(score.contact.id)
                                    }
                                }
                            }
                        }
                    } else if peopleVM.selectedTab == .depth {
                        if !peopleVM.innerCircle.isEmpty {
                            Section("Inner Circle") {
                                ForEach(peopleVM.innerCircle, id: \.contact.id) { score in
                                    ContactRow(score: score)
                                        .tag(score.contact.id)
                                }
                            }
                        }
                        if !peopleVM.growing.isEmpty {
                            Section("Growing") {
                                ForEach(peopleVM.growing, id: \.contact.id) { score in
                                    ContactRow(score: score)
                                        .tag(score.contact.id)
                                }
                            }
                        }
                        if !peopleVM.peripheral.isEmpty {
                            Section("Peripheral") {
                                ForEach(peopleVM.peripheral, id: \.contact.id) { score in
                                    ContactRow(score: score)
                                        .tag(score.contact.id)
                                }
                            }
                        }
                    } else {
                        ForEach(peopleVM.filteredContacts, id: \.contact.id) { score in
                            ContactRow(score: score)
                                .tag(score.contact.id)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(EIColor.surface)
        .task { await peopleVM.load() }
    }
}

struct ContactRow: View {
    let score: RelationshipScorer.RelationshipScore

    private var depth: ContactDepth {
        switch score.depth {
        case .deep: return .deep
        case .growing: return .growing
        case .peripheral: return .peripheral
        case .fading: return .fading
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                DepthBadge(name: score.contact.name, depth: depth)
                if score.isFading {
                    Circle()
                        .fill(EIColor.rose)
                        .frame(width: 6, height: 6)
                        .offset(x: 16, y: -16)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(score.contact.name)
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textPrimary)
                if let role = score.contact.role, !role.isEmpty {
                    Text(role)
                        .font(EITypography.caption())
                        .foregroundStyle(EIColor.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if score.contact.emailCount > 0 {
                    StatChip(icon: "envelope.fill", count: score.contact.emailCount, color: EIColor.gold)
                }
                if score.contact.meetingCount > 0 {
                    StatChip(icon: "video.fill", count: score.contact.meetingCount, color: EIColor.violet)
                }
                if score.contact.slackCount > 0 {
                    StatChip(icon: "bubble.left.fill", count: score.contact.slackCount, color: EIColor.indigo)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(score.isFading ? 0.7 : 1.0)
        .listRowBackground(Color.clear)
    }
}

struct ContactDetailView: View {
    @Environment(PeopleViewModel.self) private var peopleVM

    var body: some View {
        if let detail = peopleVM.contactDetail {
            ScrollView {
                VStack(alignment: .leading, spacing: EISpacing.sectionGap) {
                    VStack(spacing: 12) {
                        DepthBadge(name: detail.contact.name, depth: detail.depth, size: 72)
                        Text(detail.contact.name)
                            .font(EITypography.headline())
                            .foregroundStyle(EIColor.textPrimary)
                        if let role = detail.contact.role {
                            Text(role)
                                .font(EITypography.body())
                                .foregroundStyle(EIColor.textSecondary)
                        }

                        HStack(spacing: 16) {
                            StatChip(icon: "envelope.fill", count: detail.contact.emailCount, color: EIColor.gold)
                            StatChip(icon: "video.fill", count: detail.contact.meetingCount, color: EIColor.violet)
                            StatChip(icon: "bubble.left.fill", count: detail.contact.slackCount, color: EIColor.indigo)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    RelationshipStrengthBar(
                        depth: detail.depth,
                        strengthPercent: detail.strengthPercent,
                        tenure: detail.tenure,
                        totalInteractions: detail.totalInteractions
                    )

                    if !detail.insightText.isEmpty {
                        InsightCard(label: "PAI Relationship Insight", text: detail.insightText)
                    }

                    if !peopleVM.timeline.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TIMELINE")
                                .font(EITypography.label())
                                .foregroundStyle(EIColor.textTertiary)
                            InteractionTimeline(items: peopleVM.timeline)
                        }
                    }
                }
                .padding(EISpacing.detailPadding)
            }
            .background(EIColor.deep)
        }
    }
}

struct RelationshipStrengthBar: View {
    let depth: ContactDepth
    let strengthPercent: Double
    let tenure: String
    let totalInteractions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Relationship Strength")
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textSecondary)
                Text("— \(depth.label)")
                    .font(EITypography.bodySmall())
                    .foregroundStyle(depth.ringColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(EIColor.elevated)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(depth.ringColor)
                        .frame(width: geo.size.width * min(strengthPercent / 100, 1.0), height: 6)
                }
            }
            .frame(height: 6)

            Text("\(totalInteractions) total interactions over \(tenure)")
                .font(EITypography.caption())
                .foregroundStyle(EIColor.textTertiary)
        }
        .padding(EISpacing.cardPadding)
        .background(EIColor.card)
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
    }
}

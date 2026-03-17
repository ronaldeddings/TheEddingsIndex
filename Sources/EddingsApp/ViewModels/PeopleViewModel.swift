import SwiftUI
import EddingsKit
import GRDB

enum PeopleTab: String, CaseIterable, CustomStringConvertible, Sendable {
    case depth = "By Depth"
    case recent = "Recent"
    case fading = "Fading"
    case companies = "Companies"

    var description: String { rawValue }
}

@MainActor
@Observable
final class PeopleViewModel {
    var scoredContacts: [RelationshipScorer.RelationshipScore] = []
    var selectedContactId: Int64?
    var selectedTab: PeopleTab = .depth
    var searchFilter: String = ""
    var contactDetail: ContactDetail?
    var timeline: [TimelineItem] = []
    var companies: [Company] = []
    var isLoading = false

    struct ContactDetail: Sendable {
        let contact: Contact
        let depth: ContactDepth
        let company: Company?
        let strengthPercent: Double
        let tenure: String
        let totalInteractions: Int
        let insightText: String
    }

    @ObservationIgnored private let dataAccess: DataAccess?
    @ObservationIgnored private let scorer: RelationshipScorer?

    init(dataAccess: DataAccess?, dbPool: DatabasePool?) {
        self.dataAccess = dataAccess
        self.scorer = dbPool.map { RelationshipScorer(dbPool: $0) }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let scorer {
                scoredContacts = try scorer.scoreAll()
            }
            if let da = dataAccess {
                companies = try da.allCompanies()
            }
        } catch {
            scoredContacts = []
        }
    }

    var filteredContacts: [RelationshipScorer.RelationshipScore] {
        var list = scoredContacts
        if !searchFilter.isEmpty {
            let q = searchFilter.lowercased()
            list = list.filter { score in
                score.contact.name.lowercased().contains(q) ||
                (score.contact.email?.lowercased().contains(q) ?? false) ||
                (score.contact.role?.lowercased().contains(q) ?? false)
            }
        }
        switch selectedTab {
        case .depth:
            return list
        case .recent:
            return list.sorted { a, b in
                (a.contact.lastSeenAt ?? .distantPast) > (b.contact.lastSeenAt ?? .distantPast)
            }
        case .fading:
            return list.filter { $0.isFading }
        case .companies:
            return list
        }
    }

    var innerCircle: [RelationshipScorer.RelationshipScore] {
        filteredContacts.filter { $0.totalInteractions >= 100 }
    }

    var growing: [RelationshipScorer.RelationshipScore] {
        filteredContacts.filter { $0.totalInteractions >= 10 && $0.totalInteractions < 100 }
    }

    var peripheral: [RelationshipScorer.RelationshipScore] {
        filteredContacts.filter { $0.totalInteractions < 10 && $0.totalInteractions > 0 }
    }

    func selectContact(_ id: Int64?) async {
        selectedContactId = id
        guard let id, let da = dataAccess else {
            contactDetail = nil
            timeline = []
            return
        }

        do {
            guard let contact = try da.fetchContact(id: id) else { return }
            let score = scoredContacts.first { $0.contact.id == id }
            let company = try da.companyForContact(contact)

            let maxInteractions = scoredContacts.first?.totalInteractions ?? 1
            let total = score?.totalInteractions ?? 0
            let strengthPct = Double(total) / Double(max(maxInteractions, 1)) * 100

            let depth = mapDepth(score?.depth)
            let tenure = buildTenure(contact)
            let insight = buildInsight(contact: contact, score: score)

            contactDetail = ContactDetail(
                contact: contact,
                depth: depth,
                company: company,
                strengthPercent: min(strengthPct, 100),
                tenure: tenure,
                totalInteractions: total,
                insightText: insight
            )

            let items = try da.interactionTimeline(
                contactName: contact.name,
                contactEmail: contact.email,
                limit: 20
            )
            timeline = items.map { rec in
                TimelineItem(
                    id: rec.id,
                    source: mapTableToSource(rec.sourceTable),
                    title: rec.title,
                    detail: rec.detail,
                    date: rec.date
                )
            }
        } catch {
            contactDetail = nil
            timeline = []
        }
    }

    private func mapDepth(_ depth: RelationshipScorer.RelationshipScore.Depth?) -> ContactDepth {
        switch depth {
        case .deep: return .deep
        case .growing: return .growing
        case .peripheral: return .peripheral
        case .fading: return .fading
        case .none: return .peripheral
        }
    }

    private func mapTableToSource(_ table: SearchResult.SourceTable) -> EISource {
        switch table {
        case .emailChunks: return .email
        case .slackChunks: return .slack
        case .transcriptChunks: return .transcript
        case .meetings: return .meeting
        case .documents: return .file
        case .financialTransactions: return .finance
        case .contacts: return .email
        }
    }

    private func buildTenure(_ contact: Contact) -> String {
        guard let first = contact.firstSeenAt else { return "Unknown" }
        let years = Calendar.current.dateComponents([.year, .month], from: first, to: Date())
        if let y = years.year, y > 0 {
            return "\(y) year\(y == 1 ? "" : "s")"
        }
        if let m = years.month, m > 0 {
            return "\(m) month\(m == 1 ? "" : "s")"
        }
        return "Recent"
    }

    private func buildInsight(contact: Contact, score: RelationshipScorer.RelationshipScore?) -> String {
        let total = score?.totalInteractions ?? 0
        var text = "\(contact.name) has \(total) total interactions."
        if contact.emailCount > 0 { text += " \(contact.emailCount) emails." }
        if contact.meetingCount > 0 { text += " \(contact.meetingCount) meetings." }
        if contact.slackCount > 0 { text += " \(contact.slackCount) Slack messages." }
        if score?.isFading == true {
            text += " Communication has been declining recently."
        }
        return text
    }
}

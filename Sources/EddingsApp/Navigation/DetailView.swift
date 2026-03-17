import SwiftUI
import EddingsKit

struct DetailView: View {
    @Environment(EddingsEngine.self) private var engine
    @Environment(SearchViewModel.self) private var searchVM
    @Environment(PeopleViewModel.self) private var peopleVM
    @Environment(MeetingsViewModel.self) private var meetingsVM

    var body: some View {
        switch engine.selectedSection {
        case .search:
            if searchVM.selectedResult != nil {
                SearchDetailView()
            } else {
                emptyState("Select a result", subtitle: "Search results appear here")
            }
        case .people:
            if peopleVM.contactDetail != nil {
                ContactDetailView()
            } else {
                emptyState("Select a contact", subtitle: "Relationship details appear here")
            }
        case .meetings:
            if meetingsVM.meetingDetail != nil {
                MeetingDetailView()
            } else {
                emptyState("Select a meeting", subtitle: "Meeting details appear here")
            }
        case .freedom, .settings:
            emptyState("", subtitle: "")
        }
    }

    private func emptyState(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(EITypography.title())
                    .foregroundStyle(EIColor.textTertiary)
            }
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textTertiary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

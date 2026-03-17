import SwiftUI
import EddingsKit

struct ContentListView: View {
    @Environment(EddingsEngine.self) private var engine

    var body: some View {
        switch engine.selectedSection {
        case .search:
            SearchContentList()
        case .freedom:
            FreedomDashboard()
        case .meetings:
            MeetingContentList()
        case .people:
            ContactContentList()
        case .settings:
            SettingsView()
        }
    }
}

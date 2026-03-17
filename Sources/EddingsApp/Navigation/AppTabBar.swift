import SwiftUI
import EddingsKit

struct AppTabBar: View {
    @Environment(EddingsEngine.self) private var engine

    var body: some View {
        @Bindable var engine = engine

        TabView(selection: $engine.selectedSection) {
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                NavigationStack {
                    SearchContentList()
                }
            }
            Tab("Freedom", systemImage: "dollarsign.circle", value: .freedom) {
                NavigationStack {
                    FreedomDashboard()
                }
            }
            Tab("People", systemImage: "person.2", value: .people) {
                NavigationStack {
                    ContactContentList()
                }
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .tint(EIColor.gold)
    }
}

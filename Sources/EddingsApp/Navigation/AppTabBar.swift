import SwiftUI
import EddingsKit

struct AppTabBar: View {
    @Environment(EddingsEngine.self) private var engine

    var body: some View {
        @Bindable var engine = engine

        TabView(selection: $engine.selectedSection) {
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                SearchView()
            }
            Tab("Freedom", systemImage: "dollarsign.circle", value: .freedom) {
                FreedomDashboard()
            }
            Tab("People", systemImage: "person.2", value: .people) {
                ContactList()
            }
            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView()
            }
        }
        .tint(EIColor.gold)
    }
}

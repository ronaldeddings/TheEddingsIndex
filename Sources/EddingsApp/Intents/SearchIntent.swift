import AppIntents

struct SearchEddingsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Eddings Index"
    static let description: IntentDescription = "Search across emails, meetings, documents, and financial data"

    @Parameter(title: "Query")
    var query: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: "Search results for: \(query)")
    }
}

struct EddingsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchEddingsIntent(),
            phrases: [
                "Search \(.applicationName) for \(\.$query)",
                "Find in \(.applicationName) \(\.$query)"
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
    }
}

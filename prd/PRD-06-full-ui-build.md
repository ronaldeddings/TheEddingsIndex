# PRD-06: Full UI Build — The Eddings Index

**Status:** Draft
**Author:** PAI
**Date:** 2026-03-17
**Target:** macOS 15+ / iOS 18+
**Swift:** 6 (strict concurrency)
**Dependencies:** GRDB.swift 7+, USearch 2+, Swift Charts, SwiftUIDebugKit (DEBUG only)
**Design Source:** `mockups/ei-app.html`, `ei-freedom.html`, `ei-people.html`, `ei-mobile.html`, `brand-guide.html`, `design-tokens.json`
**Apple Docs Reference:** `/Volumes/VRAM/80-89_Resources/80_Reference/docs/apple-developer-docs/`

---

## 1. Problem Statement

TheEddingsIndex has a complete data layer (EddingsKit: 7,116 LOC, 15 models, hybrid search, financial intelligence, relationship scoring) and a polished design system (6 HTML mockups, 245-line design token JSON). But the SwiftUI app layer is a thin shell:

- **Search**: UI captures input but never calls `engine.performSearch()`. No result selection. No detail column.
- **Freedom Dashboard**: Gauge + 4 stat cards exist. Missing: spending categories, debt paydown, income streams, recent transactions, projection scenarios, AI insight cards, sparklines, period toggles.
- **People**: Contact list renders with depth sections. Missing: detail view, relationship strength bar, interaction timeline, PAI insights, fading indicators, company grouping, "By Depth / Recent / Fading / Companies" tab filtering.
- **3-Column Layout**: Sidebar navigates but there's no center list column + detail column separation. The mockup shows a true 3-column NavigationSplitView (240px sidebar, 380px content list, flex detail).
- **iOS**: TabView exists with 4 tabs. Missing: widget strip, AI insight card, proper mobile-optimized content for each screen.
- **Settings**: All values hard-coded. No live sync status, index counts, or iCloud metrics.
- **Design System Components**: Missing reusable components — source icons, insight cards, gauge, timeline, sparklines, depth badges, stat chips.
- **Charts**: Zero Swift Charts usage. Mockups show bar charts (spending, debt, income), sparklines (net worth), proportional bars.
- **Animations**: Zero animations. Mockups specify 180ms hover, 300ms transitions, 1500ms gauge fill, staggered card fade-in.
- **Debug Integration**: SwiftUIDebugKit not integrated. No way for Claude Code to inspect view hierarchy, read @State, or profile body evaluations during development.

This PRD closes every gap between the mockups and the running app, connecting all UI to real EddingsKit data.

---

## 2. Goals

1. **Pixel-match the mockups** — Every screen (Search, Freedom, People, Settings) matches `ei-app.html`, `ei-freedom.html`, `ei-people.html`, `ei-mobile.html` on their respective platforms.
2. **Real data everywhere** — Zero hard-coded values. Every number, name, date, and metric comes from EddingsKit (DatabaseManager, QueryEngine, FreedomTracker, RelationshipScorer, ActivityDigest, StateManager).
3. **Apple-documented patterns** — NavigationSplitView (3-column), TabView, @Observable, Swift Charts, searchable modifier, EnvironmentValues, animations — all per official Apple documentation.
4. **Reusable component library** — Source icons, insight cards, gauge, timeline, sparklines, stat chips — built once, used across all screens.
5. **SwiftUIDebugKit integration** — One-line `.debugInspectable()` in DEBUG builds for Claude Code automation.
6. **Platform-adaptive** — macOS: 3-column NavigationSplitView. iOS: TabView with 4 tabs. Shared views adapt via `#if os()` and `horizontalSizeClass`.

---

## 3. Non-Goals

- Push notifications or Live Activities (future PRD)
- Siri Shortcuts full implementation (SearchIntent stays stubbed; future PRD)
- iCloud sync UI beyond status display (sync logic exists in EddingsKit)
- AI-generated insight text (PAI integration is future; this PRD uses template-based insights from data)
- Onboarding / first-run experience
- Drag-and-drop or keyboard navigation polish

---

## 4. Architecture

### 4.1 View Model Layer — @Observable Classes

**Apple Docs Reference:** `Observation/Observable/README.md`, `Observation/README.md`

The current `EddingsEngine` is a single monolithic `@Observable` class. This PRD refactors into **feature-scoped view models** that own their data lifecycle, while `EddingsEngine` becomes the coordinator that holds shared infrastructure (dbPool, queryEngine, vectorIndex).

```
EddingsEngine (@Observable, @MainActor)
  ├── dbManager: DatabaseManager
  ├── queryEngine: QueryEngine
  ├── vectorIndex: VectorIndex
  ├── selectedSection: SidebarSection
  │
  ├── searchVM: SearchViewModel
  ├── freedomVM: FreedomViewModel
  ├── peopleVM: PeopleViewModel
  ├── meetingsVM: MeetingsViewModel
  └── settingsVM: SettingsViewModel
```

Each feature view model is `@Observable` and `@MainActor`, holds its own state, and performs async data loading via the shared `dbPool` and actors.

**Why feature-scoped VMs:** The mockups show 4 distinct screens with independent state (search query/results, freedom period toggle, people depth filter, settings sync status). A single VM forces all views to re-evaluate on any state change. Feature VMs isolate observation tracking — per Apple docs: "Only tracked properties trigger onChange" (`Observation/README.md`).

**Pattern (per Apple docs):**
```swift
@Observable
final class SearchViewModel {
    var results: [SearchResult] = []
    var query: String = ""
    var isSearching = false
    @ObservationIgnored let queryEngine: QueryEngine
}
```

### 4.2 Navigation Structure

**macOS — NavigationSplitView (3-column)**

**Apple Docs Reference:** `SwiftUI/NavigationSplitView/README.md`

```swift
NavigationSplitView(columnVisibility: $columnVisibility) {
    SidebarView()                    // 240px — nav items, logo, mini gauge
} content: {
    ContentListView(section: selectedSection)  // 380px — result/contact/meeting/transaction list
} detail: {
    DetailView(section: selectedSection)        // flex — full content, timeline, charts
}
.navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)  // sidebar
```

Per Apple docs: "Use a three-column split view to show three columns of content... NavigationSplitView collapses into a NavigationStack on narrow sizes."

**iOS — TabView**

**Apple Docs Reference:** `SwiftUI/TabView/README.md`

```swift
TabView(selection: $selectedTab) {
    Tab("Search", systemImage: "magnifyingglass", value: .search) { SearchScreen() }
    Tab("Freedom", systemImage: "dollarsign.circle.fill", value: .freedom) { FreedomScreen() }
    Tab("People", systemImage: "person.2.fill", value: .people) { PeopleScreen() }
    Tab("Settings", systemImage: "gearshape.fill", value: .settings) { SettingsScreen() }
}
.tint(EIColor.gold)
```

### 4.3 Environment Injection

**Apple Docs Reference:** `SwiftUI/Environment/README.md`, `SwiftUI/EnvironmentValues/README.md`

```swift
@main struct EddingsApp: App {
    @State private var engine = EddingsEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(engine)
                .environment(engine.searchVM)
                .environment(engine.freedomVM)
                .environment(engine.peopleVM)
                .environment(engine.meetingsVM)
                .environment(engine.settingsVM)
                #if DEBUG
                .debugInspectable()
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        #endif
    }
}
```

Per Apple docs: Use `@Environment(SearchViewModel.self) var searchVM` in views to read type-based observable objects.

### 4.4 SwiftUIDebugKit Integration

**Source:** `/Volumes/VRAM/00-09_System/01_Tools/conversift/SwiftUIDebugKit-Conversift/`

Add to `Package.swift`:
```swift
.package(path: "/Volumes/VRAM/00-09_System/01_Tools/conversift/SwiftUIDebugKit-Conversift")
```

Add to EddingsApp target dependencies:
```swift
.product(name: "SwiftUIDebugKit", package: "SwiftUIDebugMCP", condition: .when(platforms: [.macOS]))
```

One-line integration in `EddingsApp.swift`:
```swift
#if DEBUG
.debugInspectable()
#endif
```

This gives Claude Code 21 MCP tools: `read_hierarchy`, `read_view_tree`, `read_state`, `read_performance`, `screenshot`, `click`, `type_text`, `find_element`, etc. Zero release impact due to `#if DEBUG`.

---

## 5. Component Library

All reusable components live in `Sources/EddingsApp/Components/`. Each component follows the design tokens from `mockups/design-tokens.json` and `Theme/DesignTokens.swift`.

### 5.1 SourceIcon

The source identity badge used everywhere in the mockups (28px colored square with SF Symbol).

```swift
// Component: SourceIcon.swift
struct SourceIcon: View {
    let source: EISource
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: source.sfSymbol)
            .font(.system(size: size * 0.46))
            .foregroundStyle(source.color)
            .frame(width: size, height: size)
            .background(source.dimColor)
            .clipShape(RoundedRectangle(cornerRadius: EIRadius.sm))
    }
}
```

**Design tokens:** 28px size, 6px radius, 13px font (46% of size), 12% opacity background per `design-tokens.json` → `components.sourceIcon`.

**Apple Docs Reference:** `SwiftUI/Image/README.md`, `SwiftUI/RoundedRectangle/README.md`

### 5.2 InsightCard

PAI insight cards with indigo left border, used on Freedom Dashboard and People detail.

```swift
// Component: InsightCard.swift
struct InsightCard: View {
    let label: String      // e.g. "PAI FINANCIAL INSIGHT"
    let text: String       // insight body
    var accentColor: Color = EIColor.indigo

    var body: some View {
        HStack(spacing: 0) {
            accentColor.frame(width: 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(accentColor).frame(width: 8, height: 8)
                    Text(label)
                        .font(EITypography.label())
                        .foregroundStyle(accentColor)
                        .textCase(.uppercase)
                }
                Text(text)
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textSecondary)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        }
        .background(EIColor.card)
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
    }
}
```

**Design tokens:** 3px left border, [12,14] padding, 200px width (flexible in this context), 4 variants per `components.insightCard`.

### 5.3 FreedomGauge

Circular gauge showing velocity percentage, used on Freedom Dashboard (220px macOS, 180px iOS) and sidebar mini variant.

```swift
// Component: FreedomGauge.swift
struct FreedomGauge: View {
    let weeklyAmount: Double
    let weeklyTarget: Double
    var size: CGFloat = 220
    var strokeWidth: CGFloat = 10

    private var progress: Double { min(weeklyAmount / weeklyTarget, 1.0) }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(EIColor.elevated, lineWidth: strokeWidth)
            // Fill ring (gold gradient)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [Color(red: 0.83, green: 0.58, blue: 0.18),
                                 Color(red: 0.94, green: 0.75, blue: 0.38)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.5), value: progress)
            // Center labels
            VStack(spacing: 2) {
                Text(weeklyAmount.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                    .font(EITypography.metric())
                    .foregroundStyle(EIColor.gold)
                Text("of \(weeklyTarget.formatted(.currency(code: "USD").precision(.fractionLength(0)))) / week")
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textTertiary)
                Text("\(Int(progress * 100))%")
                    .font(EITypography.bodyLarge())
                    .foregroundStyle(EIColor.textPrimary)
            }
        }
        .frame(width: size, height: size)
    }
}
```

**Design tokens:** macOS: 220 size, 10 stroke. iOS: 180, 12 stroke. Mini (sidebar): 4 height (linear bar). Gauge fill animation: 1500ms decelerate per `motion.semantic.gaugeFill`.

**Apple Docs Reference:** `SwiftUI/Circle/README.md`, `SwiftUI/AngularGradient/README.md`, animation per `SwiftUI/Animations/README.md`

### 5.4 StatCard

Metric card for the Freedom Dashboard 2x2 grid. Title + value + optional change indicator + optional detail.

```swift
// Component: StatCard.swift
struct StatCard: View {
    let title: String
    let value: String
    var change: String? = nil
    var changePositive: Bool = true
    var detail: String? = nil
    var accentColor: Color = EIColor.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(EITypography.label())
                .foregroundStyle(EIColor.textTertiary)
            Text(value)
                .font(EITypography.display())
                .foregroundStyle(accentColor)
            if let change {
                Text(change)
                    .font(EITypography.caption())
                    .foregroundStyle(changePositive ? EIColor.emerald : EIColor.rose)
            }
            if let detail {
                Text(detail)
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(EISpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EIColor.card)
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
    }
}
```

### 5.5 DepthBadge

Contact depth indicator — colored ring around avatar based on interaction count.

```swift
// Component: DepthBadge.swift
struct DepthBadge: View {
    let name: String
    let depth: RelationshipScorer.RelationshipScore.Depth
    var size: CGFloat = 40

    private var ringColor: Color {
        switch depth {
        case .deep: return EIColor.gold
        case .growing: return EIColor.indigo
        case .peripheral: return EIColor.textTertiary
        case .fading: return EIColor.rose
        }
    }

    private var bgColor: Color {
        switch depth {
        case .deep: return EIColor.goldDim
        case .growing: return EIColor.indigoDim
        case .peripheral: return EIColor.elevated
        case .fading: return EIColor.roseDim
        }
    }

    var body: some View {
        Text(initials(from: name))
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(ringColor)
            .frame(width: size, height: size)
            .background(bgColor)
            .clipShape(Circle())
            .overlay(Circle().stroke(ringColor, lineWidth: 2))
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? parts.last!.prefix(1) : ""
        return "\(first)\(last)".uppercased()
    }
}
```

**Design tokens:** Avatar sizes: mini (20), small (28), medium (40), large (72) per `components.avatar`.

### 5.6 InteractionTimeline

Vertical timeline showing interactions with a contact, used in People detail view.

```swift
// Component: InteractionTimeline.swift
struct InteractionTimeline: View {
    let items: [TimelineItem]

    struct TimelineItem: Identifiable {
        let id: String
        let source: EISource
        let title: String
        let detail: String
        let date: Date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 12) {
                    // Vertical line + dot
                    VStack(spacing: 0) {
                        Circle()
                            .fill(item.source.color)
                            .frame(width: 8, height: 8)
                        if item.id != items.last?.id {
                            Rectangle()
                                .fill(EIColor.border)
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 8)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            SourceIcon(source: item.source, size: 20)
                            Text(item.title)
                                .font(EITypography.bodySmall())
                                .foregroundStyle(EIColor.textPrimary)
                        }
                        Text(item.detail)
                            .font(EITypography.caption())
                            .foregroundStyle(EIColor.textSecondary)
                            .lineLimit(2)
                        Text(item.date, style: .relative)
                            .font(EITypography.caption())
                            .foregroundStyle(EIColor.textTertiary)
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }
}
```

### 5.7 MiniSparkline

Small bar/line chart for inline trends (net worth, spending). Uses Swift Charts.

**Apple Docs Reference:** `Charts/README.md`, `Charts/LineMark/README.md`, `Charts/BarMark/README.md`

```swift
// Component: MiniSparkline.swift
import Charts

struct MiniSparkline: View {
    let data: [Double]
    var color: Color = EIColor.emerald
    var height: CGFloat = 32

    var body: some View {
        Chart(Array(data.enumerated()), id: \.offset) { index, value in
            LineMark(
                x: .value("Day", index),
                y: .value("Value", value)
            )
            .foregroundStyle(color)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Day", index),
                y: .value("Value", value)
            )
            .foregroundStyle(color.opacity(0.1))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: height)
    }
}
```

### 5.8 CategoryBar

Horizontal proportional bar showing spending/income by category. Used on Freedom Dashboard.

```swift
// Component: CategoryBar.swift
struct CategoryBar: View {
    let items: [(label: String, amount: Double, color: Color)]

    private var total: Double { items.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Proportional bar
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        item.color
                            .frame(width: max(geo.size.width * (item.amount / total), 2))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .frame(height: 6)

            // Legend rows
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack {
                    Circle().fill(item.color).frame(width: 6, height: 6)
                    Text(item.label)
                        .font(EITypography.bodySmall())
                        .foregroundStyle(EIColor.textSecondary)
                    Spacer()
                    Text(item.amount.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                        .font(EITypography.bodySmall())
                        .foregroundStyle(EIColor.textPrimary)
                        .monospacedDigit()
                }
            }
        }
    }
}
```

### 5.9 CardContainer

Standardized card wrapper used across all screens.

```swift
// Component: CardContainer.swift
struct CardContainer<Content: View>: View {
    var padding: CGFloat = EISpacing.cardPadding
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(EIColor.card)
            .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: EIRadius.md)
                    .stroke(EIColor.borderSubtle, lineWidth: 0.5)
            )
    }
}
```

---

## 6. Screen Specifications

### 6.1 Search — macOS 3-Column

**Mockup:** `ei-app.html`

#### Sidebar Column (240px)

Per current `AppSidebar.swift` — mostly correct. Changes needed:

1. **Mini Freedom Gauge** — Add a 4px-high linear progress bar below the navigation items showing freedom velocity (gold fill on elevated background). Tapping navigates to Freedom section.
2. **Recent Contacts Strip** — Below nav items, show 5 most recent contacts as small avatars (20px) in a horizontal row. Tapping navigates to People section with that contact selected.

**Data source:** `engine.freedomVM.velocityPercent`, `engine.peopleVM.recentContacts`

#### Content Column (380px)

This column shows a scrollable list of search results (or section-appropriate content when not searching).

**When section = .search:**
- **Search field** at top using `.searchable(text:prompt:)` modifier
  - Per Apple docs: `SwiftUI/View/searchable(text_placement_prompt_)/README.md`
  - Placement: `.navigationBarDrawer(displayMode: .always)` on iOS, `.automatic` on macOS
- **Source filter pills** — Horizontal scroll of `EISource` toggles (email, slack, meeting, transcript, file, finance). Each pill is a capsule button with source color when active, `elevated` background when inactive.
- **Result list** — `List` with `.listStyle(.plain)` and custom row styling.
  - Per Apple docs: `SwiftUI/List/README.md`
  - Each row: `SourceIcon` (28px) + title (15px medium, 1 line) + snippet (13px secondary, 2 lines) + meta row (12px tertiary: source label + relative date)
  - Selected row: gold 0.3-opacity border, gold 0.05-opacity background
  - Empty state: "Search your reality" + "15 years of data across email, Slack, meetings, files, and finances" (per mockup)

**Data source:** `engine.searchVM.results`, populated by `QueryEngine.search()`

**Search trigger:** `onChange(of: searchVM.query)` with 300ms debounce → calls `searchVM.performSearch()`. Also triggers on source filter changes.

**When section = .freedom / .meetings / .people:**
Content column shows a list appropriate to that section (transaction list, meeting list, contact list) acting as the "master" in a master-detail pattern.

#### Detail Column (flex)

Shows full content for the selected item from the content column.

**Search result selected:**
- Full content display with source badge header
- For email: full email thread, from/to, date, attachments indicator
- For slack: full message context with channel, thread, reactions
- For transcript: speaker attribution, timestamp range, meeting title link
- For document: rendered content preview, file path, modified date
- For finance: transaction details, category, account, recurring indicator
- For contact: relationship detail (same as People detail view)
- For meeting: participant list, duration, transcript excerpt if available

**Data source:** Fetch full record from `dbPool` by `SearchResult.id` and `SearchResult.sourceTable`

### 6.2 Freedom Dashboard

**Mockup:** `ei-freedom.html`

#### macOS: Full Detail View (replaces both content + detail columns)

**iOS: Scrollable screen within Freedom tab**

**Period Toggle** — Top-right pills: Week / Month / Quarter / Year. Controls the time window for all financial calculations below.

**Data source for all cards:** `engine.freedomVM` which wraps `FreedomTracker`, direct GRDB queries for transactions/snapshots.

#### Cards (top to bottom, matching mockup order):

**1. Velocity Hero Card** (full width, 40px padding)
- `FreedomGauge` (220px macOS / 180px iOS) on left
- Right side:
  - Headline (22px semibold): "You need $X more per week to replace your W-2" — `gapPerWeek` from FreedomScore
  - Body (14px secondary): narrative about velocity percentage and primary drivers
  - Three source blocks in row: HVM Clients (amount), Affiliate (amount), W-2 Mozilla (amount)
- **Data:** `FreedomTracker.calculate(snapshots:transactions:)` → `FreedomScore`

**2. Projection Card** (full width)
- "At current velocity, you replace your W-2 income by **[date]**"
- Scenario line: "If [deal] closes → [earlier date]" — derived from pipeline data in contacts/transactions
- **Data:** `FreedomScore.projectedFreedomDate`, scenario calculated from known deal amounts

**3. AI Insight Card** (full width)
- `InsightCard` component with "PAI FINANCIAL INSIGHT" label
- Template-driven insight text using computed data: QoQ revenue change, savings rate delta, upcoming opportunities
- **Data:** Compare current period vs prior period transactions to generate insight string

**4. 2x2 Grid:**

| Position | Card | Data Source |
|----------|------|------------|
| Top-left | **Net Worth** — value (emerald), daily change, breakdown dots (investments/business/cash/debt), proportional `CategoryBar`, `MiniSparkline` (14-day) | `FinancialSnapshot` grouped by accountType, diff vs yesterday |
| Top-right | **Spending** — `CategoryBar` with category breakdown, total | `FinancialTransaction` filtered by period, grouped by category, expenses only |
| Bottom-left | **Debt Paydown** — `CategoryBar` (rose) for each debt account, total, projected debt-free date | `FinancialSnapshot` where accountType in [creditCard, loan, mortgage], negative balances |
| Bottom-right | **Income Streams** — `CategoryBar` for each income source (W-2, HVM Salary, Sponsors, Affiliate, Speaking), total (emerald) | `FinancialTransaction` filtered by period, income only, grouped by payee/category |

**5. Recent Transactions** (full width)
- Scrollable list of last 20 transactions
- Each row: `SourceIcon` (finance), payee name (15px medium), meta (account + date, 12px tertiary), category tag (pill), amount (emerald for income, primary for expense, rose for flagged)
- **Data:** `FinancialTransaction` ordered by `transactionDate desc`, limit 20

#### FreedomViewModel

```swift
@Observable
final class FreedomViewModel {
    // State
    var selectedPeriod: Period = .month  // week, month, quarter, year
    var freedomScore: FreedomTracker.FreedomScore?
    var netWorthHistory: [FinancialSnapshot] = []
    var spendingByCategory: [(label: String, amount: Double, color: Color)] = []
    var debtAccounts: [(label: String, amount: Double, color: Color)] = []
    var incomeStreams: [(label: String, amount: Double, color: Color)] = []
    var recentTransactions: [FinancialTransaction] = []
    var insightText: String = ""
    var isLoading = false

    @ObservationIgnored let dbPool: DatabasePool
    @ObservationIgnored let freedomTracker = FreedomTracker()

    func load() async { ... }
    func changePeriod(_ period: Period) async { ... }
}
```

**GRDB Queries (all parameterized per CLAUDE.md security rules):**
- Net worth: `SELECT * FROM financialSnapshots WHERE snapshotDate = ? ORDER BY accountType`
- Spending: `SELECT category, SUM(amount) FROM financialTransactions WHERE transactionDate >= ? AND amount < 0 GROUP BY category ORDER BY SUM(amount)`
- Debt: `SELECT * FROM financialSnapshots WHERE accountType IN ('creditCard', 'loan', 'mortgage')`
- Income: `SELECT payee, category, SUM(amount) FROM financialTransactions WHERE transactionDate >= ? AND amount > 0 GROUP BY payee ORDER BY SUM(amount) DESC`
- Recent: `SELECT * FROM financialTransactions ORDER BY transactionDate DESC LIMIT 20`
- History (sparkline): `SELECT * FROM financialSnapshots WHERE snapshotDate >= ? ORDER BY snapshotDate` (last 14 days)

### 6.3 People / Relationships

**Mockup:** `ei-people.html`

#### macOS: Content Column (360px list) + Detail Column (flex)

**iOS: NavigationStack within People tab**

#### Content Column — Contact List

**Header:**
- "Relationships" title (28px bold)
- Subtitle: "{count} contacts across email, meetings, and Slack"
- Search field (filters by name, email, role)
- **Tab selector:** "By Depth" (default) | "Recent" | "Fading" | "Companies"

**Tab behavior:**
- **By Depth:** Sections — Inner Circle (>=100 interactions), Growing (10-99), Peripheral (<10). Uses `RelationshipScorer.scoreAll()`.
- **Recent:** Flat list sorted by `lastSeenAt desc`. No sections.
- **Fading:** Only contacts where `isFading == true` from `RelationshipScorer`. Shows days-since-last-seen badge.
- **Companies:** Grouped by `Company.name`. Each section header is company name + domain. Contacts listed under their company.

**Contact Row:**
- `DepthBadge` (40px) with initials + depth-colored ring
- Name (13px medium), Role (11px tertiary)
- Stat chips (right-aligned): email count (gold), meeting count (violet), slack count (indigo) — each in a 10px pill with colored background
- Fading contacts: 6px rose dot (top-right of avatar), row at 70% opacity

**Data source:** `engine.peopleVM.scoredContacts` from `RelationshipScorer.scoreAll()`

#### Detail Column — Contact Detail

**Hero Section** (centered, 40px top padding):
- `DepthBadge` (72px, large variant)
- Name (22px bold)
- Role + Company (14px secondary)
- Stat row (centered): X emails (gold), Y meetings (violet), Z messages (indigo)

**Relationship Strength Bar:**
- Label: "Relationship Strength — [Depth Label]" (gold for deep, indigo for growing, etc.)
- 6px horizontal bar with gradient fill (% based on interactions relative to max contact)
- Context text (14px secondary): response time, channel frequency, tenure (first seen → now)

**PAI Relationship Insight:**
- `InsightCard` with "PAI RELATIONSHIP INSIGHT" label
- Template-driven: "Communication pattern with [name] is [trend]. [channel] dominates at [%]. [observation about recent shift or opportunity]."
- **Data:** Compare last-30-day vs prior-30-day interaction counts per channel

**Interaction Timeline:**
- `InteractionTimeline` component
- Shows last 20 interactions across all channels (email, slack, meeting, file) sorted by date desc
- **Data:** Union query across `emailChunks`, `slackChunks`, `transcriptChunks`, `documents` filtered by contact name/email, ordered by date desc, limit 20

#### PeopleViewModel

```swift
@Observable
final class PeopleViewModel {
    // State
    var scoredContacts: [RelationshipScorer.RelationshipScore] = []
    var selectedContactId: String?
    var selectedTab: PeopleTab = .depth  // depth, recent, fading, companies
    var searchFilter: String = ""
    var contactDetail: ContactDetail?
    var timeline: [InteractionTimeline.TimelineItem] = []
    var isLoading = false

    struct ContactDetail {
        let contact: Contact
        let score: RelationshipScorer.RelationshipScore
        let company: Company?
        let strengthPercent: Double
        let tenure: String
        let channelBreakdown: (email: Int, meeting: Int, slack: Int)
        let insightText: String
    }

    @ObservationIgnored let dbPool: DatabasePool
    @ObservationIgnored let scorer: RelationshipScorer

    func load() async { ... }
    func selectContact(_ id: String) async { ... }
    func loadTimeline(for contact: Contact) async { ... }
}
```

### 6.4 Meetings

**Mockup:** Part of `ei-app.html` (macOS only; iOS omits meetings tab per current design)

#### macOS: Content Column (meeting list) + Detail Column (meeting detail)

**Content Column:**
- "Meetings" title + count
- Grouped by: Today, This Week, Earlier
- Each row: violet `SourceIcon`, title (15px medium), date + time (12px tertiary), duration badge, participant count badge, "Internal" pill if applicable

**Detail Column (when meeting selected):**
- Meeting title (22px bold)
- Date/time + duration (14px secondary)
- Participant list: `DepthBadge` (28px) + name + role for each `MeetingParticipant` joined with `Contact`
- Transcript excerpt: first 500 chars of associated `TranscriptChunk` (if meetingId matches)
- File link: `filePath` if available (opens in Finder via `NSWorkspace`)

**Data source:** `Meeting` ordered by `startTime desc`, joined with `MeetingParticipant` + `Contact`, associated `TranscriptChunk` by `meetingId`

### 6.5 Settings

**Mockup:** `ei-mobile.html` settings screen

#### Both Platforms

**Data Sources Card:**
- Row per source: SimpleFin, Email (IMAP), Slack, Fathom, VRAM Filesystem
- Status badge: "Connected" (emerald) / "Syncing" (indigo, animated) / "Error" (rose) / "Not Configured" (tertiary)
- Last sync time (relative)
- **Data:** `StateManager.getState()` → iterate `sources` dict → read `lastSyncAt`, `lastStatus`

**Index Status Card:**
- Rows: Documents, Email Chunks, Slack Chunks, Transcript Chunks, Meetings, Contacts, Financial Transactions, Vector Embeddings
- Count for each (right-aligned, monospacedDigit)
- **Data:** `dbPool.read { db in try Table.fetchCount(db) }` for each table, `vectorIndex.count512` for embeddings

**iCloud Sync Card:**
- Status: "Up to date" / "Syncing" / "Error"
- Last sync time
- Storage usage estimate
- **Data:** `iCloudManager` status (needs new public property exposure — see Section 8)

**Database Card (macOS only):**
- Database path (selectable text)
- Database file size
- "Open in Finder" button

#### SettingsViewModel

```swift
@Observable
final class SettingsViewModel {
    var syncState: SyncState?
    var tableCounts: [String: Int] = [:]
    var embeddingCount: Int = 0
    var databaseSize: String = ""
    var databasePath: String = ""
    var isLoading = false

    @ObservationIgnored let dbPool: DatabasePool
    @ObservationIgnored let stateManager: StateManager
    @ObservationIgnored let vectorIndex: VectorIndex

    func load() async { ... }
}
```

### 6.6 iOS-Specific Adaptations

**Mockup:** `ei-mobile.html`

#### Search Screen (iOS)

- **Widget Strip** — Horizontal `ScrollView(.horizontal)` below search field showing 3 mini cards:
  1. Freedom: gold gradient bg, `$X` (28px bold), "of $6,058/week" (11px), 47% mini progress bar
  2. Net Worth: emerald gradient bg, `$X` (28px), daily change (11px)
  3. Meetings: violet gradient bg, next 3 meetings (11px, dot + time + title)
- **AI Insight Card** — `InsightCard` below widget strip
- **Recent Results** — List below (same SearchResultRow as macOS but full-width, 36px source icon)

**Data source:** Widget data from `freedomVM`, `settingsVM.tableCounts`, `meetingsVM.upcomingMeetings`

#### Freedom Screen (iOS)

- Vertical scroll, gauge (180px), then cards stacked vertically (no 2x2 grid — single column)
- Same data as macOS, different layout

#### People Screen (iOS)

- `NavigationStack` — list pushes to detail view
- Contact rows are 44px height (per iOS HIG)
- Detail view is full-screen push (not split)

**Apple Docs Reference:** `SwiftUI/NavigationStack/README.md` — "Use init(path:root:) for programmatic navigation"

---

## 7. Animations & Transitions

**Design tokens reference:** `motion` section of `design-tokens.json`

### 7.1 Card Fade-In

On screen appearance, cards fade in with staggered delay (60ms per card).

```swift
.opacity(appeared ? 1 : 0)
.offset(y: appeared ? 0 : 8)
.animation(.easeOut(duration: 0.25).delay(Double(index) * 0.06), value: appeared)
```

**Design tokens:** fadeIn: 250ms, stagger: 30ms delay (we use 60ms to match mockup).

### 7.2 Gauge Fill

Freedom gauge animates from 0 to current value on appear.

```swift
.animation(.easeOut(duration: 1.5), value: progress)
```

**Design tokens:** gaugeFill: 1500ms, decelerate easing.

### 7.3 Hover States (macOS)

Cards elevate shadow and shift background on hover.

```swift
.onHover { hovering in
    withAnimation(.easeInOut(duration: 0.18)) {
        isHovered = hovering
    }
}
.background(isHovered ? EIColor.hover : EIColor.card)
```

**Design tokens:** hover: 180ms, default easing.

### 7.4 List Selection

Selected result card gains gold border + gold tint background.

```swift
.overlay(
    RoundedRectangle(cornerRadius: EIRadius.md)
        .stroke(isSelected ? EIColor.gold.opacity(0.3) : .clear, lineWidth: 1)
)
.background(isSelected ? EIColor.gold.opacity(0.05) : .clear)
.animation(.easeInOut(duration: 0.18), value: isSelected)
```

### 7.5 View Transitions

Section changes use matched geometry or slide transitions.

**Apple Docs Reference:** `SwiftUI/AnyTransition/README.md`

```swift
.transition(.asymmetric(
    insertion: .move(edge: .trailing).combined(with: .opacity),
    removal: .move(edge: .leading).combined(with: .opacity)
))
```

---

## 8. EddingsKit API Additions

The following new public APIs are needed in EddingsKit to support the UI layer. These are minimal additions — data access helpers, not new features.

### 8.1 Record Fetch Helpers (DatabaseManager extension or new DataAccess struct)

```swift
// New file: Sources/EddingsKit/Storage/DataAccess.swift
public struct DataAccess: Sendable {
    public let dbPool: DatabasePool

    // Single record fetch
    public func fetchContact(id: String) throws -> Contact?
    public func fetchCompany(id: String) throws -> Company?
    public func fetchMeeting(id: String) throws -> Meeting?

    // Relationship traversal
    public func contactsForCompany(_ companyId: String) throws -> [Contact]
    public func participantsForMeeting(_ meetingId: String) throws -> [(MeetingParticipant, Contact?)]
    public func transcriptsForMeeting(_ meetingId: String) throws -> [TranscriptChunk]
    public func companyForContact(_ contact: Contact) throws -> Company?

    // Table counts
    public func tableCounts() throws -> [String: Int]

    // Timeline query (union across sources for a contact)
    public func interactionTimeline(
        contactName: String,
        contactEmail: String?,
        limit: Int = 20
    ) throws -> [InteractionRecord]

    public struct InteractionRecord: Sendable, Identifiable {
        public let id: String
        public let sourceTable: SearchResult.SourceTable
        public let title: String
        public let detail: String
        public let date: Date
    }

    // Financial aggregations
    public func spendingByCategory(since: Date) throws -> [(category: String, amount: Double)]
    public func incomeBySource(since: Date) throws -> [(source: String, amount: Double)]
    public func recentTransactions(limit: Int) throws -> [FinancialTransaction]
    public func snapshotHistory(since: Date) throws -> [FinancialSnapshot]
    public func debtAccounts() throws -> [FinancialSnapshot]
}
```

### 8.2 StateManager Status Exposure

```swift
// Addition to existing StateManager
extension StateManager {
    public func allSourceStates() -> [String: SyncState.SourceState]
}
```

### 8.3 RelationshipScorer Depth Enum

Ensure `Depth` is public and `Sendable`:

```swift
public enum Depth: String, Sendable, Codable {
    case deep, growing, peripheral, fading
}
```

---

## 9. File Structure

```
Sources/EddingsApp/
├── EddingsApp.swift                    # @main, environment injection, debugInspectable
├── EddingsEngine.swift                 # Coordinator: dbPool, queryEngine, feature VMs
│
├── ViewModels/
│   ├── SearchViewModel.swift           # Query, results, source filters, debounce
│   ├── FreedomViewModel.swift          # Period toggle, freedom score, financial data
│   ├── PeopleViewModel.swift           # Scored contacts, tabs, detail, timeline
│   ├── MeetingsViewModel.swift         # Meeting list, selected meeting, participants
│   └── SettingsViewModel.swift         # Sync state, table counts, DB info
│
├── Navigation/
│   ├── AppSidebar.swift                # macOS NavigationSplitView (3-column)
│   ├── AppTabBar.swift                 # iOS TabView (4 tabs)
│   ├── ContentListView.swift           # Center column dispatcher (per section)
│   └── DetailView.swift                # Detail column dispatcher (per section)
│
├── Search/
│   ├── SearchContentList.swift         # Result list with source filters
│   ├── SearchResultRow.swift           # Individual result row
│   └── SearchDetailView.swift          # Full content for selected result
│
├── Finance/
│   ├── FreedomDashboard.swift          # Full freedom screen (gauge, cards, transactions)
│   ├── VelocityHeroCard.swift          # Gauge + narrative + source blocks
│   ├── ProjectionCard.swift            # Freedom date projection + scenarios
│   ├── NetWorthCard.swift              # Net worth + sparkline + breakdown
│   ├── SpendingCard.swift              # Spending by category
│   ├── DebtCard.swift                  # Debt paydown + projected date
│   ├── IncomeCard.swift                # Income streams breakdown
│   └── TransactionRow.swift            # Recent transaction row
│
├── Contacts/
│   ├── ContactContentList.swift        # Contact list with tabs + sections
│   ├── ContactRow.swift                # Individual contact row
│   ├── ContactDetailView.swift         # Full contact detail (hero, strength, timeline)
│   └── RelationshipStrengthBar.swift   # Gradient strength indicator
│
├── Meetings/
│   ├── MeetingContentList.swift        # Meeting list grouped by date
│   ├── MeetingRow.swift                # Individual meeting row
│   └── MeetingDetailView.swift         # Meeting detail with participants + transcript
│
├── Settings/
│   └── SettingsView.swift              # Data sources, index stats, iCloud, DB info
│
├── Components/
│   ├── SourceIcon.swift                # Source identity badge
│   ├── InsightCard.swift               # PAI insight card
│   ├── FreedomGauge.swift              # Circular velocity gauge
│   ├── StatCard.swift                  # Metric card
│   ├── DepthBadge.swift                # Contact avatar with depth ring
│   ├── InteractionTimeline.swift       # Vertical timeline
│   ├── MiniSparkline.swift             # Inline trend chart
│   ├── CategoryBar.swift               # Proportional breakdown bar
│   ├── CardContainer.swift             # Standard card wrapper
│   ├── PillToggle.swift                # Period/tab selector pills
│   └── StatChip.swift                  # Small count badge (email: 127)
│
├── Intents/
│   └── SearchIntent.swift              # Siri Shortcuts (stub, future PRD)
│
└── Info.plist                          # Background tasks, Face ID

Sources/EddingsKit/
├── Storage/
│   └── DataAccess.swift                # NEW: Record fetch + aggregation helpers
└── (existing files unchanged)
```

**Total new files:** ~30 SwiftUI view files + 1 EddingsKit file
**Total modified files:** ~5 (EddingsApp.swift, Package.swift, AppSidebar.swift, AppTabBar.swift, StateManager.swift)

---

## 10. Implementation Order

Ordered by dependency chain and visual impact:

| Phase | Task | Depends On | Est. Files |
|-------|------|-----------|-----------|
| **1** | Component library (all 11 components in Components/) | Design tokens (exists) | 11 |
| **2** | DataAccess.swift in EddingsKit | DatabaseManager (exists) | 1 |
| **3** | View models (all 5 in ViewModels/) | DataAccess, EddingsKit actors | 5 |
| **4** | EddingsEngine refactor + environment injection | View models | 2 |
| **5** | Navigation refactor: 3-column macOS + content/detail dispatchers | Engine | 4 |
| **6** | Search screen (content list + detail view) | SearchViewModel, components | 3 |
| **7** | Freedom Dashboard (all cards + charts) | FreedomViewModel, Charts, components | 8 |
| **8** | People screen (list + detail + timeline) | PeopleViewModel, components | 4 |
| **9** | Meetings screen (list + detail) | MeetingsViewModel | 3 |
| **10** | Settings screen (live data) | SettingsViewModel | 1 |
| **11** | iOS adaptations (widget strip, mobile layouts) | All VMs | 3 |
| **12** | Animations (fade-in, gauge, hover, transitions) | All views | 0 (modifications) |
| **13** | SwiftUIDebugKit integration | Package.swift | 1 (modification) |
| **14** | Build verification + SwiftUIDebugKit QC | All above | 0 |

---

## 11. Swift Charts Usage

**Apple Docs Reference:** `Charts/README.md`, `Charts/BarMark/README.md`, `Charts/LineMark/README.md`, `Charts/AreaMark/README.md`, `Charts/SectorMark/README.md`

Add `import Charts` to files that use chart components. Charts is a first-party Apple framework (iOS 16+, macOS 13+) — no Package.swift dependency needed.

### Usage Points:

| Screen | Chart Type | Mark | Data |
|--------|-----------|------|------|
| Freedom > Net Worth | Sparkline | `LineMark` + `AreaMark` | 14-day snapshot history |
| Freedom > Spending | Horizontal bars | `BarMark` (horizontal) | Category totals |
| Freedom > Debt | Horizontal bars | `BarMark` (horizontal) | Debt account balances |
| Freedom > Income | Horizontal bars | `BarMark` (horizontal) | Income source totals |
| People > Relationship Strength | Linear gauge | `RectangleMark` | Interaction score as % of max |

### Chart Styling Pattern:

```swift
Chart(data) { item in
    BarMark(
        x: .value("Amount", item.amount),
        y: .value("Category", item.category)
    )
    .foregroundStyle(item.color)
}
.chartXAxis(.hidden)
.chartYAxis {
    AxisMarks { _ in
        AxisValueLabel()
            .font(EITypography.bodySmall())
            .foregroundStyle(EIColor.textSecondary)
    }
}
.frame(height: CGFloat(data.count) * 28)
```

---

## 12. Accessibility

Per Apple docs: `SwiftUI/Accessibility/README.md`

All interactive components must include:
- `.accessibilityLabel()` on source icons and badges
- `.accessibilityValue()` on gauges and progress bars
- `.accessibilityHint()` on actionable items
- VoiceOver reads freedom velocity as "47 percent of weekly target"
- Dynamic Type support via `.font()` (SF Pro scales automatically)
- Reduce Motion: replace gauge animation with instant render when `@Environment(\.accessibilityReduceMotion)` is true

---

## 13. Testing Strategy

### Unit Tests (EddingsKit)
- `DataAccessTests.swift` — Verify all new fetch/aggregation methods against in-memory DB
- Existing tests remain unchanged

### UI Tests (using SwiftUIDebugKit)
After building each phase, use SwiftUIDebugKit MCP tools to verify:
1. `read_hierarchy` — Confirm view structure matches expected layout
2. `screenshot` — Visual comparison against mockup
3. `read_state` — Verify view model state matches expected data
4. `read_performance` — Check for excessive body evaluations
5. `find_element` — Verify specific UI elements exist (search field, gauge, contact rows)

### Manual QC Checklist
- [ ] macOS: 3-column layout at 1200px width
- [ ] macOS: sidebar collapses at narrow widths
- [ ] macOS: hover states on all cards
- [ ] iOS: TabView with 4 tabs
- [ ] iOS: widget strip horizontal scroll
- [ ] iOS: push navigation on People detail
- [ ] Freedom gauge animates on appear
- [ ] Cards fade in with stagger
- [ ] Search returns results for "Emily"
- [ ] Contact detail shows timeline
- [ ] Settings shows real sync status
- [ ] All financial values are real (not hard-coded)
- [ ] Source icons show correct colors
- [ ] Typography matches design tokens

---

## 14. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Empty database on first run | All screens show blank | Show meaningful empty states per screen with "Run `ei-cli sync --all` to populate" guidance |
| Swift Charts not available (macOS 13 min) | Charts won't compile | Platform is macOS 15+ / iOS 18+ (well above Charts minimum). No risk. |
| Large contact list performance | Slow scroll with 847+ contacts | Use `List` with lazy loading (SwiftUI default). `RelationshipScorer.scoreAll()` is synchronous but fast (simple SQL). |
| GRDB concurrent reads from UI | Potential blocking | `DatabasePool` supports concurrent reads by design. UI reads on background task, publishes to `@MainActor`. |
| SwiftUIDebugKit macOS-only | Can't debug iOS | External mode works for macOS. iOS debugging uses Xcode Previews and simulator. |
| Insight text quality without AI | Generic/unhelpful | Use specific data-driven templates: "Q1 revenue: $X (Y% vs Q4). Top source: Z." Better than vague AI prose. |

---

## 15. Success Criteria

1. **Visual match** — Screenshot of running app overlaid on mockup HTML achieves >90% layout correspondence (verified via SwiftUIDebugKit `screenshot` + manual comparison).
2. **Zero hard-coded data** — Every displayed number traces to a GRDB query or EddingsKit calculation. Grep for literal dollar amounts or contact names returns zero hits outside test files.
3. **Build clean** — `swift build` passes with zero warnings under Swift 6 strict concurrency.
4. **Tests pass** — `swift test` passes including new DataAccess tests.
5. **Responsive** — Search returns results within 500ms. Freedom dashboard loads within 1s. Contact list scrolls at 60fps.
6. **Both platforms** — App launches and displays correctly on macOS 15 and iOS 18 simulator.

---

## Appendix A: Design Token Quick Reference

| Token | Value | Usage |
|-------|-------|-------|
| `EIColor.deep` | rgb(10,10,15) | Window background |
| `EIColor.surface` | rgb(19,19,24) | Content area background |
| `EIColor.card` | rgb(26,26,34) | Card background |
| `EIColor.elevated` | rgb(34,34,48) | Hover state, inactive elements |
| `EIColor.gold` | #e8a849 | Primary accent, freedom, warmth |
| `EIColor.indigo` | #7c8cf5 | AI/PAI, Slack |
| `EIColor.emerald` | #3dd68c | Growth, income, positive |
| `EIColor.rose` | #f472b6 | Debt, fading, attention |
| `EIColor.violet` | #a78bfa | Meetings, creativity |
| `EIColor.blue` | #60a5fa | Information, W-2 |
| `EITypography.metric()` | 36pt bold | Financial values |
| `EITypography.display()` | 28pt bold | Page titles |
| `EITypography.headline()` | 22pt semibold | Velocity headlines |
| `EITypography.body()` | 14pt regular | Content text |
| `EITypography.caption()` | 12pt regular | Timestamps |
| `EITypography.label()` | 11pt semibold | Section headers (uppercase) |
| `EISpacing.cardPadding` | 16pt | Standard card padding |
| `EISpacing.sectionGap` | 24pt | Between sections |
| `EIRadius.md` | 10pt | Card corners |
| `EILayout.sidebarWidth` | 240pt | macOS sidebar |
| `EILayout.contentWidth` | 380pt | macOS content column |

## Appendix B: Apple Documentation File References

All API patterns in this PRD are grounded in:

| Pattern | Doc Path |
|---------|----------|
| NavigationSplitView (3-column) | `apple-developer-docs/SwiftUI/NavigationSplitView/README.md` |
| TabView (iOS tabs) | `apple-developer-docs/SwiftUI/TabView/README.md` |
| NavigationStack (iOS push nav) | `apple-developer-docs/SwiftUI/NavigationStack/README.md` |
| @Observable macro | `apple-developer-docs/Observation/Observable/README.md` |
| @Environment injection | `apple-developer-docs/SwiftUI/Environment/README.md` |
| EnvironmentValues | `apple-developer-docs/SwiftUI/EnvironmentValues/README.md` |
| List (lazy, selectable) | `apple-developer-docs/SwiftUI/List/README.md` |
| .searchable modifier | `apple-developer-docs/SwiftUI/View/searchable(text_placement_prompt_)/README.md` |
| Swift Charts (BarMark, LineMark) | `apple-developer-docs/Charts/README.md` |
| Animation timing | `apple-developer-docs/SwiftUI/Animations/README.md` |
| Transitions | `apple-developer-docs/SwiftUI/AnyTransition/README.md` |
| Toolbar / Menu | `apple-developer-docs/SwiftUI/Toolbars/README.md` |
| Color / Font APIs | `apple-developer-docs/SwiftUI/Color/README.md`, `SwiftUI/Font/README.md` |
| Accessibility | `apple-developer-docs/SwiftUI/Accessibility/README.md` |
| CKSyncEngine (status display) | `apple-developer-docs/CloudKit/CKSyncEngine-5sie5/README.md` |
| BackgroundTasks (status display) | `apple-developer-docs/BackgroundTasks/README.md` |
| Keychain (settings display) | `apple-developer-docs/Security/README.md` |

## Appendix C: SwiftUIDebugKit Integration

**Source:** `/Volumes/VRAM/00-09_System/01_Tools/conversift/SwiftUIDebugKit-Conversift/`

### Package.swift Addition

```swift
dependencies: [
    .package(url: "https://github.com/grdb/GRDB.swift.git", from: "7.0.0"),
    .package(url: "https://github.com/unum-cloud/usearch.git", from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    .package(path: "/Volumes/VRAM/00-09_System/01_Tools/conversift/SwiftUIDebugKit-Conversift"),
],
```

### EddingsApp Target

```swift
.executableTarget(
    name: "EddingsApp",
    dependencies: [
        "EddingsKit",
        .product(name: "SwiftUIDebugKit", package: "SwiftUIDebugMCP",
                 condition: .when(platforms: [.macOS])),
    ],
    path: "Sources/EddingsApp",
    exclude: ["Info.plist"]
),
```

### Conditional Import

```swift
// In EddingsApp.swift
#if DEBUG && canImport(SwiftUIDebugKit)
import SwiftUIDebugKit
#endif
```

### Verification Commands

After integration, verify with:
```bash
swift build  # Confirms no compile errors
# Then in a Claude Code session with swiftui-debug MCP:
# read_hierarchy → confirms EddingsApp view tree is visible
# read_state → confirms @Observable properties are inspectable
```

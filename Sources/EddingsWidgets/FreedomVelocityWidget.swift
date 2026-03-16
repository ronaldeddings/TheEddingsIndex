import WidgetKit
import SwiftUI
import GRDB

struct FreedomVelocityEntry: TimelineEntry {
    let date: Date
    let weeklyAmount: Double
    let weeklyTarget: Double
    let velocityPercent: Double
}

private func loadLatestWidgetSnapshot() -> (weeklyAmount: Double, weeklyTarget: Double, velocityPercent: Double)? {
    guard let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.hackervalley.eddingsindex"
    ) else { return nil }
    let dbPath = containerURL.appending(path: "eddingsindex.sqlite").path()
    guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

    do {
        let dbPool = try DatabasePool(path: dbPath)
        return try dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT weeklyAmount, weeklyTarget, velocityPercent FROM widgetSnapshots ORDER BY date DESC LIMIT 1"
            )
            guard let row else { return nil }
            return (
                weeklyAmount: row["weeklyAmount"] as Double,
                weeklyTarget: row["weeklyTarget"] as Double,
                velocityPercent: row["velocityPercent"] as Double
            )
        }
    } catch {
        return nil
    }
}

struct FreedomVelocityProvider: TimelineProvider {
    func placeholder(in context: Context) -> FreedomVelocityEntry {
        FreedomVelocityEntry(date: .now, weeklyAmount: 2847, weeklyTarget: 6058, velocityPercent: 47)
    }

    func getSnapshot(in context: Context, completion: @escaping (FreedomVelocityEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FreedomVelocityEntry>) -> Void) {
        let snapshot = loadLatestWidgetSnapshot()
        let entry = FreedomVelocityEntry(
            date: .now,
            weeklyAmount: snapshot?.weeklyAmount ?? 2847,
            weeklyTarget: snapshot?.weeklyTarget ?? 6058,
            velocityPercent: snapshot?.velocityPercent ?? 47
        )
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 6, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct FreedomVelocityWidgetView: View {
    let entry: FreedomVelocityEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Freedom Velocity")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("$\(Int(entry.weeklyAmount).formatted())")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(red: 232/255, green: 168/255, blue: 73/255))

            Text("of $\(Int(entry.weeklyTarget).formatted()) / week")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 232/255, green: 168/255, blue: 73/255))
                        .frame(width: geo.size.width * entry.velocityPercent / 100, height: 5)
                }
            }
            .frame(height: 5)
        }
        .padding(16)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 26/255, green: 21/255, blue: 16/255),
                    Color(red: 31/255, green: 18/255, blue: 8/255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct FreedomVelocityWidget: Widget {
    let kind = "FreedomVelocityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FreedomVelocityProvider()) { entry in
            FreedomVelocityWidgetView(entry: entry)
        }
        .configurationDisplayName("Freedom Velocity")
        .description("Your weekly non-W2 income vs $6,058 target")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NetWorthEntry: TimelineEntry {
    let date: Date
    let netWorth: Double
    let dailyChange: Double
}

private func loadLatestNetWorthSnapshot() -> (netWorth: Double, dailyChange: Double)? {
    guard let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.hackervalley.eddingsindex"
    ) else { return nil }
    let dbPath = containerURL.appending(path: "eddingsindex.sqlite").path()
    guard FileManager.default.fileExists(atPath: dbPath) else { return nil }

    do {
        let dbPool = try DatabasePool(path: dbPath)
        return try dbPool.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT netWorth, dailyChange FROM widgetSnapshots ORDER BY date DESC LIMIT 1"
            )
            guard let row else { return nil }
            return (
                netWorth: row["netWorth"] as Double,
                dailyChange: row["dailyChange"] as Double
            )
        }
    } catch {
        return nil
    }
}

struct NetWorthProvider: TimelineProvider {
    func placeholder(in context: Context) -> NetWorthEntry {
        NetWorthEntry(date: .now, netWorth: 89490, dailyChange: 1435)
    }

    func getSnapshot(in context: Context, completion: @escaping (NetWorthEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetWorthEntry>) -> Void) {
        let snapshot = loadLatestNetWorthSnapshot()
        let entry = NetWorthEntry(
            date: .now,
            netWorth: snapshot?.netWorth ?? 89490,
            dailyChange: snapshot?.dailyChange ?? 1435
        )
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 6, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

struct NetWorthWidgetView: View {
    let entry: NetWorthEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Net Worth")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("$\(Int(entry.netWorth).formatted())")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(red: 61/255, green: 214/255, blue: 140/255))

            Text("▲ $\(Int(entry.dailyChange).formatted()) today")
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 61/255, green: 214/255, blue: 140/255))

            Spacer()
        }
        .padding(16)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 15/255, green: 26/255, blue: 18/255),
                    Color(red: 8/255, green: 31/255, blue: 13/255)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct NetWorthWidget: Widget {
    let kind = "NetWorthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NetWorthProvider()) { entry in
            NetWorthWidgetView(entry: entry)
        }
        .configurationDisplayName("Net Worth")
        .description("Assets minus liabilities, updated daily")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct EddingsWidgets: WidgetBundle {
    var body: some Widget {
        FreedomVelocityWidget()
        NetWorthWidget()
    }
}

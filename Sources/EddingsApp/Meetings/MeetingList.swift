import SwiftUI
import EddingsKit

struct MeetingList: View {
    @Environment(EddingsEngine.self) private var engine

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meetings")
                    .font(EITypography.display())
                    .foregroundStyle(EIColor.textPrimary)
                Text("\(engine.meetings.count) recent meetings")
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EISpacing.detailPadding)

            if engine.meetings.isEmpty {
                ContentUnavailableView("No Meetings", systemImage: "video", description: Text("Run ei-cli sync --meetings to import"))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(engine.meetings) { meeting in
                        meetingRow(meeting: meeting)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(EIColor.deep)
        .onAppear { engine.loadMeetings() }
    }

    private func meetingRow(meeting: Meeting) -> some View {
        let dateStr = meeting.startTime.map { Self.dateFormatter.string(from: $0) } ?? "Unknown date"
        let durationStr = meeting.durationMinutes.map { "\($0) min" } ?? ""
        let participantStr = meeting.participantCount.map { "\($0) participants" } ?? ""
        let isInternal = meeting.isInternal

        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: EIRadius.sm)
                .fill(EIColor.violet.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: isInternal ? "person.2" : "video")
                        .font(.system(size: 14))
                        .foregroundStyle(EIColor.violet)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title ?? "Untitled Meeting")
                    .font(EITypography.bodyLarge())
                    .foregroundStyle(EIColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(dateStr)
                        .font(EITypography.caption())
                        .foregroundStyle(EIColor.textTertiary)
                    if !durationStr.isEmpty {
                        Text("·")
                            .foregroundStyle(EIColor.textTertiary)
                        Text(durationStr)
                            .font(EITypography.caption())
                            .foregroundStyle(EIColor.textTertiary)
                    }
                    if !participantStr.isEmpty {
                        Text("·")
                            .foregroundStyle(EIColor.textTertiary)
                        Text(participantStr)
                            .font(EITypography.caption())
                            .foregroundStyle(EIColor.textTertiary)
                    }
                }
            }

            Spacer()

            if isInternal {
                Text("Internal")
                    .font(EITypography.micro())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(EIColor.elevated)
                    .foregroundStyle(EIColor.textTertiary)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
    }
}

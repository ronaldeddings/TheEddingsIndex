import SwiftUI
import EddingsKit

struct MeetingContentList: View {
    @Environment(MeetingsViewModel.self) private var meetingsVM

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meetings")
                    .font(EITypography.display())
                    .foregroundStyle(EIColor.textPrimary)
                Text("\(meetingsVM.meetings.count) recent meetings")
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EISpacing.sidebarPadding)

            if meetingsVM.meetings.isEmpty {
                ContentUnavailableView("No Meetings", systemImage: "video", description: Text("Run ei-cli sync --meetings to import"))
                    .frame(maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { meetingsVM.selectedMeetingId },
                    set: { id in
                        if let id { Task { await meetingsVM.selectMeeting(id) } }
                    }
                )) {
                    if !meetingsVM.todayMeetings.isEmpty {
                        Section("Today") {
                            ForEach(meetingsVM.todayMeetings) { meeting in
                                MeetingRow(meeting: meeting)
                                    .tag(meeting.id)
                            }
                        }
                    }
                    if !meetingsVM.thisWeekMeetings.isEmpty {
                        Section("This Week") {
                            ForEach(meetingsVM.thisWeekMeetings) { meeting in
                                MeetingRow(meeting: meeting)
                                    .tag(meeting.id)
                            }
                        }
                    }
                    if !meetingsVM.earlierMeetings.isEmpty {
                        Section("Earlier") {
                            ForEach(meetingsVM.earlierMeetings) { meeting in
                                MeetingRow(meeting: meeting)
                                    .tag(meeting.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(EIColor.surface)
        .task { await meetingsVM.load() }
    }
}

struct MeetingRow: View {
    let meeting: Meeting

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d · h:mm a"
        return f
    }()

    var body: some View {
        HStack(spacing: 12) {
            SourceIcon(source: .meeting, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title ?? "Untitled Meeting")
                    .font(EITypography.bodyLarge())
                    .foregroundStyle(EIColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if let start = meeting.startTime {
                        Text(Self.dateFormatter.string(from: start))
                            .font(EITypography.caption())
                            .foregroundStyle(EIColor.textTertiary)
                    }
                    if let dur = meeting.durationMinutes {
                        Text("·").foregroundStyle(EIColor.textTertiary)
                        Text("\(dur) min")
                            .font(EITypography.caption())
                            .foregroundStyle(EIColor.textTertiary)
                    }
                    if let count = meeting.participantCount {
                        Text("·").foregroundStyle(EIColor.textTertiary)
                        Text("\(count) participants")
                            .font(EITypography.caption())
                            .foregroundStyle(EIColor.textTertiary)
                    }
                }
            }

            Spacer()

            if meeting.isInternal {
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

struct MeetingDetailView: View {
    @Environment(MeetingsViewModel.self) private var meetingsVM

    var body: some View {
        if let detail = meetingsVM.meetingDetail {
            ScrollView {
                VStack(alignment: .leading, spacing: EISpacing.sectionGap) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.meeting.title ?? "Untitled Meeting")
                            .font(EITypography.headline())
                            .foregroundStyle(EIColor.textPrimary)

                        HStack(spacing: 12) {
                            if let start = detail.meeting.startTime {
                                Label(start.formatted(.dateTime.month().day().hour().minute()), systemImage: "calendar")
                                    .font(EITypography.body())
                                    .foregroundStyle(EIColor.textSecondary)
                            }
                            if let dur = detail.meeting.durationMinutes {
                                Label("\(dur) min", systemImage: "clock")
                                    .font(EITypography.body())
                                    .foregroundStyle(EIColor.textSecondary)
                            }
                        }
                    }

                    if !detail.participants.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PARTICIPANTS")
                                .font(EITypography.label())
                                .foregroundStyle(EIColor.textTertiary)
                            ForEach(detail.participants, id: \.participant.id) { p in
                                HStack(spacing: 10) {
                                    let name = p.contact?.name ?? "Unknown"
                                    DepthBadge(name: name, depth: .peripheral, size: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(name)
                                            .font(EITypography.bodySmall())
                                            .foregroundStyle(EIColor.textPrimary)
                                        if let role = p.participant.role {
                                            Text(role)
                                                .font(EITypography.caption())
                                                .foregroundStyle(EIColor.textTertiary)
                                        }
                                    }
                                    Spacer()
                                    if let speaking = p.participant.speakingTimeSeconds, speaking > 0 {
                                        Text("\(speaking / 60) min")
                                            .font(EITypography.caption())
                                            .foregroundStyle(EIColor.textTertiary)
                                    }
                                }
                            }
                        }
                    }

                    if let excerpt = detail.transcriptExcerpt, !excerpt.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TRANSCRIPT EXCERPT")
                                .font(EITypography.label())
                                .foregroundStyle(EIColor.textTertiary)
                            Text(excerpt)
                                .font(EITypography.body())
                                .foregroundStyle(EIColor.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(EISpacing.detailPadding)
            }
            .background(EIColor.deep)
        }
    }
}

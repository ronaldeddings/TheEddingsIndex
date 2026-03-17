import SwiftUI
import EddingsKit
import GRDB

@MainActor
@Observable
final class MeetingsViewModel {
    var meetings: [Meeting] = []
    var selectedMeetingId: Int64?
    var meetingDetail: MeetingDetail?
    var isLoading = false

    struct MeetingDetail: Sendable {
        let meeting: Meeting
        let participants: [(participant: MeetingParticipant, contact: Contact?)]
        let transcriptExcerpt: String?
    }

    @ObservationIgnored private let dataAccess: DataAccess?

    init(dataAccess: DataAccess?) {
        self.dataAccess = dataAccess
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let da = dataAccess else { return }
        do {
            meetings = try da.recentMeetings(limit: 50)
        } catch {
            meetings = []
        }
    }

    func selectMeeting(_ id: Int64?) async {
        selectedMeetingId = id
        guard let id, let da = dataAccess else {
            meetingDetail = nil
            return
        }

        do {
            guard let meeting = try da.fetchMeeting(id: id) else { return }
            let participants = try da.participantsForMeeting(id)
            var excerpt: String?
            if let mid = meeting.meetingId as String? {
                let chunks = try da.transcriptsForMeeting(mid)
                excerpt = chunks.prefix(3).compactMap { $0.chunkText }.joined(separator: "\n\n")
                if excerpt?.isEmpty == true { excerpt = nil }
            }
            meetingDetail = MeetingDetail(
                meeting: meeting,
                participants: participants,
                transcriptExcerpt: excerpt
            )
        } catch {
            meetingDetail = nil
        }
    }

    var todayMeetings: [Meeting] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        return meetings.filter { m in
            guard let start = m.startTime else { return false }
            return start >= today && start < tomorrow
        }
    }

    var thisWeekMeetings: [Meeting] {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let weekEnd = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: today) ?? today
        return meetings.filter { m in
            guard let start = m.startTime else { return false }
            return start >= tomorrow && start < weekEnd
        }
    }

    var earlierMeetings: [Meeting] {
        let today = Calendar.current.startOfDay(for: Date())
        return meetings.filter { m in
            guard let start = m.startTime else { return true }
            return start < today
        }
    }

    var upcomingMeetings: [Meeting] {
        meetings.filter { m in
            guard let start = m.startTime else { return false }
            return start >= Date()
        }.prefix(3).map { $0 }
    }
}

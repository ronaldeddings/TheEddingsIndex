import SwiftUI
import EddingsKit

struct MeetingList: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meetings")
                    .font(EITypography.display())
                    .foregroundStyle(EIColor.textPrimary)
                Text("212 meetings in Q1 2026")
                    .font(EITypography.bodySmall())
                    .foregroundStyle(EIColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EISpacing.detailPadding)

            List {
                meetingRow(title: "CISO Roundtable Prep", date: "Yesterday · 2:00 PM", duration: "45 min", participants: 3, isInternal: false)
                meetingRow(title: "Emily 1:1 — Content Calendar", date: "Mar 12 · 3:30 PM", duration: "28 min", participants: 2, isInternal: true)
                meetingRow(title: "Optro <> Hacker Valley Kick-off", date: "Mar 12 · 10:00 AM", duration: "52 min", participants: 5, isInternal: false)
                meetingRow(title: "Mozilla Standup", date: "Mar 11 · 4:00 PM", duration: "15 min", participants: 8, isInternal: true)
                meetingRow(title: "Dr. Sharma Interview — Podcast", date: "Mar 10 · 11:00 AM", duration: "62 min", participants: 3, isInternal: false)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(EIColor.deep)
    }

    private func meetingRow(title: String, date: String, duration: String, participants: Int, isInternal: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: EIRadius.sm)
                .fill(EIColor.violet.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: isInternal ? "person.2" : "video")
                        .font(.system(size: 14))
                        .foregroundStyle(EIColor.violet)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(EITypography.bodyLarge())
                    .foregroundStyle(EIColor.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(date)
                        .font(EITypography.caption())
                        .foregroundStyle(EIColor.textTertiary)
                    Text("·")
                        .foregroundStyle(EIColor.textTertiary)
                    Text(duration)
                        .font(EITypography.caption())
                        .foregroundStyle(EIColor.textTertiary)
                    Text("·")
                        .foregroundStyle(EIColor.textTertiary)
                    Text("\(participants) participants")
                        .font(EITypography.caption())
                        .foregroundStyle(EIColor.textTertiary)
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

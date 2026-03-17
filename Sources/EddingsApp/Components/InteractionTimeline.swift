import SwiftUI
import EddingsKit

struct TimelineItem: Identifiable, Sendable {
    let id: String
    let source: EISource
    let title: String
    let detail: String
    let date: Date
}

struct InteractionTimeline: View {
    let items: [TimelineItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(item.source.color)
                            .frame(width: 8, height: 8)
                        if index < items.count - 1 {
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
                                .lineLimit(1)
                        }
                        if !item.detail.isEmpty {
                            Text(item.detail)
                                .font(EITypography.caption())
                                .foregroundStyle(EIColor.textSecondary)
                                .lineLimit(2)
                        }
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

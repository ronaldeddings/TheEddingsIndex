import SwiftUI
import EddingsKit

struct SearchView: View {
    @Environment(EddingsEngine.self) private var engine
    @State private var query = ""
    @State private var selectedSource: EISource? = nil

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(EIColor.textTertiary)
                    TextField("Search your reality...", text: $query)
                        .textFieldStyle(.plain)
                        .font(EITypography.body())
                        .foregroundStyle(EIColor.textPrimary)
                }
                .padding(12)
                .background(EIColor.card)
                .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: EIRadius.md)
                        .stroke(EIColor.border, lineWidth: 1)
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(EISource.allCases, id: \.self) { source in
                            Button {
                                selectedSource = selectedSource == source ? nil : source
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: source.sfSymbol)
                                        .font(.system(size: 11))
                                    Text(source.label)
                                        .font(EITypography.caption())
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 12)
                                .background(selectedSource == source ? source.dimColor : EIColor.elevated)
                                .foregroundStyle(selectedSource == source ? source.color : EIColor.textSecondary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(EISpacing.cardPadding)

            if engine.searchResults.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text("Search your reality")
                        .font(EITypography.title())
                        .foregroundStyle(EIColor.textTertiary)
                    Text("Emails, meetings, Slack, files, finances")
                        .font(EITypography.bodySmall())
                        .foregroundStyle(EIColor.textTertiary.opacity(0.6))
                }
                Spacer()
            } else {
                List(engine.searchResults) { result in
                    SearchResultRow(result: result)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(EIColor.deep)
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    private var source: EISource {
        switch result.sourceTable {
        case .emailChunks: return .email
        case .slackChunks: return .slack
        case .transcriptChunks: return .transcript
        case .documents: return .file
        case .financialTransactions: return .finance
        case .contacts, .meetings: return .file
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: EIRadius.sm)
                .fill(source.dimColor)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: source.sfSymbol)
                        .font(.system(size: 13))
                        .foregroundStyle(source.color)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(EITypography.bodyLarge())
                    .foregroundStyle(EIColor.textPrimary)
                    .lineLimit(1)

                if let snippet = result.snippet {
                    Text(snippet)
                        .font(EITypography.bodySmall())
                        .foregroundStyle(EIColor.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let date = result.date {
                        Text(date, style: .date)
                            .font(EITypography.caption())
                            .foregroundStyle(EIColor.textTertiary)
                    }
                    Text(source.label)
                        .font(EITypography.micro())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(source.dimColor)
                        .foregroundStyle(source.color)
                        .clipShape(RoundedRectangle(cornerRadius: EIRadius.sm))
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, EISpacing.cardPadding)
        .background(EIColor.card)
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
    }
}

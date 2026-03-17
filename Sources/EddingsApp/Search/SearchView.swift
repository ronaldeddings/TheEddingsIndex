import SwiftUI
import EddingsKit

struct SearchContentList: View {
    @Environment(SearchViewModel.self) private var searchVM

    var body: some View {
        @Bindable var searchVM = searchVM

        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(EIColor.textTertiary)
                    TextField("Search your reality...", text: $searchVM.query)
                        .textFieldStyle(.plain)
                        .font(EITypography.body())
                        .foregroundStyle(EIColor.textPrimary)
                        .onSubmit { searchVM.search() }
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
                                searchVM.toggleSource(source)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: source.sfSymbol)
                                        .font(.system(size: 11))
                                    Text(source.label)
                                        .font(EITypography.caption())
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 12)
                                .background(searchVM.selectedSources.contains(source) ? source.dimColor : EIColor.elevated)
                                .foregroundStyle(searchVM.selectedSources.contains(source) ? source.color : EIColor.textSecondary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(EISpacing.cardPadding)

            if searchVM.isSearching {
                Spacer()
                ProgressView()
                    .tint(EIColor.gold)
                Spacer()
            } else if searchVM.results.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text("Search your reality")
                        .font(EITypography.title())
                        .foregroundStyle(EIColor.textTertiary)
                    Text("15 years of data across email, Slack, meetings, files, and finances")
                        .font(EITypography.bodySmall())
                        .foregroundStyle(EIColor.textTertiary.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                List(searchVM.results, selection: Binding(
                    get: { searchVM.selectedResultId },
                    set: { searchVM.selectResult($0) }
                )) { result in
                    SearchResultRow(result: result, isSelected: result.id == searchVM.selectedResultId)
                        .tag(result.id)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(EIColor.surface)
        .onChange(of: searchVM.query) { _, _ in
            searchVM.search()
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult
    var isSelected: Bool = false

    private var source: EISource {
        switch result.sourceTable {
        case .emailChunks: return .email
        case .slackChunks: return .slack
        case .transcriptChunks: return .transcript
        case .documents: return .file
        case .financialTransactions: return .finance
        case .contacts: return .email
        case .meetings: return .meeting
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SourceIcon(source: source)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(EITypography.bodyLarge())
                    .foregroundStyle(EIColor.textPrimary)
                    .lineLimit(1)

                if let snippet = result.snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(EITypography.bodySmall())
                        .foregroundStyle(EIColor.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let date = result.date {
                        Text(date, style: .relative)
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
        .background(isSelected ? EIColor.gold.opacity(0.05) : EIColor.card)
        .clipShape(RoundedRectangle(cornerRadius: EIRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: EIRadius.md)
                .stroke(isSelected ? EIColor.gold.opacity(0.3) : EIColor.borderSubtle, lineWidth: isSelected ? 1 : 0.5)
        )
    }
}

struct SearchDetailView: View {
    @Environment(SearchViewModel.self) private var searchVM

    var body: some View {
        if let result = searchVM.selectedResult {
            let resolved = searchVM.resolveResult(result)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let source = mapSource(result.sourceTable)
                    HStack(spacing: 12) {
                        SourceIcon(source: source, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(resolved.title)
                                .font(EITypography.title())
                                .foregroundStyle(EIColor.textPrimary)
                            Text(source.label)
                                .font(EITypography.caption())
                                .foregroundStyle(source.color)
                        }
                    }

                    Divider().background(EIColor.border)

                    ForEach(Array(resolved.metadata.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                        if !value.isEmpty {
                            HStack(alignment: .top) {
                                Text(key.capitalized)
                                    .font(EITypography.label())
                                    .foregroundStyle(EIColor.textTertiary)
                                    .frame(width: 80, alignment: .leading)
                                Text(value)
                                    .font(EITypography.body())
                                    .foregroundStyle(EIColor.textSecondary)
                            }
                        }
                    }

                    if !resolved.fullText.isEmpty {
                        Divider().background(EIColor.border)
                        Text(resolved.fullText)
                            .font(EITypography.body())
                            .foregroundStyle(EIColor.textPrimary)
                            .textSelection(.enabled)
                    }
                }
                .padding(EISpacing.detailPadding)
            }
            .background(EIColor.deep)
        }
    }

    private func mapSource(_ table: SearchResult.SourceTable) -> EISource {
        switch table {
        case .emailChunks: return .email
        case .slackChunks: return .slack
        case .transcriptChunks: return .transcript
        case .documents: return .file
        case .financialTransactions: return .finance
        case .contacts: return .email
        case .meetings: return .meeting
        }
    }
}

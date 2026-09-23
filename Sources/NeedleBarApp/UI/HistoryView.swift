import SwiftUI
import NeedleBarCore

public struct HistoryView: View {
    @ObservedObject var appState: AppState
    @State private var searchText: String = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    private var filteredRecords: [HistoryRecord] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return appState.recentHistory
        }
        return appState.historyStore.search(query: searchText)
    }

    public var body: some View {
        AdaptiveGlassContainer(spacing: 8) {
            VStack(spacing: 8) {
                // Search & Clear bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))

                    TextField("Search history...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if !appState.recentHistory.isEmpty {
                        if #available(macOS 26, iOS 26, *) {
                            Button("Clear") {
                                appState.historyStore.clear()
                                appState.recentHistory = []
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                            .foregroundColor(.red.opacity(0.8))
                        } else {
                            Button("Clear") {
                                appState.historyStore.clear()
                                appState.recentHistory = []
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.8))
                        }
                    }
                }
                .padding(8)
                .liquidGlassCard(cornerRadius: 10)

                if filteredRecords.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(searchText.isEmpty ? "No command history yet." : "No matching commands found.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: 160)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filteredRecords) { record in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(record.success ? .green : .red)
                                        .font(.system(size: 12))
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(record.query)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)

                                        Text(record.summary)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)

                                        HStack(spacing: 6) {
                                            Text(formattedTimestamp(record.timestamp))
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary.opacity(0.7))

                                            if !record.toolNames.isEmpty {
                                                Text("• \(record.toolNames.joined(separator: ", "))")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.secondary.opacity(0.7))
                                            }
                                        }
                                    }

                                    Spacer()

                                    if #available(macOS 26, iOS 26, *) {
                                        Button(action: {
                                            appState.inputQuery = record.query
                                            appState.selectedTab = .command
                                            Task {
                                                await appState.submitCommand(record.query)
                                            }
                                        }) {
                                            Image(systemName: "arrow.counterclockwise")
                                                .font(.system(size: 11))
                                        }
                                        .buttonStyle(.glass)
                                        .help("Run again")
                                    } else {
                                        Button(action: {
                                            appState.inputQuery = record.query
                                            appState.selectedTab = .command
                                            Task {
                                                await appState.submitCommand(record.query)
                                            }
                                        }) {
                                            Image(systemName: "arrow.counterclockwise")
                                                .font(.system(size: 11))
                                                .foregroundColor(.accentColor)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Run again")
                                    }
                                }
                                .padding(8)
                                .liquidGlassCard(cornerRadius: 8)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }
        }
    }

    private func formattedTimestamp(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "Today at " + f.string(from: date)
        }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f.string(from: date)
    }
}

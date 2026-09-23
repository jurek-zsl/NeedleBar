import SwiftUI
import NeedleBarCore

public struct HelpCatalogView: View {
    @ObservedObject var appState: AppState
    @State private var selectedCategory: CapabilityCategory = .all
    @State private var filterQuery: String = ""
    @State private var hoveredExample: String? = nil

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("What NeedleBar Can Do")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Ask in natural language or click any sample command below to try it.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    appState.dismissHelp()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Circle().fill(Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("Close Help (Escape)")
            }

            // Search filter bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("Filter commands (e.g. volume, timer, window, search)...", text: $filterQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .rounded))

                if !filterQuery.isEmpty {
                    Button(action: { filterQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.8))

            // Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CapabilityCategory.allCases) { category in
                        Button(action: {
                            selectedCategory = category
                        }) {
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: selectedCategory == category ? .semibold : .medium, design: .rounded))
                                .foregroundColor(selectedCategory == category ? .white : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(selectedCategory == category ? Color.accentColor : Color.primary.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            // Scrollable list of capability cards
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 10) {
                    ForEach(filteredCapabilities) { item in
                        capabilityCard(item)
                    }

                    if filteredCapabilities.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "questionmark.folder")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            Text("No commands match \"\(filterQuery)\"")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 280)

            // Footer tips
            HStack {
                Text("Tip: Click an example to insert it, or click ▶ to execute immediately.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Press ⎋ to close")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.top, 2)
        }
    }

    private var filteredCapabilities: [CapabilityItem] {
        let all = HelpCatalog.allCapabilities
        return all.filter { item in
            let matchesCategory = (selectedCategory == .all) || (item.category == selectedCategory)
            guard matchesCategory else { return false }

            let query = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { return true }

            return item.title.lowercased().contains(query) ||
                   item.description.lowercased().contains(query) ||
                   item.category.rawValue.lowercased().contains(query) ||
                   item.examples.contains(where: { $0.lowercased().contains(query) })
        }
    }

    @ViewBuilder
    private func capabilityCard(_ item: CapabilityItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title & description header
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(item.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(item.category.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.04)))
            }

            // Clickable examples
            FlowLayout(spacing: 6) {
                ForEach(item.examples, id: \.self) { example in
                    exampleChip(example)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private func exampleChip(_ example: String) -> some View {
        HStack(spacing: 4) {
            // Clickable text to populate search bar
            Button(action: {
                appState.inputQuery = example
                appState.dismissHelp()
            }) {
                Text(example)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Insert \"\(example)\" into search bar")

            // One-click Run button
            Button(action: {
                appState.inputQuery = example
                appState.dismissHelp()
                Task {
                    await appState.submitCommand(example)
                }
            }) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.accentColor)
                    .padding(3)
                    .background(Circle().fill(Color.accentColor.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Run \"\(example)\" immediately")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(hoveredExample == example ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(hoveredExample == example ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 0.6)
        )
        .onHover { isHovered in
            hoveredExample = isHovered ? example : nil
        }
    }
}

// MARK: - Flow Layout Helper for Wrap Chips
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                height += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

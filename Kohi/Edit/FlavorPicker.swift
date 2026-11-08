import SwiftUI

/// Hierarchical flavour picker: search, quick set, then the wheel by family.
struct FlavorPicker: View {
    @Binding var selection: [FlavorTag]
    var recent: [FlavorTag] = []
    /// What the pack announces. Shown in its own row above, so Quick leaves it out.
    var declared: [FlavorTag] = []

    @State private var query = ""
    @State private var showAll = false
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !selection.isEmpty {
                selected
            }

            TextField("Search flavours", text: $query)
                .font(Typography.value)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(commitQuery)

            if !query.isEmpty {
                results
            } else {
                quick
                all
            }
        }
    }

    private var selected: some View {
        let grouped = Dictionary(grouping: selection) { tag -> String in
            FlavorWheel.shared.node(id: tag.id)?.parent
                .flatMap { FlavorWheel.shared.node(id: $0) }
                .map { family(of: $0) } ?? "other"
        }
        let families = FlavorWheel.shared.families
        return HStack(spacing: 6) {
            ForEach(families, id: \.id) { family in
                if let tags = grouped[family.id], !tags.isEmpty {
                    Text(tags.map(\.displayName).joined(separator: " · "))
                        .font(Typography.tag)
                        .foregroundStyle(Palette.ink)
                }
            }
            if let custom = grouped["other"] {
                Text(custom.map(\.displayName).joined(separator: " · "))
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
        }
    }

    private func family(of node: FlavorNode) -> String {
        var current = node
        while let parentID = current.parent, let parent = FlavorWheel.shared.node(id: parentID) {
            current = parent
        }
        return current.id
    }

    private var results: some View {
        let matches = FlavorWheel.shared.nodes.filter { node in
            let q = query.lowercased()
            return node.en.localizedCaseInsensitiveContains(q)
                || node.fr.localizedCaseInsensitiveContains(q)
                || node.synonyms.contains { $0.localizedCaseInsensitiveContains(q) }
                || node.id.contains(q)
        }
        return FlowLayout {
            ForEach(matches) { node in
                chip(FlavorTag(id: node.id))
            }
        }
    }

    private var quick: some View {
        let tags = QuickFlavors.compose(
            recent: recent,
            standard: FlavorWheel.shared.quick.map { FlavorTag(id: $0.id) },
            declared: declared,
            selection: selection
        )
        return VStack(alignment: .leading, spacing: 10) {
            Text("Quick").catalogueLabel()
            FlowLayout {
                ForEach(tags) { tag in
                    chip(tag)
                }
            }
        }
    }

    private var all: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Motion.quick) { showAll.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("All").catalogueLabel()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Palette.inkMuted)
                        .rotationEffect(.degrees(showAll ? 90 : 0))
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if showAll {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(FlavorWheel.shared.families) { family in
                        familyBlock(family)
                    }
                }
            }
        }
    }

    private func familyBlock(_ family: FlavorNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(family.en)
                .catalogueLabel()
            Rectangle().fill(Palette.hairline).frame(height: 1)
            FlowLayout {
                ForEach(FlavorWheel.shared.children(of: family.id)) { child in
                    HStack(spacing: 4) {
                        chip(FlavorTag(id: child.id))
                        let leaves = FlavorWheel.shared.children(of: child.id)
                        if !leaves.isEmpty {
                            Button {
                                withAnimation(Motion.quick) {
                                    if expanded.contains(child.id) {
                                        expanded.remove(child.id)
                                    } else {
                                        expanded.insert(child.id)
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Palette.inkMuted)
                                    .rotationEffect(.degrees(expanded.contains(child.id) ? 90 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            ForEach(FlavorWheel.shared.children(of: family.id)) { child in
                if expanded.contains(child.id) {
                    FlowLayout {
                        ForEach(FlavorWheel.shared.children(of: child.id)) { leaf in
                            chip(FlavorTag(id: leaf.id))
                        }
                    }
                    .padding(.leading, 8)
                }
            }
        }
    }

    private func chip(_ tag: FlavorTag) -> some View {
        let selected = selection.contains { $0.id == tag.id }
        return TagChip(text: tag.displayName, isSelected: selected) {
            withAnimation(Motion.quick) {
                if selected {
                    selection.removeAll { $0.id == tag.id }
                } else {
                    selection.append(tag)
                }
            }
        }
    }

    private func commitQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let match = FlavorMatcher.match(trimmed)
        for tag in match.tags where !selection.contains(where: { $0.id == tag.id }) {
            selection.append(tag)
        }
        query = ""
    }
}

/// The Quick row: your recent flavours, then the standard set, never what the
/// pack already shows. Capped, so the row stays a shortcut and search reaches
/// the rest of the wheel.
nonisolated enum QuickFlavors {
    static let cap = 12

    /// A ticked flavour beyond the cap is kept at the end: the summary above
    /// the picker is text, so this chip is the only way to untick it.
    static func compose(
        recent: [FlavorTag],
        standard: [FlavorTag],
        declared: [FlavorTag],
        selection: [FlavorTag],
        cap: Int = cap
    ) -> [FlavorTag] {
        var seen = Set(declared.map(\.id))
        let pool = (recent + standard).filter { seen.insert($0.id).inserted }
        let shown = Array(pool.prefix(cap))
        let shownIDs = Set(shown.map(\.id))
        let declaredIDs = Set(declared.map(\.id))
        var extraSeen = Set<String>()
        let ticked = selection.filter {
            !shownIDs.contains($0.id) && !declaredIDs.contains($0.id) && extraSeen.insert($0.id).inserted
        }
        return shown + ticked
    }
}

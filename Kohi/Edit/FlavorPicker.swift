import SwiftUI

/// Hierarchical flavour picker: search, quick set, then the wheel by family.
struct FlavorPicker: View {
    @Binding var selection: [FlavorTag]
    var recent: [FlavorTag] = []
    var suggested: [FlavorTag] = []

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
        let quickNodes = recent + suggested + FlavorWheel.shared.quick.map { FlavorTag(id: $0.id) }
        let unique = unique(quickNodes)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Quick").catalogueLabel()
            FlowLayout {
                ForEach(unique) { tag in
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

    private func unique(_ tags: [FlavorTag]) -> [FlavorTag] {
        var seen = Set<String>()
        return tags.filter { seen.insert($0.id).inserted }
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

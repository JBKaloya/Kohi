import SwiftUI

protocol CatalogItem {
    var catalogID: String { get }
    var brand: String { get }
    var model: String { get }
    var subfamily: String { get }
    var searchTerms: String { get }
}

extension CatalogItem {
    var catalogTitle: String {
        [brand, model].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    func catalogEntry(owned: Bool, subtitle: String? = nil) -> CatalogEntry {
        CatalogEntry(
            id: catalogID,
            title: catalogTitle.isEmpty ? catalogID : catalogTitle,
            subtitle: subtitle ?? subfamily,
            subfamily: subfamily,
            searchTerms: searchTerms,
            owned: owned
        )
    }
}

enum CatalogID {
    static func kit(_ id: UUID) -> String { "kit:\(id.uuidString)" }

    static func parseKit(_ id: String) -> UUID? {
        guard id.hasPrefix("kit:") else { return nil }
        return UUID(uuidString: String(id.dropFirst(4)))
    }
}

extension ReferenceBase.Grinder: CatalogItem {
    var catalogID: String { id }
    var subfamily: String {
        if let isManual { return isManual ? "Manual" : "Electric" }
        return adjustment?.label ?? "Grinder"
    }
    var searchTerms: String { "\(brand) \(model) \(id)" }
}

extension ReferenceBase.Brewer: CatalogItem {
    var catalogID: String { id }
    var subfamily: String { dripperFamily.brewerType.subfamily }
    var searchTerms: String { "\(brand) \(model) \(displayName) \(family)" }
}

extension FilterModel: CatalogItem {
    var catalogID: String { id }
    var subfamily: String { shape.label }
    var searchTerms: String { "\(displayName) \(model) \(id) \(shape.label)" }
}

extension ReferenceBase.Item: CatalogItem {
    var catalogID: String { id }
    var subfamily: String { family?.subfamily ?? kind.label }
    var searchTerms: String { "\(brand) \(model) \(displayName) \(kind.label)" }
}

/// One searchable catalogue for drippers, grinders and papers.
struct CatalogEntry: Identifiable, Hashable {
    var id: String
    var title: String
    var subtitle: String
    var subfamily: String
    var searchTerms: String
    var owned: Bool
}

struct CatalogPicker: View {
    var title: String
    var entries: [CatalogEntry]
    var selectedID: String?
    var unmatchedNote: String? = nil
    var confirmation: String = Copy.addedToYourKit
    var ownedSectionTitle: String = "From your kit"
    var onPick: (CatalogEntry) -> Void
    var onAddManually: () -> Void

    @State private var query = ""
    @State private var addedTag: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TextField("Search", text: $query)
                        .font(Typography.value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if let unmatchedNote {
                        Text(unmatchedNote)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }

                    if let addedTag {
                        Text(addedTag)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                    }

                    if !owned.isEmpty {
                        section(ownedSectionTitle, entries: owned)
                    }
                    ForEach(grouped, id: \.name) { group in
                        section(group.name, entries: group.entries)
                    }

                    Button {
                        dismiss()
                        onAddManually()
                    } label: {
                        Text(Copy.addManually)
                            .catalogueLabel()
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 44)
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(Palette.ink)
    }

    private var filtered: [CatalogEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return entries }
        return entries.filter { $0.searchTerms.lowercased().contains(needle) }
    }

    private var owned: [CatalogEntry] {
        filtered.filter(\.owned)
    }

    private var grouped: [(name: String, entries: [CatalogEntry])] {
        let rest = filtered.filter { !$0.owned }
        let keys = Array(Set(rest.map(\.subfamily))).sorted()
        return keys.map { key in
            let label = key.isEmpty ? "All" : key
            return (label, rest.filter { $0.subfamily == key })
        }
    }

    private func section(_ title: String, entries: [CatalogEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).catalogueLabel()
                .padding(.bottom, 8)
            ForEach(entries) { entry in
                Button {
                    onPick(entry)
                    if !entry.owned, !confirmation.isEmpty {
                        addedTag = confirmation
                    }
                    dismiss()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(Typography.value)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            if !entry.subtitle.isEmpty {
                                Text(entry.subtitle)
                                    .font(Typography.tag)
                                    .foregroundStyle(Palette.inkMuted)
                            }
                        }
                        Spacer()
                        if selectedID == entry.id {
                            CatalogueMark(text: "On", isSelected: true)
                        }
                    }
                    .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
        }
    }
}

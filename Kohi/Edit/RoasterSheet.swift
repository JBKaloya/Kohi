import SwiftUI

/// The smallest form that makes an index entry worth sharing: a name, and
/// where the roastery is.
///
/// City and country are not decoration — they are what tells two roasteries
/// with the same name apart, and the country is half of the dedupe key. While
/// either is typed, the index offers the spelling it already uses. A country
/// that can only mean one place is stored that way, so "Danemark" and
/// "Denmark" do not become two roasteries. The links are optional and exist
/// so a later enrichment pass has somewhere to start.
struct RoasterSheet: View {
    @Environment(RoasterStore.self) private var roasters
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    private let onAdd: (Roaster) -> Void

    @State private var name: String
    @State private var city = ""
    @State private var country = ""
    @State private var website = ""
    @State private var instagram = ""
    @State private var nameError: String?
    @State private var rejectTrigger = 0

    init(name: String, onAdd: @escaping (Roaster) -> Void) {
        _name = State(initialValue: name.trimmingCharacters(in: .whitespaces))
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 16) {
                        TextRow(
                            label: "Name",
                            text: $name,
                            placeholder: Placeholders.text(.roasterName),
                            labelWidth: 74,
                            presence: .useful,
                            hint: FieldCopy.roasterShared,
                            error: nameError
                        )
                        TextRow(
                            label: "City",
                            text: $city,
                            placeholder: Placeholders.text(.roasterCity),
                            labelWidth: 74,
                            presence: .useful,
                            hint: FieldCopy.roasterPlace,
                            completions: cityOffers.map(\.title),
                            onComplete: acceptCity
                        )
                        TextRow(
                            label: "Country",
                            text: $country,
                            placeholder: Placeholders.text(.roasterCountry),
                            labelWidth: 74,
                            presence: .useful,
                            hint: FieldCopy.roasterPlace,
                            completions: PlaceCompletion.countries(
                                matching: country,
                                known: knownCountries
                            ),
                            onComplete: { picked in
                                withAnimation(Motion.snappy) { country = picked }
                            }
                        )
                        TextRow(
                            label: "Website",
                            text: $website,
                            placeholder: Placeholders.text(.roasterWebsite),
                            labelWidth: 74,
                            capitalization: .never
                        )
                        TextRow(
                            label: "Instagram",
                            text: $instagram,
                            placeholder: Placeholders.text(.roasterInstagram),
                            labelWidth: 74,
                            capitalization: .never
                        )
                    }

                    if let existing {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.system(size: 10))
                            Text("Already in the index as \(existing.summary)")
                                .font(Typography.tag)
                        }
                        .foregroundStyle(Palette.inkMuted)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 40)
                .fieldKeyboardClearance()
            }
            .scrollIndicators(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Add roaster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Use existing", action: commit)
                        .fontWeight(.medium)
                }
            }
            .onChange(of: name) { _, _ in
                if trimmedName.count >= 2 { nameError = nil }
            }
        }
        .tint(Palette.ink)
        .haptic(.deleted, trigger: rejectTrigger)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var knownCountries: [String] {
        roasters.roasters.map(\.country)
    }

    private var cityOffers: [PlaceCompletion.CityOffer] {
        PlaceCompletion.cities(matching: city, in: roasters.roasters, country: country)
    }

    /// Shown before saving, not after: finding out you created a duplicate is
    /// worse than being told you were about to. The country is the resolved
    /// one, so a French spelling still finds the roastery already filed.
    private var existing: Roaster? {
        guard trimmedName.count >= 2 else { return nil }
        let probe = Roaster(name: trimmedName, country: resolvedCountry)
        return roasters.roasters.first { $0.dedupeKey == probe.dedupeKey }
    }

    private var resolvedCountry: String {
        PlaceCompletion.canonicalCountry(country, known: knownCountries)
    }

    private func acceptCity(_ title: String) {
        let filled = cityOffers.first { $0.title == title }?.country
        withAnimation(Motion.snappy) {
            city = title
            if country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let filled {
                country = filled
            }
        }
    }

    private func commit() {
        guard trimmedName.count >= 2 else {
            nameError = FieldCopy.roasterNameTooShort
            rejectTrigger += 1
            return
        }
        let roaster = Roaster(
            name: trimmedName,
            country: resolvedCountry.trimmingCharacters(in: .whitespaces),
            city: city.trimmingCharacters(in: .whitespaces),
            website: clean(website),
            instagram: clean(instagram),
            createdBy: account.userID
        )
        // `add` returns the existing entry when there is one, so the caller is
        // always handed the row that is really in the index.
        onAdd(roasters.add(roaster))
        dismiss()
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import SwiftUI

/// The coffees read off a menu, to pick the one in the cup.
///
/// Each row shows what was read; values with a question mark were inferred
/// and will be offered to confirm rather than filled.
struct MenuPickSheet: View {
    let candidates: [MenuCandidate]
    var canAskModel = false
    var onAskModel: () async -> [MenuCandidate] = { [] }
    /// The model is reading the menu on its own; its list replaces this one
    /// when it lands.
    var isModelReading = false
    let onPick: (MenuCandidate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shown: [MenuCandidate]?
    @State private var isAsking = false

    private var list: [MenuCandidate] { shown ?? candidates }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if list.isEmpty {
                        Text(Copy.menuNothingRead)
                            .font(Typography.body)
                            .foregroundStyle(Palette.inkMuted)
                            .padding(.vertical, 16)
                    }
                    ForEach(list) { candidate in
                        Button { onPick(candidate) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text(candidate.name)
                                        .font(Typography.value)
                                        .foregroundStyle(Palette.ink)
                                    if candidate.field(.name)?.confidence == .uncertain {
                                        Text("?").font(Typography.value).foregroundStyle(Palette.inkMuted)
                                    }
                                }
                                if !candidate.summary.isEmpty {
                                    Text(candidate.summary)
                                        .font(Typography.tag)
                                        .foregroundStyle(Palette.inkMuted)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Palette.hairline).frame(height: 1)
                    }

                    if canAskModel {
                        Button {
                            Task {
                                isAsking = true
                                shown = await onAskModel()
                                isAsking = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(Copy.menuReadWithModel).catalogueLabel()
                                if isAsking { ProgressView().controlSize(.mini) }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isAsking)
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(Copy.menuTitle)
            .navigationBarTitleDisplayMode(.inline)
            .tint(Palette.ink)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if isModelReading {
                    ToolbarItem(placement: .confirmationAction) {
                        ProgressView().controlSize(.mini)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.paper)
    }
}

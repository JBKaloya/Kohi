import SwiftUI

/// The template for anything the app deduced or asked a model for.
///
/// A provenance line is mandatory: that is what replaced the evidence chips.
/// Tap the block to read the detail; the sparkles mark a model, not a source.
struct InsightBlock<Detail: View>: View {
    var title: String
    var bodyText: String
    var provenance: String
    var isModel: Bool = false
    var action: (() -> Void)?
    @ViewBuilder var detail: () -> Detail

    init(
        title: String,
        bodyText: String,
        provenance: String,
        isModel: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.title = title
        self.bodyText = bodyText
        self.provenance = provenance
        self.isModel = isModel
        self.action = action
        self.detail = detail
    }

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    if isModel {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Text(title)
                        .catalogueLabel()
                }

                Text(bodyText)
                    .font(Typography.body)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                detail()

                Text(provenance)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
                    .textCase(.uppercase)
                    .tracking(Typography.labelTracking)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

extension InsightBlock where Detail == EmptyView {
    init(
        title: String,
        bodyText: String,
        provenance: String,
        isModel: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            bodyText: bodyText,
            provenance: provenance,
            isModel: isModel,
            action: action
        ) {
            EmptyView()
        }
    }
}

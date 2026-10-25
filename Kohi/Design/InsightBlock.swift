import SwiftUI

/// The template for anything the app deduced or asked a model for.
///
/// A provenance line is mandatory: that is what replaced the evidence chips.
/// Tap the block to read the detail; the cup marks a model, not a source.
/// An accessory sits on the title row, outside the tap target.
struct InsightBlock<Detail: View, Accessory: View>: View {
    var title: String
    var bodyText: String
    var provenance: String
    var isModel: Bool = false
    var action: (() -> Void)?
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var detail: () -> Detail

    init(
        title: String,
        bodyText: String,
        provenance: String,
        isModel: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.title = title
        self.bodyText = bodyText
        self.provenance = provenance
        self.isModel = isModel
        self.action = action
        self.accessory = accessory
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if isModel {
                    CoffeeCupIcon(size: 12, color: Palette.primary)
                }
                Text(title)
                    .catalogueLabel()
                if Accessory.self != EmptyView.self {
                    Spacer(minLength: 8)
                    accessory()
                }
            }

            Group {
                if let action {
                    Button(action: action) { reading }
                        .buttonStyle(.plain)
                } else {
                    reading
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 10) {
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
}

extension InsightBlock where Accessory == EmptyView {
    init(
        title: String,
        bodyText: String,
        provenance: String,
        isModel: Bool = false,
        action: (() -> Void)? = nil,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.init(
            title: title,
            bodyText: bodyText,
            provenance: provenance,
            isModel: isModel,
            action: action,
            accessory: { EmptyView() },
            detail: detail
        )
    }
}

extension InsightBlock where Detail == EmptyView, Accessory == EmptyView {
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

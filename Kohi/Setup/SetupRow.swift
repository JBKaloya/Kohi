import SwiftUI

/// A catalogue row: name on the left, one line of specifics in the `tag`
/// column on the right, hairline underneath. The same shape as a brew row, so
/// Setup reads as another section of the catalogue rather than as settings.
struct SetupRow: View {
    let title: String
    var detail: String = ""
    var tag: String = ""
    var isDefault: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(title)
                                .font(Typography.value)
                                .foregroundStyle(Palette.ink)
                            if isDefault {
                                Text("default")
                                    .font(Typography.tag)
                                    .foregroundStyle(Palette.inkMuted)
                            }
                        }
                        if !detail.isEmpty {
                            Text(detail)
                                .font(Typography.tag)
                                .foregroundStyle(Palette.inkMuted)
                        }
                    }
                    Spacer(minLength: 8)
                    if !tag.isEmpty {
                        Text(tag)
                            .font(Typography.tag)
                            .foregroundStyle(Palette.inkMuted)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Rectangle().fill(Palette.hairline).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The "Add a grinder" line that closes a section. Reads as an invitation, not
/// as a button: a plus sign and the same type as the rows above it.
struct SetupAddRow: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .catalogueLabel()
                Spacer()
            }
            .padding(.top, 2)
        }
        .buttonStyle(.plain)
    }
}

/// A catalogue section: uppercase heading, rows, and a line to say what is
/// missing when there are none.
struct SetupSection<Content: View>: View {
    let title: String
    var waiting: String = ""
    var isEmpty: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .catalogueLabel()

            if isEmpty, !waiting.isEmpty {
                Text(waiting)
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }
            content
        }
    }
}

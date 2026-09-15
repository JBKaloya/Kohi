import SwiftUI

/// Full-screen view of a single attachment with a delete option.
struct AttachmentDetailSheet: View {
    let cardID: UUID
    let attachment: CardAttachment
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.paper.ignoresSafeArea()

                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(20)
                } else {
                    ProgressView().tint(Palette.inkMuted)
                }
            }
            .navigationTitle(attachment.role.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        onDelete()
                        dismiss()
                    } label: {
                        Text("Remove")
                            .catalogueLabel()
                    }
                }
            }
        }
        .tint(Palette.ink)
        .task { await loadFull() }
    }

    private func loadFull() async {
        image = await Task.detached(priority: .userInitiated) {
            let url = ImageStore.shared.url(for: cardID, kind: .attachment(attachment.id))
            return ImageCodec.downsample(url, maxPixel: 2048)
        }.value
    }
}
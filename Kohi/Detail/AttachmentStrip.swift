import SwiftUI

/// Horizontal strip of attachment thumbnails with an add button. Used in both
/// the edit sheet and the detail view.
struct AttachmentStrip: View {
    let cardID: UUID
    let attachments: [CardAttachment]
    let onAdd: () -> Void
    var onSelect: ((CardAttachment) -> Void)?

    private let thumbHeight: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pages & documents")
                    .catalogueLabel()
                Spacer()
                Text("\(attachments.count)")
                    .font(Typography.tag)
                    .foregroundStyle(Palette.inkMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(attachments) { attachment in
                        attachmentThumb(attachment)
                    }
                    addButton
                }
            }
        }
    }

    private func attachmentThumb(_ attachment: CardAttachment) -> some View {
        Button {
            onSelect?(attachment)
        } label: {
            AttachmentThumbnailView(
                cardID: cardID,
                attachment: attachment,
                height: thumbHeight
            )
            .overlay(alignment: .bottomLeading) {
                if !attachment.caption.isEmpty {
                    Text(attachment.caption)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.5), in: .capsule)
                        .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) {
                Text(attachment.role.badge)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(width: 14, height: 14)
                    .background(Palette.ink.opacity(0.6), in: Circle())
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
                .frame(width: thumbHeight * 0.75, height: thumbHeight)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(Palette.inkMuted)
                }
        }
        .buttonStyle(.plain)
    }
}

/// Loads and displays a single attachment thumbnail.
struct AttachmentThumbnailView: View {
    let cardID: UUID
    let attachment: CardAttachment
    let height: CGFloat

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
            } else {
                Rectangle().fill(Palette.paperShade)
            }
        }
        .frame(width: height * attachment.aspectRatio, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .animation(Motion.quick, value: image == nil)
        .task(id: attachment.id) {
            image = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> CGImage? {
        await Task.detached(priority: .utility) {
            let store = ImageStore.shared
            let bucket = 512

            let thumbURL = store.url(for: cardID, kind: .attachmentThumbnail(attachment.id, bucket))
            if FileManager.default.fileExists(atPath: thumbURL.path(percentEncoded: false)),
               let img = ImageCodec.decode(thumbURL) {
                return img
            }

            return ImagePipeline.makeAttachmentThumbnail(
                cardID: cardID, attachmentID: attachment.id, bucket: bucket
            )
        }.value
    }
}

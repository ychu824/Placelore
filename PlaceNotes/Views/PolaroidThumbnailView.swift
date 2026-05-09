import SwiftUI

/// A single white polaroid-style card showing the first photo of a journal
/// entry plus the place name as a caption. Used as ambient decoration on the
/// Tracking page. Decode is asynchronous; an empty placeholder is shown until
/// the image is available.
struct PolaroidThumbnailView: View {
    let entry: JournalEntry

    @State private var image: UIImage?

    private var placeName: String {
        entry.place?.displayName ?? "Place"
    }

    private var firstAssetId: String? {
        entry.photoAssetIdentifiers.first
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                }
            }
            .frame(width: 98, height: 78)
            .clipped()

            Text(placeName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 4)
        }
        .padding(6)
        .background(Color.white)
        .cornerRadius(2)
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        .task(id: firstAssetId) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let id = firstAssetId else {
            image = nil
            return
        }
        image = PhotoStorage.loadImage(filename: id)
    }
}

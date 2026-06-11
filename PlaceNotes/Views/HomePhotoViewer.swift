import SwiftUI
import SwiftData

struct HomePhotoViewer: View {
    let item: HomePhotoItem
    @Binding var pendingPlaceID: PersistentIdentifier?
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            if let placeID = item.placeID {
                Button {
                    pendingPlaceID = placeID
                    dismiss()
                } label: {
                    Label("Go to Place", systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.black)
                }
                .padding(.bottom, 32)
            }
        }
        .task(id: item.filename) {
            image = await PhotoStorage.loadImageDetached(filename: item.filename)
        }
    }
}

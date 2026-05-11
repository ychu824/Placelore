import SwiftUI

struct AppIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedId: String = AppIconManager.currentOption.id

    var body: some View {
        List {
            Section {
                ForEach(AppIconManager.options) { option in
                    Button {
                        select(option)
                    } label: {
                        HStack(spacing: 16) {
                            Image(option.previewAsset)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )

                            Text(option.displayName)
                                .foregroundStyle(.primary)

                            Spacer()

                            if option.id == selectedId {
                                Image(systemName: "checkmark")
                                    .font(.body.bold())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                if !AppIconManager.supportsAlternateIcons {
                    Text("Your device doesn't support alternate app icons.")
                } else {
                    Text("The Home Screen icon updates immediately after you choose.")
                }
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func select(_ option: AppIconManager.Option) {
        selectedId = option.id
        Task { @MainActor in
            let error = await AppIconManager.setIcon(option)
            if error != nil {
                selectedId = AppIconManager.currentOption.id
            }
        }
    }
}

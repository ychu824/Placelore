import SwiftUI

struct HomePhotoGrid: View {
    let items: [HomePhotoItem]
    let now: Date
    let onTap: (HomePhotoItem) -> Void

    private let spacing: CGFloat = 2

    private var hero: HomePhotoItem? { items.first }
    private var followers: [HomePhotoItem] { Array(items.dropFirst()) }
    private var heroFollowersTopRow: [HomePhotoItem] { Array(followers.prefix(2)) }
    private var rest: [HomePhotoItem] { Array(followers.dropFirst(2)) }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        VStack(spacing: spacing) {
            if let hero {
                heroRow(hero: hero, followers: heroFollowersTopRow)
            }
            if !rest.isEmpty {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(rest) { item in
                        cell(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func heroRow(hero: HomePhotoItem, followers: [HomePhotoItem]) -> some View {
        GeometryReader { geo in
            let cellSize = (geo.size.width - spacing * 2) / 3
            HStack(alignment: .top, spacing: spacing) {
                heroCell(hero, size: cellSize * 2 + spacing)
                VStack(spacing: spacing) {
                    if let first = followers.first {
                        cell(first).frame(width: cellSize, height: cellSize)
                    } else {
                        Color.clear.frame(width: cellSize, height: cellSize)
                    }
                    if followers.count > 1 {
                        cell(followers[1]).frame(width: cellSize, height: cellSize)
                    } else {
                        Color.clear.frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
        .aspectRatio(1.5, contentMode: .fit)
    }

    @ViewBuilder
    private func heroCell(_ item: HomePhotoItem, size: CGFloat) -> some View {
        Button { onTap(item) } label: {
            PhotoThumbnailView(filename: item.filename)
                .frame(width: size, height: size)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .topLeading) {
                    if isFromToday(item) {
                        Text("NEW")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.65), in: Capsule())
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func cell(_ item: HomePhotoItem) -> some View {
        Button { onTap(item) } label: {
            PhotoThumbnailView(filename: item.filename)
                .aspectRatio(1, contentMode: .fill)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func isFromToday(_ item: HomePhotoItem) -> Bool {
        Calendar.current.isDate(item.date, inSameDayAs: now)
    }
}

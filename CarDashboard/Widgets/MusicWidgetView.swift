import MediaPlayer
import SwiftUI

struct MusicWidgetView: DashboardWidget {
    static let widgetTitle = "Musique"
    static let widgetSystemImage = "music.note"

    @StateObject private var player = MusicPlayerObserver()

    var body: some View {
        WidgetCard(title: Self.widgetTitle, systemImage: Self.widgetSystemImage) {
            switch player.authorizationStatus {
            case .authorized:
                if let item = player.nowPlayingItem {
                    playingContent(item)
                } else {
                    idleContent()
                }
            case .notDetermined:
                Button("Autoriser l'accès à Apple Music") {
                    player.requestAuthorization()
                }
                .buttonStyle(.borderedProminent)
            default:
                Text("Accès à Apple Music refusé — active-le dans Réglages")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// The card's aspect ratio differs a lot between orientations (wide-and-short in
    /// landscape, narrow-and-tall in the portrait right column), so the content adapts:
    /// artwork beside the text when there's width, stacked above it when there isn't.
    @ViewBuilder
    private func playingContent(_ item: MPMediaItem) -> some View {
        GeometryReader { proxy in
            if proxy.size.width >= proxy.size.height {
                horizontalContent(item, size: proxy.size)
            } else {
                verticalContent(item, size: proxy.size)
            }
        }
    }

    private func horizontalContent(_ item: MPMediaItem, size: CGSize) -> some View {
        let controlSize = min(60, size.height * 0.34)
        return HStack(spacing: 24) {
            artwork(item)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                trackLabels(item, alignment: .leading)
                Spacer(minLength: 8)
                controls(controlSize: controlSize)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func verticalContent(_ item: MPMediaItem, size: CGSize) -> some View {
        let controlSize = min(56, size.width * 0.24)
        return VStack(spacing: 12) {
            artwork(item)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            trackLabels(item, alignment: .center)
            controls(controlSize: controlSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trackLabels(_ item: MPMediaItem, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(item.title ?? "Titre inconnu")
                .font(.title.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
            Text(item.artist ?? "Artiste inconnu")
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private func controls(controlSize: CGFloat) -> some View {
        HStack(spacing: controlSize * 0.42) {
            Button {
                player.skipToPrevious()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: controlSize * 0.6))
            }

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.playbackState == .playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: controlSize))
            }

            Button {
                player.skipToNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: controlSize * 0.6))
            }

            if !player.playlists.isEmpty {
                playlistMenu {
                    Image(systemName: "music.note.list")
                        .font(.system(size: controlSize * 0.55))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func idleContent() -> some View {
        VStack(spacing: 16) {
            Text("Aucune lecture en cours")
                .foregroundStyle(.tertiary)
            if !player.playlists.isEmpty {
                playlistMenu {
                    Label("Lancer une playlist", systemImage: "music.note.list")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playlistMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Menu {
            ForEach(Array(player.playlists.enumerated()), id: \.offset) { _, playlist in
                Button(playlist.name ?? "Playlist") {
                    player.play(playlist: playlist)
                }
            }
        } label: {
            label()
        }
    }

    @ViewBuilder
    private func artwork(_ item: MPMediaItem) -> some View {
        if let artwork = item.artwork, let image = artwork.image(at: CGSize(width: 200, height: 200)) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
    }
}

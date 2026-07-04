import MediaPlayer
import SwiftUI

@MainActor
final class MusicPlayerObserver: ObservableObject {
    @Published private(set) var authorizationStatus = MPMediaLibrary.authorizationStatus()
    @Published private(set) var nowPlayingItem: MPMediaItem?
    @Published private(set) var playbackState: MPMusicPlaybackState = .stopped
    @Published private(set) var playlists: [MPMediaPlaylist] = []

    private let player = MPMusicPlayerController.systemMusicPlayer

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nowPlayingItemChanged),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: player
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playbackStateChanged),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: player
        )
        player.beginGeneratingPlaybackNotifications()
        nowPlayingItem = player.nowPlayingItem
        playbackState = player.playbackState
        loadPlaylists()
    }

    deinit {
        player.endGeneratingPlaybackNotifications()
        NotificationCenter.default.removeObserver(self)
    }

    func requestAuthorization() {
        MPMediaLibrary.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
                if status == .authorized { self?.loadPlaylists() }
            }
        }
    }

    func togglePlayPause() {
        if playbackState == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func skipToNext() {
        player.skipToNextItem()
    }

    func skipToPrevious() {
        player.skipToPreviousItem()
    }

    func play(playlist: MPMediaPlaylist) {
        player.setQueue(with: playlist)
        player.play()
    }

    func loadPlaylists() {
        guard authorizationStatus == .authorized else { return }
        Task.detached {
            let collections = MPMediaQuery.playlists().collections as? [MPMediaPlaylist] ?? []
            await MainActor.run { self.playlists = collections }
        }
    }

    @objc private func nowPlayingItemChanged() {
        nowPlayingItem = player.nowPlayingItem
    }

    @objc private func playbackStateChanged() {
        playbackState = player.playbackState
    }
}

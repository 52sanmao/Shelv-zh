import SwiftUI

struct AlbumContextMenuModifier: ViewModifier {
    let album: Album
    var showPreview: Bool = true

    @ObservedObject var libraryStore = LibraryStore.shared
    @ObservedObject var offlineMode = OfflineModeService.shared
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @AppStorage("enableDownloads") private var enableDownloads = false
    @AppStorage("themeColor") private var themeColorName = "violet"

    @State private var cachedSongs: [Song]?
    @State private var pendingPlaylistIds: PendingPlaylistIds?
    @State private var showDeleteAlbumDownloadConfirm = false

    func body(content: Content) -> some View {
        if showPreview {
            content.contextMenu {
                menuItems
            } preview: {
                AlbumArtView(coverArtId: album.coverArt, size: 600, cornerRadius: 0)
                    .frame(width: 280, height: 280)
                    .task { let _ = await fetchSongs() }
            }
            .sheet(item: $pendingPlaylistIds) { item in
                AddToPlaylistSheet(songIds: item.ids)
                    .environmentObject(libraryStore)
                    .tint(AppTheme.color(for: themeColorName))
            }
            .alert(tr("Delete Downloads?", "Downloads löschen?", "删除下载？"), isPresented: $showDeleteAlbumDownloadConfirm) {
                Button(tr("Delete", "Löschen", "删除"), role: .destructive) {
                    DownloadStore.shared.deleteAlbum(album.id)
                }
                Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
            } message: {
                Text(tr("The downloads will be removed from this device.", "Die Downloads werden von diesem Gerät entfernt.", "下载内容将从本设备删除。"))
            }
        } else {
            content.contextMenu { menuItems }
            .sheet(item: $pendingPlaylistIds) { item in
                AddToPlaylistSheet(songIds: item.ids)
                    .environmentObject(libraryStore)
                    .tint(AppTheme.color(for: themeColorName))
            }
            .alert(tr("Delete Downloads?", "Downloads löschen?", "删除下载？"), isPresented: $showDeleteAlbumDownloadConfirm) {
                Button(tr("Delete", "Löschen", "删除"), role: .destructive) {
                    DownloadStore.shared.deleteAlbum(album.id)
                }
                Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
            } message: {
                Text(tr("The downloads will be removed from this device.", "Die Downloads werden von diesem Gerät entfernt.", "下载内容将从本设备删除。"))
            }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button {
            Task {
                guard let songs = await fetchSongs(), !songs.isEmpty else { return }
                AudioPlayerService.shared.play(songs: songs, startIndex: 0)
            }
        } label: {
            Label(tr("Play", "Abspielen", "播放"), systemImage: "play.fill")
        }

        Button {
            Task {
                guard let songs = await fetchSongs(), !songs.isEmpty else { return }
                AudioPlayerService.shared.playShuffled(songs: songs)
            }
        } label: {
            Label(tr("Shuffle", "Zufällig", "随机播放"), systemImage: "shuffle")
        }

        Divider()

        Button {
            Task {
                guard let songs = await fetchSongs(), !songs.isEmpty else { return }
                AudioPlayerService.shared.addPlayNext(songs)
            }
        } label: {
            Label(tr("Play Next", "Als nächstes", "下一个播放"), systemImage: "text.insert")
        }

        Button {
            Task {
                guard let songs = await fetchSongs(), !songs.isEmpty else { return }
                AudioPlayerService.shared.addToQueue(songs)
            }
        } label: {
            Label(tr("Add to Queue", "Zur Warteschlange", "添加到播放队列"), systemImage: "text.badge.plus")
        }

        if !offlineMode.isOffline && (enableFavorites || enablePlaylists) {
            Divider()
            if enableFavorites {
                Button {
                    Task { await libraryStore.toggleStarAlbum(album) }
                } label: {
                    Label(
                        libraryStore.isAlbumStarred(album)
                            ? tr("Unfavorite", "Aus Favoriten entfernen", "取消收藏")
                            : tr("Favorite", "Zu Favoriten", "收藏"),
                        systemImage: libraryStore.isAlbumStarred(album) ? "heart.slash" : "heart"
                    )
                }
            }
            if enablePlaylists {
                Button {
                    if let cached = cachedSongs, !cached.isEmpty {
                        pendingPlaylistIds = PendingPlaylistIds(ids: cached.map(\.id))
                    } else {
                        Task {
                            guard let songs = await fetchSongs(), !songs.isEmpty else { return }
                            pendingPlaylistIds = PendingPlaylistIds(ids: songs.map(\.id))
                        }
                    }
                } label: {
                    Label(tr("Add to Playlist…", "Zur Playlist hinzufügen…", "添加到播放列表…"), systemImage: "music.note.list")
                }
            }
        }

        if enableDownloads {
            Divider()
            albumDownloadMenuItems
        }
    }

    @ViewBuilder
    private var albumDownloadMenuItems: some View {
        let status = DownloadStore.shared.albumDownloadStatus(
            albumId: album.id,
            totalSongs: album.songCount ?? 0
        )
        switch status {
        case .none:
            if !offlineMode.isOffline {
                Button {
                    DownloadStore.shared.enqueueAlbum(album)
                } label: {
                    Label(tr("Download Album", "Album herunterladen", "下载专辑"),
                          systemImage: "arrow.down.circle")
                }
            }
        case .partial:
            if !offlineMode.isOffline {
                Button {
                    DownloadStore.shared.enqueueAlbum(album)
                } label: {
                    Label(tr("Download Remaining", "Rest herunterladen", "下载剩余"),
                          systemImage: "arrow.down.circle")
                }
            }
            Button(role: .destructive) {
                showDeleteAlbumDownloadConfirm = true
            } label: {
                Label { Text(tr("Delete Downloads", "Downloads löschen", "删除下载")) } icon: { DeleteDownloadIcon(tint: .red) }
            }
        case .complete:
            Button(role: .destructive) {
                showDeleteAlbumDownloadConfirm = true
            } label: {
                Label { Text(tr("Delete Downloads", "Downloads löschen", "删除下载")) } icon: { DeleteDownloadIcon(tint: .red) }
            }
        }
    }

    private func fetchSongs() async -> [Song]? {
        if let cachedSongs { return cachedSongs }
        guard let detail = try? await SubsonicAPIService.shared.getAlbum(id: album.id) else { return nil }
        let songs = detail.song ?? []
        await MainActor.run { cachedSongs = songs }
        return songs
    }
}

extension View {
    func albumContextMenu(_ album: Album, showPreview: Bool = true) -> some View {
        modifier(AlbumContextMenuModifier(album: album, showPreview: showPreview))
    }
}

private struct PendingPlaylistIds: Identifiable {
    let id = UUID()
    let ids: [String]
}

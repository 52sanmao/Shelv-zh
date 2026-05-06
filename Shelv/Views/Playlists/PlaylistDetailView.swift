import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist

    @ObservedObject var libraryStore = LibraryStore.shared
    @ObservedObject var downloadStore = DownloadStore.shared
    @ObservedObject var offlineMode = OfflineModeService.shared
    private let player = AudioPlayerService.shared
    @AppStorage("themeColor") private var themeColorName = "violet"
    private var accentColor: Color { AppTheme.color(for: themeColorName) }
    @AppStorage("enableFavorites") private var enableFavorites = true
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    @AppStorage("enableDownloads") private var enableDownloads = false

    @State private var songs: [Song] = []
    @State private var displayName: String = ""
    @State private var showAddToPlaylist = false
    @State private var playlistSongIds: [String] = []
    @State private var isLoading = true
    @State private var isEditMode = false
    @State private var searchQuery = ""
    @State private var showRenameAlert = false
    @State private var newName = ""
    @State private var newComment = ""
    @State private var showDeleteConfirm = false
    @State private var showDeleteDownloadConfirm = false
    @State private var currentToast: ShelveToast?
    @State private var isSyncing = false
    @Environment(\.dismiss) private var dismiss

    private var displayedSongs: [Song] {
        guard !searchQuery.isEmpty, !isEditMode else { return songs }
        return songs.filter { $0.title.localizedCaseInsensitiveContains(searchQuery) }
    }

    var body: some View {
        List {
            Section {
                headerView
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if isLoading {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowSeparator(.hidden)
                }
            } else if songs.isEmpty {
                Section {
                    Text(tr("No songs in this playlist.", "Keine Titel in dieser Playlist.", "此播放列表中暂无歌曲。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(Array(displayedSongs.enumerated()), id: \.element.id) { displayIndex, song in
                        let songsIndex = songs.firstIndex(where: { $0.id == song.id }) ?? displayIndex
                        Button {
                            player.play(songs: songs, startIndex: songsIndex)
                        } label: {
                            HStack(spacing: 14) {
                                if !isEditMode {
                                    NowPlayingIndicator(
                                        songId: song.id,
                                        fallbackIndex: songsIndex + 1,
                                        accentColor: accentColor
                                    )
                                }
                                AlbumArtView(coverArtId: song.coverArt, size: 100, cornerRadius: 6)
                                    .frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if let artist = song.artist {
                                        Text(artist)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                if !isEditMode {
                                    DownloadStatusIcon(songId: song.id)
                                    Text(song.durationFormatted)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                haptic(); player.addToQueue(song)
                                currentToast = ShelveToast(message: tr("Added to Queue", "Zur Warteschlange hinzugefügt", "已添加到播放队列"))
                            } label: {
                                Image(systemName: "text.badge.plus")
                            }
                            .tint(accentColor)

                            Button {
                                haptic(); player.addPlayNext(song)
                                currentToast = ShelveToast(message: tr("Plays Next", "Wird als nächstes gespielt", "将下一个播放"))
                            } label: {
                                Image(systemName: "text.insert")
                            }
                            .tint(.orange)

                            if enableDownloads {
                                downloadSwipeButton(for: song)
                            }

                            if searchQuery.isEmpty {
                                Button(role: .destructive) {
                                    haptic(); Task { await removeSong(at: songsIndex) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .tint(.red)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if enableFavorites && !offlineMode.isOffline {
                                Button {
                                    haptic(.medium); Task { await libraryStore.toggleStarSong(song) }
                                } label: {
                                    Image(systemName: libraryStore.isSongStarred(song) ? "heart.slash" : "heart.fill")
                                }
                                .tint(.pink)
                            }
                            if enablePlaylists && !offlineMode.isOffline {
                                Button {
                                    playlistSongIds = [song.id]
                                    showAddToPlaylist = true
                                } label: {
                                    Image(systemName: "music.note.list")
                                }
                                .tint(accentColor)
                            }
                        }
                    }
                    .onMove { from, to in
                        songs.move(fromOffsets: from, toOffset: to)
                        Task { await syncOrder() }
                    }
                    .onDelete { offsets in
                        Task { await removeSongs(at: offsets) }
                    }
                    .deleteDisabled(isEditMode)

                    PlayerBottomSpacer(activeHeight: 110, inactiveHeight: 0)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.hidden)
        .searchable(text: $searchQuery, prompt: tr("Search songs…", "Titel suchen…", "搜索歌曲…"))
        .environment(\.editMode, .constant(isEditMode ? .active : .inactive))
        .navigationTitle(displayName.isEmpty ? playlist.name : displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isEditMode {
                    Button(tr("Done", "Fertig", "完成")) {
                        isEditMode = false
                    }
                    .bold()
                } else {
                    Menu {
                        Button {
                            searchQuery = ""
                            isEditMode = true
                        } label: {
                            Label(tr("Reorder / Delete", "Sortieren / Löschen", "排序 / 删除"), systemImage: "pencil")
                        }

                        Button {
                            newName = playlist.name
                            newComment = playlist.comment ?? ""
                            showRenameAlert = true
                        } label: {
                            Label(tr("Rename", "Umbenennen", "重命名"), systemImage: "pencil.line")
                        }

                        Divider()

                        Button {
                            if !songs.isEmpty { player.play(songs: songs, startIndex: 0) }
                        } label: {
                            Label(tr("Play", "Abspielen", "播放"), systemImage: "play.fill")
                        }
                        .disabled(songs.isEmpty)

                        Button {
                            if !songs.isEmpty { player.playShuffled(songs: songs) }
                        } label: {
                            Label(tr("Shuffle", "Zufällig", "随机播放"), systemImage: "shuffle")
                        }
                        .disabled(songs.isEmpty)

                        Button {
                            if !songs.isEmpty {
                                player.addPlayNext(songs)
                                currentToast = ShelveToast(message: tr("Plays Next", "Wird als nächstes gespielt", "将下一个播放"))
                            }
                        } label: {
                            Label(tr("Play Next", "Als nächstes", "下一个播放"), systemImage: "text.insert")
                        }
                        .disabled(songs.isEmpty)

                        Button {
                            if !songs.isEmpty {
                                player.addToQueue(songs)
                                currentToast = ShelveToast(message: tr("Added to Queue", "Zur Warteschlange hinzugefügt", "已添加到播放队列"))
                            }
                        } label: {
                            Label(tr("Add to Queue", "Zur Warteschlange", "添加到播放队列"), systemImage: "text.badge.plus")
                        }
                        .disabled(songs.isEmpty)

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label(tr("Delete Playlist", "Playlist löschen", "删除播放列表"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
        }
        .shelveToast($currentToast)
        .alert(tr("Rename Playlist", "Playlist umbenennen", "重命名播放列表"), isPresented: $showRenameAlert) {
            TextField(tr("Name", "Name", "名称"), text: $newName)
            TextField(tr("Comment", "Kommentar", "备注"), text: $newComment)
            Button(tr("Save", "Speichern", "保存")) {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let comment = newComment.trimmingCharacters(in: .whitespaces)
                Task {
                    await libraryStore.renamePlaylist(playlist, newName: name, newComment: comment)
                    displayName = name
                }
            }
            .bold()
            Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
        }
        .alert(
            tr("Delete Downloads?", "Downloads löschen?", "删除下载？"),
            isPresented: $showDeleteDownloadConfirm
        ) {
            Button(tr("Delete", "Löschen", "删除"), role: .destructive) {
                for song in songs { downloadStore.deleteSong(song.id) }
                downloadStore.removeOfflinePlaylist(playlist.id)
                currentToast = ShelveToast(message: tr("Downloads deleted", "Downloads gelöscht", "下载已删除"))
            }
            Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
        } message: {
            Text(tr("The downloads will be removed from this device.", "Die Downloads werden von diesem Gerät entfernt.", "下载内容将从本设备删除。"))
        }
        .alert(tr("Delete Playlist?", "Playlist löschen?", "删除播放列表？"), isPresented: $showDeleteConfirm) {
            Button(tr("Delete", "Löschen", "删除"), role: .destructive) {
                Task {
                    do {
                        try await libraryStore.deletePlaylist(playlist)
                        dismiss()
                    } catch {
                        if !(error is CancellationError) {
                            currentToast = ShelveToast(message: tr("Could not delete playlist", "Playlist konnte nicht gelöscht werden", "无法删除播放列表"), isError: true)
                        }
                    }
                }
            }
            Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
        } message: {
            Text("\"\(playlist.name)\"")
        }
        .sheet(isPresented: $showAddToPlaylist) {
            AddToPlaylistSheet(songIds: playlistSongIds)
                .environmentObject(libraryStore)
                .tint(accentColor)
        }
        .task(id: playlist.id) {
            displayName = playlist.name
            songs = []
            await loadSongs()
        }
        .onChange(of: offlineMode.isOffline) { _, _ in
            songs = []
            Task { await loadSongs() }
        }
        .onChange(of: downloadStore.songs.count) { _, _ in
            guard offlineMode.isOffline else { return }
            Task { await loadSongs() }
        }
    }

    private var headerView: some View {
        VStack(spacing: 16) {
            AlbumArtView(coverArtId: playlist.coverArt, size: 600, cornerRadius: 16)
                .frame(width: 220, height: 220)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)

            VStack(spacing: 4) {
                Text(displayName.isEmpty ? playlist.name : displayName)
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)
                if let comment = playlist.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if !isLoading {
                    Text("\(songs.count) \(tr("Songs", "Titel", "歌曲"))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal)

            VStack(spacing: 8) {
                HStack(spacing: 14) {
                    Button {
                        if !songs.isEmpty { player.play(songs: songs, startIndex: 0) }
                    } label: {
                        Label(tr("Play", "Abspielen", "播放"), systemImage: "play.fill")
                            .font(.body).bold()
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(songs.isEmpty)

                    Button {
                        if !songs.isEmpty { player.playShuffled(songs: songs) }
                    } label: {
                        Label(tr("Shuffle", "Zufällig", "随机播放"), systemImage: "shuffle")
                            .font(.body).bold()
                            .foregroundStyle(accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(songs.isEmpty)
                }
                if enableDownloads && !songs.isEmpty {
                    downloadHeaderButtons()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private func downloadHeaderButtons() -> some View {
        let isMarked = downloadStore.offlinePlaylistIds.contains(playlist.id)
        HStack(spacing: 10) {
            if !isMarked && !offlineMode.isOffline {
                Button {
                    haptic()
                    let missing = songs.filter { !downloadStore.isDownloaded(songId: $0.id) }
                    if !missing.isEmpty { downloadStore.enqueueSongs(missing) }
                    downloadStore.addOfflinePlaylist(playlist.id, songIds: songs.map(\.id))
                    currentToast = ShelveToast(message: tr("Download started", "Download gestartet", "下载已开始"))
                } label: {
                    Label(tr("Download", "Herunterladen", "下载"), systemImage: "arrow.down.circle")
                        .font(.subheadline).bold()
                        .foregroundStyle(accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            if isMarked {
                Button {
                    haptic()
                    showDeleteDownloadConfirm = true
                } label: {
                    Label(tr("Delete Downloads", "Downloads löschen", "删除下载"), systemImage: "arrow.down.circle")
                        .font(.subheadline).bold()
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadSongs() async {
        isLoading = true
        if let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id) {
            let allSongs = loaded.songs ?? []
            songs = offlineMode.isOffline
                ? allSongs.filter { downloadStore.isDownloaded(songId: $0.id) }
                : allSongs
        }
        // Fallback auf heruntergeladene Songs wenn API fehlschlug und Playlist markiert ist
        if songs.isEmpty && !offlineMode.isOffline && downloadStore.offlinePlaylistIds.contains(playlist.id) {
            let ids = downloadStore.playlistSongIds[playlist.id] ?? []
            songs = ids.compactMap { id in downloadStore.songs.first { $0.songId == id }?.asSong() }
        }
        if !offlineMode.isOffline && downloadStore.offlinePlaylistIds.contains(playlist.id) {
            if songs.contains(where: { !downloadStore.isDownloaded(songId: $0.id) }) {
                downloadStore.removeOfflinePlaylist(playlist.id)
            }
        }
        isLoading = false
    }

    private func removeSong(at index: Int) async {
        guard !isSyncing else { return }
        isSyncing = true
        songs.remove(at: index)
        await libraryStore.removeSongsFromPlaylist(playlist, indices: [index])
        isSyncing = false
    }

    private func removeSongs(at offsets: IndexSet) async {
        guard !isSyncing else { return }
        isSyncing = true
        let indices = Array(offsets).sorted(by: >)
        songs.remove(atOffsets: offsets)
        await libraryStore.removeSongsFromPlaylist(playlist, indices: indices)
        isSyncing = false
    }

    @ViewBuilder
    private func downloadSwipeButton(for song: Song) -> some View {
        if downloadStore.isDownloaded(songId: song.id) {
            Button {
                haptic(); downloadStore.deleteSong(song.id)
            } label: {
                DeleteDownloadIcon()
            }
            .tint(.red)
        } else if !offlineMode.isOffline {
            Button {
                haptic(); downloadStore.enqueueSongs([song])
            } label: {
                Image(systemName: "arrow.down.circle")
            }
            .tint(accentColor)
        }
    }

    private func syncOrder() async {
        guard !isSyncing else { return }
        isSyncing = true
        let newIds = songs.map(\.id)
        let allOldIndices = Array(0..<newIds.count)
        do {
            try await SubsonicAPIService.shared.updatePlaylist(
                id: playlist.id,
                songIdsToAdd: newIds,
                songIndicesToRemove: allOldIndices
            )
        } catch {
            currentToast = ShelveToast(message: tr("Order could not be saved", "Reihenfolge konnte nicht gespeichert werden", "排序无法保存"), isError: true)
            await loadSongs()
        }
        isSyncing = false
    }
}

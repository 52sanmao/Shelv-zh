import SwiftUI

struct PlaylistsView: View {
    @ObservedObject var libraryStore = LibraryStore.shared
    @EnvironmentObject var recapStore: RecapStore
    @ObservedObject var downloadStore = DownloadStore.shared
    @ObservedObject var offlineMode = OfflineModeService.shared
    private let player = AudioPlayerService.shared
    @AppStorage("themeColor") private var themeColorName = "violet"
    @AppStorage("enableDownloads") private var enableDownloads = false
    @AppStorage("enablePlaylists") private var enablePlaylists = true
    private var accentColor: Color { AppTheme.color(for: themeColorName) }

    private var visiblePlaylists: [Playlist] {
        let noRecap = libraryStore.playlists.filter { !recapStore.recapPlaylistIds.contains($0.id) }
        if offlineMode.isOffline {
            return noRecap.filter { downloadStore.offlinePlaylistIds.contains($0.id) }
        }
        return noRecap
    }

    @State private var showCreateSheet = false
    @State private var newPlaylistName = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var showDeleteConfirm = false
    @State private var playlistToDelete: Playlist?
    @State private var currentToast: ShelveToast?
    @State private var playlistToDeleteDownloads: Playlist?
    @State private var refreshContinuation: CheckedContinuation<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if libraryStore.isLoadingPlaylists && libraryStore.playlists.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visiblePlaylists.isEmpty {
                    List {
                        ContentUnavailableView(
                            tr("No Playlists", "Keine Playlists", "暂无播放列表"),
                            systemImage: "music.note.list",
                            description: Text(tr(
                                "Create a playlist to get started.",
                                "Erstelle eine Playlist, um loszulegen.",
                                "创建一个播放列表以开始使用。"
                            ))
                        )
                        .frame(maxWidth: .infinity, minHeight: 400)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.hidden)
                } else {
                    List {
                        Section {
                            ForEach(visiblePlaylists) { playlist in
                                NavigationLink(value: playlist) {
                                    playlistRow(playlist)
                                }
                                .contextMenu { playlistContextMenu(playlist) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        Task {
                                            if let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id),
                                               let songs = loaded.songs, !songs.isEmpty {
                                                await MainActor.run {
                                                    haptic(); player.addToQueue(songs)
                                                    currentToast = ShelveToast(message: tr("Added to Queue", "Zur Warteschlange hinzugefügt", "已添加到播放队列"))
                                                }
                                            }
                                        }
                                    } label: { Image(systemName: "text.badge.plus") }
                                    .tint(accentColor)
                                    Button {
                                        Task {
                                            if let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id),
                                               let songs = loaded.songs, !songs.isEmpty {
                                                await MainActor.run {
                                                    haptic(); player.addPlayNext(songs)
                                                    currentToast = ShelveToast(message: tr("Plays Next", "Wird als nächstes gespielt", "将下一个播放"))
                                                }
                                            }
                                        }
                                    } label: { Image(systemName: "text.insert") }
                                    .tint(.orange)
                                    if enableDownloads {
                                        playlistDownloadSwipe(playlist)
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if !offlineMode.isOffline {
                                        Button {
                                            playlistToDelete = playlist
                                            showDeleteConfirm = true
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .tint(.red)
                                    }
                                }
                            }
                        }
                        .listSectionSeparator(.hidden, edges: .top)

                        PlayerBottomSpacer()
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle(tr("Playlists", "Playlists", "播放列表"))
            .navigationDestination(for: Playlist.self) { playlist in
                PlaylistDetailView(playlist: playlist)
                    .id(playlist.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newPlaylistName = ""
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task(id: libraryStore.reloadID) {
                await libraryStore.loadPlaylists()
            }
            .refreshable {
                await withCheckedContinuation { cont in
                    refreshContinuation = cont
                    Task { @MainActor in
                        let bannerTask = Task {
                            try? await Task.sleep(for: .seconds(3))
                            if !Task.isCancelled { offlineMode.notifyServerError() }
                        }
                        async let reload: Void = libraryStore.loadPlaylists()
                        async let sync:   Void = CloudKitSyncService.shared.syncNow()
                        _ = await (reload, sync)
                        bannerTask.cancel()
                        if let cont = refreshContinuation {
                            refreshContinuation = nil
                            cont.resume()
                        }
                    }
                }
            }
            .onChange(of: offlineMode.isOffline) { _, isOffline in
                if isOffline, let cont = refreshContinuation {
                    refreshContinuation = nil
                    cont.resume()
                }
            }
            .alert(
                tr("Delete Playlist?", "Playlist löschen?", "删除播放列表？"),
                isPresented: $showDeleteConfirm,
                presenting: playlistToDelete
            ) { playlist in
                Button(tr("Delete", "Löschen", "删除"), role: .destructive) {
                    Task {
                        do {
                            try await libraryStore.deletePlaylist(playlist)
                        } catch {
                            if !(error is CancellationError) {
                                currentToast = ShelveToast(message: tr("Could not delete playlist", "Playlist konnte nicht gelöscht werden", "无法删除播放列表"), isError: true)
                            }
                        }
                    }
                }
                Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
            } message: { playlist in
                Text("\"\(playlist.name)\"")
            }
            .shelveToast($currentToast)
            .alert(
                tr("Delete Downloads?", "Downloads löschen?", "删除下载？"),
                isPresented: Binding(get: { playlistToDeleteDownloads != nil }, set: { if !$0 { playlistToDeleteDownloads = nil } }),
                presenting: playlistToDeleteDownloads
            ) { playlist in
                Button(tr("Delete", "Löschen", "删除"), role: .destructive) {
                    deletePlaylistDownloads(playlist)
                    currentToast = ShelveToast(message: tr("Downloads deleted", "Downloads gelöscht", "下载已删除"))
                }
                Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
            } message: { _ in
                Text(tr("The downloads will be removed from this device.", "Die Downloads werden von diesem Gerät entfernt.", "下载内容将从本设备删除。"))
            }
            .sheet(isPresented: $showCreateSheet) {
                createPlaylistSheet
            }
        }
    }

    @ViewBuilder
    private func playlistContextMenu(_ playlist: Playlist) -> some View {
        Button {
            Task {
                if let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id),
                   let songs = loaded.songs, !songs.isEmpty {
                    await MainActor.run { player.play(songs: songs, startIndex: 0) }
                }
            }
        } label: { Label(tr("Play", "Abspielen", "播放"), systemImage: "play.fill") }

        Button {
            Task {
                if let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id),
                   let songs = loaded.songs, !songs.isEmpty {
                    await MainActor.run { player.playShuffled(songs: songs) }
                }
            }
        } label: { Label(tr("Shuffle", "Zufällig", "随机播放"), systemImage: "shuffle") }

        Divider()

        Button {
            Task {
                if let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id),
                   let songs = loaded.songs, !songs.isEmpty {
                    await MainActor.run {
                        player.addPlayNext(songs)
                        currentToast = ShelveToast(message: tr("Plays Next", "Wird als nächstes gespielt", "将下一个播放"))
                    }
                }
            }
        } label: { Label(tr("Play Next", "Als nächstes", "下一个播放"), systemImage: "text.insert") }

        Button {
            Task {
                if let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id),
                   let songs = loaded.songs, !songs.isEmpty {
                    await MainActor.run {
                        player.addToQueue(songs)
                        currentToast = ShelveToast(message: tr("Added to Queue", "Zur Warteschlange hinzugefügt", "已添加到播放队列"))
                    }
                }
            }
        } label: { Label(tr("Add to Queue", "Zur Warteschlange", "添加到播放队列"), systemImage: "text.badge.plus") }

        if enablePlaylists {
            Button {
                Task {
                    if let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id),
                       let songs = loaded.songs, !songs.isEmpty {
                        NotificationCenter.default.post(name: .addSongsToPlaylist, object: songs.map(\.id))
                    }
                }
            } label: { Label(tr("Add to Playlist…", "Zur Playlist hinzufügen…", "添加到播放列表…"), systemImage: "music.note.list") }
        }

        if enableDownloads {
            Divider()
            if !offlineMode.isOffline && !downloadStore.offlinePlaylistIds.contains(playlist.id) {
                Button {
                    Task {
                        let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id)
                        libraryStore.errorMessage = nil
                        if let songs = loaded?.songs, !songs.isEmpty {
                            let missing = songs.filter { !downloadStore.isDownloaded(songId: $0.id) }
                            if !missing.isEmpty { downloadStore.enqueueSongs(missing) }
                            downloadStore.addOfflinePlaylist(playlist.id, songIds: songs.map(\.id))
                            currentToast = ShelveToast(message: tr("Download started", "Download gestartet", "下载已开始"))
                        }
                    }
                } label: { Label(tr("Download Playlist", "Playlist herunterladen", "下载播放列表"), systemImage: "arrow.down.circle") }
            }

            if downloadStore.offlinePlaylistIds.contains(playlist.id) {
                Button(role: .destructive) {
                    playlistToDeleteDownloads = playlist
                } label: {
                    Label { Text(tr("Delete Downloads", "Downloads löschen", "删除下载")) } icon: { DeleteDownloadIcon(tint: .red) }
                }
            }
        }

        Divider()

        if !offlineMode.isOffline {
            Button(role: .destructive) {
                playlistToDelete = playlist
                showDeleteConfirm = true
            } label: { Label(tr("Delete Playlist", "Playlist löschen", "删除播放列表"), systemImage: "trash") }
        }
    }

    @ViewBuilder
    private func playlistDownloadSwipe(_ playlist: Playlist) -> some View {
        if downloadStore.offlinePlaylistIds.contains(playlist.id) {
            Button(role: .destructive) {
                haptic(); playlistToDeleteDownloads = playlist
            } label: { DeleteDownloadIcon() }
            .tint(.red)
        } else if !offlineMode.isOffline {
            Button {
                haptic()
                Task {
                    let loaded = await libraryStore.loadPlaylistDetail(id: playlist.id)
                    libraryStore.errorMessage = nil
                    if let songs = loaded?.songs, !songs.isEmpty {
                        let missing = songs.filter { !downloadStore.isDownloaded(songId: $0.id) }
                        if !missing.isEmpty { downloadStore.enqueueSongs(missing) }
                        downloadStore.addOfflinePlaylist(playlist.id, songIds: songs.map(\.id))
                        currentToast = ShelveToast(message: tr("Download started", "Download gestartet", "下载已开始"))
                    }
                }
            } label: { Image(systemName: "arrow.down.circle") }
            .tint(accentColor)
        }
    }

    private func deletePlaylistDownloads(_ playlist: Playlist) {
        // Marker zuerst entfernen — Row verschwindet sofort aus der Liste,
        // verhindert dass weiteres Swipe/Tap auf der gerade verschwindenden Row crasht.
        let playlistId = playlist.id
        downloadStore.removeOfflinePlaylist(playlistId)
        Task {
            if let loaded = await libraryStore.loadPlaylistDetail(id: playlistId),
               let songs = loaded.songs {
                for song in songs {
                    downloadStore.deleteSong(song.id)
                }
            }
        }
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        HStack(spacing: 12) {
            AlbumArtView(coverArtId: playlist.coverArt, size: 150, cornerRadius: 8)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                let count = offlineMode.isOffline
                    ? downloadStore.downloadedCount(for: playlist.id)
                    : playlist.songCount
                if let count {
                    Text("\(count) \(tr("Songs", "Titel", "歌曲"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            PlaylistDownloadBadge(playlistId: playlist.id)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var createPlaylistSheet: some View {
        NavigationStack {
            Form {
                Section(tr("Name", "Name", "名称")) {
                    TextField(tr("My Playlist", "Meine Playlist", "我的播放列表"), text: $newPlaylistName)
                        .focused($nameFieldFocused)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(tr("New Playlist", "Neue Playlist", "新建播放列表"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    nameFieldFocused = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {
                        showCreateSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Create", "Erstellen", "创建")) {
                        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        showCreateSheet = false
                        Task { await libraryStore.createPlaylist(name: name) }
                    }
                    .bold()
                    .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .tint(accentColor)
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(24)
    }
}

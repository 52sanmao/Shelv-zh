import SwiftUI

struct RecapAdvancedView: View {
    let serverId: String
    @EnvironmentObject var recapStore: RecapStore
    @AppStorage("themeColor") private var themeColorName = "violet"

    @State private var testResult: String?
    @State private var resetLastWeekResult: String?
    @State private var resetLastMonthResult: String?
    @State private var resetLastYearResult: String?
    @State private var showResetConfirm = false
    @State private var showIcloudResetConfirm = false
    @State private var showFullResetConfirm = false
    @State private var showResetLastWeekConfirm = false
    @State private var showResetLastMonthConfirm = false
    @State private var showResetLastYearConfirm = false
    @State private var isIcloudResetting = false
    @State private var isFullResetting = false
    @State private var isResettingLastWeek = false
    @State private var isResettingLastMonth = false
    @State private var isResettingLastYear = false

    private var accentColor: Color { AppTheme.color(for: themeColorName) }

    var body: some View {
        List {
            Section(tr("Testing", "Testen", "测试")) {
                Button {
                    testResult = nil
                    Task {
                        let created = await recapStore.generateTest(serverId: serverId)
                        testResult = created
                            ? tr("Playlist created.", "Playlist erstellt.", "播放列表已创建。")
                            : tr("No plays logged yet — skip songs first.", "Noch keine Plays — zuerst Songs skippen.", "暂无播放记录——请先跳过歌曲。")
                    }
                } label: {
                    if recapStore.isGenerating {
                        ProgressView()
                    } else {
                        Label(
                            tr("Generate test recap (last 7 days)", "Test-Recap erstellen (letzte 7 Tage)", "生成测试回顾（最近7天）"),
                            systemImage: "wand.and.stars"
                        )
                        .foregroundStyle(accentColor)
                    }
                }
                .disabled(recapStore.isGenerating)

                if let result = testResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
                if let err = recapStore.generationError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                Button(role: .destructive) {
                    showResetLastWeekConfirm = true
                } label: {
                    if isResettingLastWeek {
                        HStack {
                            ProgressView()
                            Text(tr("Resetting…", "Setze zurück…", "重置中…")).foregroundStyle(.red)
                        }
                    } else {
                        Label(
                            tr("Reset latest weekly recap", "Letzten Wochen-Recap zurücksetzen", "重置最近的周回顾"),
                            systemImage: "arrow.uturn.backward.circle"
                        )
                        .foregroundStyle(.red)
                    }
                }
                .disabled(isResettingLastWeek)

                if let result = resetLastWeekResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    showResetLastMonthConfirm = true
                } label: {
                    if isResettingLastMonth {
                        HStack {
                            ProgressView()
                            Text(tr("Resetting…", "Setze zurück…", "重置中…")).foregroundStyle(.red)
                        }
                    } else {
                        Label(
                            tr("Reset latest monthly recap", "Letzten Monats-Recap zurücksetzen", "重置最近的月回顾"),
                            systemImage: "arrow.uturn.backward.circle"
                        )
                        .foregroundStyle(.red)
                    }
                }
                .disabled(isResettingLastMonth)

                if let result = resetLastMonthResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    showResetLastYearConfirm = true
                } label: {
                    if isResettingLastYear {
                        HStack {
                            ProgressView()
                            Text(tr("Resetting…", "Setze zurück…", "重置中…")).foregroundStyle(.red)
                        }
                    } else {
                        Label(
                            tr("Reset latest yearly recap", "Letzten Jahres-Recap zurücksetzen", "重置最近的年回顾"),
                            systemImage: "arrow.uturn.backward.circle"
                        )
                        .foregroundStyle(.red)
                    }
                }
                .disabled(isResettingLastYear)

                if let result = resetLastYearResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(tr("Destructive actions", "Löschaktionen", "危险操作")) {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label(
                        tr("Reset local database", "Lokale Datenbank zurücksetzen", "重置本地数据库"),
                        systemImage: "arrow.counterclockwise"
                    )
                    .foregroundStyle(.red)
                }

                Button(role: .destructive) {
                    showIcloudResetConfirm = true
                } label: {
                    if isIcloudResetting {
                        HStack {
                            ProgressView()
                            Text(tr("Deleting…", "Lösche…", "删除中…")).foregroundStyle(.red)
                        }
                    } else {
                        Label(
                            tr("Delete iCloud data", "iCloud-Daten löschen", "删除 iCloud 数据"),
                            systemImage: "icloud.slash"
                        )
                        .foregroundStyle(.red)
                    }
                }
                .disabled(isIcloudResetting)

                Button(role: .destructive) {
                    showFullResetConfirm = true
                } label: {
                    if isFullResetting {
                        HStack {
                            ProgressView()
                            Text(tr("Deleting…", "Lösche…", "删除中…")).foregroundStyle(.red)
                        }
                    } else {
                        Label(
                            tr("Delete everything", "Alles löschen", "删除所有数据"),
                            systemImage: "trash.slash"
                        )
                        .foregroundStyle(.red)
                    }
                }
                .disabled(isFullResetting)
            }

            PlayerBottomSpacer(activeHeight: 110, inactiveHeight: 0)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .navigationTitle(tr("Advanced", "Erweitert", "高级"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            tr("Reset local database?", "Lokale Datenbank zurücksetzen?", "重置本地数据库？"),
            isPresented: $showResetConfirm
        ) {
            Button(tr("Reset", "Zurücksetzen", "重置"), role: .destructive) {
                Task {
                    await PlayLogService.shared.resetLog(serverId: serverId)
                    await PlayLogService.shared.resetRegistry(serverId: serverId)
                    await CloudKitSyncService.shared.resetChangeToken()
                    await recapStore.loadEntries(serverId: serverId)
                    NotificationCenter.default.post(name: .recapRegistryUpdated, object: nil)
                    testResult = nil
                }
            }
            Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
        } message: {
            Text(tr("Clears the local cache only. iCloud and Navidrome stay untouched. Next sync will re-fetch from iCloud.", "Löscht nur den lokalen Cache. iCloud und Navidrome bleiben unberührt. Beim nächsten Sync kommt alles aus iCloud zurück.", "仅清除本地缓存。iCloud 和 Navidrome 不受影响。下次同步将从 iCloud 重新获取。"))
        }
        .alert(
            tr("Delete iCloud data?", "iCloud-Daten löschen?", "删除 iCloud 数据？"),
            isPresented: $showIcloudResetConfirm
        ) {
            Button(tr("Delete", "Löschen", "删除"), role: .destructive) {
                Task { await performIcloudReset() }
            }
            Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
        } message: {
            Text(tr("All iCloud records for this server will be deleted. Local database and Navidrome playlists stay untouched.", "Alle iCloud-Einträge für diesen Server werden gelöscht. Lokale Datenbank und Navidrome-Playlists bleiben unberührt.", "该服务器的所有 iCloud 记录将被删除。本地数据库和 Navidrome 播放列表不受影响。"))
        }
        .alert(
            tr("Reset latest weekly recap?", "Letzten Wochen-Recap zurücksetzen?", "重置最近的周回顾？"),
            isPresented: $showResetLastWeekConfirm
        ) {
            Button(tr("Reset", "Zurücksetzen", "重置"), role: .destructive) {
                Task { await performResetLastWeek() }
            }
            Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
        } message: {
            Text(tr("Deletes the newest weekly recap (playlist, iCloud marker, local entry) and clears the auto-generation timestamp. Restart the app to trigger regeneration.", "Löscht den neuesten Wochen-Recap (Playlist, iCloud-Marker, DB-Eintrag) und setzt den Zeitstempel der Auto-Generation zurück. App neu starten, um die Neu-Generation auszulösen.", "删除最新的周回顾（播放列表、iCloud 标记、本地记录）并清除自动生成时间戳。请重启应用以触发重新生成。"))
        }
        .alert(
            tr("Reset latest monthly recap?", "Letzten Monats-Recap zurücksetzen?", "重置最近的月回顾？"),
            isPresented: $showResetLastMonthConfirm
        ) {
            Button(tr("Reset", "Zurücksetzen", "重置"), role: .destructive) {
                Task { await performResetLastMonth() }
            }
            Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
        } message: {
            Text(tr("Deletes the newest monthly recap and clears its auto-generation timestamp. Restart the app to trigger regeneration.", "Löscht den neuesten Monats-Recap und setzt den Zeitstempel der Auto-Generation zurück. App neu starten, um die Neu-Generation auszulösen.", "删除最新的月回顾并清除自动生成时间戳。请重启应用以触发重新生成。"))
        }
        .alert(
            tr("Reset latest yearly recap?", "Letzten Jahres-Recap zurücksetzen?", "重置最近的年回顾？"),
            isPresented: $showResetLastYearConfirm
        ) {
            Button(tr("Reset", "Zurücksetzen", "重置"), role: .destructive) {
                Task { await performResetLastYear() }
            }
            Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
        } message: {
            Text(tr("Deletes the newest yearly recap and clears its auto-generation timestamp. Restart the app to trigger regeneration.", "Löscht den neuesten Jahres-Recap und setzt den Zeitstempel der Auto-Generation zurück. App neu starten, um die Neu-Generation auszulösen.", "删除最新的年回顾并清除自动生成时间戳。请重启应用以触发重新生成。"))
        }
        .alert(
            tr("Delete everything?", "Alles löschen?", "删除所有数据？"),
            isPresented: $showFullResetConfirm
        ) {
            Button(tr("Delete everything", "Alles löschen", "删除所有数据"), role: .destructive) {
                Task { await performFullReset() }
            }
            Button(tr("Cancel", "Abbrechen", "取消"), role: .cancel) {}
        } message: {
            Text(tr("All recap playlists on Navidrome, local play logs and iCloud records for this server will be permanently deleted. This bypasses the iCloud sync toggle.", "Alle Recap-Playlists auf Navidrome, lokale Plays und iCloud-Einträge für diesen Server werden unwiderruflich gelöscht. Umgeht den iCloud-Sync-Schalter.", "该服务器在 Navidrome 上的所有回顾播放列表、本地播放日志和 iCloud 记录将被永久删除。此操作会绕过 iCloud 同步开关。"))
        }
    }

    private func performResetLastWeek() async {
        isResettingLastWeek = true
        defer { isResettingLastWeek = false }
        resetLastWeekResult = nil
        let removed = await recapStore.resetLastWeek(serverId: serverId)
        resetLastWeekResult = removed
            ? tr("Removed — restart the app to regenerate.", "Entfernt — App neu starten zum Regenerieren.", "已删除——请重启应用以重新生成。")
            : tr("No weekly recap to reset.", "Kein Wochen-Recap vorhanden.", "暂无可重置的周回顾。")
    }

    private func performResetLastMonth() async {
        isResettingLastMonth = true
        defer { isResettingLastMonth = false }
        resetLastMonthResult = nil
        let removed = await recapStore.resetLastMonth(serverId: serverId)
        resetLastMonthResult = removed
            ? tr("Removed — restart the app to regenerate.", "Entfernt — App neu starten zum Regenerieren.", "已删除——请重启应用以重新生成。")
            : tr("No monthly recap to reset.", "Kein Monats-Recap vorhanden.", "暂无可重置的月回顾。")
    }

    private func performResetLastYear() async {
        isResettingLastYear = true
        defer { isResettingLastYear = false }
        resetLastYearResult = nil
        let removed = await recapStore.resetLastYear(serverId: serverId)
        resetLastYearResult = removed
            ? tr("Removed — restart the app to regenerate.", "Entfernt — App neu starten zum Regenerieren.", "已删除——请重启应用以重新生成。")
            : tr("No yearly recap to reset.", "Kein Jahres-Recap vorhanden.", "暂无可重置的年回顾。")
    }

    private func performIcloudReset() async {
        isIcloudResetting = true
        defer { isIcloudResetting = false }

        await CloudKitSyncService.shared.deleteZone(force: true)
        await PlayLogService.shared.markServerUnsyncedForReUpload(serverId: serverId)
        await CloudKitSyncService.shared.updatePendingCounts()
    }

    private func performFullReset() async {
        isFullResetting = true
        defer { isFullResetting = false }

        let registry = await PlayLogService.shared.allRegistryEntries(serverId: serverId)
        for entry in registry {
            try? await SubsonicAPIService.shared.deletePlaylist(id: entry.playlistId)
        }

        await CloudKitSyncService.shared.deleteZone(force: true)

        await PlayLogService.shared.resetLog(serverId: serverId)
        await PlayLogService.shared.resetRegistry(serverId: serverId)
        await PlayLogService.shared.removeScrobbles(serverId: serverId)
        await CloudKitSyncService.shared.resetChangeToken()
        await CloudKitSyncService.shared.updatePendingCounts()

        await recapStore.loadEntries(serverId: serverId)
        testResult = nil
    }
}

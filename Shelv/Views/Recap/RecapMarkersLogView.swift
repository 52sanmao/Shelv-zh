import SwiftUI

private struct PeriodStatus {
    let period: RecapPeriod
    let processed: Bool
    let entryExists: Bool
    let plays: Int
}

struct RecapMarkersLogView: View {
    let serverId: String
    @AppStorage("themeColor") private var themeColorName = "violet"
    @State private var weekly: [PeriodStatus] = []
    @State private var monthly: PeriodStatus?
    @State private var yearly: PeriodStatus?
    @State private var isLoading = false

    private var accentColor: Color { AppTheme.color(for: themeColorName) }

    private let rangeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d. MMM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private let yearFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()

    private func rangeString(_ p: RecapPeriod) -> String {
        switch p.type {
        case .week:
            return "\(rangeFmt.string(from: p.start)) – \(rangeFmt.string(from: p.end))"
        case .month:
            let f = DateFormatter()
            f.dateFormat = "MMMM yyyy"
            return f.string(from: p.start)
        case .year:
            return yearFmt.string(from: p.start)
        }
    }

    var body: some View {
        List {
            Section {
                if weekly.isEmpty {
                    Text(tr("Loading…", "Lade…", "加载中…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(weekly.indices, id: \.self) { idx in
                        row(status: weekly[idx])
                    }
                }
            } header: {
                Text(tr("Weekly — last 4 weeks", "Wöchentlich — letzte 4 Wochen", "每周——最近4周"))
            } footer: {
                Text(tr("A week is marked ✓ processed when generate() succeeds. An unprocessed week will be retried on next app start.", "Eine Woche wird ✓ markiert, sobald generate() erfolgreich war. Nicht markierte Wochen werden beim nächsten App-Start erneut versucht.", "当 generate() 成功时，该周标记为 ✓ 已处理。未处理的周将在下次启动时重试。"))
            }

            Section(tr("Monthly — last month", "Monatlich — letzter Monat", "每月——上个月")) {
                if let m = monthly {
                    row(status: m)
                } else {
                    Text(tr("—", "—")).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(tr("Yearly — last year", "Jährlich — letztes Jahr", "每年——去年")) {
                if let y = yearly {
                    row(status: y)
                } else {
                    Text(tr("—", "—")).font(.caption).foregroundStyle(.secondary)
                }
            }

            PlayerBottomSpacer(activeHeight: 110, inactiveHeight: 0)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .navigationTitle(tr("Auto-gen markers", "Auto-Gen-Marker", "自动生成标记"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await reload() } } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .tint(accentColor)
                .disabled(isLoading)
            }
        }
        .task { await reload() }
    }

    @ViewBuilder
    private func row(status: PeriodStatus) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(rangeString(status.period))
                    .font(.body.weight(.medium))
                Spacer()
                Text(status.period.periodKey)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text(tr("Marker:", "Marker:", "标记：")).foregroundStyle(.secondary)
                Text(status.processed ? tr("set", "gesetzt", "已设置") : tr("not set", "nicht gesetzt", "未设置"))
                    .foregroundStyle(status.processed ? .green : .secondary)
                Text("·").foregroundStyle(.secondary)
                Text(tr("Playlist:", "Playlist:", "播放列表：")).foregroundStyle(.secondary)
                Text(status.entryExists ? tr("exists", "vorhanden", "存在") : tr("missing", "fehlt", "缺失"))
                    .foregroundStyle(status.entryExists ? accentColor : .secondary)
                Text("·").foregroundStyle(.secondary)
                Text(tr("Plays:", "Plays:", "播放次数：")).foregroundStyle(.secondary)
                Text("\(status.plays)")
                    .foregroundStyle(status.plays > 0 ? .primary : .secondary)
            }
            .font(.caption)

            if !status.processed && status.plays == 0 {
                Text(tr("Will retry on next app start (no plays yet).", "Wird beim nächsten App-Start erneut versucht (keine Plays).", "将在下次启动时重试（暂无播放记录）。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !status.processed && status.plays > 0 && !status.entryExists {
                Text(tr("Pending generation on next app start.", "Wartet auf Generierung beim nächsten App-Start.", "等待下次启动时生成。"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if status.processed && !status.entryExists {
                Text(tr("Processed, playlist deleted — will not regenerate.", "Markiert, Playlist gelöscht — wird nicht regeneriert.", "已处理，播放列表已删除——不会重新生成。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Loading

    private func reload() async {
        isLoading = true
        defer { isLoading = false }

        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2

        var weeks: [RecapPeriod] = []
        if let mostRecent = RecapPeriod.lastWeek() {
            weeks.append(mostRecent)
            var current = mostRecent
            for _ in 0..<3 {
                guard
                    let prevStart = cal.date(byAdding: .weekOfYear, value: -1, to: current.start),
                    let prevEnd   = cal.date(byAdding: .second, value: -1, to: current.start)
                else { break }
                current = RecapPeriod(type: .week, start: prevStart, end: prevEnd)
                weeks.append(current)
            }
        }

        let processedSet = RecapProcessedWeeks.load()
        var weeklyStatuses: [PeriodStatus] = []
        for w in weeks {
            let plays = await PlayLogService.shared.playCount(serverId: serverId, from: w.start, to: w.end)
            let entry = await PlayLogService.shared.registryEntry(
                serverId: serverId,
                periodType: RecapPeriod.PeriodType.week.rawValue,
                periodStart: w.start.timeIntervalSince1970,
                isTest: false
            )
            weeklyStatuses.append(PeriodStatus(
                period: w,
                processed: processedSet.contains(w.start.timeIntervalSince1970),
                entryExists: entry != nil,
                plays: plays
            ))
        }
        weekly = weeklyStatuses

        if let m = RecapPeriod.lastMonth() {
            let plays = await PlayLogService.shared.playCount(serverId: serverId, from: m.start, to: m.end)
            let entry = await PlayLogService.shared.registryEntry(
                serverId: serverId,
                periodType: RecapPeriod.PeriodType.month.rawValue,
                periodStart: m.start.timeIntervalSince1970,
                isTest: false
            )
            let lastGen = UserDefaults.standard.double(forKey: "recap_last_gen_month")
            monthly = PeriodStatus(
                period: m,
                processed: lastGen >= m.start.timeIntervalSince1970 && lastGen > 0,
                entryExists: entry != nil,
                plays: plays
            )
        }

        if let y = RecapPeriod.lastYear() {
            let plays = await PlayLogService.shared.playCount(serverId: serverId, from: y.start, to: y.end)
            let entry = await PlayLogService.shared.registryEntry(
                serverId: serverId,
                periodType: RecapPeriod.PeriodType.year.rawValue,
                periodStart: y.start.timeIntervalSince1970,
                isTest: false
            )
            let lastGen = UserDefaults.standard.double(forKey: "recap_last_gen_year")
            yearly = PeriodStatus(
                period: y,
                processed: lastGen >= y.start.timeIntervalSince1970 && lastGen > 0,
                entryExists: entry != nil,
                plays: plays
            )
        }
    }
}

// SSD-Backup – Menüleisten-App für das Skript ~/bin/ssd-backup
// Bauen: siehe build.sh

import SwiftUI
import AppKit

// MARK: - Pfade & Hilfsfunktionen

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let cli = home + "/bin/ssd-backup"
    static let confDir = home + "/.config/ssd-backup"
    static let settings = confDir + "/settings.conf"
    static let include = confDir + "/include.txt"
    static let exclude = confDir + "/exclude.txt"
    static let stateDir = home + "/Library/Application Support/ssd-backup"
    static let statusJSON = stateDir + "/status.json"
    static let lastRunJSON = stateDir + "/last_run.json"
    static let lastSuccess = stateDir + "/last_success"
    static let paused = stateDir + "/paused"
    static let needsRepair = stateDir + "/needs_repair"
    static let log = home + "/Library/Logs/ssd-backup.log"
    static let mountPoint = home + "/restic-mount"
    static let appAgent = home + "/Library/LaunchAgents/com.user.ssd-backup-app.plist"
}

/// Führt `ssd-backup <args>` aus und liefert die Ausgabe.
@discardableResult
func runCLI(_ args: [String]) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = [Paths.cli] + args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}

func readJSON(_ path: String) -> [String: String] {
    guard let d = FileManager.default.contents(atPath: path),
          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
    return o.mapValues { "\($0)" }
}

func fmtBytes(_ s: String?) -> String {
    let v = Double(s ?? "") ?? 0
    return ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .decimal)
}

func fmtNumber(_ s: String?) -> String {
    let v = Int(Double(s ?? "") ?? 0)
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = "'"
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
}

func fmtDuration(_ seconds: Double) -> String {
    let s = Int(max(0, seconds))
    if s < 60 { return "\(s) Sek." }
    if s < 3600 { return "\(s / 60) Min." }
    if s < 86400 { return "\(s / 3600) Std. \(s % 3600 / 60) Min." }
    return "\(s / 86400) Tg. \(s % 86400 / 3600) Std."
}

func symbol(_ name: String, fallback: String = "externaldrive") -> String {
    NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : fallback
}

// MARK: - Ordnerlisten (include.txt / exclude.txt)

struct ListFile {
    let path: String

    /// Einträge ohne Kommentare und Leerzeilen
    func entries() -> [String] {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { s in
                var s = s
                while s.hasPrefix("/") { s.removeFirst() }
                while s.hasSuffix("/") { s.removeLast() }
                return s
            }
    }

    /// Schreibt die Einträge zurück und behält die Kommentarzeilen oben
    func save(_ items: [String]) {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let header = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init).filter { $0.hasPrefix("#") }
        let out = (header + items).joined(separator: "\n") + "\n"
        try? out.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - Einstellungen (settings.conf)

struct SettingsDraft: Equatable {
    var runOnMount = true
    var schedule = "interval"      // interval | daily | none
    var intervalHours = 1
    var dailyTime = "03:00"
    var minHours = 20
    var keepDaily = 7, keepWeekly = 4, keepMonthly = 12, keepYearly = 3
    var notifications = true, notifyProgress = true
    var connections = 2

    init() {}
    init(_ s: [String: String]) {
        func i(_ k: String, _ d: Int) -> Int { Int(s[k] ?? "") ?? d }
        runOnMount = i("RUN_ON_MOUNT", 1) != 0
        schedule = s["SCHEDULE"].flatMap { ["interval", "daily", "none"].contains($0) ? $0 : nil } ?? "interval"
        intervalHours = max(1, i("INTERVAL_HOURS", 1))
        dailyTime = s["DAILY_TIME"] ?? "03:00"
        minHours = i("MIN_HOURS_BETWEEN", 20)
        keepDaily = i("KEEP_DAILY", 7); keepWeekly = i("KEEP_WEEKLY", 4)
        keepMonthly = i("KEEP_MONTHLY", 12); keepYearly = i("KEEP_YEARLY", 3)
        notifications = i("NOTIFICATIONS", 1) != 0
        notifyProgress = i("NOTIFY_PROGRESS", 1) != 0
        connections = i("RCLONE_CONNECTIONS", 2)
    }

    var pairs: [String] {
        ["RUN_ON_MOUNT", runOnMount ? "1" : "0", "SCHEDULE", schedule,
         "INTERVAL_HOURS", "\(intervalHours)", "DAILY_TIME", dailyTime,
         "MIN_HOURS_BETWEEN", "\(minHours)",
         "KEEP_DAILY", "\(keepDaily)", "KEEP_WEEKLY", "\(keepWeekly)",
         "KEEP_MONTHLY", "\(keepMonthly)", "KEEP_YEARLY", "\(keepYearly)",
         "NOTIFICATIONS", notifications ? "1" : "0", "NOTIFY_PROGRESS", notifyProgress ? "1" : "0",
         "RCLONE_CONNECTIONS", "\(connections)"]
    }

    func scheduleDiffers(from o: SettingsDraft) -> Bool {
        runOnMount != o.runOnMount || schedule != o.schedule || intervalHours != o.intervalHours || dailyTime != o.dailyTime
    }

    /// Uhrzeit als Date (für den DatePicker)
    var dailyDate: Date {
        get {
            let parts = dailyTime.split(separator: ":").compactMap { Int($0) }
            return Calendar.current.date(bySettingHour: parts.first ?? 3, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: Date()) ?? Date()
        }
        set {
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            dailyTime = String(format: "%02d:%02d", c.hour ?? 3, c.minute ?? 0)
        }
    }

    static func hoursText(_ h: Int) -> String {
        h % 24 == 0 && h >= 48 ? "\(h / 24) Tage" : (h == 24 ? "1 Tag" : (h == 1 ? "1 Stunde" : "\(h) Stunden"))
    }

    var scheduleText: String {
        var t: [String] = []
        if runOnMount { t.append("beim Einstecken") }
        switch schedule {
        case "interval": t.append(intervalHours == 1 ? "stündlich" : "alle \(intervalHours) Std.")
        case "daily": t.append("täglich \(dailyTime)")
        default: break
        }
        return t.isEmpty ? "nur manuell" : t.joined(separator: " + ")
    }
}

// MARK: - Modell

@MainActor
final class BackupModel: ObservableObject {
    @Published var status: [String: String] = [:]
    @Published var lastRun: [String: String] = [:]
    @Published var lastSuccess: Date?
    @Published var ssdName = "SSD"
    @Published var repoPath = ""
    @Published var ssdConnected = false
    @Published var paused = false
    @Published var repairPending = false
    @Published var mounted = false
    @Published var mounting = false
    @Published var includes: [String] = []
    @Published var excludes: [String] = []
    @Published var autostart = false
    @Published var cliMissing = false
    @Published var message: String?
    @Published var selInclude = Set<String>()
    @Published var selExclude = Set<String>()
    @Published var pattern = ""
    @Published var settings: [String: String] = [:]
    @Published var draft = SettingsDraft()
    @Published var settingsMessage: String?
    @Published var applying = false

    var savedSettings: SettingsDraft { SettingsDraft(settings) }

    private var timer: Timer?
    private var mountProcess: Process?

    var ssdPath: String { "/Volumes/" + ssdName }

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Zustand

    enum State { case none, running, ok, warning, error }

    var state: State {
        switch status["state"] {
        case "running": return isRunning ? .running : .error
        case "ok": return .ok
        case "warning": return .warning
        case "error": return .error
        default: return .none
        }
    }

    /// Läuft der Prozess aus status.json wirklich noch?
    var isRunning: Bool {
        guard status["state"] == "running", let pid = Int32(status["pid"] ?? "") else { return false }
        return kill(pid, 0) == 0
    }

    var stateMessage: String {
        if status["state"] == "running" && !isRunning { return "Abgebrochen (Mac aus / SSD entfernt?)" }
        return status["message"] ?? ""
    }

    var phaseText: String {
        switch status["phase"] {
        case "connect": return "Verbinde mit pCloud …"
        case "backup": return "Sichere Dateien"
        case "verify": return "Prüfe Vollständigkeit auf pCloud"
        case "repair": return "Repariere beschädigte Daten"
        case "cleanup": return "Räume alte Stände auf"
        case "check": return "Prüfe Backup (Stichprobe)"
        default: return status["phase"] ?? ""
        }
    }

    var percent: Double { (Double(status["percent"] ?? "") ?? 0) / 100 }

    var menuIcon: String {
        switch state {
        case .running: return symbol("arrow.triangle.2.circlepath")
        case .ok: return symbol("externaldrive.badge.checkmark")
        case .warning, .error: return symbol("externaldrive.badge.exclamationmark")
        case .none: return symbol("externaldrive")
        }
    }

    func refresh() {
        let fm = FileManager.default
        cliMissing = !fm.fileExists(atPath: Paths.cli)
        if let s = try? String(contentsOfFile: Paths.settings, encoding: .utf8) {
            var d: [String: String] = [:]
            for line in s.split(separator: "\n") {
                let l = line.trimmingCharacters(in: .whitespaces)
                guard !l.hasPrefix("#"), let eq = l.firstIndex(of: "=") else { continue }
                let key = String(l[..<eq])
                if let v = Self.settingValue(line, key: key) { d[key] = v }
            }
            if d != settings { settings = d }
            if let v = d["SSD_NAME"] { ssdName = v }
            if let v = d["REPO_PATH"] { repoPath = v }
        }
        status = readJSON(Paths.statusJSON)
        lastRun = readJSON(Paths.lastRunJSON)
        if let t = try? String(contentsOfFile: Paths.lastSuccess, encoding: .utf8),
           let ts = Double(t.trimmingCharacters(in: .whitespacesAndNewlines)) {
            lastSuccess = Date(timeIntervalSince1970: ts)
        } else { lastSuccess = nil }
        var isDir: ObjCBool = false
        ssdConnected = fm.fileExists(atPath: ssdPath, isDirectory: &isDir) && isDir.boolValue
        paused = fm.fileExists(atPath: Paths.paused)
        repairPending = fm.fileExists(atPath: Paths.needsRepair)
        mounted = fm.fileExists(atPath: Paths.mountPoint + "/snapshots")
        if mounted { mounting = false }
        includes = ListFile(path: Paths.include).entries()
        excludes = ListFile(path: Paths.exclude).entries()
        autostart = fm.fileExists(atPath: Paths.appAgent)
    }

    static func settingValue(_ line: Substring, key: String) -> String? {
        let l = line.trimmingCharacters(in: .whitespaces)
        guard l.hasPrefix(key + "=") else { return nil }
        var v = String(l.dropFirst(key.count + 1))
        if let hash = v.range(of: "#") { v = String(v[..<hash.lowerBound]) }
        v = v.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("\""), let end = v.dropFirst().firstIndex(of: "\"") {
            v = String(v[v.index(after: v.startIndex)..<end])
        }
        return v
    }

    // MARK: Aktionen

    func startBackup() {
        guard ssdConnected else { message = "Die SSD „\(ssdName)“ ist nicht angesteckt."; return }
        if mounted { message = "Hinweis: Während das Backup eingehängt ist, kann eine Reparatur nicht laufen." }
        DispatchQueue.global().async {
            let r = runCLI(["start"])
            Task { @MainActor in
                if r.status != 0 { self.message = "Start fehlgeschlagen: \(r.output)" }
                self.refresh()
            }
        }
    }

    func stopBackup() {
        let alert = NSAlert()
        alert.messageText = "Backup abbrechen?"
        alert.informativeText = "Bereits hochgeladene Daten bleiben erhalten. Das Backup wird beim nächsten Lauf fortgesetzt."
        alert.addButton(withTitle: "Abbrechen")
        alert.addButton(withTitle: "Weiterlaufen lassen")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runCLI(["stop"])
        refresh()
    }

    func togglePause() {
        runCLI([paused ? "resume" : "pause"])
        refresh()
    }

    func browse() {
        if mounted { openSnapshots(); return }
        mounting = true
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [Paths.cli, "browse", Paths.mountPoint]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle(forWritingAtPath: Paths.log) ?? FileHandle.nullDevice
        p.terminationHandler = { _ in
            Task { @MainActor in self.mounting = false; self.mountProcess = nil; self.refresh() }
        }
        do { try p.run(); mountProcess = p } catch {
            mounting = false; message = "Einhängen fehlgeschlagen: \(error.localizedDescription)"; return
        }
        // warten, bis die Ordner erscheinen, dann Finder öffnen
        Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if FileManager.default.fileExists(atPath: Paths.mountPoint + "/snapshots") {
                    self.refresh(); self.openSnapshots(); return
                }
                if self.mountProcess == nil { break }
            }
            if !self.mounted { self.message = "Einhängen hat nicht geklappt – siehe Protokoll." }
            self.mounting = false
        }
    }

    func openSnapshots() {
        // Übersicht aller Stände (ein Ordner pro Datum + "latest")
        NSWorkspace.shared.open(URL(fileURLWithPath: Paths.mountPoint + "/snapshots"))
    }

    func unmount() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/sbin/umount")
        p.arguments = [Paths.mountPoint]
        try? p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 {
            let d = Process()
            d.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            d.arguments = ["unmount", "force", Paths.mountPoint]
            try? d.run(); d.waitUntilExit()
        }
        mountProcess?.interrupt()
        refresh()
    }

    func openLog() {
        NSWorkspace.shared.open([URL(fileURLWithPath: Paths.log)],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// settings.conf im Texteditor öffnen (für .conf gibt es keine Standard-App)
    func openSettingsFile() {
        NSWorkspace.shared.open([URL(fileURLWithPath: Paths.settings)],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    func loadDraft() {
        refresh()
        draft = savedSettings
        settingsMessage = nil
    }

    func applySettings() {
        let new = draft, old = savedSettings
        applying = true
        settingsMessage = nil
        DispatchQueue.global().async {
            var r = runCLI(["set"] + new.pairs)
            var msg = r.status == 0 ? "Gespeichert." : "Fehler: \(r.output)"
            if r.status == 0 && new.scheduleDiffers(from: old) {
                r = runCLI(["schedule", "apply"])
                msg = r.status == 0 ? "Gespeichert – Zeitplan ist aktiv." : "Zeitplan konnte nicht aktiviert werden: \(r.output)"
            }
            Task { @MainActor in
                self.applying = false
                self.settingsMessage = msg
                self.refresh()
                if r.status == 0 { self.draft = self.savedSettings }
            }
        }
    }

    func setAutostart(_ on: Bool) {
        if on {
            let appPath = Bundle.main.bundlePath
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>com.user.ssd-backup-app</string>
              <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-g</string><string>\(appPath)</string></array>
              <key>RunAtLoad</key><true/>
            </dict></plist>
            """
            try? plist.write(toFile: Paths.appAgent, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: Paths.appAgent)
        }
        refresh()
    }

    // MARK: Ordnerlisten

    /// Absoluten Pfad in einen Pfad relativ zur SSD umwandeln
    func relative(_ url: URL) -> String? {
        let root = URL(fileURLWithPath: ssdPath).resolvingSymlinksInPath().standardizedFileURL.path
        let p = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard p.hasPrefix(root + "/") else { return nil }
        return String(p.dropFirst(root.count + 1))
    }

    func pickFolders() -> [String] {
        guard ssdConnected else { message = "Die SSD „\(ssdName)“ ist nicht angesteckt."; return [] }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: ssdPath)
        panel.prompt = "Auswählen"
        panel.message = "Ordner auf „\(ssdName)“ wählen (Mehrfachauswahl mit ⌘)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return [] }
        var out: [String] = []
        for u in panel.urls {
            if let r = relative(u) { out.append(r) } else { message = "„\(u.path)“ liegt nicht auf der SSD." }
        }
        return out
    }

    func add(_ items: [String], include: Bool) {
        let file = ListFile(path: include ? Paths.include : Paths.exclude)
        var list = file.entries()
        for i in items where !i.isEmpty && !list.contains(i) { list.append(i) }
        file.save(list)
        refresh()
    }

    func remove(_ items: Set<String>, include: Bool) {
        let file = ListFile(path: include ? Paths.include : Paths.exclude)
        file.save(file.entries().filter { !items.contains($0) })
        refresh()
    }
}

// MARK: - Menüleisten-Popover

struct StatusView: View {
    @EnvironmentObject var m: BackupModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Kopf
            HStack {
                Image(systemName: "externaldrive.fill").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text("SSD-Backup").font(.headline)
                    Text("\(m.ssdName) → pCloud/\(m.repoPath)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(m.ssdConnected ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                Text(m.ssdConnected ? "angesteckt" : "nicht angesteckt").font(.caption).foregroundStyle(.secondary)
            }

            if m.cliMissing {
                Label("~/bin/ssd-backup fehlt – bitte install.sh ausführen.", systemImage: "xmark.octagon")
                    .foregroundStyle(.red).font(.callout)
            }

            stateCard

            if let msg = m.message {
                HStack(alignment: .top) {
                    Image(systemName: "info.circle")
                    Text(msg).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button { m.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(8).background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }

            // Hauptaktionen
            HStack {
                if m.isRunning {
                    Button(role: .destructive) { m.stopBackup() } label: {
                        Label("Abbrechen", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                } else {
                    Button { m.startBackup() } label: {
                        Label("Backup starten", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!m.ssdConnected)
                }
                if m.mounted {
                    Button { m.openSnapshots() } label: {
                        Label("Im Finder öffnen", systemImage: "folder").frame(maxWidth: .infinity)
                    }
                    Button { m.unmount() } label: { Image(systemName: "eject.fill") }
                        .help("Backup aushängen")
                } else {
                    Button { m.browse() } label: {
                        Label(m.mounting ? "Wird eingehängt …" : "Durchstöbern", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(m.mounting)
                    .help("Backup als Laufwerk im Finder öffnen – Dateien einfach herausziehen, um sie wiederherzustellen")
                }
            }
            .controlSize(.large)

            if m.mounted {
                Text("Im Finder: jeder Ordner mit Datum = ein Stand, **latest** = neuester. Dateien herausziehen = wiederherstellen.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Nebenaktionen
            HStack(spacing: 14) {
                Button { openWindow(id: "folders"); NSApp.activate(ignoringOtherApps: true) } label: {
                    Label("Ordner …", systemImage: "folder.badge.gearshape")
                }
                Button { m.openLog() } label: { Label("Protokoll", systemImage: "doc.text.magnifyingglass") }
                Spacer()
                Menu {
                    Toggle("Automatik pausieren", isOn: Binding(get: { m.paused }, set: { _ in m.togglePause() }))
                    Toggle("App beim Anmelden starten", isOn: Binding(get: { m.autostart }, set: { m.setAutostart($0) }))
                    Divider()
                    Button("Einstellungen …") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
                    Divider()
                    Button("App beenden") { NSApp.terminate(nil) }
                } label: { Image(systemName: "gearshape") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 360)
    }

    @ViewBuilder var stateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch m.state {
            case .running:
                Label { Text("Läuft – \(m.phaseText)") } icon: { ProgressView().controlSize(.small) }
                    .font(.callout.weight(.medium))
                if m.status["phase"] == "backup" || m.status["phase"] == "repair" {
                    ProgressView(value: m.percent) {
                        HStack {
                            Text(String(format: "%.1f %%", m.percent * 100)).monospacedDigit().bold()
                            Spacer()
                            if let eta = Double(m.status["eta"] ?? ""), eta > 0 {
                                Text("noch ca. \(fmtDuration(eta))").foregroundStyle(.secondary)
                            }
                        }.font(.caption)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                        GridRow { Text("Daten").foregroundStyle(.secondary)
                            Text("\(fmtBytes(m.status["bytes_done"])) von \(fmtBytes(m.status["total_bytes"]))") }
                        GridRow { Text("Dateien").foregroundStyle(.secondary)
                            Text("\(fmtNumber(m.status["files_done"])) von \(fmtNumber(m.status["total_files"]))") }
                        if let started = Double(m.status["started"] ?? "") {
                            GridRow { Text("Läuft seit").foregroundStyle(.secondary)
                                Text(fmtDuration(Date().timeIntervalSince1970 - started)) }
                        }
                    }.font(.caption).monospacedDigit()
                    if let cur = m.status["current"], !cur.isEmpty {
                        Text(cur.replacingOccurrences(of: m.ssdPath + "/", with: ""))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
            case .ok:
                Label("Letztes Backup erfolgreich", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout.weight(.medium))
            case .warning:
                Label("Fertig mit Warnungen", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout.weight(.medium))
                Text(m.stateMessage).font(.caption).foregroundStyle(.secondary)
            case .error:
                Label("Fehler", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red).font(.callout.weight(.medium))
                Text(m.stateMessage).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .none:
                Label("Noch kein Backup gelaufen", systemImage: "clock")
                    .foregroundStyle(.secondary).font(.callout.weight(.medium))
            }

            if m.repairPending && m.state != .running {
                Label("Reparatur vorgemerkt – läuft beim nächsten Backup automatisch.", systemImage: "wrench.and.screwdriver")
                    .font(.caption).foregroundStyle(.orange)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                GridRow {
                    Text("Letztes Backup").foregroundStyle(.secondary)
                    if let d = m.lastSuccess {
                        Text("\(d.formatted(date: .abbreviated, time: .shortened)) (vor \(fmtDuration(Date().timeIntervalSince(d))))")
                    } else { Text("—") }
                }
                if let added = m.lastRun["data_added"] {
                    GridRow { Text("Hochgeladen").foregroundStyle(.secondary)
                        Text("\(fmtBytes(added)) neu, gesamt \(fmtBytes(m.lastRun["total_bytes"]))") }
                }
                GridRow { Text("Umfang").foregroundStyle(.secondary)
                    Text((m.includes.isEmpty ? "ganze SSD" : "\(m.includes.count) Ordner") + (m.excludes.isEmpty ? "" : ", \(m.excludes.count) Ausschlüsse")) }
                GridRow { Text("Automatik").foregroundStyle(.secondary)
                    Text(m.paused ? "pausiert" : m.savedSettings.scheduleText)
                        .foregroundStyle(m.paused ? .orange : .primary) }
            }.font(.caption)

            if let d = m.lastSuccess, Date().timeIntervalSince(d) > 7 * 86400 {
                Label("Das letzte Backup ist über eine Woche alt – SSD mal wieder anstecken!", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Fenster „Ordner“

struct FoldersView: View {
    @EnvironmentObject var m: BackupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !m.ssdConnected {
                Label("„\(m.ssdName)“ ist nicht angesteckt – Ordner auswählen geht erst, wenn sie da ist. Entfernen und Muster gehen trotzdem.",
                      systemImage: "externaldrive.badge.xmark")
                    .font(.callout).foregroundStyle(.orange)
            }

            section(title: "Gesicherte Ordner",
                    hint: m.includes.isEmpty ? "Leer – die ganze SSD wird gesichert." : "Nur diese Ordner werden gesichert.",
                    items: m.includes, selection: $m.selInclude, include: true)

            section(title: "Ausgeschlossen",
                    hint: "Diese Ordner/Dateien werden nicht gesichert. Muster mit * gelten überall, z. B. *.tmp",
                    items: m.excludes, selection: $m.selExclude, include: false)

            HStack {
                TextField("Muster hinzufügen, z. B. *.tmp oder **/node_modules", text: $m.pattern)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPattern)
                Button("Hinzufügen", action: addPattern).disabled(m.pattern.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Text("Tipp: Eine leere Datei „.nobackup“ in einem Ordner schließt ihn ebenfalls aus. Änderungen gelten ab dem nächsten Backup; bereits gesicherte Daten werden nicht neu hochgeladen.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 520)
        .onAppear { m.refresh() }
    }

    func addPattern() {
        let p = m.pattern.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return }
        m.add([p], include: false)
        m.pattern = ""
    }

    @ViewBuilder
    func section(title: String, hint: String, items: [String], selection: Binding<Set<String>>, include: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(hint).font(.caption).foregroundStyle(.secondary)
            List(items, id: \.self, selection: selection) { item in
                Label(item, systemImage: item.contains("*") || item.contains("?") ? "asterisk" : "folder")
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 110)
            HStack {
                Button { m.add(m.pickFolders(), include: include) } label: {
                    Label("Ordner hinzufügen …", systemImage: "plus")
                }.disabled(!m.ssdConnected)
                Button { m.remove(selection.wrappedValue, include: include); selection.wrappedValue = [] } label: {
                    Label("Entfernen", systemImage: "minus")
                }.disabled(selection.wrappedValue.isEmpty)
            }
        }
    }
}

// MARK: - Fenster „Einstellungen“

struct SettingsView: View {
    @EnvironmentObject var m: BackupModel
    static let minHourOptions = [1, 6, 12, 20, 24, 48, 72, 168]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Beim Einstecken der SSD starten", isOn: $m.draft.runOnMount)
                    Picker("Regelmäßig", selection: $m.draft.schedule) {
                        Text("Alle paar Stunden").tag("interval")
                        Text("Täglich zu einer Uhrzeit").tag("daily")
                        Text("Nie").tag("none")
                    }
                    if m.draft.schedule == "interval" {
                        Stepper(value: $m.draft.intervalHours, in: 1...24) {
                            Text(m.draft.intervalHours == 1 ? "Jede Stunde" : "Alle \(m.draft.intervalHours) Stunden")
                        }
                    }
                    if m.draft.schedule == "daily" {
                        DatePicker("Uhrzeit", selection: $m.draft.dailyDate, displayedComponents: .hourAndMinute)
                    }
                    Picker("Höchstens ein Backup alle", selection: $m.draft.minHours) {
                        ForEach(Self.minHourOptions + (Self.minHourOptions.contains(m.draft.minHours) ? [] : [m.draft.minHours]), id: \.self) {
                            Text(SettingsDraft.hoursText($0)).tag($0)
                        }
                    }
                    Toggle("Automatik pausieren", isOn: Binding(get: { m.paused }, set: { _ in m.togglePause() }))
                } header: {
                    Text("Zeitplan")
                } footer: {
                    Text("Zu diesen Zeitpunkten wird ein Backup versucht. Es läuft nur, wenn die SSD angesteckt ist und das letzte erfolgreiche Backup länger als der Mindestabstand her ist. Abgebrochene Backups werden beim nächsten Zeitpunkt fortgesetzt. Schläft der Mac zur Uhrzeit, wird es beim Aufwachen nachgeholt.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Stepper("Tägliche Stände: \(m.draft.keepDaily)", value: $m.draft.keepDaily, in: 0...60)
                    Stepper("Wöchentliche Stände: \(m.draft.keepWeekly)", value: $m.draft.keepWeekly, in: 0...52)
                    Stepper("Monatliche Stände: \(m.draft.keepMonthly)", value: $m.draft.keepMonthly, in: 0...120)
                    Stepper("Jährliche Stände: \(m.draft.keepYearly)", value: $m.draft.keepYearly, in: 0...50)
                } header: {
                    Text("Aufbewahrung")
                } footer: {
                    Text("Ältere Stände werden einmal pro Woche entfernt.").font(.caption).foregroundStyle(.secondary)
                }

                Section("Mitteilungen") {
                    Toggle("Mitteilungen anzeigen", isOn: $m.draft.notifications)
                    Toggle("Zusätzlich bei 25 / 50 / 75 %", isOn: $m.draft.notifyProgress)
                        .disabled(!m.draft.notifications)
                }

                Section {
                    Stepper("Gleichzeitige Uploads: \(m.draft.connections)", value: $m.draft.connections, in: 1...8)
                    Button("settings.conf im Texteditor öffnen …") { m.openSettingsFile() }
                } header: {
                    Text("Erweitert")
                } footer: {
                    Text("Mehr Uploads = schneller, aber pCloud antwortet dann öfter mit Fehlern. 2 ist ein guter Wert.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let msg = m.settingsMessage {
                    Text(msg).font(.callout).foregroundStyle(msg.hasPrefix("Gespeichert") ? Color.secondary : Color.red)
                        .lineLimit(2)
                }
                Spacer()
                if m.applying { ProgressView().controlSize(.small) }
                Button("Zurücksetzen") { m.draft = m.savedSettings; m.settingsMessage = nil }
                    .disabled(m.draft == m.savedSettings || m.applying)
                Button("Übernehmen") { m.applySettings() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(m.draft == m.savedSettings || m.applying)
            }
            .padding(12)
        }
        .frame(minWidth: 460, minHeight: 600)
        .onAppear { m.loadDraft() }
    }
}

// MARK: - App

@main
struct SSDBackupApp: App {
    @StateObject private var model = BackupModel()

    init() {
        // Testmodus: SSD-Backup --render <ordner> → Vorschaubilder der Oberfläche
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            let dir = args[i + 1]
            let m = BackupModel()
            func save<V: View>(_ v: V, _ name: String) {
                let r = ImageRenderer(content: v.environmentObject(m).background(Color(nsColor: .windowBackgroundColor)))
                r.scale = 2
                if let img = r.nsImage, let tiff = img.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dir + "/" + name))
                }
            }
            save(StatusView(), "status.png")
            save(FoldersView().frame(width: 480, height: 560), "folders.png")
            m.draft = m.savedSettings; m.draft.schedule = "daily"
            // Formulare rendert ImageRenderer nicht – echtes Fenster abfotografieren
            func snapWindow<V: View>(_ v: V, _ size: NSSize, _ name: String) {
                let host = NSHostingView(rootView: v.environmentObject(m))
                let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
                win.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name))
                }
            }
            _ = NSApplication.shared
            snapWindow(SettingsView(), NSSize(width: 480, height: 900), "settings.png")
            m.draft.schedule = "interval"
            snapWindow(SettingsView(), NSSize(width: 480, height: 900), "settings2.png")
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            StatusView().environmentObject(model)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: model.menuIcon)
                if model.state == .running, model.status["phase"] == "backup" {
                    Text(String(format: "%.0f%%", model.percent * 100)).monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Ordner auswählen", id: "folders") {
            FoldersView().environmentObject(model)
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Einstellungen", id: "settings") {
            SettingsView().environmentObject(model)
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(CommandLine.arguments.contains("--settings") ? .presented : .suppressed)
    }
}

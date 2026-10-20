import AppKit
import ServiceManagement

// herdr's install script uses ~/.local/bin; Homebrew uses /opt/homebrew/bin (Apple silicon) or /usr/local/bin
let herdr = [NSHomeDirectory() + "/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
    .first(where: FileManager.default.isExecutableFile) ?? "herdr"

// (title, SF Symbol, herdr keybind, CLI args).
// "{pane}", "{tab}", "{workspace}" become the focused ids at click time; "{label}" prompts for a name.
// ponytail: keybinds are herdr's defaults (prefix ctrl+b), not read from config.toml; parse [keys] if I rebind.
typealias Action = (title: String, icon: String, keys: String, args: [String])

let dirs = ["left", "right", "up", "down"]

// The rows of a "Focus ›" style submenu, one per direction
func four(_ verb: String, icons: [String], keys: [String]) -> [Action] {
    dirs.indices.map { (dirs[$0].capitalized, icons[$0], keys[$0], ["pane", verb, "--direction", dirs[$0]]) }
}

let paneActions: [Action] = [
    ("Split right", "rectangle.split.2x1", "⌃B V", ["pane", "split", "--direction", "right", "--focus"]),
    ("Split down", "rectangle.split.1x2", "⌃B −", ["pane", "split", "--direction", "down", "--focus"]),
    ("Toggle zoom", "arrow.up.left.and.arrow.down.right", "⌃B Z", ["pane", "zoom", "--toggle"]),
]
let paneSubmenus: [(title: String, icon: String, actions: [Action])] = [
    ("Focus", "rectangle.lefthalf.inset.filled",
     four("focus", icons: ["rectangle.lefthalf.filled", "rectangle.righthalf.filled", "rectangle.tophalf.filled", "rectangle.bottomhalf.filled"],
          keys: ["⌃B H", "⌃B L", "⌃B K", "⌃B J"])),
    ("Resize", "arrow.up.and.down.and.arrow.left.and.right",
     four("resize", icons: ["arrow.left.to.line", "arrow.right.to.line", "arrow.up.to.line", "arrow.down.to.line"],
          keys: ["←", "→", "↑", "↓"].map { "⌃B R \($0)" })),
    ("Swap", "rectangle.2.swap",
     four("swap", icons: ["arrow.left.arrow.right", "arrow.left.arrow.right", "arrow.up.arrow.down", "arrow.up.arrow.down"],
          keys: ["", "", "", ""])),
]
let closePane: Action = ("Close pane", "xmark.square", "⌃B X", ["pane", "close", "{pane}"])
let tabActions: [Action] = [
    ("New tab", "plus.rectangle.on.rectangle", "⌃B C", ["tab", "create", "--focus"]),
    ("Rename tab", "pencil", "⌃B ⇧T", ["tab", "rename", "{tab}", "{label}"]),
    ("Close tab", "xmark.rectangle", "⌃B ⇧X", ["tab", "close", "{tab}"]),
]
let workspaceActions: [Action] = [
    ("New workspace", "macwindow.badge.plus", "⌃B ⇧N", ["workspace", "create", "--focus"]),
    ("Rename workspace", "square.and.pencil", "⌃B ⇧W", ["workspace", "rename", "{workspace}", "{label}"]),
    ("Close workspace", "rectangle.badge.xmark", "⌃B ⇧D", ["workspace", "close", "{workspace}"]),
]

func run(_ args: [String], exe: String = herdr) -> (ok: Bool, out: Data, err: String) {
    let p = Process(), out = Pipe(), err = Pipe()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    // Drop herdr's caller context (HERDR_PANE_ID etc.) in case this app was launched from a herdr pane:
    // the CLI would treat that pane as the caller, so "current pane" and splits would ignore what's focused.
    p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("HERDR_") }
    p.standardOutput = out
    p.standardError = err
    do { try p.run() } catch { return (false, Data(), error.localizedDescription) }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    p.waitUntilExit()
    return (p.terminationStatus == 0, data, msg)
}

// The "result" object of a herdr JSON response.
func result(_ args: [String]) -> [String: Any]? {
    let json = try? JSONSerialization.jsonObject(with: run(args).out) as? [String: Any]
    return json?["result"] as? [String: Any]
}

func agentStatuses() -> [String] {
    (result(["agent", "list"])?["agents"] as? [[String: Any]] ?? []).compactMap { $0["agent_status"] as? String }
}

let idFields = ["{pane}": "pane_id", "{tab}": "tab_id", "{workspace}": "workspace_id"]

// What to call a pane or agent: its terminal title, else the agent, else its folder
func displayName(_ pane: [String: Any]) -> String {
    for key in ["terminal_title_stripped", "agent"] {
        if let s = pane[key] as? String, !s.isEmpty { return s }
    }
    return URL(fileURLWithPath: pane["cwd"] as? String ?? "pane").lastPathComponent
}

func short(_ s: String, _ max: Int) -> String {
    s.count > max ? s.prefix(max - 1) + "…" : s
}

// A herdr TUI client is `herdr [--options]` or `herdr session attach <name>`.
// The long-lived server (`herdr server`) and one-shot CLI calls (`herdr pane ...`) don't count.
// ponytail: splits on spaces, so a herdr binary whose path contains a space is missed.
func isHerdrClient(_ command: String) -> Bool {
    let t = command.split(separator: " ")
    guard let exe = t.first, exe == "herdr" || exe.hasSuffix("/herdr") else { return false }
    return t.count == 1 || t[1].hasPrefix("-") || (t[1] == "session" && t.count > 2 && t[2] == "attach")
}

func herdrClientPID() -> String? {
    String(decoding: run(["-axo", "pid=,command="], exe: "/bin/ps").out, as: UTF8.self)
        .split(separator: "\n").lazy
        .map { $0.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init) }
        .first { $0.count == 2 && isHerdrClient($0[1]) }?[0]
}

// Bring forward the terminal app the herdr client runs in. macOS puts the launching app's
// bundle id in every child's environment as __CFBundleIdentifier (com.googlecode.iterm2 for iTerm2).
// openApplication is what the Dock does, so it works from a menu bar app where activate() may not.
// ponytail: raises the app's frontmost window, not necessarily the herdr one if the terminal has several.
func bringTerminalForward() {
    guard let pid = herdrClientPID() else { return }
    let env = String(decoding: run(["eww", "-o", "command=", "-p", pid], exe: "/bin/ps").out, as: UTF8.self)
    guard let entry = env.split(separator: " ").first(where: { $0.hasPrefix("__CFBundleIdentifier=") }),
          let id = entry.split(separator: "=", maxSplits: 1).last,
          let url = NSRunningApplication.runningApplications(withBundleIdentifier: String(id)).first?.bundleURL else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
}

// Icon, title, then keybind right-aligned in grey, like Rectangle.
// The icon lives inside the title text: macOS hides NSMenuItem.image for this app, bundled or not.
func label(_ title: String, icon: String, keys: String, tint: NSColor? = nil) -> NSAttributedString {
    let font = NSFont.menuFont(ofSize: 0)
    let para = NSMutableParagraphStyle()
    // icon | title | prefix (right-aligned) | key (left-aligned), so "⌃B" and the keys each form a straight column
    para.tabStops = [
        NSTextTab(textAlignment: .left, location: 26),
        NSTextTab(textAlignment: .right, location: 200),
        NSTextTab(textAlignment: .left, location: 206),
    ]
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: para]
    let att = NSTextAttachment()
    var config = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
    if let tint { config = config.applying(.init(paletteColors: [tint])) }
    if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        att.image = img
        att.bounds = NSRect(x: 0, y: (font.capHeight - img.size.height) / 2, width: img.size.width, height: img.size.height)
    }
    let s = NSMutableAttributedString(attachment: att)
    s.addAttributes(attrs, range: NSRange(location: 0, length: s.length))
    s.append(NSAttributedString(string: "\t" + title, attributes: attrs))
    let (prefix, key) = keys.isEmpty ? ("", "") : (String(keys.prefix(2)), String(keys.dropFirst(3)))
    s.append(NSAttributedString(string: "\t\(prefix)\t\(key)", attributes: attrs.merging([.foregroundColor: NSColor.secondaryLabelColor]) { $1 }))
    return s
}

func hex(_ v: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
}

// Agent status -> (SF Symbol, colour), matching herdr's sidebar dots (src/client/shell.rs status_icon/status_color).
// ponytail: Catppuccin Mocha hard-coded, herdr's default theme; read [theme] from config.toml if I switch themes.
// Blocked sorts first, then done, working, the rest (herdr's status_priority).
let statusIcons: [String: (String, NSColor)] = [
    "blocked": ("circlebadge.fill", hex(0xf38ba8)), // red
    "done": ("circlebadge.fill", hex(0x94e2d5)), // teal
    "working": ("circlebadge.fill", hex(0xf9e2af)), // yellow
    "idle": ("circlebadge", hex(0xa6e3a1)), // green
]
let unknownIcon = ("circle.dotted", hex(0x6c7086)) // overlay0
let statusOrder = ["blocked", "done", "working", "idle"]

class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var icon = NSImage(), notched = NSImage()
    let dot = NSView()

    // The status badge: a 7pt dot in an 11pt notch cut from the icon's bottom-right corner.
    // The icon stays a template image (macOS tints it for light/dark); only the dot is coloured.
    let iconSize: CGFloat = 18, dotSize: CGFloat = 7, notchSize: CGFloat = 11

    func applicationDidFinishLaunching(_: Notification) {
        icon = Bundle.main.image(forResource: "sheep")
            ?? NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "herdr")!
        icon.size = NSSize(width: iconSize, height: iconSize)
        icon.isTemplate = true
        notched = NSImage(size: icon.size, flipped: false) { [icon, iconSize, dotSize, notchSize] r in
            icon.draw(in: r)
            let c = iconSize - dotSize / 2
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: c - notchSize / 2, y: dotSize / 2 - notchSize / 2, width: notchSize, height: notchSize)).fill()
            return true
        }
        notched.isTemplate = true
        status.button?.image = icon
        dot.wantsLayer = true
        dot.layer?.cornerRadius = dotSize / 2
        status.button?.addSubview(dot)

        status.menu = NSMenu()
        status.menu?.delegate = self

        refresh()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    // Always running (brew services); the icon only shows while a herdr client is open.
    // A red dot means an agent is blocked on me, teal means one finished and I haven't looked yet.
    func refresh() {
        status.isVisible = herdrClientPID() != nil
        guard status.isVisible, let button = status.button else { return }
        let statuses = agentStatuses()
        let blocked = statuses.filter { $0 == "blocked" }.count, done = statuses.filter { $0 == "done" }.count
        let color = blocked > 0 ? statusIcons["blocked"]?.1 : done > 0 ? statusIcons["done"]?.1 : nil
        button.image = color == nil ? icon : notched
        dot.isHidden = color == nil
        dot.layer?.backgroundColor = color?.cgColor
        // Same spot as the notch: the icon's bottom-right corner, wherever the button centres it
        let x0 = (button.bounds.width - iconSize) / 2, y0 = (button.bounds.height - iconSize) / 2
        dot.frame = NSRect(x: x0 + iconSize - dotSize, y: button.isFlipped ? y0 + iconSize - dotSize : y0,
                           width: dotSize, height: dotSize)
        let counts = [(blocked, "blocked"), (done, "done")].filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        button.toolTip = counts.isEmpty ? "herdr" : "Agents: " + counts.joined(separator: ", ")
    }

    // The whole menu is rebuilt from the live snapshot each time it opens:
    // Agents / Pane (named after the focused pane) / Tab / Workspace / Quit
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let snap = result(["api", "snapshot"])?["snapshot"] as? [String: Any]

        let workspaces = snap?["workspaces"] as? [[String: Any]] ?? []
        // Workspace and tab ids -> their names (tabs carry a workspace_id too, so tab_id is checked first)
        let labels = (workspaces + (snap?["tabs"] as? [[String: Any]] ?? [])).reduce(into: [String: String]()) {
            $0[$1["tab_id"] as? String ?? $1["workspace_id"] as? String ?? ""] = $1["label"] as? String
        }

        // Named like herdr's sidebar: workspace, then the tab in grey
        menu.addItem(.sectionHeader(title: "Agents"))
        let rank = { (a: [String: Any]) in statusOrder.firstIndex(of: a["agent_status"] as? String ?? "") ?? statusOrder.count }
        let agents = (snap?["agents"] as? [[String: Any]] ?? []).sorted { rank($0) < rank($1) }
        if agents.isEmpty { menu.addItem(NSMenuItem(title: "No agents", action: nil, keyEquivalent: "")) }
        for a in agents {
            menu.addItem(listRow(labels[a["workspace_id"] as? String ?? ""] ?? displayName(a),
                                 detail: labels[a["tab_id"] as? String ?? ""] ?? displayName(a), from: a,
                                 args: ["agent", "focus", a["pane_id"] as? String ?? ""]))
        }
        menu.addItem(.separator())

        let focused = (snap?["panes"] as? [[String: Any]] ?? []).first { $0["focused"] as? Bool == true }
        menu.addItem(.sectionHeader(title: focused.map { "Pane · " + short(displayName($0), 30) } ?? "Pane"))
        paneActions.forEach { menu.addItem(item($0)) }
        for sub in paneSubmenus {
            let mi = NSMenuItem(title: sub.title, action: nil, keyEquivalent: "")
            mi.attributedTitle = label(sub.title, icon: sub.icon, keys: "")
            mi.submenu = NSMenu()
            sub.actions.forEach { mi.submenu?.addItem(item($0)) }
            menu.addItem(mi)
        }
        menu.addItem(item(closePane))
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Tab"))
        tabActions.forEach { menu.addItem(item($0)) }
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Workspace"))
        for w in workspaces {
            menu.addItem(listRow(w["label"] as? String ?? "workspace", detail: "", from: w,
                                 args: ["workspace", "focus", w["workspace_id"] as? String ?? ""]))
        }
        workspaceActions.forEach { menu.addItem(item($0)) }
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.attributedTitle = label("Launch at login", icon: "sunrise", keys: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        menu.addItem(login)
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "")
        quit.attributedTitle = label("Quit", icon: "power", keys: "")
        menu.addItem(quit)
    }

    func item(_ a: Action) -> NSMenuItem {
        let mi = NSMenuItem(title: a.title, action: #selector(click), keyEquivalent: "")
        mi.attributedTitle = label(a.title, icon: a.icon, keys: a.keys)
        mi.representedObject = a.args
        mi.target = self
        return mi
    }

    // An agent or workspace row: herdr's status dot, name, grey detail, checkmark when focused
    func listRow(_ title: String, detail: String, from info: [String: Any], args: [String]) -> NSMenuItem {
        let (icon, tint) = statusIcons[info["agent_status"] as? String ?? ""] ?? unknownIcon
        let name = short(title, 26) // keeps the detail column straight
        let text = NSMutableAttributedString(attributedString: label(name, icon: icon, keys: "", tint: tint))
        text.append(NSAttributedString(string: short(detail, 30),
                                       attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
        let mi = NSMenuItem(title: name, action: #selector(click), keyEquivalent: "")
        mi.attributedTitle = text
        mi.representedObject = args
        mi.state = info["focused"] as? Bool == true ? .on : .off
        mi.target = self
        return mi
    }

    // A macOS login item (System Settings → General → Login Items), so the app starts at login.
    // It stays hidden until a herdr client is open, like any other time.
    @objc func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            alert("Couldn't change Launch at login: \(error.localizedDescription)")
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc func click(_ sender: NSMenuItem) {
        guard var args = sender.representedObject as? [String] else { return }
        var pane: [String: Any] = [:]
        if args.contains(where: idFields.keys.contains) {
            guard let p = result(["pane", "current"])?["pane"] as? [String: Any] else {
                return alert("Couldn't find the focused herdr pane.")
            }
            pane = p
            args = args.map { idFields[$0].flatMap { pane[$0] as? String } ?? $0 }
        }
        // Confirmations follow Apple's alert guidelines: say what ends, name the button after the action,
        // style it as destructive, and keep Return on Cancel.
        if args.starts(with: ["pane", "close"]), let agent = pane["agent"] as? String {
            guard ask("Close this pane?", "This ends the \(agent) agent running in “\(displayName(pane))”.",
                      button: "Close Pane", destructive: true) else { return }
        }
        // Tabs and workspaces always ask: everything inside them closes, agents included
        if args.count == 3, args[1] == "close", ["tab", "workspace"].contains(args[0]) {
            let kind = args[0], id = args[2]
            let info = result([kind, "get", id])?[kind] as? [String: Any] ?? [:]
            let panes = info["pane_count"] as? Int ?? 0
            let agents = (result(["agent", "list"])?["agents"] as? [[String: Any]] ?? [])
                .filter { $0["\(kind)_id"] as? String == id }.compactMap { $0["agent"] as? String }
            let ending = "its \(panes) pane\(panes == 1 ? "" : "s")"
            let who = agents.count == 1 ? "the \(agents[0]) agent" : "\(agents.count) agents (\(agents.joined(separator: ", ")))"
            guard ask("Close the \(kind) “\(info["label"] as? String ?? kind)”?",
                      agents.isEmpty ? "This ends \(ending)." : "This ends \(ending), including \(who) running there.",
                      button: "Close \(kind.capitalized)", destructive: true) else { return }
        }
        if let i = args.firstIndex(of: "{label}") {
            // args are [kind, "rename", id, label]; prefill with the current name from `<kind> get <id>`
            let kind = args[0]
            let field = NSTextField(string: (result([kind, "get", args[2]])?[kind] as? [String: Any])?["label"] as? String ?? "")
            field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
            guard ask("Rename \(kind)", "", button: "Rename", field: field) else { return }
            args[i] = field.stringValue
        }
        let r = run(args)
        if r.ok { bringTerminalForward() } else { alert(r.err.isEmpty ? "herdr \(args.joined(separator: " ")) failed" : r.err) }
    }

    // A two-button dialog (button / Cancel), optionally with a text field. True if the button was pressed.
    // Destructive: the button is drawn red and Return presses Cancel instead.
    func ask(_ title: String, _ text: String, button: String, destructive: Bool = false, field: NSTextField? = nil) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        let action = a.addButton(withTitle: button)
        let cancel = a.addButton(withTitle: "Cancel")
        if destructive {
            action.hasDestructiveAction = true
            action.keyEquivalent = ""
            cancel.keyEquivalent = "\r"
        }
        if let field {
            a.accessoryView = field
            a.window.initialFirstResponder = field
        }
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn
    }

    func alert(_ text: String) {
        let a = NSAlert()
        a.messageText = "herdr"
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

if CommandLine.arguments.contains("--self-test") {
    precondition(isHerdrClient("herdr"))
    precondition(isHerdrClient("/Users/me/.local/bin/herdr --session work"))
    precondition(isHerdrClient("herdr session attach work"))
    precondition(!isHerdrClient("/Users/me/.local/bin/herdr server"))
    precondition(!isHerdrClient("herdr pane split --direction right"))
    precondition(!isHerdrClient("herdr session list"))
    precondition(!isHerdrClient("/path/herdr-bar --watch-titles 3"))
    precondition(!isHerdrClient("vim herdr"))
    print("self-test ok")
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

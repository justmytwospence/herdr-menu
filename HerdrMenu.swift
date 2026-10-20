import AppKit
import ServiceManagement

// herdr's install script uses ~/.local/bin; Homebrew uses /opt/homebrew/bin (Apple silicon) or /usr/local/bin
let herdr = [NSHomeDirectory() + "/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
    .first(where: FileManager.default.isExecutableFile) ?? "herdr"

// (title, SF Symbol, herdr keybinding action, CLI args). The keybind shown comes from Keybinds below.
// "{pane}", "{tab}", "{workspace}" become the focused ids at click time; "{label}" prompts for a name.
typealias Action = (title: String, icon: String, action: String, args: [String])

let dirs = ["left", "right", "up", "down"]

// The rows of a "Focus ›" style submenu, one per direction; herdr names the actions focus_pane_left etc.
func four(_ verb: String, icons: [String]) -> [Action] {
    dirs.indices.map { (dirs[$0].capitalized, icons[$0], "\(verb)_pane_\(dirs[$0])", ["pane", verb, "--direction", dirs[$0]]) }
}

let paneActions: [Action] = [
    ("Split right", "rectangle.split.2x1", "split_vertical", ["pane", "split", "--direction", "right", "--focus"]),
    ("Split down", "rectangle.split.1x2", "split_horizontal", ["pane", "split", "--direction", "down", "--focus"]),
    ("Toggle zoom", "arrow.up.left.and.arrow.down.right", "zoom", ["pane", "zoom", "--toggle"]),
]
let paneSubmenus: [(title: String, icon: String, actions: [Action])] = [
    ("Focus", "rectangle.lefthalf.inset.filled",
     four("focus", icons: ["rectangle.lefthalf.filled", "rectangle.righthalf.filled", "rectangle.tophalf.filled", "rectangle.bottomhalf.filled"])),
    ("Resize", "arrow.up.and.down.and.arrow.left.and.right",
     four("resize", icons: ["arrow.left.to.line", "arrow.right.to.line", "arrow.up.to.line", "arrow.down.to.line"])),
    ("Swap", "rectangle.2.swap",
     four("swap", icons: ["arrow.left.arrow.right", "arrow.left.arrow.right", "arrow.up.arrow.down", "arrow.up.arrow.down"])),
]
let closePane: Action = ("Close pane", "xmark.square", "close_pane", ["pane", "close", "{pane}"])
let tabActions: [Action] = [
    ("New tab", "plus.rectangle.on.rectangle", "new_tab", ["tab", "create", "--focus"]),
    ("Rename tab", "pencil", "rename_tab", ["tab", "rename", "{tab}", "{label}"]),
    ("Close tab", "xmark.rectangle", "close_tab", ["tab", "close", "{tab}"]),
]
let workspaceActions: [Action] = [
    ("New workspace", "macwindow.badge.plus", "new_workspace", ["workspace", "create", "--focus"]),
    ("Rename workspace", "square.and.pencil", "rename_workspace", ["workspace", "rename", "{workspace}", "{label}"]),
    ("Close workspace", "rectangle.badge.xmark", "close_workspace", ["workspace", "close", "{workspace}"]),
]

// My herdr keybinds from config.toml, resolved the way herdr does (src/config/keybinds.rs): a [keys] entry wins,
// a default that shares a key with any of mine (including [[keys.command]] keys) is dropped, and "" or [] unbinds.
// ponytail: reads `name = "x"` and `name = ["x", "y"]` on one line; multi-line arrays are skipped.
struct Keybinds {
    // herdr's defaults for the menu's actions: `herdr --default-config`, plus swap (missing there) from its keymap docs
    static let defaults = [
        "split_vertical": "prefix+v", "split_horizontal": "prefix+minus", "zoom": "prefix+z", "close_pane": "prefix+x",
        "focus_pane_left": "prefix+h", "focus_pane_right": "prefix+l", "focus_pane_up": "prefix+k", "focus_pane_down": "prefix+j",
        "swap_pane_left": "prefix+shift+h", "swap_pane_right": "prefix+shift+l",
        "swap_pane_up": "prefix+shift+k", "swap_pane_down": "prefix+shift+j", "resize_mode": "prefix+r",
        "new_tab": "prefix+c", "rename_tab": "prefix+shift+t", "close_tab": "prefix+shift+x",
        "new_workspace": "prefix+shift+n", "rename_workspace": "prefix+shift+w", "close_workspace": "prefix+shift+d",
    ]
    static let modifierSymbols = [("ctrl", "⌃"), ("alt", "⌥"), ("shift", "⇧"), ("cmd", "⌘"), ("super", "⌘")]
    static let keyNames = [
        "minus": "−", "plus": "+", "equal": "=", "comma": ",", "period": ".", "slash": "/", "backslash": "\\",
        "semicolon": ";", "quote": "'", "backtick": "`", "ampersand": "&", "left": "←", "right": "→", "up": "↑",
        "down": "↓", "enter": "↩", "tab": "⇥", "esc": "⎋", "space": "Space", "backspace": "⌫", "delete": "⌦",
        "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
    ]

    var prefix = "ctrl+b"
    var mine: [String: [String]] = [:] // [keys] action -> bindings
    var commands: [String] = [] // [[keys.command]] keys

    init(toml: String) {
        var section = ""
        for raw in toml.split(separator: "\n") {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                section = line.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                continue
            }
            let kv = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard kv.count == 2 else { continue }
            // The quoted strings in the value: odd pieces when split on quotes
            let values = kv[1].split(separator: "\"", omittingEmptySubsequences: false).enumerated()
                .filter { $0.offset % 2 == 1 && !$0.element.isEmpty }.map { String($0.element).lowercased() }
            if section == "keys", kv[0] == "prefix" {
                prefix = values.first ?? prefix
            } else if section == "keys" {
                mine[kv[0]] = values
            } else if section == "keys.command", kv[0] == "key" {
                commands += values
            }
        }
    }

    // The first active binding for a herdr action, nil when unbound
    func binding(_ action: String) -> String? {
        if let bindings = mine[action] { return bindings.first }
        guard let fallback = Self.defaults[action] else { return nil }
        return (mine.values.flatMap { $0 } + commands).contains(fallback) ? nil : fallback
    }

    // What the menu shows: (modifier column, key column), e.g. ("⌃B", "⇧N") or ("⌃⌥⇧", "←").
    // Resize falls back to resize mode plus an arrow when resize_pane_* isn't bound.
    func keys(for action: String) -> (String, String) {
        if let b = binding(action) { return display(b) }
        if action.hasPrefix("resize_pane_"), let mode = binding("resize_mode") {
            let (left, right) = display(mode)
            return (left, right + " " + Self.symbol(String(action.dropFirst("resize_pane_".count))))
        }
        return ("", "")
    }

    func display(_ binding: String) -> (String, String) {
        var parts = binding.split(separator: "+").map(String.init)
        let viaPrefix = parts.first == "prefix"
        if viaPrefix { parts.removeFirst() }
        let key = Self.symbol(parts.popLast() ?? "")
        let mods = Self.modifierSymbols.filter { parts.contains($0.0) }.map(\.1).joined()
        if viaPrefix {
            let (prefixMods, prefixKey) = display(prefix)
            return (prefixMods + prefixKey, mods + key)
        }
        return (mods, key)
    }

    static func symbol(_ key: String) -> String { keyNames[key] ?? key.uppercased() }
}

// ponytail: always ~/.config/herdr/config.toml; honour XDG_CONFIG_HOME if herdr ever reads it from elsewhere for me
let herdrConfig = NSHomeDirectory() + "/.config/herdr/config.toml"

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
func label(_ title: String, icon: String, keys: (String, String) = ("", ""), tint: NSColor? = nil) -> NSAttributedString {
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
    s.append(NSAttributedString(string: "\t\(keys.0)\t\(keys.1)", attributes: attrs.merging([.foregroundColor: NSColor.secondaryLabelColor]) { $1 }))
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

// `--demo` shows this made-up session instead of herdr's, for README screenshots: one agent in each state,
// neutral names, and clicks that do nothing. `--open-menu` opens the menu a second after launch.
let demo = CommandLine.arguments.contains("--demo")
let demoSnapshot: [String: Any] = {
    let spaces = [("api", "auth refactor", "blocked"), ("website", "landing page copy", "done"),
                  ("docs", "api reference", "working"), ("infra", "terraform plan", "idle")]
    var workspaces: [[String: Any]] = [], tabs: [[String: Any]] = [], agents: [[String: Any]] = []
    for (i, (space, tab, status)) in spaces.enumerated() {
        let w = "w\(i + 1)", focused = space == "docs"
        workspaces.append(["workspace_id": w, "label": space, "agent_status": status, "focused": focused])
        tabs.append(["tab_id": "\(w):t1", "workspace_id": w, "label": tab])
        agents.append(["pane_id": "\(w):p1", "tab_id": "\(w):t1", "workspace_id": w, "agent": "claude",
                       "agent_status": status, "terminal_title_stripped": tab, "focused": focused])
    }
    return ["workspaces": workspaces, "tabs": tabs, "agents": agents, "panes": agents]
}()

class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var icon = NSImage(), notched = NSImage()
    let dot = NSView()
    var keybinds = Keybinds(toml: "")

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
        if CommandLine.arguments.contains("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.status.button?.performClick(nil) }
        }
    }

    // Always running (brew services); the icon only shows while a herdr client is open.
    // A red dot means an agent is blocked on me, teal means one finished and I haven't looked yet.
    func refresh() {
        status.isVisible = demo || herdrClientPID() != nil
        guard status.isVisible, let button = status.button else { return }
        let statuses = demo ? (demoSnapshot["agents"] as! [[String: Any]]).map { $0["agent_status"] as! String } : agentStatuses()
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
        // Demo screenshots use herdr's defaults; otherwise reread my config so edits show up straight away
        keybinds = Keybinds(toml: demo ? "" : (try? String(contentsOfFile: herdrConfig, encoding: .utf8)) ?? "")
        let snap = demo ? demoSnapshot : result(["api", "snapshot"])?["snapshot"] as? [String: Any]

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
            mi.attributedTitle = label(sub.title, icon: sub.icon)
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
        login.attributedTitle = label("Launch at login", icon: "sunrise")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.target = self
        menu.addItem(login)
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "")
        quit.attributedTitle = label("Quit", icon: "power")
        menu.addItem(quit)
    }

    func item(_ a: Action) -> NSMenuItem {
        let mi = NSMenuItem(title: a.title, action: #selector(click), keyEquivalent: "")
        mi.attributedTitle = label(a.title, icon: a.icon, keys: keybinds.keys(for: a.action))
        mi.representedObject = a.args
        mi.target = self
        return mi
    }

    // An agent or workspace row: herdr's status dot, name, grey detail, checkmark when focused
    func listRow(_ title: String, detail: String, from info: [String: Any], args: [String]) -> NSMenuItem {
        let (icon, tint) = statusIcons[info["agent_status"] as? String ?? ""] ?? unknownIcon
        let name = short(title, 26) // keeps the detail column straight
        let text = NSMutableAttributedString(attributedString: label(name, icon: icon, tint: tint))
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
        guard !demo else { return }
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            alert("Couldn't change Launch at login: \(error.localizedDescription)")
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    @objc func click(_ sender: NSMenuItem) {
        guard !demo else { return }
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
    let k = Keybinds(toml: """
    [keys]
    prefix = "ctrl+a"  # a comment
    new_tab = ["prefix+t", "ctrl+alt+t"]
    close_tab = ""
    resize_pane_left = "ctrl+shift+alt+left"
    [[keys.command]]
    key = "prefix+k"
    command = "echo #not-a-key"
    """)
    precondition(k.keys(for: "new_tab") == ("⌃A", "T")) // first of a list, my prefix
    precondition(k.keys(for: "close_tab") == ("", "")) // "" unbinds
    precondition(k.keys(for: "focus_pane_up") == ("", "")) // default taken by a custom command
    precondition(k.keys(for: "split_horizontal") == ("⌃A", "−")) // default, my prefix, named key
    precondition(k.keys(for: "swap_pane_left") == ("⌃A", "⇧H"))
    precondition(k.keys(for: "resize_pane_left") == ("⌃⌥⇧", "←")) // direct binding
    precondition(k.keys(for: "resize_pane_up") == ("⌃A", "R ↑")) // resize mode fallback
    precondition(Keybinds(toml: "").keys(for: "new_workspace") == ("⌃B", "⇧N"))
    print("self-test ok")
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

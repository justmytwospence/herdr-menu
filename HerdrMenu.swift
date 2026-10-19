import AppKit

let herdr = NSHomeDirectory() + "/.local/bin/herdr"

// (title, SF Symbol, herdr keybind, CLI args). nil = separator.
// "{pane}", "{tab}", "{workspace}" become the focused ids at click time; "{label}" prompts for a name.
// ponytail: keybinds are herdr's defaults (prefix ctrl+b), not read from config.toml; parse [keys] if I rebind.
typealias Item = (String, String, String, [String])?

let dirs = ["left", "right", "up", "down"]

func four(_ verb: String, icons: [String], keys: [String]) -> [Item] {
    dirs.indices.map { ("\(verb.capitalized) \(dirs[$0])", icons[$0], keys[$0], ["pane", verb, "--direction", dirs[$0]]) } + [nil]
}

let items: [Item] = [
    ("Split right", "rectangle.split.2x1", "⌃B V", ["pane", "split", "--direction", "right", "--focus"]),
    ("Split down", "rectangle.split.1x2", "⌃B −", ["pane", "split", "--direction", "down", "--focus"]),
    nil,
] + four("focus", icons: ["rectangle.lefthalf.filled", "rectangle.righthalf.filled", "rectangle.tophalf.filled", "rectangle.bottomhalf.filled"],
         keys: ["⌃B H", "⌃B L", "⌃B K", "⌃B J"])
  + four("resize", icons: ["arrow.left.to.line", "arrow.right.to.line", "arrow.up.to.line", "arrow.down.to.line"],
         keys: ["←", "→", "↑", "↓"].map { "⌃B R \($0)" })
  + four("swap", icons: ["arrow.left.arrow.right", "arrow.left.arrow.right", "arrow.up.arrow.down", "arrow.up.arrow.down"],
         keys: ["", "", "", ""]) + [
    ("Toggle zoom", "arrow.up.left.and.arrow.down.right", "⌃B Z", ["pane", "zoom", "--toggle"]),
    ("Close pane", "xmark.square", "⌃B X", ["pane", "close", "{pane}"]),
    nil,
    ("New tab", "plus.rectangle.on.rectangle", "⌃B C", ["tab", "create", "--focus"]),
    ("New workspace", "macwindow.badge.plus", "⌃B ⇧N", ["workspace", "create", "--focus"]),
    ("Rename tab", "pencil", "⌃B ⇧T", ["tab", "rename", "{tab}", "{label}"]),
    ("Rename workspace", "square.and.pencil", "⌃B ⇧W", ["workspace", "rename", "{workspace}", "{label}"]),
]

func run(_ args: [String], exe: String = herdr) -> (ok: Bool, out: Data, err: String) {
    let p = Process(), out = Pipe(), err = Pipe()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
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

let idFields = ["{pane}": "pane_id", "{tab}": "tab_id", "{workspace}": "workspace_id"]

// A herdr TUI client is `herdr [--options]` or `herdr session attach <name>`.
// The long-lived server (`herdr server`) and one-shot CLI calls (`herdr pane ...`) don't count.
// ponytail: splits on spaces, so a herdr binary whose path contains a space is missed.
func isHerdrClient(_ command: String) -> Bool {
    let t = command.split(separator: " ")
    guard let exe = t.first, exe == "herdr" || exe.hasSuffix("/herdr") else { return false }
    return t.count == 1 || t[1].hasPrefix("-") || (t[1] == "session" && t.count > 2 && t[2] == "attach")
}

func herdrClientOpen() -> Bool {
    String(decoding: run(["-axo", "command="], exe: "/bin/ps").out, as: UTF8.self)
        .split(separator: "\n").contains { isHerdrClient(String($0)) }
}

// Icon, title, then keybind right-aligned in grey, like Rectangle.
// The icon lives inside the title text: macOS hides NSMenuItem.image for this app, bundled or not.
func label(_ title: String, icon: String, keys: String) -> NSAttributedString {
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
    if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .regular)) {
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

class App: NSObject, NSApplicationDelegate {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func applicationDidFinishLaunching(_: Notification) {
        let sheep = Bundle.main.image(forResource: "sheep")
        sheep?.size = NSSize(width: 18, height: 18)
        sheep?.isTemplate = true
        status.button?.image = sheep ?? NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "herdr")

        let menu = NSMenu()
        for (i, item) in items.enumerated() {
            guard let (title, icon, keys, _) = item else { menu.addItem(.separator()); continue }
            let mi = NSMenuItem(title: title, action: #selector(click), keyEquivalent: "")
            mi.attributedTitle = label(title, icon: icon, keys: keys)
            mi.target = self
            mi.tag = i
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate), keyEquivalent: "")
        quit.attributedTitle = label("Quit", icon: "power", keys: "")
        menu.addItem(quit)
        status.menu = menu

        // Always running (brew services); the icon only shows while a herdr client is open.
        status.isVisible = herdrClientOpen()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.status.isVisible = herdrClientOpen() }
    }

    @objc func click(_ sender: NSMenuItem) {
        var args = items[sender.tag]!.3
        if args.contains(where: idFields.keys.contains) {
            guard let pane = result(["pane", "current"])?["pane"] as? [String: Any] else {
                return alert("Couldn't find the focused herdr pane.")
            }
            args = args.map { idFields[$0].flatMap { pane[$0] as? String } ?? $0 }
        }
        if let i = args.firstIndex(of: "{label}") {
            // args are [kind, "rename", id, label]; prefill with the current name from `<kind> get <id>`
            let kind = args[0]
            let current = (result([kind, "get", args[2]])?[kind] as? [String: Any])?["label"] as? String ?? ""
            guard let name = prompt("Rename \(kind)", current) else { return }
            args[i] = name
        }
        let r = run(args)
        if !r.ok { alert(r.err.isEmpty ? "herdr \(args.joined(separator: " ")) failed" : r.err) }
    }

    func prompt(_ title: String, _ value: String) -> String? {
        let a = NSAlert()
        a.messageText = title
        a.addButton(withTitle: "Rename")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        a.accessoryView = field
        a.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
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

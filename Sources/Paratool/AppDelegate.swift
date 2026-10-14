import AppKit
import SwiftUI
import ImageIO
import ParatoolCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let watcher = CaptureWatcher()
    let shelf = ShelfController()
    private var history = RecentItems<Capture>()
    private var editors: [UUID: EditorController] = [:]
    private var welcome: NSWindow?
    private var statusMessage: String?
    private var activeFolder: URL?
    private var preferenceTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.dashed.inset.filled", accessibilityDescription: "Paratool")
        statusItem.button?.toolTip = "Paratool — スクショを撮って、すぐ注釈"
        shelf.model.open = { [weak self] in self?.openEditor($0) }
        shelf.model.dismiss = { [weak self] capture in self?.history.remove(id: capture.id.uuidString); self?.refreshShelf() }
        watcher.onCapture = { [weak self] url, image in self?.addCapture(url: url, image: image) }
        watcher.onStatus = { [weak self] message in self?.statusMessage = message; self?.rebuildMenu() }
        if CommandLine.arguments.contains("--smoke-test") {
            SmokeTest.run(app: self)
            return
        }
        if CommandLine.arguments.contains("--demo") {
            Demo.populate(app: self)
            rebuildMenu()
            return
        }
        refreshFolder()
        preferenceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refreshFolder() }
        if !UserDefaults.standard.bool(forKey: "hasSeenWelcome") { showWelcome(nil) }
    }
    private func installMainMenu() {
        let menu = NSMenu()
        let app = NSMenuItem(); let appMenu = NSMenu()
        let quit = NSMenuItem(title: "Paratoolを終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quit); app.submenu = appMenu; menu.addItem(app)
        let edit = NSMenuItem(); edit.title = "編集"; let editMenu = NSMenu(title: "編集")
        for (title, selector, key) in [("カット", #selector(NSText.cut(_:)), "x"), ("コピー", #selector(NSText.copy(_:)), "c"), ("ペースト", #selector(NSText.paste(_:)), "v"), ("すべて選択", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
    }
    private func refreshFolder() {
        let folder = UserDefaults.standard.string(forKey: "captureFolder").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? CaptureWatcher.systemFolder
        guard activeFolder != folder else { return }
        activeFolder = folder
        watcher.start(folder: folder)
        rebuildMenu()
    }
    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "Paratool  /  \(history.items.count) 枚", action: nil, keyEquivalent: "")
        title.isEnabled = false; menu.addItem(title)
        let state = NSMenuItem(title: statusMessage ?? "⌘⇧4 で撮影すると左下に表示", action: nil, keyEquivalent: "")
        state.isEnabled = false; menu.addItem(state)
        menu.addItem(.separator())
        addMenu("最新のスクショを編集", #selector(openLatest), to: menu, enabled: !history.items.isEmpty)
        addMenu("画像を開く…", #selector(openImage), to: menu)
        addMenu("左下の一覧を表示", #selector(showShelf), to: menu)
        menu.addItem(.separator())
        let path = NSMenuItem(title: "監視先: \(activeFolder?.lastPathComponent ?? "—")", action: nil, keyEquivalent: "")
        path.toolTip = activeFolder?.path; path.isEnabled = false; menu.addItem(path)
        addMenu("スクショの保存先を選択…", #selector(chooseFolder), to: menu)
        addMenu("macOSの保存先に合わせる", #selector(resetFolder), to: menu)
        addMenu("使い方", #selector(showWelcome(_:)), to: menu)
        menu.addItem(.separator())
        addMenu("Paratoolを終了", #selector(quit), to: menu)
        statusItem.menu = menu
    }
    private func addMenu(_ title: String, _ action: Selector, to menu: NSMenu, enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; item.isEnabled = enabled; menu.addItem(item)
    }
    func addCapture(url: URL, image: CGImage) {
        let capture = Capture(url: url, image: image)
        history.insert(capture, id: capture.id.uuidString)
        refreshShelf()
    }
    private func refreshShelf() { shelf.update(history.items); rebuildMenu() }
    func openEditor(_ capture: Capture) {
        if let editor = editors[capture.id] { editor.showWindow(nil); return }
        let editor = EditorController(capture: capture)
        editor.onClose = { [weak self] in self?.editors.removeValue(forKey: capture.id) }
        editor.onExport = { [weak self] in self?.watcher.ignore($0) }
        editors[capture.id] = editor
        editor.showWindow(nil)
    }
    @objc private func openLatest() { if let capture = history.items.first { openEditor(capture) } }
    @objc private func showShelf() { shelf.update(history.items) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func resetFolder() { UserDefaults.standard.removeObject(forKey: "captureFolder"); activeFolder = nil; refreshFolder() }
    @objc private func chooseFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = "⌘⇧4 の画像が保存されるフォルダを選んでください。"
        panel.directoryURL = activeFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: "captureFolder"); activeFolder = nil; refreshFolder()
    }
    @objc private func openImage() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            let alert = NSAlert(); alert.messageText = "この画像を読み込めませんでした。"; alert.runModal(); return
        }
        addCapture(url: url, image: image)
        openLatest()
    }
    @objc private func showWelcome(_ sender: Any?) {
        if let welcome { welcome.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let view = WelcomeView { [weak self] in
            UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            self?.welcome?.close(); self?.welcome = nil
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 530, height: 470), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Paratool"; window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: view)
        window.center(); welcome = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    let done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "square.dashed.inset.filled").font(.system(size: 26)).foregroundColor(.indigo)
                Text("PARATOOL").font(.system(size: 13, weight: .bold, design: .rounded)).tracking(3)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("撮る。伝える。すぐ送る。").font(.system(size: 28, weight: .bold))
                Text("いつものスクショに、ひと手間だけ。").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                step("1", "⌘ ⇧ 4 でスクショ", "普段と同じ操作で、撮りたい範囲を選択。")
                step("2", "左下に、最新3枚をキープ", "クリックで編集。古い画像も元ファイルは残ります。")
                step("3", "注釈を入れて、完了してコピー", "矢印・文字・目隠しで、伝えたいことをはっきり。")
            }
            Text("画像が出ない場合は、メニューバーから保存先フォルダを選択してください。標準の右下プレビューは ⌘⇧5 → オプション →「フローティングサムネールを表示」でオフにできます。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("使いはじめる", action: done).buttonStyle(.borderedProminent).controlSize(.large) }
        }.padding(32).frame(width: 530, height: 470).environment(\.colorScheme, .dark)
    }
    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.system(size: 11, weight: .bold, design: .monospaced)).frame(width: 25, height: 25).background(.indigo.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 13, weight: .semibold)); Text(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
    }
}

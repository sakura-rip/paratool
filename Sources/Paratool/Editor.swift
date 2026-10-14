import AppKit
import UniformTypeIdentifiers
import ParatoolCore

private final class EditorWindow: NSWindow {
    var shortcut: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if attachedSheet == nil, shortcut?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}

final class EditorController: NSWindowController, NSWindowDelegate {
    let capture: Capture
    let canvas: AnnotationCanvas
    private let scroll = NSScrollView()
    private var zoomLabel = NSTextField(labelWithString: "100%")
    private var toolButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []
    private var undoButton = NSButton()
    private var redoButton = NSButton()
    private var fitMode = true
    var onClose: (() -> Void)?
    var onExport: ((URL) -> Void)?

    init(capture: Capture) {
        self.capture = capture
        canvas = AnnotationCanvas(capture: capture)
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Paratool — \(capture.url.lastPathComponent)"
        window.minSize = NSSize(width: 850, height: 440)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        window.isReleasedWhenClosed = false
        window.delegate = self
        if let frame = NSScreen.main?.visibleFrame {
            window.setContentSize(NSSize(width: min(1080, frame.width - 80), height: min(760, frame.height - 80)))
        }
        window.center()
        buildUI()
        window.shortcut = { [weak self] event in self?.handleShortcut(event) ?? false }
        canvas.onChange = { [weak self] in self?.refresh() }
        canvas.onText = { [weak self] p in self?.addText(at: p) }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func button(_ title: String = "", symbol: String? = nil, action: Selector, help: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.font = .systemFont(ofSize: 12, weight: .medium)
        b.toolTip = help
        if let symbol { b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help); b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading }
        b.heightAnchor.constraint(equalToConstant: 30).isActive = true
        if title.isEmpty { b.widthAnchor.constraint(equalToConstant: 34).isActive = true }
        return b
    }
    private func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }
    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(srgbRed: 0.16, green: 0.17, blue: 0.19, alpha: 1).cgColor
        let colors = NSStackView(); colors.spacing = 8; colors.orientation = .horizontal
        let label = NSTextField(labelWithString: "スタイル")
        label.font = .systemFont(ofSize: 10, weight: .semibold); label.textColor = .secondaryLabelColor
        colors.addArrangedSubview(label)
        for (index, ink) in InkColor.palette.enumerated() {
            let b = NSButton(title: "", target: self, action: #selector(selectColor(_:)))
            b.tag = index; b.isBordered = false; b.wantsLayer = true
            b.layer?.backgroundColor = ink.nsColor.cgColor
            b.layer?.cornerRadius = 4
            b.widthAnchor.constraint(equalToConstant: 22).isActive = true
            b.heightAnchor.constraint(equalToConstant: 22).isActive = true
            b.toolTip = ["赤", "黄", "緑", "青", "黒", "白"][index]
            colorButtons.append(b); colors.addArrangedSubview(b)
        }
        let width = NSPopUpButton(frame: .zero, pullsDown: false)
        width.addItems(withTitles: ["細い · 2 px", "標準 · 4 px", "太い · 8 px", "極太 · 12 px"])
        width.selectItem(at: 1); width.target = self; width.action = #selector(selectWidth(_:)); width.toolTip = "線幅 / 文字サイズ"
        colors.addArrangedSubview(width)
        colors.addArrangedSubview(spacer())
        let hint = NSTextField(labelWithString: "描いて、コピーして、そのまま共有。")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
        colors.addArrangedSubview(hint)

        let tools = NSStackView(); tools.orientation = .horizontal; tools.spacing = 6
        tools.addArrangedSubview(button(symbol: "minus.magnifyingglass", action: #selector(zoomOut), help: "縮小（⌘−）"))
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        zoomLabel.alignment = .center; zoomLabel.widthAnchor.constraint(equalToConstant: 46).isActive = true
        tools.addArrangedSubview(zoomLabel)
        tools.addArrangedSubview(button(symbol: "plus.magnifyingglass", action: #selector(zoomIn), help: "拡大（⌘＋）"))
        tools.addArrangedSubview(button(symbol: "arrow.up.left.and.arrow.down.right", action: #selector(fit), help: "全体表示（⌘0）"))
        for (index, tool) in AnnotationTool.allCases.enumerated() {
            let b = button(symbol: tool.symbol, action: #selector(selectTool(_:)), help: tool.title)
            b.tag = index; b.setButtonType(.pushOnPushOff)
            toolButtons.append(b); tools.addArrangedSubview(b)
        }
        undoButton = button(symbol: "arrow.uturn.backward", action: #selector(undoEdit), help: "元に戻す（⌘Z）")
        redoButton = button(symbol: "arrow.uturn.forward", action: #selector(redoEdit), help: "やり直す（⇧⌘Z）")
        tools.addArrangedSubview(undoButton); tools.addArrangedSubview(redoButton)
        tools.addArrangedSubview(button(symbol: "trash", action: #selector(deleteMark), help: "選択した注釈を削除"))
        tools.addArrangedSubview(spacer())
        tools.addArrangedSubview(button("保存", symbol: "square.and.arrow.down", action: #selector(savePNG), help: "PNG保存（⌘S）"))
        let copy = button("完了してコピー", action: #selector(copyAndClose), help: "画像をコピーして閉じる（⌘Return）")
        copy.bezelColor = NSColor(srgbRed: 0.30, green: 0.42, blue: 0.94, alpha: 1)
        tools.addArrangedSubview(copy)

        scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        scroll.drawsBackground = true; scroll.backgroundColor = NSColor(calibratedWhite: 0.085, alpha: 1)
        scroll.documentView = canvas
        let footer = NSTextField(labelWithString: "\(capture.image.width) × \(capture.image.height) px    •    元画像は変更されません       選択ツールで移動 / Deleteで削除")
        footer.font = .systemFont(ofSize: 10); footer.textColor = .secondaryLabelColor
        for view in [colors, tools, scroll, footer] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            colors.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), colors.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            colors.topAnchor.constraint(equalTo: content.topAnchor, constant: 10), colors.heightAnchor.constraint(equalToConstant: 30),
            tools.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), tools.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tools.topAnchor.constraint(equalTo: colors.bottomAnchor, constant: 8), tools.heightAnchor.constraint(equalToConstant: 36),
            scroll.topAnchor.constraint(equalTo: tools.bottomAnchor, constant: 10), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
        ])
    }
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.contentView?.layoutSubtreeIfNeeded()
        updateCanvas()
        window?.makeFirstResponder(canvas)
    }
    private func updateCanvas() {
        let size = scroll.contentSize
        guard size.width > 0, size.height > 0 else { return }
        if fitMode { canvas.scale = max(0.02, min((size.width - 64) / canvas.imageSize.width, (size.height - 64) / canvas.imageSize.height, 1)) }
        canvas.setFrameSize(NSSize(width: max(size.width, canvas.imageSize.width * canvas.scale + 64), height: max(size.height, canvas.imageSize.height * canvas.scale + 64)))
        zoomLabel.stringValue = "\(Int((canvas.scale * 100).rounded()))%"
        canvas.needsDisplay = true
    }
    func windowDidResize(_ notification: Notification) { updateCanvas() }
    func windowWillClose(_ notification: Notification) { onClose?() }
    private func refresh() {
        for (index, b) in toolButtons.enumerated() {
            let selected = AnnotationTool.allCases[index] == canvas.tool
            b.state = selected ? .on : .off; b.contentTintColor = selected ? .systemBlue : .labelColor
        }
        for (index, b) in colorButtons.enumerated() {
            b.layer?.borderWidth = canvas.ink == InkColor.palette[index] ? 2 : 0
            b.layer?.borderColor = NSColor.white.cgColor
        }
        undoButton.isEnabled = capture.document.canUndo; redoButton.isEnabled = capture.document.canRedo
        canvas.needsDisplay = true
    }
    @objc private func selectTool(_ sender: NSButton) { canvas.tool = AnnotationTool.allCases[sender.tag]; refresh() }
    @objc private func selectColor(_ sender: NSButton) { canvas.ink = InkColor.palette[sender.tag]; restyleSelection(); refresh() }
    @objc private func selectWidth(_ sender: NSPopUpButton) { canvas.lineWidth = [2, 4, 8, 12][sender.indexOfSelectedItem]; restyleSelection() }
    private func restyleSelection() {
        guard let id = canvas.selectedID, let index = capture.document.annotations.firstIndex(where: { $0.id == id }) else { return }
        var marks = capture.document.annotations
        marks[index].color = canvas.ink; marks[index].width = canvas.lineWidth
        capture.document.commit(marks); refresh()
    }
    @objc private func undoEdit() { capture.document.undo(); canvas.selectedID = nil; refresh() }
    @objc private func redoEdit() { capture.document.redo(); canvas.selectedID = nil; refresh() }
    @objc private func deleteMark() { canvas.deleteSelection() }
    @objc private func fit() { fitMode = true; updateCanvas() }
    @objc private func zoomIn() { fitMode = false; canvas.scale = min(4, canvas.scale * 1.25); updateCanvas() }
    @objc private func zoomOut() { fitMode = false; canvas.scale = max(0.02, canvas.scale / 1.25); updateCanvas() }
    private func addText(at point: CGPoint) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "文字を追加"; alert.informativeText = "画像に入れる文字を入力してください。"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 28)); input.placeholderString = "ここに注釈を入力"
        alert.accessoryView = input; alert.addButton(withTitle: "追加"); alert.addButton(withTitle: "キャンセル")
        alert.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .alertFirstButtonReturn, !input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let mark = Annotation(tool: .text, points: [point], color: self.canvas.ink, width: self.canvas.lineWidth, text: input.stringValue)
            self.capture.document.commit(self.capture.document.annotations + [mark]); self.refresh()
        }
        alert.window.initialFirstResponder = input
        alert.window.makeFirstResponder(input)
    }
    @objc private func copyAndClose() { if copyImage() { close() } }
    @discardableResult private func copyImage() -> Bool {
        guard let data = ImageRenderer.png(base: capture.image, annotations: capture.document.annotations) else { showError("画像を合成できませんでした。"); return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else { showError("クリップボードへコピーできませんでした。"); return false }
        if let image = NSImage(data: data), let tiff = image.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        return true
    }
    @objc private func savePNG() {
        guard let window else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = capture.url.deletingPathExtension().lastPathComponent + "-annotated.png"
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let url = panel.url else { return }
            // Never overwrite the source screenshot, even if selected explicitly.
            guard url.standardizedFileURL != self.capture.url.standardizedFileURL else { self.showError("元のスクショを残すため、別のファイル名で保存してください。"); return }
            guard let data = ImageRenderer.png(base: self.capture.image, annotations: self.capture.document.annotations) else { self.showError("画像を合成できませんでした。"); return }
            self.onExport?(url)
            do { try data.write(to: url, options: .atomic) }
            catch { self.showError("保存できませんでした: \(error.localizedDescription)") }
        }
    }
    private func showError(_ message: String) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = message; alert.beginSheetModal(for: window)
    }
    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z": event.modifierFlags.contains(.shift) ? redoEdit() : undoEdit()
        case "s": savePNG()
        case "c": copyImage()
        case "w": close()
        case "0": fit()
        case "+", "=": zoomIn()
        case "-": zoomOut()
        case "\r": copyAndClose()
        default: return false
        }
        return true
    }
}

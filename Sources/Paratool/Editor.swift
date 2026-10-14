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
    private let opacityControl = NSPopUpButton(frame: .zero, pullsDown: false)
    var onClose: (() -> Void)?
    var onExport: ((URL) -> Void)?

    init(capture: Capture) {
        self.capture = capture
        canvas = AnnotationCanvas(capture: capture)
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Paratool — \(capture.url.lastPathComponent)"
        window.minSize = NSSize(width: 940, height: 480)
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
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func button(_ title: String = "", symbol: String? = nil, action: Selector, help: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .large
        b.font = .systemFont(ofSize: 14, weight: .semibold)
        b.toolTip = help
        if let symbol { b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help); b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading }
        b.heightAnchor.constraint(equalToConstant: 40).isActive = true
        b.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        if title.isEmpty { b.widthAnchor.constraint(equalToConstant: 40).isActive = true }
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
        for (index, ink) in InkColor.palette.enumerated() {
            let b = NSButton(title: "", target: self, action: #selector(selectColor(_:)))
            b.tag = index; b.isBordered = false; b.wantsLayer = true
            b.layer?.backgroundColor = ink.nsColor.cgColor; b.layer?.cornerRadius = 5
            b.widthAnchor.constraint(equalToConstant: 26).isActive = true
            b.heightAnchor.constraint(equalToConstant: 26).isActive = true
            b.toolTip = ["赤", "黄", "緑", "青", "黒", "白"][index]
            colorButtons.append(b); colors.addArrangedSubview(b)
        }
        let width = NSPopUpButton(frame: .zero, pullsDown: false)
        width.addItems(withTitles: ["線幅 · 2 px", "線幅 · 4 px", "線幅 · 8 px", "線幅 · 12 px"])
        width.font = .systemFont(ofSize: 13); width.controlSize = .large
        width.selectItem(at: 1); width.target = self; width.action = #selector(selectWidth(_:)); width.toolTip = "線幅 / 文字サイズ / モザイクの粗さ"
        colors.addArrangedSubview(width)
        opacityControl.addItems(withTitles: ["不透明度 25%", "不透明度 50%", "不透明度 75%", "不透明度 100%"])
        opacityControl.font = .systemFont(ofSize: 13); opacityControl.controlSize = .large
        opacityControl.selectItem(at: 3); opacityControl.target = self; opacityControl.action = #selector(selectOpacity(_:))
        colors.addArrangedSubview(opacityControl)
        colors.addArrangedSubview(spacer())
        colors.addArrangedSubview(button(symbol: "minus.magnifyingglass", action: #selector(zoomOut), help: "縮小（⌘−）"))
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        zoomLabel.alignment = .center; zoomLabel.widthAnchor.constraint(equalToConstant: 52).isActive = true
        colors.addArrangedSubview(zoomLabel)
        colors.addArrangedSubview(button(symbol: "plus.magnifyingglass", action: #selector(zoomIn), help: "拡大（⌘＋）"))
        colors.addArrangedSubview(button(symbol: "arrow.up.left.and.arrow.down.right", action: #selector(fit), help: "全体表示（⌘0）"))
        undoButton = button(symbol: "arrow.uturn.backward", action: #selector(undoEdit), help: "元に戻す（⌘Z）")
        redoButton = button(symbol: "arrow.uturn.forward", action: #selector(redoEdit), help: "やり直す（⇧⌘Z）")
        colors.addArrangedSubview(undoButton); colors.addArrangedSubview(redoButton)
        colors.addArrangedSubview(button(symbol: "trash", action: #selector(deleteMark), help: "選択した注釈を削除"))

        let tools = NSStackView(); tools.orientation = .horizontal; tools.spacing = 8
        for (index, tool) in AnnotationTool.allCases.enumerated() {
            let b = button(symbol: tool.symbol, action: #selector(selectTool(_:)), help: tool.title)
            b.tag = index; b.setButtonType(.pushOnPushOff)
            toolButtons.append(b); tools.addArrangedSubview(b)
        }
        tools.addArrangedSubview(spacer())
        let close = button("閉じる", symbol: "xmark", action: #selector(closeEditor), help: "編集画面を閉じる（⌘W）")
        close.widthAnchor.constraint(equalToConstant: 96).isActive = true; tools.addArrangedSubview(close)
        let save = button("保存", symbol: "square.and.arrow.down", action: #selector(savePNG), help: "PNG保存（⌘S）")
        save.widthAnchor.constraint(equalToConstant: 98).isActive = true; tools.addArrangedSubview(save)
        let copy = button("完了してコピー", symbol: "doc.on.doc", action: #selector(copyAndClose), help: "画像をコピーして閉じる（⌘Return）")
        copy.widthAnchor.constraint(equalToConstant: 180).isActive = true
        copy.bezelColor = NSColor(srgbRed: 0.30, green: 0.42, blue: 0.94, alpha: 1)
        tools.addArrangedSubview(copy)

        scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.borderType = .noBorder
        scroll.drawsBackground = true; scroll.backgroundColor = NSColor(calibratedWhite: 0.085, alpha: 1)
        scroll.documentView = canvas
        let footer = NSTextField(labelWithString: "\(capture.image.width) × \(capture.image.height) px    ·    文字はクリックして直接入力 / Enterで確定 / ダブルクリックで再編集")
        footer.font = .systemFont(ofSize: 12); footer.textColor = .secondaryLabelColor
        for view in [colors, tools, scroll, footer] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            colors.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), colors.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            colors.topAnchor.constraint(equalTo: content.topAnchor, constant: 12), colors.heightAnchor.constraint(equalToConstant: 40),
            tools.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), tools.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            tools.topAnchor.constraint(equalTo: colors.bottomAnchor, constant: 10), tools.heightAnchor.constraint(equalToConstant: 44),
            scroll.topAnchor.constraint(equalTo: tools.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -10),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)
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
    func windowDidResize(_ notification: Notification) { canvas.finishText(); updateCanvas() }
    func windowWillClose(_ notification: Notification) { canvas.finishText(); onClose?() }
    private func refresh() {
        for (index, b) in toolButtons.enumerated() {
            let selected = AnnotationTool.allCases[index] == canvas.tool
            b.state = selected ? .on : .off; b.bezelColor = selected ? .systemIndigo : nil; b.contentTintColor = .labelColor
        }
        for (index, b) in colorButtons.enumerated() {
            let color = InkColor.palette[index]
            b.layer?.borderWidth = canvas.ink.red == color.red && canvas.ink.green == color.green && canvas.ink.blue == color.blue ? 2 : 0
            b.layer?.borderColor = NSColor.white.cgColor
        }
        undoButton.isEnabled = capture.document.canUndo; redoButton.isEnabled = capture.document.canRedo
        canvas.needsDisplay = true
    }
    @objc private func selectTool(_ sender: NSButton) {
        let previous = canvas.tool
        canvas.tool = AnnotationTool.allCases[sender.tag]
        if canvas.tool == .highlight { canvas.ink = InkColor.palette[1]; canvas.ink.alpha = 0.5; opacityControl.selectItem(at: 1) }
        else if previous == .highlight { canvas.ink.alpha = 1; opacityControl.selectItem(at: 3) }
        refresh()
    }
    @objc private func selectColor(_ sender: NSButton) {
        canvas.finishText()
        let alpha = canvas.ink.alpha; canvas.ink = InkColor.palette[sender.tag]; canvas.ink.alpha = alpha
        restyleSelection(); refresh()
    }
    @objc private func selectOpacity(_ sender: NSPopUpButton) {
        canvas.finishText(); canvas.ink.alpha = [0.25, 0.5, 0.75, 1][sender.indexOfSelectedItem]; restyleSelection(); refresh()
    }
    @objc private func selectWidth(_ sender: NSPopUpButton) { canvas.finishText(); canvas.lineWidth = [2, 4, 8, 12][sender.indexOfSelectedItem]; restyleSelection(changeColor: false, changeWidth: true) }
    private func restyleSelection(changeColor: Bool = true, changeWidth: Bool = false) {
        guard let id = canvas.selectedID, let index = capture.document.annotations.firstIndex(where: { $0.id == id }) else { return }
        var marks = capture.document.annotations
        if changeColor { marks[index].color = canvas.ink }
        if changeWidth { marks[index].width = canvas.lineWidth }
        capture.document.commit(marks); refresh()
    }
    @objc private func undoEdit() { canvas.finishText(); capture.document.undo(); canvas.selectedID = nil; refresh() }
    @objc private func redoEdit() { canvas.finishText(); capture.document.redo(); canvas.selectedID = nil; refresh() }
    @objc private func deleteMark() { canvas.deleteSelection() }
    @objc private func fit() { canvas.finishText(); fitMode = true; updateCanvas() }
    @objc private func zoomIn() { canvas.finishText(); fitMode = false; canvas.scale = min(4, canvas.scale * 1.25); updateCanvas() }
    @objc private func zoomOut() { canvas.finishText(); fitMode = false; canvas.scale = max(0.02, canvas.scale / 1.25); updateCanvas() }
    @objc private func closeEditor() { close() }
    @objc private func copyAndClose() { if copyImage() { close() } }
    @discardableResult private func copyImage() -> Bool {
        canvas.finishText()
        guard let data = ImageRenderer.png(base: capture.image, annotations: capture.document.annotations) else { showError("画像を合成できませんでした。"); return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("Paratool", forType: ClipboardWatcher.exportMarker)
        guard pasteboard.setData(data, forType: .png) else { showError("クリップボードへコピーできませんでした。"); return false }
        if let image = NSImage(data: data), let tiff = image.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        return true
    }
    @objc private func savePNG() {
        canvas.finishText()
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
        if canvas.isEditingText, !["s", "w", "\r"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") { return false }
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

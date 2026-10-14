import AppKit
import SwiftUI
import ParatoolCore

final class Capture: Identifiable {
    let id = UUID()
    let url: URL
    let image: CGImage
    let document = AnnotationDocument()
    init(url: URL, image: CGImage) { self.url = url; self.image = image }
    lazy var preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
}

final class ShelfModel: ObservableObject {
    @Published var captures: [Capture] = []
    var open: ((Capture) -> Void)?
    var dismiss: ((Capture) -> Void)?
}

private struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.captures) { capture in
                ZStack(alignment: .topTrailing) {
                    Button { model.open?(capture) } label: {
                        VStack(spacing: 0) {
                            Image(nsImage: capture.preview).resizable().aspectRatio(contentMode: .fit)
                                .frame(width: 240, height: 132).background(Color.black.opacity(0.25)).clipped()
                            HStack {
                                Text("\(capture.image.width) × \(capture.image.height)")
                                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "pencil.tip").font(.system(size: 11))
                                Text("編集").font(.system(size: 12, weight: .medium))
                            }.padding(.horizontal, 10).frame(height: 32)
                                .background(Color.white.opacity(0.06))
                        }
                        .background(Color(red: 0.10, green: 0.11, blue: 0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.white.opacity(0.12)))
                    }.buttonStyle(.plain).help("クリックして注釈を追加")
                    Button { model.dismiss?(capture) } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(width: 32, height: 32)
                            .background(Color.white, in: Circle())
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    }.buttonStyle(.plain).padding(8).accessibilityLabel("このスクショを一覧から閉じる").help("一覧から外す（ファイルは残ります）")
                }
            }
        }.frame(width: 240)
            .environment(\.colorScheme, .dark)
    }
}

final class ShelfController {
    let model = ShelfModel()
    let panel: NSPanel
    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: ShelfView(model: model))
        NotificationCenter.default.addObserver(self, selector: #selector(reposition), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    func update(_ captures: [Capture]) {
        model.captures = captures
        guard !captures.isEmpty else { panel.orderOut(nil); return }
        reposition()
        panel.orderFrontRegardless()
    }
    @objc func reposition() {
        // screens.first is the display containing the menu bar, independent of editor focus.
        guard let screen = NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let height = CGFloat(model.captures.count * 164 + max(0, model.captures.count - 1) * 10)
        panel.setFrame(NSRect(x: frame.minX + 16, y: frame.minY + 16, width: 240, height: height), display: true)
    }
}

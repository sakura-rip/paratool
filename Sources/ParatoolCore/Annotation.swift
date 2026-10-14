import AppKit

public enum AnnotationTool: String, CaseIterable {
    case select, rectangle, ellipse, arrow, pen, text, highlight, mosaic, tag, redact
    public var title: String {
        switch self {
        case .select: return "選択"
        case .rectangle: return "四角"
        case .ellipse: return "楕円"
        case .arrow: return "矢印"
        case .pen: return "ペン"
        case .text: return "文字"
        case .highlight: return "ハイライト"
        case .mosaic: return "モザイク"
        case .tag: return "タグ"
        case .redact: return "目隠し"
        }
    }
    public var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .mosaic: return "square.grid.3x3.fill"
        case .tag: return "tag"
        case .redact: return "rectangle.fill"
        }
    }
}

public struct InkColor: Equatable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    public static let palette: [InkColor] = [
        .init(red: 0.98, green: 0.30, blue: 0.32),
        .init(red: 1, green: 0.79, blue: 0.25),
        .init(red: 0.40, green: 0.80, blue: 0.42),
        .init(red: 0.36, green: 0.51, blue: 1),
        .init(red: 0.07, green: 0.07, blue: 0.09),
        .init(red: 1, green: 1, blue: 1)
    ]
}

public struct Annotation: Identifiable, Equatable {
    public let id: UUID
    public var tool: AnnotationTool
    public var points: [CGPoint]
    public var color: InkColor
    public var width: CGFloat
    public var text: String
    public init(tool: AnnotationTool, points: [CGPoint], color: InkColor = InkColor.palette[3], width: CGFloat = 4, text: String = "", id: UUID = UUID()) {
        self.id = id; self.tool = tool; self.points = points; self.color = color; self.width = width; self.text = text
    }
    public var font: NSFont { .systemFont(ofSize: max(16, width * 6), weight: .semibold) }
    public var bounds: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .tag {
            let diameter = max(28, width * 10)
            return CGRect(origin: first, size: CGSize(width: diameter, height: diameter))
        }
        if tool == .text {
            let size = (text as NSString).size(withAttributes: [.font: font])
            return CGRect(origin: first, size: size)
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
    public func translated(dx: CGFloat, dy: CGFloat) -> Annotation {
        var result = self
        result.points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return result
    }
    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if [.text, .redact, .highlight, .mosaic, .tag].contains(tool) { return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) }
        if tool == .rectangle {
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point) && !bounds.insetBy(dx: tolerance, dy: tolerance).contains(point)
        }
        if tool == .ellipse {
            let rx = max(bounds.width / 2, 1), ry = max(bounds.height / 2, 1)
            let d = hypot((point.x - bounds.midX) / rx, (point.y - bounds.midY) / ry)
            return abs(d - 1) <= tolerance / min(rx, ry)
        }
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
            let t = length == 0 ? 0 : max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / length))
            if hypot(point.x - a.x - t * dx, point.y - a.y - t * dy) <= tolerance { return true }
        }
        return false
    }
}

public final class AnnotationDocument {
    public private(set) var annotations: [Annotation] = []
    private var past: [[Annotation]] = []
    private var future: [[Annotation]] = []
    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public func commit(_ value: [Annotation]) {
        guard value != annotations else { return }
        past.append(annotations)
        if past.count > 100 { past.removeFirst() }
        annotations = value; future.removeAll()
    }
    public func undo() {
        guard let previous = past.popLast() else { return }
        future.append(annotations); annotations = previous
    }
    public func redo() {
        guard let next = future.popLast() else { return }
        past.append(annotations); annotations = next
    }
}

public struct CanvasTransform {
    public let imageRect: CGRect
    public let scale: CGFloat
    public init(imageSize: CGSize, bounds: CGRect, scale: CGFloat) {
        self.scale = max(0.01, scale)
        let size = CGSize(width: imageSize.width * self.scale, height: imageSize.height * self.scale)
        imageRect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
    public func imagePoint(from point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - imageRect.minX) / scale, y: (point.y - imageRect.minY) / scale)
    }
}

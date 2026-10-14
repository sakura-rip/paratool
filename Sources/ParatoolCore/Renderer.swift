import AppKit

public enum ImageRenderer {
    // Shared by the flipped canvas and export; annotation coordinates start at top-left.
    public static func draw(_ annotations: [Annotation]) {
        for mark in annotations {
            guard let first = mark.points.first else { continue }
            NSGraphicsContext.saveGraphicsState()
            let color = mark.tool == .redact ? mark.color.nsColor.withAlphaComponent(1) : mark.color.nsColor
            let cgColor = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [mark.color.red, mark.color.green, mark.color.blue, mark.tool == .redact ? 1 : mark.color.alpha])!
            NSGraphicsContext.current?.cgContext.setStrokeColor(cgColor)
            NSGraphicsContext.current?.cgContext.setFillColor(cgColor)
            let path = NSBezierPath()
            path.lineWidth = mark.width; path.lineCapStyle = .round; path.lineJoinStyle = .round
            switch mark.tool {
            case .select: break
            case .rectangle: path.appendRect(mark.bounds); path.stroke()
            case .ellipse: path.appendOval(in: mark.bounds); path.stroke()
            case .redact: path.appendRect(mark.bounds); path.fill()
            case .pen:
                path.move(to: first)
                for p in mark.points.dropFirst() { path.line(to: p) }
                path.stroke()
            case .arrow:
                guard let end = mark.points.last else { break }
                path.move(to: first); path.line(to: end); path.stroke()
                let angle = atan2(end.y - first.y, end.x - first.x)
                let length = max(12, mark.width * 4)
                let head = NSBezierPath()
                head.move(to: end)
                head.line(to: CGPoint(x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
                head.line(to: CGPoint(x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
                head.close(); head.fill()
            case .text:
                (mark.text as NSString).draw(at: first, withAttributes: [.font: mark.font, .foregroundColor: color])
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    public static func render(base: CGImage, annotations: [Annotation]) -> CGImage? {
        guard let context = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        context.draw(base, in: rect)
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw(annotations)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    public static func png(base: CGImage, annotations: [Annotation]) -> Data? {
        guard let image = render(base: base, annotations: annotations) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

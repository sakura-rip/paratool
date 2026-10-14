import AppKit

public enum ImageRenderer {
    // Shared by the flipped canvas and export; annotation coordinates start at top-left.
    public static func draw(_ annotations: [Annotation], base: CGImage? = nil) {
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
            case .redact, .highlight: path.appendRect(mark.bounds); path.fill()
            case .mosaic:
                if let base { drawMosaic(base: base, bounds: mark.bounds, blockSize: max(12, mark.width * 4)) }
            case .tag:
                path.appendOval(in: mark.bounds); path.fill()
                let textColor: NSColor = mark.color.red * 0.299 + mark.color.green * 0.587 + mark.color.blue * 0.114 > 0.65 ? .black : .white
                let attributes: [NSAttributedString.Key: Any] = [.font: mark.font, .foregroundColor: textColor]
                let size = (mark.text as NSString).size(withAttributes: attributes)
                (mark.text as NSString).draw(at: CGPoint(x: mark.bounds.midX - size.width / 2, y: mark.bounds.midY - size.height / 2), withAttributes: attributes)
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


    private static func drawMosaic(base: CGImage, bounds: CGRect, blockSize: CGFloat) {
        let rect = bounds.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !rect.isEmpty, let cropped = base.cropping(to: rect) else { return }
        let width = max(1, Int(ceil(rect.width / blockSize)))
        let height = max(1, Int(ceil(rect.height / blockSize)))
        guard let small = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .high
        small.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixels = small.makeImage() else { return }
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: pixels, size: NSSize(width: width, height: height)).draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
    }

    public static func render(base: CGImage, annotations: [Annotation]) -> CGImage? {
        guard let context = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        context.draw(base, in: rect)
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw(annotations, base: base)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    public static func png(base: CGImage, annotations: [Annotation]) -> Data? {
        guard let image = render(base: base, annotations: annotations) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}

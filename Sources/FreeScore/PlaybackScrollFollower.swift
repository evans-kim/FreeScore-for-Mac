import AppKit

enum PlaybackScrollFollower {
    enum Axes { case both, horizontal }

    @discardableResult
    static func center(_ point: CGPoint, in view: NSView, smoothly: Bool,
                       axes: Axes = .both) -> Bool {
        guard let scrollView = view.enclosingScrollView,
              let documentView = scrollView.documentView else { return false }
        let clipView = scrollView.contentView
        let location = view.convert(point, to: documentView)
        let viewport = clipView.bounds.size
        let document = documentView.bounds
        let current = clipView.bounds.origin
        let target = CGPoint(
            x: min(max(document.minX, location.x - viewport.width / 2),
                   max(document.minX, document.maxX - viewport.width)),
            y: axes == .horizontal ? current.y :
                min(max(document.minY, location.y - viewport.height / 2),
                    max(document.minY, document.maxY - viewport.height))
        )
        let xDistance = abs(target.x - current.x)
        let yDistance = abs(target.y - current.y)
        let xFraction: CGFloat = smoothly ? (xDistance > viewport.width / 2 ? 0.65 : 0.32) : 1
        let yFraction: CGFloat = smoothly ? (yDistance > viewport.height / 2 ? 0.65 : 0.32) : 1
        let next = CGPoint(x: current.x + (target.x - current.x) * xFraction,
                           y: current.y + (target.y - current.y) * yFraction)
        guard abs(next.x - current.x) > 0.25 || abs(next.y - current.y) > 0.25 else { return true }
        clipView.scroll(to: next)
        scrollView.reflectScrolledClipView(clipView)
        return true
    }
}

import AppKit

final class WaveformView: NSView {
    private let weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private var smoothed: [Float] = Array(repeating: 0, count: 5)
    private var displayLink: CVDisplayLink?

    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 3
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 24
    private let cornerRadius: CGFloat = 2

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupDisplayLink()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let dl = displayLink { CVDisplayLinkStop(dl) }
    }

    func update(level: Float) {
        let attack: Float = 0.4
        let release: Float = 0.15
        for i in 0..<5 {
            let target = level * weights[i]
            let alpha = target > smoothed[i] ? attack : release
            let jitter = Float.random(in: -0.04...0.04)
            smoothed[i] = smoothed[i] * (1 - alpha) + target * alpha + jitter
            smoothed[i] = max(0, min(1, smoothed[i]))
        }
    }

    private func setupDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let dl = displayLink else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(dl, { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<WaveformView>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { view.setNeedsDisplay(view.bounds) }
            return kCVReturnSuccess
        }, selfPtr)

        CVDisplayLinkStart(dl)
    }

    override func draw(_ dirtyRect: NSRect) {
        let totalBarWidth = CGFloat(5) * barWidth + CGFloat(4) * barSpacing
        let startX = (bounds.width - totalBarWidth) / 2

        for i in 0..<5 {
            let level = CGFloat(smoothed[i])
            let height = minHeight + (maxHeight - minHeight) * level
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let y = (bounds.height - height) / 2

            let rect = NSRect(x: x, y: y, width: barWidth, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.white.withAlphaComponent(0.85).setFill()
            path.fill()
        }
    }
}

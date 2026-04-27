import AppKit
import QuartzCore

final class WaveformView: NSView {
    private let weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private var smoothed: [Float] = Array(repeating: 0, count: 5)
    private var displayLink: CADisplayLink?
    private var barLayers: [CALayer] = []

    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 3
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 26
    private let cornerRadius: CGFloat = 2

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers = []
        for _ in 0..<5 {
            let layer = CALayer()
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            layer.cornerRadius = cornerRadius
            layer.shadowColor = NSColor.white.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 0)
            layer.shadowRadius = 3
            layer.shadowOpacity = 0.4
            self.layer?.addSublayer(layer)
            barLayers.append(layer)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        if let window {
            let link = window.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    deinit {
        displayLink?.invalidate()
    }

    @MainActor
    func update(level: Float) {
        let attack: Float = 0.35
        let release: Float = 0.12
        for i in 0..<5 {
            let target = level * weights[i]
            let alpha = target > smoothed[i] ? attack : release
            let jitter = Float.random(in: -0.03...0.03)
            smoothed[i] = smoothed[i] * (1 - alpha) + target * alpha + jitter
            smoothed[i] = max(0, min(1, smoothed[i]))
        }
    }

    @objc private func tick() {
        layoutBars()
    }

    private func layoutBars() {
        let totalBarWidth = CGFloat(5) * barWidth + CGFloat(4) * barSpacing
        let startX = (bounds.width - totalBarWidth) / 2

        for i in 0..<5 {
            let level = CGFloat(smoothed[i])
            let height = minHeight + (maxHeight - minHeight) * level
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let y = (bounds.height - height) / 2

            let rect = CGRect(x: x, y: y, width: barWidth, height: height)
            barLayers[i].frame = rect

            // 动态调整光晕强度
            barLayers[i].shadowOpacity = 0.2 + 0.5 * Float(level)
        }
    }

    override func layout() {
        super.layout()
        layoutBars()
    }
}

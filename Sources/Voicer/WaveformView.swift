import AppKit
import QuartzCore

final class WaveformView: NSView {
    private let barCount = 8
    private var smoothed: [Float] = Array(repeating: 0, count: 8)
    private var displayLink: CADisplayLink?
    private var barLayers: [CALayer] = []

    // Symmetric weights: center bars taller
    private let weights: [Float] = [0.35, 0.55, 0.8, 1.0, 1.0, 0.8, 0.55, 0.35]

    private let barWidth: CGFloat = 3.5
    private let barSpacing: CGFloat = 2.5
    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 22
    private let cornerRadius: CGFloat = 1.75

    private var isIdle = true
    private var idlePhase: Float = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers = []
        for i in 0..<barCount {
            let layer = CAGradientLayer()
            layer.cornerRadius = cornerRadius
            layer.masksToBounds = true

            // Gradient: bright center to slightly dimmer edges
            let centerBright = NSColor.white.cgColor
            let edgeDim = NSColor.white.withAlphaComponent(0.55).cgColor
            if i < barCount / 2 {
                layer.colors = [edgeDim, centerBright]
            } else {
                layer.colors = [centerBright, edgeDim]
            }
            layer.startPoint = CGPoint(x: 0.5, y: 1)
            layer.endPoint = CGPoint(x: 0.5, y: 0)

            layer.shadowColor = NSColor.white.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 0)
            layer.shadowRadius = 4
            layer.shadowOpacity = 0.3

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
        isIdle = level < 0.01
        for i in 0..<barCount {
            let target = level * weights[i]
            let attack: Float = 0.38
            let release: Float = 0.10
            let alpha = target > smoothed[i] ? attack : release
            let jitter = Float.random(in: -0.02...0.02)
            smoothed[i] = smoothed[i] * (1 - alpha) + target * alpha + jitter
            smoothed[i] = max(0, min(1, smoothed[i]))
        }
    }

    @objc private func tick() {
        // Idle breathing animation
        if isIdle {
            idlePhase += 0.04
            for i in 0..<barCount {
                let breath = 0.12 + 0.08 * sinf(idlePhase + Float(i) * 0.6)
                smoothed[i] = smoothed[i] * 0.88 + breath * 0.12
            }
        }
        layoutBars()
    }

    private func layoutBars() {
        let totalBarWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (bounds.width - totalBarWidth) / 2

        for i in 0..<barCount {
            let level = CGFloat(smoothed[i])
            let height = minHeight + (maxHeight - minHeight) * level
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let y = (bounds.height - height) / 2

            barLayers[i].frame = CGRect(x: x, y: y, width: barWidth, height: height)
            barLayers[i].shadowOpacity = Float(0.15 + 0.45 * level)
        }
    }

    override func layout() {
        super.layout()
        layoutBars()
    }
}
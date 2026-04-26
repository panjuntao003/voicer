import AppKit

final class FloatingPanelController {
    private var panel: NSPanel?
    private var waveformView: WaveformView?
    private var label: NSTextField?
    private var textWidthConstraint: NSLayoutConstraint?

    private let panelHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 28
    private let horizontalPadding: CGFloat = 20
    private let waveformWidth: CGFloat = 44
    private let waveformHeight: CGFloat = 32
    private let gap: CGFloat = 12
    private let minTextWidth: CGFloat = 160
    private let maxTextWidth: CGFloat = 560

    func showRecording() {
        if panel == nil { buildPanel() }
        guard let panel = panel else { return }

        label?.stringValue = ""
        label?.textColor = .white
        updateTextWidth(animated: false)
        positionPanel()

        panel.alphaValue = 0
        panel.orderFront(nil)

        guard let contentLayer = panel.contentView?.layer else { return }

        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.damping = 12
        spring.initialVelocity = 8
        spring.fromValue = 0.7
        spring.toValue = 1.0
        spring.duration = 0.35
        spring.isRemovedOnCompletion = true
        contentLayer.add(spring, forKey: "entry")

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1.0
        }
    }

    func updateTranscription(_ text: String) {
        guard let label else { return }
        label.stringValue = text
        label.textColor = .white
        updateTextWidth(animated: true)
        positionPanel()
    }

    func showRefining() {
        label?.stringValue = "Refining…"
        label?.textColor = NSColor.white.withAlphaComponent(0.6)
    }

    @MainActor
    func updateLevel(_ level: Float) {
        waveformView?.update(level: level)
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func buildPanel() {
        let initialWidth = horizontalPadding * 2 + waveformWidth + gap + minTextWidth
        let frame = NSRect(x: 0, y: 0, width: initialWidth, height: panelHeight)

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        p.contentView = blur

        let wv = WaveformView(frame: NSRect(
            x: horizontalPadding,
            y: (panelHeight - waveformHeight) / 2,
            width: waveformWidth,
            height: waveformHeight
        ))
        wv.autoresizingMask = [.minYMargin, .maxYMargin]
        blur.addSubview(wv)
        waveformView = wv

        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 16, weight: .medium)
        tf.textColor = .white
        tf.lineBreakMode = .byTruncatingTail
        tf.maximumNumberOfLines = 1
        tf.drawsBackground = false
        tf.isBordered = false
        blur.addSubview(tf)

        let textLeft = horizontalPadding + waveformWidth + gap
        let widthConstraint = tf.widthAnchor.constraint(equalToConstant: minTextWidth)
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: textLeft),
            tf.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            widthConstraint
        ])
        textWidthConstraint = widthConstraint
        label = tf
        panel = p

        // Set anchor point once so spring animation scales from center
        p.contentView?.wantsLayer = true
        p.contentView?.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    private func updateTextWidth(animated: Bool) {
        guard let label, let constraint = textWidthConstraint, let panel else { return }
        let sizer = NSTextField(labelWithString: label.stringValue)
        sizer.font = label.font
        let needed = min(max(sizer.intrinsicContentSize.width + 8, minTextWidth), maxTextWidth)
        let newPanelWidth = horizontalPadding * 2 + waveformWidth + gap + needed

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                constraint.animator().constant = needed
                panel.animator().setFrame(
                    NSRect(x: panel.frame.minX, y: panel.frame.minY,
                           width: newPanelWidth, height: panelHeight),
                    display: true
                )
            }
        } else {
            constraint.constant = needed
            panel.setFrame(
                NSRect(x: panel.frame.minX, y: panel.frame.minY,
                       width: newPanelWidth, height: panelHeight),
                display: false
            )
        }
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let x = screen.visibleFrame.midX - panel.frame.width / 2
        let y = screen.visibleFrame.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

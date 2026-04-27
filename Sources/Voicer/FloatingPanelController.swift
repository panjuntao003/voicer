import AppKit

enum PanelState {
    case recording
    case processing(message: String)
    case hidden
}

final class FloatingPanelController {
    private var panel: NSPanel?
    private var waveformView: WaveformView?
    private var label: NSTextField?
    private var statusIndicator: NSView?
    private var spinner: NSProgressIndicator?
    private var textWidthConstraint: NSLayoutConstraint?
    private var currentState: PanelState = .hidden

    private let panelHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 28
    private let horizontalPadding: CGFloat = 20
    private let waveformWidth: CGFloat = 44
    private let waveformHeight: CGFloat = 32
    private let gap: CGFloat = 12
    private let minTextWidth: CGFloat = 160
    private let maxTextWidth: CGFloat = 560

    // MARK: - Public API

    func showRecording() {
        transition(to: .recording)
    }

    func showProcessing(message: String) {
        transition(to: .processing(message: message))
    }

    func updateTranscription(_ text: String) {
        guard let label else { return }
        label.stringValue = text
        label.textColor = .white
        updateTextWidth(animated: true)
        positionPanel()
    }

    @MainActor
    func updateLevel(_ level: Float) {
        waveformView?.update(level: level)
    }

    func hide() {
        transition(to: .hidden)
    }

    // MARK: - State Management

    private func transition(to state: PanelState) {
        switch state {
        case .recording:
            showPanel()
            configureForRecording()
        case .processing(let message):
            guard panel != nil else { return }
            configureForProcessing(message: message)
        case .hidden:
            animateHide()
        }
        currentState = state
    }

    // MARK: - Panel Lifecycle

    private func showPanel() {
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

    private func animateHide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 0
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue = 0.9
            scale.duration = 0.22
            panel.contentView?.layer?.add(scale, forKey: "exit")
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - State Configurations

    private func configureForRecording() {
        label?.stringValue = "正在聆听…"
        label?.textColor = .white
        waveformView?.isHidden = false
        statusIndicator?.isHidden = false
        spinner?.isHidden = true
        spinner?.stopAnimation(nil)
        updateTextWidth(animated: true)
        positionPanel()
        startStatusPulse()
    }

    private func configureForProcessing(message: String) {
        label?.stringValue = message
        label?.textColor = NSColor.white.withAlphaComponent(0.8)
        waveformView?.isHidden = true
        statusIndicator?.isHidden = true
        spinner?.isHidden = false
        spinner?.startAnimation(nil)
        updateTextWidth(animated: true)
        positionPanel()
        stopStatusPulse()
    }

    // MARK: - Panel Construction

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

        // Waveform
        let wv = WaveformView(frame: NSRect(
            x: horizontalPadding,
            y: (panelHeight - waveformHeight) / 2,
            width: waveformWidth,
            height: waveformHeight
        ))
        wv.autoresizingMask = [.minYMargin, .maxYMargin]
        blur.addSubview(wv)
        waveformView = wv

        // Status indicator (green pulse dot)
        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.isHidden = true
        blur.addSubview(dot)
        statusIndicator = dot

        NSLayoutConstraint.activate([
            dot.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -horizontalPadding),
            dot.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])

        // Spinner
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        blur.addSubview(spinner)
        self.spinner = spinner

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: horizontalPadding),
            spinner.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Label
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 16, weight: .semibold)
        tf.textColor = .white
        tf.lineBreakMode = .byTruncatingTail
        tf.maximumNumberOfLines = 1
        tf.drawsBackground = false
        tf.isBordered = false

        // Text shadow for crispness
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 0
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        tf.shadow = shadow

        blur.addSubview(tf)

        let textLeft = horizontalPadding + waveformWidth + gap
        let widthConstraint = tf.widthAnchor.constraint(equalToConstant: minTextWidth)
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: textLeft),
            tf.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            widthConstraint,
            tf.trailingAnchor.constraint(lessThanOrEqualTo: dot.leadingAnchor, constant: -gap)
        ])
        textWidthConstraint = widthConstraint
        label = tf
        panel = p

        p.contentView?.wantsLayer = true
        p.contentView?.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    // MARK: - Layout

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
        let y = screen.visibleFrame.maxY - panel.frame.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Status Indicator Animation

    private var pulseAnimation: CABasicAnimation?

    private func startStatusPulse() {
        guard let dotLayer = statusIndicator?.layer else { return }
        pulseAnimation?.removeAnimation(forKey: "pulse")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotLayer.add(pulse, forKey: "pulse")
        pulseAnimation = pulse
    }

    private func stopStatusPulse() {
        statusIndicator?.layer?.removeAnimation(forKey: "pulse")
        pulseAnimation = nil
    }
}

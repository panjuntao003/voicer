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

    private let panelHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 28
    private let padding: CGFloat = 18
    private let gap: CGFloat = 10

    // Recording: waveform + "正在聆听…" + green dot
    private let recordingWidth: CGFloat = 200
    // Processing: spinner + "正在识别…" / "正在润色…"
    private let processingWidth: CGFloat = 240

    // MARK: - Public API

    func showRecording() {
        transition(to: .recording)
    }

    func showProcessing(message: String) {
        transition(to: .processing(message: message))
    }

    func updateTranscription(_ text: String) {
        // Panel only shows state indicators, no real-time text
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
            showPanel(width: recordingWidth)
            configureForRecording()
        case .processing(let message):
            showPanel(width: processingWidth)
            configureForProcessing(message: message)
        case .hidden:
            animateHide()
        }
    }

    // MARK: - Panel Lifecycle

    private func showPanel(width: CGFloat) {
        if panel == nil { buildPanel() }
        guard let panel = panel else { return }

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - width / 2
            let targetY = screen.visibleFrame.maxY - panelHeight - 12
            // Start above the screen (hidden)
            let startY = screen.visibleFrame.maxY + 20
            panel.setFrame(NSRect(x: x, y: startY, width: width, height: panelHeight), display: true)

            // Animate sliding down from top
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1.0)
                panel.animator().setFrame(NSRect(x: x, y: targetY, width: width, height: panelHeight), display: true)
                panel.animator().alphaValue = 1.0
            })
        }

        panel.alphaValue = 1.0
        panel.orderFront(nil)
    }

    private func animateHide() {
        guard let panel, let screen = NSScreen.main else { return }
        let currentFrame = panel.frame

        // Animate sliding up and fading out
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1.0)
            panel.animator().setFrame(
                NSRect(x: currentFrame.minX, y: screen.visibleFrame.maxY + 20, width: currentFrame.width, height: panelHeight),
                display: true
            )
            panel.animator().alphaValue = 0
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
        // Position label between waveform and dot
        label?.alignment = .left
        startStatusPulse()
    }

    private func configureForProcessing(message: String) {
        label?.stringValue = message
        label?.textColor = .white
        waveformView?.isHidden = true
        statusIndicator?.isHidden = true
        spinner?.isHidden = false
        spinner?.startAnimation(nil)
        // Center label in processing state
        label?.alignment = .center
        stopStatusPulse()
    }

    // MARK: - Panel Construction

    private func buildPanel() {
        let frame = NSRect(x: 0, y: 0, width: recordingWidth, height: panelHeight)

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

        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = cornerRadius
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        container.autoresizingMask = [.width, .height]
        p.contentView = container

        // Waveform (left side for recording state)
        let wv = WaveformView(frame: NSRect(
            x: padding,
            y: (panelHeight - 32) / 2,
            width: 44,
            height: 32
        ))
        wv.autoresizingMask = [.minYMargin, .maxYMargin]
        container.addSubview(wv)
        waveformView = wv

        // Status indicator (green pulse dot, right side)
        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.isHidden = true
        container.addSubview(dot)
        statusIndicator = dot

        NSLayoutConstraint.activate([
            dot.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            dot.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])

        // Spinner (left side for processing state)
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        container.addSubview(spinner)
        self.spinner = spinner

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Label — positioned between waveform and dot for recording, centered for processing
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 15, weight: .semibold)
        tf.textColor = .white
        tf.lineBreakMode = .byTruncatingTail
        tf.maximumNumberOfLines = 1
        tf.drawsBackground = false
        tf.isBordered = false
        tf.alignment = .left

        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        tf.shadow = shadow

        container.addSubview(tf)

        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: wv.trailingAnchor, constant: gap),
            tf.trailingAnchor.constraint(equalTo: dot.leadingAnchor, constant: -gap),
            tf.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        label = tf
        panel = p

        p.contentView?.wantsLayer = true
        p.contentView?.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    // MARK: - Status Indicator Animation

    private func startStatusPulse() {
        guard let dotLayer = statusIndicator?.layer else { return }
        dotLayer.removeAnimation(forKey: "pulse")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotLayer.add(pulse, forKey: "pulse")
    }

    private func stopStatusPulse() {
        statusIndicator?.layer?.removeAnimation(forKey: "pulse")
    }
}
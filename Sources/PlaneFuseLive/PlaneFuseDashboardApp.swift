import AppKit
import AVFoundation
import Foundation
import PlaneFuseCore

/// Judge-facing PlaneFuse Live shell. Live values are populated only after a
/// real camera callback and inference; the stored evidence panel is explicitly
/// labeled and never doubles as live state.
func runPlaneFuseDashboardApp() {
    let application = NSApplication.shared
    application.setActivationPolicy(.regular)
    let delegate = PlaneFuseDashboardAppDelegate()
    application.delegate = delegate
    application.activate(ignoringOtherApps: true)
    application.run()
}

final class PlaneFuseDashboardAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: PlaneFuseDashboardController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = PlaneFuseDashboardController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_360, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PlaneFuse Live"
        window.minSize = NSSize(width: 1_120, height: 720)
        window.center()
        window.contentView = controller.rootView
        window.makeKeyAndOrderFront(nil)
        self.controller = controller
        self.window = window
        controller.start()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        controller?.stop()
        return .terminateNow
    }
}

final class PlaneFuseDashboardController: NSObject {
    let rootView: NSView

    private let previewView = PreviewHostView()
    private let previewStatus = NSTextField(labelWithString: "CONNECTING TO CAMERA")
    private let liveStatus = NSTextField(labelWithString: "LIVE METRICS · WAITING")
    private let selectedMode = NSSegmentedControl(labels: ["B2 · RGB", "PLANEFUSE · NV12"], trackingMode: .selectOne, target: nil, action: nil)
    private let selectedModeLabel = NSTextField(labelWithString: "PLANEFUSE · C1-SR SOURCE REUSE")
    private let top3Label = NSTextField(labelWithString: "Top predictions will appear after the first real frame.")
    private let bTop3Label = NSTextField(labelWithString: "B2 · waiting")
    private let cTop3Label = NSTextField(labelWithString: "PlaneFuse · waiting")
    private let frontendValue = NSTextField(labelWithString: "—")
    private let endToEndValue = NSTextField(labelWithString: "—")
    private let fpsValue = NSTextField(labelWithString: "—")
    private let dropsValue = NSTextField(labelWithString: "—")
    private let parityValue = NSTextField(labelWithString: "PENDING")
    private let errorValue = NSTextField(labelWithString: "—")
    private let cameraValue = NSTextField(labelWithString: "INITIALIZING")
    private let storedEvidence = NSTextField(labelWithString: "STORED EVIDENCE · R7.5 confirmation · C1-SR 6.18% below C1 / 11.81% below B2")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var capture: LiveCameraCapture?
    private var stopped = false
    private let stateLock = NSLock()
    private var modeIndex = 1

    init(rootView: NSView = NSView()) {
        self.rootView = rootView
        super.init()
        buildInterface()
    }

    func start() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.runLiveLoop() }
    }

    func stop() {
        stateLock.lock(); stopped = true; stateLock.unlock()
    }

    @objc private func changeMode(_ sender: NSSegmentedControl) {
        stateLock.lock(); modeIndex = sender.selectedSegment; stateLock.unlock()
        let label = sender.selectedSegment == 0 ? "B2 · RGB baseline" : "PlaneFuse · C1-SR source reuse"
        DispatchQueue.main.async { [weak self] in self?.selectedModeLabel.stringValue = label.uppercased() }
    }

    private func buildInterface() {
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor(hex: 0x0B1015).cgColor

        let header = makeHeader()
        let previewCard = makePreviewCard()
        let panel = makePanel()
        let body = NSStackView(views: [previewCard, panel])
        body.orientation = .horizontal; body.spacing = 22; body.alignment = .top; body.distribution = .fill

        let stack = NSStackView(views: [header, body])
        stack.orientation = .vertical; stack.spacing = 18; stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -24),
            previewCard.widthAnchor.constraint(equalTo: panel.widthAnchor, multiplier: 61.0 / 39.0),
            previewCard.heightAnchor.constraint(equalTo: body.heightAnchor),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor),
            body.heightAnchor.constraint(equalTo: stack.heightAnchor, constant: -90)
        ])
        selectedMode.target = self; selectedMode.action = #selector(changeMode(_:)); selectedMode.selectedSegment = 1
    }

    private func makeHeader() -> NSView {
        let view = NSView(); view.translatesAutoresizingMaskIntoConstraints = false
        let brand = label("PLANEFUSE / LIVE", size: 12, weight: .bold, color: NSColor(hex: 0x62E6C5))
        let title = label("A camera frame, before the tensor exists.", size: 27, weight: .bold, color: NSColor(hex: 0xF4F7F6))
        let subtitle = label("Local MobileNetV2 inference · one honest boundary at a time", size: 12, weight: .regular, color: NSColor(hex: 0x8B9AA5))
        let stack = NSStackView(views: [brand, title, subtitle]); stack.orientation = .vertical; stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.topAnchor.constraint(equalTo: view.topAnchor), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor), view.heightAnchor.constraint(equalToConstant: 74)])
        return view
    }

    private func makePreviewCard() -> NSView {
        let card = cardView(); card.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true; previewView.layer?.backgroundColor = NSColor(hex: 0x111A20).cgColor; previewView.translatesAutoresizingMaskIntoConstraints = false
        previewStatus.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium); previewStatus.textColor = NSColor(hex: 0x62E6C5); previewStatus.alignment = .center; previewStatus.translatesAutoresizingMaskIntoConstraints = false
        let tag = label("CONTINUOUS PREVIEW", size: 10, weight: .bold, color: NSColor(hex: 0x8B9AA5)); tag.translatesAutoresizingMaskIntoConstraints = false
        let diagram = label("NV12 camera  →  resize boundary  →  B2 RGB / PlaneFuse NV12  →  shared tail", size: 11, weight: .regular, color: NSColor(hex: 0xAEBAC0)); diagram.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(previewView); card.addSubview(tag); card.addSubview(previewStatus); card.addSubview(diagram)
        NSLayoutConstraint.activate([
            tag.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), tag.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            previewView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16), previewView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16), previewView.topAnchor.constraint(equalTo: tag.bottomAnchor, constant: 12), previewView.bottomAnchor.constraint(equalTo: diagram.topAnchor, constant: -14),
            previewStatus.centerXAnchor.constraint(equalTo: previewView.centerXAnchor), previewStatus.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            diagram.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), diagram.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18), diagram.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -17)
        ])
        return card
    }

    private func makePanel() -> NSView {
        let panel = NSView(); panel.translatesAutoresizingMaskIntoConstraints = false
        let modeRow = NSStackView(views: [selectedMode, selectedModeLabel]); modeRow.orientation = .vertical; modeRow.spacing = 8
        let liveBlock = makeBlock(title: "LIVE FRAME", views: [liveStatus, top3Label])
        let compareBlock = makeBlock(title: "B2 / PLANEFUSE PARITY", views: [bTop3Label, cTop3Label, parityValue, errorValue])
        let metrics = makeMetricsBlock()
        let resources = makeResourceBlock()
        let stored = makeBlock(title: "JUDGE CONTEXT", views: [storedEvidence])
        let stack = NSStackView(views: [modeRow, liveBlock, compareBlock, metrics, resources, stored]); stack.orientation = .vertical; stack.spacing = 12; stack.alignment = .width
        stack.translatesAutoresizingMaskIntoConstraints = false; panel.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor), stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor), stack.topAnchor.constraint(equalTo: panel.topAnchor), stack.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor)])
        [liveStatus, selectedModeLabel, top3Label, bTop3Label, cTop3Label, parityValue, errorValue, frontendValue, endToEndValue, fpsValue, dropsValue, cameraValue, storedEvidence].forEach { $0.maximumNumberOfLines = 3; $0.lineBreakMode = .byWordWrapping; $0.translatesAutoresizingMaskIntoConstraints = false }
        return panel
    }

    private func makeMetricsBlock() -> NSView {
        let block = cardView(); let title = label("MEASURED LIVE STATE", size: 10, weight: .bold, color: NSColor(hex: 0x8B9AA5)); title.translatesAutoresizingMaskIntoConstraints = false
        let rows = NSStackView(); rows.orientation = .vertical; rows.spacing = 6; rows.translatesAutoresizingMaskIntoConstraints = false
        for (name, value) in [("stem + frontend", frontendValue), ("post-resize → result", endToEndValue), ("comparison-loop FPS", fpsValue), ("drops / overwrite", dropsValue), ("camera", cameraValue)] {
            let row = NSStackView(views: [label(name.uppercased(), size: 10, weight: .medium, color: NSColor(hex: 0x8B9AA5)), value]); row.orientation = .horizontal; row.distribution = .fill; row.spacing = 10
            value.alignment = .right; row.translatesAutoresizingMaskIntoConstraints = false; rows.addArrangedSubview(row)
        }
        block.addSubview(title); block.addSubview(rows); NSLayoutConstraint.activate([title.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), title.topAnchor.constraint(equalTo: block.topAnchor, constant: 12), rows.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), rows.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -14), rows.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10), rows.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -12)]); return block
    }

    private func makeResourceBlock() -> NSView {
        let block = cardView(); let title = label("RESOURCE BOUNDARIES", size: 10, weight: .bold, color: NSColor(hex: 0x8B9AA5)); title.translatesAutoresizingMaskIntoConstraints = false
        let text = label("B2  ·  RGB intermediate  602,112 B logical / 606,208 B Metal allocated\nC1-SR  ·  full RGB intermediate  NONE\nBoth  ·  CPU activation element-copy  0 B\nBoth  ·  shared pretrained tail", size: 11, weight: .medium, color: NSColor(hex: 0xD4DDD9)); text.maximumNumberOfLines = 4; text.translatesAutoresizingMaskIntoConstraints = false
        block.addSubview(title); block.addSubview(text); NSLayoutConstraint.activate([title.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), title.topAnchor.constraint(equalTo: block.topAnchor, constant: 12), text.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), text.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -14), text.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 9), text.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -12)]); return block
    }

    private func makeBlock(title: String, views: [NSView]) -> NSView {
        let block = NSView(); block.translatesAutoresizingMaskIntoConstraints = false; block.wantsLayer = true; block.layer?.backgroundColor = NSColor(hex: 0x121B21).cgColor; block.layer?.cornerRadius = 8
        let heading = label(title, size: 10, weight: .bold, color: NSColor(hex: 0x8B9AA5)); heading.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: views); stack.orientation = .vertical; stack.spacing = 5; stack.translatesAutoresizingMaskIntoConstraints = false
        block.addSubview(heading); block.addSubview(stack); NSLayoutConstraint.activate([heading.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), heading.topAnchor.constraint(equalTo: block.topAnchor, constant: 12), stack.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), stack.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -14), stack.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8), stack.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -12)]); return block
    }

    private func cardView() -> NSView { let view = NSView(); view.wantsLayer = true; view.layer?.backgroundColor = NSColor(hex: 0x121B21).cgColor; view.layer?.cornerRadius = 8; view.translatesAutoresizingMaskIntoConstraints = false; return view }
    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField { let field = NSTextField(labelWithString: text); field.font = NSFont.systemFont(ofSize: size, weight: weight); field.textColor = color; field.isSelectable = false; return field }

    private func runLiveLoop() {
        do {
            let capture = try LiveCameraCapture(); let runner = try CameraInferenceRunner(); self.capture = capture
            DispatchQueue.main.async { [weak self] in self?.installPreview(capture: capture) }
            let outputs = try capture.bridge.makeOutputRing(count: 3, geometry: capture.geometry)
            var index = 0; let started = ProcessInfo.processInfo.systemUptime
            while !isStopped {
                let frame = try capture.nextFrame(timeout: 2); let output = outputs[index % outputs.count]
                _ = try capture.bridge.execute(pixelBuffer: frame.pixelBuffer, into: output)
                let ready = ProcessInfo.processInfo.systemUptime
                let input = MetalRGBBaseline.NV12Textures(yPlane: output.yPlane, uvPlane: output.uvPlane)
                let b = try runner.inferB2(input: input, resizedReadyUptime: ready, callbackArrivalUptime: frame.callbackArrivalUptime)
                let c = try runner.inferC1SourceReuse(input: input, resizedReadyUptime: ready, callbackArrivalUptime: frame.callbackArrivalUptime, verifyAgainstCurrentB2: true)
                index += 1; let snapshot = capture.delegate.snapshot(); let elapsed = ProcessInfo.processInfo.systemUptime - started
                let selected = currentMode == 0 ? b : c
                DispatchQueue.main.async { [weak self] in self?.update(b: b, c: c, selected: selected, snapshot: snapshot, fps: elapsed > 0 ? Double(index) / elapsed : 0) }
            }
        } catch { DispatchQueue.main.async { [weak self] in self?.showCameraError(error.localizedDescription) } }
    }

    private var isStopped: Bool { stateLock.lock(); defer { stateLock.unlock() }; return stopped }
    private var currentMode: Int { stateLock.lock(); defer { stateLock.unlock() }; return modeIndex }

    private func installPreview(capture: LiveCameraCapture) { previewLayer?.removeFromSuperlayer(); let layer = AVCaptureVideoPreviewLayer(session: capture.session); layer.videoGravity = .resizeAspectFill; previewView.previewLayer = layer; previewView.layer?.addSublayer(layer); previewLayer = layer; previewStatus.stringValue = "LIVE · NV12 VIDEO-RANGE · \(capture.activeFormat)"; cameraValue.stringValue = capture.activeFormat }
    private func update(b: CameraInferenceRunner.CandidateResult, c: CameraInferenceRunner.CandidateResult, selected: CameraInferenceRunner.CandidateResult, snapshot: CameraFrameDelegate.Snapshot, fps: Double) {
        liveStatus.stringValue = "LIVE METRICS · FRAME \(snapshot.callbackCount)"
        top3Label.stringValue = formatTop3(selected.topPredictions)
        bTop3Label.stringValue = "B2 · RGB baseline\n\(formatTop3(b.topPredictions))"
        cTop3Label.stringValue = "PlaneFuse · C1-SR source reuse\n\(formatTop3(c.topPredictions))"
        frontendValue.stringValue = String(format: "%.3f ms", selected.frontendMilliseconds)
        endToEndValue.stringValue = String(format: "%.3f ms", selected.postResizeInputToResultMilliseconds)
        fpsValue.stringValue = String(format: "%.1f", fps)
        dropsValue.stringValue = "\(snapshot.droppedCallbackCount) / \(snapshot.overwrittenFrameCount)"
        parityValue.stringValue = c.prediction.label == b.prediction.label ? "PASS · top-1" : "QUALIFIED · top-1 differs"
        errorValue.stringValue = String(format: "activation max %.7g", c.activationMaxAbsoluteDifference)
    }
    private func formatTop3(_ predictions: [(label: String, confidence: Double)]) -> String { predictions.enumerated().map { "\($0.offset + 1)  \($0.element.label)  \(String(format: "%.1f%%", $0.element.confidence * 100))" }.joined(separator: "   ·   ") }
    private func showCameraError(_ message: String) { liveStatus.stringValue = "NO LIVE CAMERA METRICS"; previewStatus.stringValue = message.uppercased(); cameraValue.stringValue = "UNAVAILABLE"; top3Label.stringValue = "No prediction inferred. The stored evidence panel remains separate."; parityValue.stringValue = "UNMEASURED"; errorValue.stringValue = "—" }
}

private final class PreviewHostView: NSView {
    weak var previewLayer: AVCaptureVideoPreviewLayer?

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}

private extension NSColor {
    convenience init(hex: UInt32) { self.init(calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1) }
}

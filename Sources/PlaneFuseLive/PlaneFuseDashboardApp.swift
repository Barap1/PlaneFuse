import AppKit
import AVFoundation
import Foundation
import PlaneFuseCore

/// PlaneFuse Live is a local research dashboard. Live camera values and stored
/// benchmark evidence are deliberately kept in separate sections.
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
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(960, visible.width * 0.88), 1440)
        let height = min(max(640, visible.height * 0.84), 900)
        let controller = PlaneFuseDashboardController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PlaneFuse Live"
        window.minSize = NSSize(width: 960, height: 640)
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
    private let liveStatus = NSTextField(labelWithString: "WAITING FOR A CAMERA FRAME")
    private let selectedMode = NSSegmentedControl(labels: ["B2 · RGB", "PLANEFUSE · NV12"], trackingMode: .selectOne, target: nil, action: nil)
    private let selectedModeLabel = NSTextField(labelWithString: "PLANEFUSE · C1-SR SOURCE REUSE")
    private let top3Label = NSTextField(labelWithString: "Predictions appear after the first real frame.")
    private let bTop3Label = NSTextField(labelWithString: "B2 · waiting")
    private let cTop3Label = NSTextField(labelWithString: "PlaneFuse · waiting")
    private let frontendValue = NSTextField(labelWithString: "—")
    private let endToEndValue = NSTextField(labelWithString: "—")
    private let fpsValue = NSTextField(labelWithString: "—")
    private let dropsValue = NSTextField(labelWithString: "—")
    private let parityValue = NSTextField(labelWithString: "UNMEASURED")
    private let errorValue = NSTextField(labelWithString: "—")
    private let cameraValue = NSTextField(labelWithString: "INITIALIZING")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var capture: LiveCameraCapture?
    private var stopped = false
    private let stateLock = NSLock()
    private var modeIndex = 1
    private var predictionSmoother = PredictionPresentationSmoother()

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
        let label = sender.selectedSegment == 0 ? "B2 · RGB BASELINE" : "PLANEFUSE · C1-SR SOURCE REUSE"
        DispatchQueue.main.async { [weak self] in self?.selectedModeLabel.stringValue = label }
    }

    private func buildInterface() {
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor(hex: 0x0B1117).cgColor

        let header = makeHeader()
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        let previewColumn = makePreviewColumn()
        let inspector = makeInspector()
        split.addArrangedSubview(previewColumn)
        split.addArrangedSubview(inspector)
        let splitRatio = previewColumn.widthAnchor.constraint(equalTo: split.widthAnchor, multiplier: 0.60)
        splitRatio.priority = .defaultHigh
        let footer = makeFooter()
        let layout = NSStackView(views: [header, split, footer])
        layout.orientation = .vertical
        layout.spacing = 16
        layout.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 24),
            layout.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -24),
            layout.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20),
            layout.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -18),
            header.heightAnchor.constraint(equalToConstant: 68),
            split.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),
            splitRatio,
            previewColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 500),
            inspector.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            footer.heightAnchor.constraint(equalToConstant: 20)
        ])
        selectedMode.target = self
        selectedMode.action = #selector(changeMode(_:))
        selectedMode.selectedSegment = 1
    }

    private func makeHeader() -> NSView {
        let view = NSView(); view.translatesAutoresizingMaskIntoConstraints = false
        let eyebrow = label("PLANEFUSE  /  LIVE INFERENCE", size: 11, weight: .bold, color: NSColor(hex: 0x64E6C4))
        let title = label("Native-plane inference on Apple Silicon", size: 25, weight: .bold, color: NSColor(hex: 0xF3F7F5))
        let subtitle = label("A local MobileNetV2 camera path with a visible representation boundary", size: 12, weight: .regular, color: NSColor(hex: 0x8D9CA7))
        let stack = NSStackView(views: [eyebrow, title, subtitle])
        stack.orientation = .vertical; stack.spacing = 4; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.topAnchor.constraint(equalTo: view.topAnchor), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        return view
    }

    private func makePreviewColumn() -> NSView {
        let column = NSView(); column.translatesAutoresizingMaskIntoConstraints = false
        let previewCard = cardView()
        let section = label("CAMERA PREVIEW", size: 10, weight: .bold, color: NSColor(hex: 0x8D9CA7)); section.translatesAutoresizingMaskIntoConstraints = false
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true; previewView.layer?.backgroundColor = NSColor(hex: 0x111C24).cgColor; previewView.layer?.cornerRadius = 8
        previewStatus.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium); previewStatus.textColor = NSColor(hex: 0x64E6C4); previewStatus.alignment = .center; previewStatus.translatesAutoresizingMaskIntoConstraints = false
        previewStatus.maximumNumberOfLines = 2; previewStatus.lineBreakMode = .byWordWrapping
        let instruction = label("Place one object inside the classification region", size: 11, weight: .medium, color: NSColor(hex: 0xB5C1C7)); instruction.translatesAutoresizingMaskIntoConstraints = false
        previewCard.addSubview(section); previewCard.addSubview(previewView); previewCard.addSubview(previewStatus); previewCard.addSubview(instruction)
        NSLayoutConstraint.activate([
            section.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 16), section.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 14),
            previewView.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 14), previewView.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -14), previewView.topAnchor.constraint(equalTo: section.bottomAnchor, constant: 10),
            previewView.widthAnchor.constraint(greaterThanOrEqualToConstant: 440), previewView.heightAnchor.constraint(equalTo: previewView.widthAnchor, multiplier: 9.0 / 16.0),
            previewStatus.centerXAnchor.constraint(equalTo: previewView.centerXAnchor), previewStatus.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            instruction.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 16), instruction.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -16), instruction.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10), instruction.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -14)
        ])

        let pipelineCard = cardView()
        let pipelineTitle = label("REPRESENTATION BOUNDARY", size: 10, weight: .bold, color: NSColor(hex: 0x8D9CA7)); pipelineTitle.translatesAutoresizingMaskIntoConstraints = false
        let pipeline = PipelineDiagramView(); pipeline.translatesAutoresizingMaskIntoConstraints = false
        pipelineCard.addSubview(pipelineTitle); pipelineCard.addSubview(pipeline)
        NSLayoutConstraint.activate([
            pipelineTitle.leadingAnchor.constraint(equalTo: pipelineCard.leadingAnchor, constant: 16), pipelineTitle.topAnchor.constraint(equalTo: pipelineCard.topAnchor, constant: 14),
            pipeline.leadingAnchor.constraint(equalTo: pipelineCard.leadingAnchor, constant: 12), pipeline.trailingAnchor.constraint(equalTo: pipelineCard.trailingAnchor, constant: -12), pipeline.topAnchor.constraint(equalTo: pipelineTitle.bottomAnchor, constant: 8), pipeline.bottomAnchor.constraint(equalTo: pipelineCard.bottomAnchor, constant: -12), pipeline.heightAnchor.constraint(equalToConstant: 164)
        ])
        let stack = NSStackView(views: [previewCard, pipelineCard]); stack.orientation = .vertical; stack.spacing = 14; stack.translatesAutoresizingMaskIntoConstraints = false
        column.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: column.leadingAnchor), stack.trailingAnchor.constraint(equalTo: column.trailingAnchor), stack.topAnchor.constraint(equalTo: column.topAnchor), stack.bottomAnchor.constraint(lessThanOrEqualTo: column.bottomAnchor)])
        return column
    }

    private func makeInspector() -> NSView {
        let document = InspectorDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false
        let modeRow = NSStackView(views: [selectedMode, selectedModeLabel]); modeRow.orientation = .vertical; modeRow.spacing = 7; modeRow.translatesAutoresizingMaskIntoConstraints = false
        let liveBlock = makeBlock(title: "LIVE CLASSIFICATION", views: [liveStatus, top3Label], minHeight: 104)
        let compareBlock = makeBlock(title: "MODEL PARITY", views: [bTop3Label, cTop3Label, parityValue, errorValue], minHeight: 168)
        let metrics = makeMetricsBlock()
        let resources = makeResourceBlock()
        let stored = makeStoredBenchmarkBlock()
        let stack = NSStackView(views: [modeRow, liveBlock, compareBlock, metrics, resources, stored])
        stack.orientation = .vertical; stack.spacing = 11; stack.alignment = .width; stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: document.leadingAnchor), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor), stack.topAnchor.constraint(equalTo: document.topAnchor), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)])
        [liveStatus, selectedModeLabel, top3Label, bTop3Label, cTop3Label, parityValue, errorValue, frontendValue, endToEndValue, fpsValue, dropsValue, cameraValue].forEach {
            $0.maximumNumberOfLines = 4; $0.lineBreakMode = .byWordWrapping; $0.translatesAutoresizingMaskIntoConstraints = false
        }
        let scroll = NSScrollView(); scroll.translatesAutoresizingMaskIntoConstraints = false; scroll.hasVerticalScroller = true; scroll.borderType = .noBorder; scroll.drawsBackground = false; scroll.documentView = document
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor), document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor)])
        return scroll
    }

    private func makeMetricsBlock() -> NSView {
        let block = cardView(); let title = label("MEASURED LIVE STATE", size: 10, weight: .bold, color: NSColor(hex: 0x8D9CA7)); title.translatesAutoresizingMaskIntoConstraints = false
        let rows = NSStackView(); rows.orientation = .vertical; rows.spacing = 7; rows.translatesAutoresizingMaskIntoConstraints = false
        for (name, value) in [("stem + frontend", frontendValue), ("post-resize → result", endToEndValue), ("comparison-loop FPS", fpsValue), ("drops / overwrite", dropsValue), ("camera", cameraValue)] {
            let row = NSStackView(views: [label(name.uppercased(), size: 10, weight: .medium, color: NSColor(hex: 0x8D9CA7)), value]); row.orientation = .horizontal; row.spacing = 10; row.distribution = .fill; row.translatesAutoresizingMaskIntoConstraints = false
            value.alignment = .right; row.addConstraint(value.widthAnchor.constraint(greaterThanOrEqualToConstant: 92)); rows.addArrangedSubview(row)
        }
        block.addSubview(title); block.addSubview(rows)
        NSLayoutConstraint.activate([title.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), title.topAnchor.constraint(equalTo: block.topAnchor, constant: 13), rows.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), rows.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -14), rows.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10), rows.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -13)])
        return block
    }

    private func makeResourceBlock() -> NSView {
        let block = cardView(); let title = label("RESOURCE BOUNDARIES", size: 10, weight: .bold, color: NSColor(hex: 0x8D9CA7)); title.translatesAutoresizingMaskIntoConstraints = false
        let diagram = ResourceBoundaryView(); diagram.translatesAutoresizingMaskIntoConstraints = false
        block.addSubview(title); block.addSubview(diagram)
        NSLayoutConstraint.activate([title.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), title.topAnchor.constraint(equalTo: block.topAnchor, constant: 13), diagram.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), diagram.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -14), diagram.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8), diagram.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -12), diagram.heightAnchor.constraint(equalToConstant: 82)])
        return block
    }

    private func makeStoredBenchmarkBlock() -> NSView {
        let block = cardView(); let title = label("STORED BENCHMARK", size: 10, weight: .bold, color: NSColor(hex: 0xF0B46A)); title.translatesAutoresizingMaskIntoConstraints = false
        let context = label("Reviewed R7.5 confirmation · MobileNetV2 / NV12", size: 11, weight: .medium, color: NSColor(hex: 0xB9C5CA)); context.translatesAutoresizingMaskIntoConstraints = false
        let metrics = label("B2 RGB     1.7379 ms\nC1-SR       1.5326 ms\nMatched p50  11.8% lower", size: 13, weight: .semibold, color: NSColor(hex: 0xF4F7F5)); metrics.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold); metrics.translatesAutoresizingMaskIntoConstraints = false
        let note = label("Stored evidence is not a current live measurement.", size: 10, weight: .regular, color: NSColor(hex: 0x8D9CA7)); note.translatesAutoresizingMaskIntoConstraints = false
        block.addSubview(title); block.addSubview(context); block.addSubview(metrics); block.addSubview(note)
        NSLayoutConstraint.activate([title.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), title.topAnchor.constraint(equalTo: block.topAnchor, constant: 13), context.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), context.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -14), context.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8), metrics.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), metrics.topAnchor.constraint(equalTo: context.bottomAnchor, constant: 10), note.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), note.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -14), note.topAnchor.constraint(equalTo: metrics.bottomAnchor, constant: 8), note.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -13)])
        return block
    }

    private func makeBlock(title: String, views: [NSView], minHeight: CGFloat) -> NSView {
        let block = cardView(); let heading = label(title, size: 10, weight: .bold, color: NSColor(hex: 0x8D9CA7)); heading.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: views); stack.orientation = .vertical; stack.spacing = 6; stack.translatesAutoresizingMaskIntoConstraints = false
        block.addSubview(heading); block.addSubview(stack)
        NSLayoutConstraint.activate([block.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight), heading.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), heading.topAnchor.constraint(equalTo: block.topAnchor, constant: 13), stack.leadingAnchor.constraint(equalTo: block.leadingAnchor, constant: 14), stack.trailingAnchor.constraint(equalTo: block.trailingAnchor, constant: -14), stack.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 9), stack.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -13)])
        return block
    }

    private func makeFooter() -> NSView {
        let footer = NSTextField(labelWithString: "LOCAL PROCESS  ·  NV12 SOURCE  ·  SAME PRETRAINED MOBILENETV2 TAIL  ·  LIVE VALUES UPDATE ONLY AFTER A REAL FRAME")
        footer.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium); footer.textColor = NSColor(hex: 0x70808B); footer.alignment = .center; footer.translatesAutoresizingMaskIntoConstraints = false
        return footer
    }

    private func cardView() -> NSView { let view = NSView(); view.wantsLayer = true; view.layer?.backgroundColor = NSColor(hex: 0x14212A).cgColor; view.layer?.cornerRadius = 9; view.translatesAutoresizingMaskIntoConstraints = false; return view }
    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField { let field = NSTextField(labelWithString: text); field.font = NSFont.systemFont(ofSize: size, weight: weight); field.textColor = color; field.isSelectable = false; return field }

    private func runLiveLoop() {
        do {
            let capture = try LiveCameraCapture(); let runner = try CameraInferenceRunner(semantics: capture.colorSemantics); self.capture = capture
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

    private func installPreview(capture: LiveCameraCapture) {
        previewLayer?.removeFromSuperlayer(); let layer = AVCaptureVideoPreviewLayer(session: capture.session); layer.videoGravity = .resizeAspectFill; previewView.previewLayer = layer; previewView.layer?.insertSublayer(layer, at: 0); previewLayer = layer
        previewStatus.stringValue = "LIVE · NV12 VIDEO-RANGE · \(capture.activeFormat)\n\(capture.colorMetadata)"; cameraValue.stringValue = capture.activeFormat
    }

    private func update(b: CameraInferenceRunner.CandidateResult, c: CameraInferenceRunner.CandidateResult, selected: CameraInferenceRunner.CandidateResult, snapshot: CameraFrameDelegate.Snapshot, fps: Double) {
        liveStatus.stringValue = "LIVE · FRAME \(snapshot.callbackCount) · CLASSIFICATION"
        top3Label.stringValue = formatTop3(predictionSmoother.update(selected.topPredictions))
        bTop3Label.stringValue = "B2 · RGB baseline\n\(formatTop3(b.topPredictions))"
        cTop3Label.stringValue = "PlaneFuse · C1-SR source reuse\n\(formatTop3(c.topPredictions))"
        frontendValue.stringValue = String(format: "%.3f ms", selected.frontendMilliseconds)
        endToEndValue.stringValue = String(format: "%.3f ms", selected.postResizeInputToResultMilliseconds)
        fpsValue.stringValue = String(format: "%.1f", fps)
        dropsValue.stringValue = "\(snapshot.droppedCallbackCount) / \(snapshot.overwrittenFrameCount)"
        parityValue.stringValue = c.prediction.label == b.prediction.label ? "PASS · top-1" : "QUALIFIED · top-1 differs"
        errorValue.stringValue = String(format: "activation max %.7g", c.activationMaxAbsoluteDifference)
    }

    private func formatTop3(_ predictions: [(label: String, confidence: Double)]) -> String {
        predictions.enumerated().map { "\($0.offset + 1)  \(humanLabel($0.element.label))  \(String(format: "%.1f%%", $0.element.confidence * 100))" }.joined(separator: "\n")
    }

    private func humanLabel(_ raw: String) -> String {
        let replacements = ["microphone, mike": "Microphone", "coffee mug": "Coffee mug", "computer keyboard, keypad": "Keyboard", "mouse, computer mouse": "Computer mouse"]
        if let exact = replacements[raw.lowercased()] { return exact }
        return raw.split(separator: ",", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces).capitalized } ?? raw
    }

    private func showCameraError(_ message: String) {
        liveStatus.stringValue = "NO LIVE CAMERA METRICS"
        previewStatus.stringValue = message.uppercased()
        cameraValue.stringValue = "UNAVAILABLE"
        top3Label.stringValue = "No prediction inferred. Stored benchmark evidence remains separate."
        parityValue.stringValue = "UNMEASURED"; errorValue.stringValue = "—"
    }
}

/// Smooths only the labels shown in the live dashboard. Inference, parity, and
/// measured timings remain the raw values returned by the model and kernels.
private struct PredictionPresentationSmoother {
    private var scores: [String: Double] = [:]
    private let alpha = 0.35

    mutating func update(_ predictions: [(label: String, confidence: Double)]) -> [(label: String, confidence: Double)] {
        let current = Dictionary(uniqueKeysWithValues: predictions.map { ($0.label, $0.confidence) })
        let labels = Set(scores.keys).union(current.keys)
        scores = labels.reduce(into: [:]) { result, label in
            result[label] = (1 - alpha) * scores[label, default: 0] + alpha * current[label, default: 0]
        }
        return scores
            .filter { $0.value > 0.01 }
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { (label: $0.key, confidence: $0.value) }
    }
}

private final class InspectorDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class PreviewHostView: NSView {
    weak var previewLayer: AVCaptureVideoPreviewLayer?
    override func layout() { super.layout(); previewLayer?.frame = bounds }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 100, bounds.height > 100 else { return }
        let side = min(bounds.width, bounds.height) * 0.56
        let region = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        NSColor(calibratedWhite: 1, alpha: 0.68).setStroke(); let path = NSBezierPath(roundedRect: region, xRadius: 12, yRadius: 12); path.lineWidth = 1.5; path.stroke()
    }
}

private final class PipelineDiagramView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = insetRect(bounds, dx: 2, dy: 4)
        let laneWidth = (bounds.width - 18) / 2
        drawLane(x: bounds.minX, width: laneWidth, title: "B2  RGB BASELINE", accent: NSColor(hex: 0x7C9CF5), nodes: ["NV12 Y + UV", "RGB tensor  606 KB", "RGB stem", "shared tail"])
        drawLane(x: bounds.minX + laneWidth + 18, width: laneWidth, title: "C1-SR  PLANEFUSE", accent: NSColor(hex: 0x64E6C4), nodes: ["NV12 Y + UV", "source tile staging", "transformed stem", "shared tail"])
    }
    private func drawLane(x: CGFloat, width: CGFloat, title: String, accent: NSColor, nodes: [String]) {
        let titleRect = NSRect(x: x, y: bounds.maxY - 18, width: width, height: 16); drawText(title, in: titleRect, font: NSFont.monospacedSystemFont(ofSize: 9, weight: .bold), color: accent)
        let nodeHeight: CGFloat = 24; let gap: CGFloat = 7; var y = bounds.maxY - 48
        for (index, node) in nodes.enumerated() {
            let rect = NSRect(x: x, y: y, width: width, height: nodeHeight); accent.withAlphaComponent(index == 0 ? 0.16 : 0.10).setFill(); NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill(); accent.withAlphaComponent(0.45).setStroke(); let outline = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5); outline.lineWidth = 0.7; outline.stroke(); drawText(node, in: rect.insetBy(dx: 8, dy: 5), font: NSFont.systemFont(ofSize: 10, weight: .medium), color: NSColor(hex: 0xD9E3E1))
            if index < nodes.count - 1 { accent.withAlphaComponent(0.5).setStroke(); let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: x + width / 2, y: y - 5)); arrow.line(to: NSPoint(x: x + width / 2, y: y - gap + 2)); arrow.lineWidth = 1; arrow.stroke() }
            y -= nodeHeight + gap
        }
    }
    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) { let style = NSMutableParagraphStyle(); style.alignment = .center; (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]) }
}

private final class ResourceBoundaryView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect); let body = bounds.insetBy(dx: 2, dy: 2)
        drawRow("B2", "full RGB intermediate", "606,208 B Metal", y: body.maxY - 20, color: NSColor(hex: 0x7C9CF5))
        drawRow("C1-SR", "full RGB intermediate", "0 B", y: body.maxY - 43, color: NSColor(hex: 0x64E6C4))
        drawRow("Both", "CPU activation copy", "0 B", y: body.maxY - 66, color: NSColor(hex: 0xB9C5CA))
    }
    private func drawRow(_ left: String, _ middle: String, _ right: String, y: CGFloat, color: NSColor) { drawText(left, in: NSRect(x: 0, y: y, width: 42, height: 16), font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold), color: color, alignment: .left); drawText(middle, in: NSRect(x: 45, y: y, width: max(70, bounds.width - 140), height: 16), font: NSFont.systemFont(ofSize: 10, weight: .regular), color: NSColor(hex: 0xB9C5CA), alignment: .left); drawText(right, in: NSRect(x: max(110, bounds.width - 92), y: y, width: 90, height: 16), font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium), color: NSColor(hex: 0xE9F1ED), alignment: .right) }
    private func drawText(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) { let style = NSMutableParagraphStyle(); style.alignment = alignment; (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]) }
}

private func insetRect(_ rect: NSRect, dx: CGFloat, dy: CGFloat) -> NSRect { rect.insetBy(dx: dx, dy: dy) }

private extension NSColor {
    convenience init(hex: UInt32) { self.init(calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1) }
}

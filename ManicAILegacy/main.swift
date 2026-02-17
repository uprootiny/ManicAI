import Cocoa

final class LegacyController: NSObject {
    private var queueItems: [String] = [
        "run smoke checks",
        "fix first blocker",
        "rerun smoke",
        "report concise status"
    ]

    let window: NSWindow
    private let queueField = NSTextField(string: "")
    private let queueView = NSTextView(frame: .zero)
    private let centerView = NSTextView(frame: .zero)
    private let rightView = NSTextView(frame: .zero)

    override init() {
        self.window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1220, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "ManicAI Legacy 10.11"
        window.minSize = NSSize(width: 960, height: 620)
        buildUI()
        refreshQueue()
        populateTelemetry()
    }

    private func buildUI() {
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        root.autoresizingMask = [.width, .height]
        window.contentView = root

        let header = NSTextField(labelWithString: "H Y P E R  P R O D U C T I V I T Y  P A N E L")
        header.font = NSFont.boldSystemFont(ofSize: 15)
        header.textColor = NSColor(calibratedRed: 0.54, green: 0.89, blue: 0.98, alpha: 1.0)
        header.frame = NSRect(x: 20, y: root.bounds.height - 42, width: 620, height: 20)
        header.autoresizingMask = [.maxXMargin, .minYMargin]
        root.addSubview(header)

        let status = NSTextField(labelWithString: "pipeline: available | build: warming | dev: aligned")
        status.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        status.textColor = NSColor.secondaryLabelColor
        status.frame = NSRect(x: root.bounds.width - 430, y: root.bounds.height - 42, width: 410, height: 20)
        status.alignment = .right
        status.autoresizingMask = [.minXMargin, .minYMargin]
        root.addSubview(status)

        let split = NSSplitView(frame: NSRect(x: 16, y: 16, width: root.bounds.width - 32, height: root.bounds.height - 70))
        split.autoresizingMask = [.width, .height]
        split.dividerStyle = .thin
        split.isVertical = true

        split.addSubview(makeLeftPane())
        split.addSubview(makeScrollPane(textView: centerView, title: "PANE LIVENESS + THROUGHPUT"))
        split.addSubview(makeScrollPane(textView: rightView, title: "SMOKE + BREADCRUMBS"))

        split.adjustSubviews()
        root.addSubview(split)
    }

    private func makeLeftPane() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 300))

        let queueTitle = NSTextField(labelWithString: "AGENT PROMPT QUEUE")
        queueTitle.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        queueTitle.frame = NSRect(x: 8, y: container.bounds.height - 28, width: 240, height: 16)
        queueTitle.autoresizingMask = [.maxXMargin, .minYMargin]
        container.addSubview(queueTitle)

        queueField.placeholderString = "Enqueue prompt"
        queueField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        queueField.frame = NSRect(x: 8, y: container.bounds.height - 56, width: 230, height: 24)
        queueField.autoresizingMask = [.width, .minYMargin]
        container.addSubview(queueField)

        let enqueue = NSButton(title: "Enqueue", target: self, action: #selector(onEnqueue))
        enqueue.frame = NSRect(x: 246, y: container.bounds.height - 56, width: 76, height: 24)
        enqueue.bezelStyle = .rounded
        enqueue.autoresizingMask = [.minXMargin, .minYMargin]
        container.addSubview(enqueue)

        let runNext = NSButton(title: "Run Next", target: self, action: #selector(onRunNext))
        runNext.frame = NSRect(x: 8, y: container.bounds.height - 86, width: 96, height: 24)
        runNext.bezelStyle = .rounded
        runNext.autoresizingMask = [.maxXMargin, .minYMargin]
        container.addSubview(runNext)

        let queueScroll = NSScrollView(frame: NSRect(x: 8, y: 8, width: 314, height: container.bounds.height - 100))
        queueScroll.autoresizingMask = [.width, .height]
        queueView.isEditable = false
        queueView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        queueView.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1.0)
        queueView.textColor = NSColor(calibratedWhite: 0.93, alpha: 1.0)
        queueScroll.documentView = queueView
        queueScroll.hasVerticalScroller = true
        container.addSubview(queueScroll)

        return container
    }

    private func makeScrollPane(textView: NSTextView, title: String) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 300))

        let caption = NSTextField(labelWithString: title)
        caption.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        caption.frame = NSRect(x: 8, y: container.bounds.height - 28, width: 360, height: 16)
        caption.autoresizingMask = [.maxXMargin, .minYMargin]
        container.addSubview(caption)

        let scroll = NSScrollView(frame: NSRect(x: 8, y: 8, width: container.bounds.width - 16, height: container.bounds.height - 40))
        scroll.autoresizingMask = [.width, .height]
        textView.isEditable = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1.0)
        textView.textColor = NSColor(calibratedWhite: 0.90, alpha: 1.0)
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        container.addSubview(scroll)

        return container
    }

    @objc private func onEnqueue() {
        let value = queueField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        queueItems.append(value)
        queueField.stringValue = ""
        refreshQueue()
    }

    @objc private func onRunNext() {
        guard !queueItems.isEmpty else { return }
        let task = queueItems.removeFirst()
        append(textView: rightView, line: "[run] \(task)")
        append(textView: rightView, line: "[smoke] status=ok blocker=none")
        refreshQueue()
    }

    private func refreshQueue() {
        if queueItems.isEmpty {
            queueView.string = "(empty)\n"
            return
        }
        queueView.string = queueItems.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n") + "\n"
    }

    private func populateTelemetry() {
        centerView.string = [
            "candidates:",
            "- coggy:1.0 liveness=warm thr=0 auth=openrouter",
            "- constellation:1.0 liveness=warm thr=0 auth=auth",
            "- ibid:0.0 liveness=warm thr=0 auth=token",
            "",
            "adapters:",
            "- tmux capture + pane send",
            "- git smoke loop",
            "- prompt queue + breadcrumb trail"
        ].joined(separator: "\n") + "\n"

        rightView.string = [
            "breadcrumbs:",
            "- observation -> decision -> action -> outcome",
            "- smoke: pending",
            "- blocker: approval_gate",
            "- resolver: risk-evaluate and escalate"
        ].joined(separator: "\n") + "\n"
    }

    private func append(textView: NSTextView, line: String) {
        textView.string += line + "\n"
        textView.scrollToEndOfDocument(nil)
    }
}

final class LegacyAppDelegate: NSObject, NSApplicationDelegate {
    private var controller: LegacyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = LegacyController()
        controller?.window.center()
        controller?.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

let app = NSApplication.shared
let delegate = LegacyAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

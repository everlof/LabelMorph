import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?
    private let captureWriter = DispatchQueue(label: "LabelMorphShowcase.capture-writer",
                                              qos: .utility)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMenu()

        let window = NSWindow(contentRect: NSRect(origin: .zero,
                                                  size: ShowcaseViewController.initialContentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "LabelMorph Showcase"
        window.isRestorable = false
        window.contentViewController = ShowcaseViewController()
        window.setContentSize(ShowcaseViewController.initialContentSize)
        window.contentMinSize = ShowcaseViewController.minimumContentSize
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        captureShowcaseFramesIfRequested(window: window)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// `-captureDirectory <path>` records a short transition from the actual
    /// Showcase window. This is intentionally launch-argument-only: it gives
    /// visual regression work deterministic evidence without adding debug UI.
    private func captureShowcaseFramesIfRequested(window: NSWindow) {
        guard let directory = UserDefaults.standard.string(forKey: "captureDirectory") else { return }

        let outputDirectory = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDirectory,
                                                 withIntermediateDirectories: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak window] in
            guard let window,
                  let controller = window.contentViewController as? ShowcaseViewController else { return }

            // Do not let the field editor's selection/caret become a timing-
            // dependent part of otherwise deterministic visual evidence.
            window.makeFirstResponder(nil)
            window.contentView?.displayIfNeeded()

            guard let captureBackdrop = self.captureBackdrop(for: window) else { return }
            let frameCount = 14
            self.capture(window: window,
                         backdrop: captureBackdrop,
                         to: outputDirectory.appendingPathComponent("frame-00.png"),
                         quitsAfterWriting: false)
            controller.beginScriptedMorph()

            for frameIndex in 1..<frameCount {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09 * Double(frameIndex)) { [weak window] in
                    guard let window else { return }
                    let fileURL = outputDirectory
                        .appendingPathComponent(String(format: "frame-%02d.png", frameIndex))
                    self.capture(
                        window: window,
                        backdrop: captureBackdrop,
                        to: fileURL,
                        quitsAfterWriting: frameIndex == frameCount - 1
                            && UserDefaults.standard.bool(forKey: "captureAndQuit")
                    )
                }
            }
        }
    }

    /// Captures the static AppKit controls once. Reusing this backdrop keeps
    /// field-editor and layer redraw timing from changing unrelated pixels
    /// between animation frames.
    private func captureBackdrop(for window: NSWindow) -> CGImage? {
        guard let contentView = window.contentView else { return nil }
        contentView.layoutSubtreeIfNeeded()

        let bounds = contentView.bounds
        guard let image = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        image.size = bounds.size
        contentView.cacheDisplay(in: bounds, to: image)

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: image) {
            NSGraphicsContext.current = context
            context.cgContext.saveGState()
            context.cgContext.setBlendMode(.destinationOver)
            context.cgContext.setFillColor(window.backgroundColor.cgColor)
            context.cgContext.fill(bounds)
            context.cgContext.restoreGState()
            (window.contentViewController as? ShowcaseViewController)?
                .clearAnimatedPreview(in: context.cgContext, relativeTo: contentView)
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()
        return image.cgImage
    }

    /// Copies the settled AppKit backdrop and the in-flight presentation layer
    /// on the main thread, then performs the comparatively expensive PNG
    /// compression and file I/O on a serial utility queue. Serial writes
    /// preserve frame order and keep animation sampling from stalling behind
    /// the previous PNG.
    private func capture(window: NSWindow,
                         backdrop: CGImage,
                         to fileURL: URL,
                         quitsAfterWriting: Bool) {
        guard let contentView = window.contentView else { return }
        let bounds = contentView.bounds
        guard let image = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        image.size = bounds.size

        NSGraphicsContext.saveGraphicsState()
        if let context = NSGraphicsContext(bitmapImageRep: image) {
            NSGraphicsContext.current = context
            let backdropImage = NSImage(cgImage: backdrop, size: bounds.size)
            backdropImage.draw(in: bounds,
                               from: NSRect(origin: .zero, size: bounds.size),
                               operation: .copy,
                               fraction: 1)
            (window.contentViewController as? ShowcaseViewController)?
                .drawAnimatedPreview(in: context.cgContext, relativeTo: contentView)
            context.flushGraphics()
        }
        NSGraphicsContext.restoreGraphicsState()

        captureWriter.async {
            if let data = image.representation(using: .png, properties: [:]) {
                try? data.write(to: fileURL, options: .atomic)
            }
            if quitsAfterWriting {
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About LabelMorph Showcase",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit LabelMorph Showcase",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}

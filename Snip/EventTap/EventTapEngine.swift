// ABOUTME: Owns the global CGEventTap that detects the user's trigger (held key, held mouse button, or
// ABOUTME: double-click-and-hold) and streams the drag. Consumes the triggering events; runs off-main.
import AppKit
import SnipKit

final class EventTapEngine {
    /// Stamped onto events we synthesize (paste, arrows) so our own tap passes them through.
    static let magicUserData: Int64 = 0x534E4950   // "SNIP"

    private let config: TriggerConfig
    private let permissions: PermissionsCoordinator
    private let onBloom: (CGPoint) -> Void
    private let onPointer: (RadialSelection) -> Void
    private let onCommit: (RadialSelection) -> Void
    private let onCancel: () -> Void

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?

    /// The dead zone matches the ring's see-through hub, so the visible hole IS the cancel target.
    private let session = RadialSession(wedgeCount: 8, deadZoneRadius: 35, hysteresisDegrees: 6)
    /// Which input currently has the ring open, so mouse and key handling never interfere: a held
    /// mouse button streams `.otherMouseDragged`; a held key streams `.mouseMoved`.
    private enum OpenTrigger { case mouse, key }
    private var openTrigger: OpenTrigger?
    private var isOpen: Bool { openTrigger != nil }
    private var anchor = CGPoint.zero
    private var selection: RadialSelection = .none
    /// If the tap dies mid-hold we never see mouseUp, and the ring would hang on screen forever.
    private var watchdog: DispatchWorkItem?

    // Frontmost-app tracking for the per-app ignore list. NSWorkspace is main-thread AppKit, so the
    // frontmost id is cached on main and read (locked) from the tap thread on the hot path.
    private let ignoreLock = NSLock()
    private var ignoredBundleIDs: Set<String>
    private var frontmostBundleID: String?
    private var workspaceObserver: NSObjectProtocol?

    init(config: TriggerConfig,
         permissions: PermissionsCoordinator,
         ignoredBundleIDs: Set<String>,
         onBloom: @escaping (CGPoint) -> Void,
         onPointer: @escaping (RadialSelection) -> Void,
         onCommit: @escaping (RadialSelection) -> Void,
         onCancel: @escaping () -> Void) {
        self.config = config
        self.permissions = permissions
        self.ignoredBundleIDs = ignoredBundleIDs
        self.onBloom = onBloom
        self.onPointer = onPointer
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    /// Returns false when Accessibility trust is missing: tapCreate is the reliable signal,
    /// because CGEvent.post silently no-ops instead of failing.
    @discardableResult
    func start() -> Bool {
        guard permissions.isTrusted else { return false }

        observeFrontmost()

        let mask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.mouseMoved.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<EventTapEngine>.fromOpaque(refcon).takeUnretainedValue()
            return engine.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        runLoopSource = source

        // A tap on the main run loop dies of kCGEventTapDisabledByTimeout the first time the
        // main thread hitches, and we animate on main. Give it a thread of its own.
        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource, let tap = self.tap else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "ai.symbiotica.Snip.eventtap"
        thread.start()
        return true
    }

    /// Pauses/resumes the tap without tearing it down. Settings pauses it while recording a new
    /// binding, so the pressed key/button reaches the recorder instead of being consumed as a trigger.
    func setPaused(_ paused: Bool) {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: !paused)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapRunLoop { CFRunLoopStop(tapRunLoop) }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        tap = nil
        runLoopSource = nil
        tapRunLoop = nil
        workspaceObserver = nil
    }

    // MARK: - Per-app ignore list

    private func observeFrontmost() {
        updateFrontmost(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.updateFrontmost(app?.bundleIdentifier)
        }
    }

    private func updateFrontmost(_ bundleID: String?) {
        ignoreLock.lock(); frontmostBundleID = bundleID; ignoreLock.unlock()
    }

    private var frontmostIsIgnored: Bool {
        ignoreLock.lock(); defer { ignoreLock.unlock() }
        guard let id = frontmostBundleID else { return false }
        return ignoredBundleIDs.contains(id)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // The system hands these back as event types; re-enable and resync rather than die.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if isOpen { closeAndCancel() }
            return Unmanaged.passUnretained(event)
        }

        // Never react to events we posted ourselves, or we build a feedback loop.
        if event.getIntegerValueField(.eventSourceUserData) == Self.magicUserData {
            return Unmanaged.passUnretained(event)
        }

        let binding = config.binding

        switch type {
        // A bound mouse button opens the ring. A double-click binding waits for the 2nd press
        // (clickState >= 2), so the first single click still reaches the app underneath.
        case .otherMouseDown where openTrigger == nil
            && binding.mouseDownOpens(button: event.getIntegerValueField(.mouseEventButtonNumber),
                                      clickState: event.getIntegerValueField(.mouseEventClickState)):
            // Let the button through in ignored apps (e.g. Blender orbit, browser new-tab).
            if frontmostIsIgnored { return Unmanaged.passUnretained(event) }
            beginSession(at: event.location, trigger: .mouse)
            return nil   // consume: the app underneath never sees the opening press

        case .otherMouseDragged where openTrigger == .mouse
            && binding.isMouseButton(event.getIntegerValueField(.mouseEventButtonNumber)):
            updateSelection(at: event.location)
            return nil

        case .otherMouseUp where openTrigger == .mouse
            && binding.isMouseButton(event.getIntegerValueField(.mouseEventButtonNumber)):
            commit()
            return nil

        case .keyDown where openTrigger == nil
            && binding.keyOpens(code: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags)
            && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 && !frontmostIsIgnored:
            beginSession(at: event.location, trigger: .key)
            return nil   // consume so the key doesn't type

        case .keyDown where openTrigger == .key
            && binding.isKeyCode(event.getIntegerValueField(.keyboardEventKeycode)):
            return nil   // swallow autorepeats of the held key, even if the modifier was let go first

        case .keyUp where openTrigger == .key
            && binding.isKeyCode(event.getIntegerValueField(.keyboardEventKeycode)):
            commit()
            return nil

        case .mouseMoved where openTrigger == .key:
            updateSelection(at: event.location)
            return Unmanaged.passUnretained(event)   // never consume: swallowing this freezes the cursor

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Anchors a new drag session under the cursor and blooms the ring.
    private func beginSession(at location: CGPoint, trigger: OpenTrigger) {
        anchor = location
        selection = .none
        openTrigger = trigger
        armWatchdog()
        DispatchQueue.main.async { self.onBloom(self.anchor) }
    }

    /// Ends the open session and inserts the wedge under the cursor at release.
    private func commit() {
        let committed = selection
        openTrigger = nil
        watchdog?.cancel()
        DispatchQueue.main.async { self.onCommit(committed) }
    }

    private func updateSelection(at point: CGPoint) {
        let dx = Double(point.x - anchor.x)
        let dy = Double(point.y - anchor.y)   // Quartz: downward is positive
        let next = session.selection(dx: dx, dy: dy, previous: selection)
        guard next != selection else { return }
        selection = next
        DispatchQueue.main.async { self.onPointer(next) }
    }

    /// Ground truth beats our own bookkeeping: if the trigger is genuinely still held, keep waiting.
    private func armWatchdog() {
        watchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let stillHeld: Bool
            switch self.openTrigger {
            case .key:
                if let code = self.config.binding.keyCode {
                    stillHeld = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
                } else { stillHeld = false }
            case .mouse:
                if let button = self.config.binding.mouseButtonNumber,
                   let cgButton = CGMouseButton(rawValue: UInt32(button)) {
                    stillHeld = CGEventSource.buttonState(.combinedSessionState, button: cgButton)
                } else {
                    // Thumb buttons (> 2) have no CGMouseButton case to poll; fall back to closing.
                    stillHeld = false
                }
            case nil:
                return
            }
            guard !stillHeld else { self.armWatchdog(); return }
            self.closeAndCancel()
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: item)
    }

    private func closeAndCancel() {
        openTrigger = nil
        watchdog?.cancel()
        DispatchQueue.main.async { self.onCancel() }
    }
}

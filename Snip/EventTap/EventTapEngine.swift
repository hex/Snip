// ABOUTME: Owns the global CGEventTap that detects the trigger armed for the app in front (held key,
// ABOUTME: held mouse button, or double-click-and-hold) and streams the drag. Runs off-main.
import AppKit
import SnipKit

final class EventTapEngine {
    /// Stamped onto events we synthesize (paste, arrows) so our own tap passes them through.
    static let magicUserData: Int64 = 0x534E4950   // "SNIP"

    private let routing: TriggerRouting
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
    /// The binding that opened the ring, captured at open so drag/commit tracking and the watchdog
    /// stay on it even if the frontmost app (and with it the armed binding) changes mid-hold.
    private var heldBinding: TriggerBinding?
    private var anchor = CGPoint.zero
    private var selection: RadialSelection = .none
    /// If the tap dies mid-hold we never see mouseUp, and the ring would hang on screen forever.
    private var watchdog: DispatchWorkItem?

    // Frontmost-app tracking for the per-app rules. NSWorkspace is main-thread AppKit, so the
    // frontmost id is cached on main and read (locked) from the tap thread on the hot path.
    private let frontmostLock = NSLock()
    private var frontmostBundleID: String?
    private var workspaceObserver: NSObjectProtocol?

    init(routing: TriggerRouting,
         permissions: PermissionsCoordinator,
         onBloom: @escaping (CGPoint) -> Void,
         onPointer: @escaping (RadialSelection) -> Void,
         onCommit: @escaping (RadialSelection) -> Void,
         onCancel: @escaping () -> Void) {
        self.routing = routing
        self.permissions = permissions
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

    // MARK: - Frontmost-app routing

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
        frontmostLock.lock(); frontmostBundleID = bundleID; frontmostLock.unlock()
    }

    /// The binding armed for the app in front; nil where a rule suppresses the ring, so every
    /// trigger event passes through (e.g. Blender orbit, browser new-tab).
    private var armedBinding: TriggerBinding? {
        frontmostLock.lock(); defer { frontmostLock.unlock() }
        return routing.config(for: frontmostBundleID)?.binding
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

        // Opening matches the binding armed for the app in front; a ring already open tracks the
        // binding that opened it.
        let armed = armedBinding

        switch type {
        // A bound mouse button opens the ring. A double-click binding waits for the 2nd press
        // (clickState >= 2), so the first single click still reaches the app underneath.
        case .otherMouseDown where openTrigger == nil
            && armed?.mouseDownOpens(button: event.getIntegerValueField(.mouseEventButtonNumber),
                                     clickState: event.getIntegerValueField(.mouseEventClickState)) == true:
            guard let armed else { return Unmanaged.passUnretained(event) }
            beginSession(at: event.location, trigger: .mouse, binding: armed)
            return nil   // consume: the app underneath never sees the opening press

        case .otherMouseDragged where openTrigger == .mouse
            && heldBinding?.isMouseButton(event.getIntegerValueField(.mouseEventButtonNumber)) == true:
            updateSelection(at: event.location)
            return nil

        case .otherMouseUp where openTrigger == .mouse
            && heldBinding?.isMouseButton(event.getIntegerValueField(.mouseEventButtonNumber)) == true:
            commit()
            return nil

        case .keyDown where openTrigger == nil
            && armed?.keyOpens(code: event.getIntegerValueField(.keyboardEventKeycode), flags: event.flags) == true
            && event.getIntegerValueField(.keyboardEventAutorepeat) == 0:
            guard let armed else { return Unmanaged.passUnretained(event) }
            beginSession(at: event.location, trigger: .key, binding: armed)
            return nil   // consume so the key doesn't type

        case .keyDown where openTrigger == .key
            && heldBinding?.isKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == true:
            return nil   // swallow autorepeats of the held key, even if the modifier was let go first

        case .keyUp where openTrigger == .key
            && heldBinding?.isKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == true:
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
    private func beginSession(at location: CGPoint, trigger: OpenTrigger, binding: TriggerBinding) {
        anchor = location
        selection = .none
        openTrigger = trigger
        heldBinding = binding
        armWatchdog(for: binding)
        DispatchQueue.main.async { self.onBloom(self.anchor) }
    }

    /// Ends the open session and inserts the wedge under the cursor at release.
    private func commit() {
        let committed = selection
        openTrigger = nil
        heldBinding = nil
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
    /// The binding rides into the work item as a captured value: it is constant for the session, and
    /// the item runs on main while the tap thread owns the stored session state.
    private func armWatchdog(for binding: TriggerBinding) {
        watchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.openTrigger != nil else { return }
            let stillHeld: Bool
            if let code = binding.keyCode {
                stillHeld = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code))
            } else if let button = binding.mouseButtonNumber,
                      let cgButton = CGMouseButton(rawValue: UInt32(button)) {
                stillHeld = CGEventSource.buttonState(.combinedSessionState, button: cgButton)
            } else {
                // Thumb buttons (> 2) have no CGMouseButton case to poll; fall back to closing.
                stillHeld = false
            }
            guard !stillHeld else { self.armWatchdog(for: binding); return }
            self.closeAndCancel()
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: item)
    }

    private func closeAndCancel() {
        openTrigger = nil
        heldBinding = nil
        watchdog?.cancel()
        DispatchQueue.main.async { self.onCancel() }
    }
}

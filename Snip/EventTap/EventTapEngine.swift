// ABOUTME: Owns the global CGEventTap that detects a middle-mouse hold or a keyboard chord hold and streams the drag.
// ABOUTME: Consumes the triggering events so the app underneath never sees them; runs off-main.
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
    /// Which trigger currently has the ring open, so mouse and hotkey handling never interfere.
    private enum OpenTrigger { case mouse, hotkey }
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

        // "otherMouse" covers buttons 2...31; thumb buttons are 3/4 and must pass through.
        let isMiddleButton = event.getIntegerValueField(.mouseEventButtonNumber) == 2

        switch type {
        case .otherMouseDown where config.middleMouseEnabled && openTrigger == nil && isMiddleButton:
            // Let the middle button through in ignored apps (e.g. Blender orbit, browser new-tab).
            if frontmostIsIgnored { return Unmanaged.passUnretained(event) }
            anchor = event.location
            selection = .none
            openTrigger = .mouse
            armWatchdog()
            DispatchQueue.main.async { self.onBloom(self.anchor) }
            return nil   // consume: the app underneath never sees the middle click

        case .otherMouseDragged where openTrigger == .mouse && isMiddleButton:
            updateSelection(at: event.location)
            return nil

        case .otherMouseUp where openTrigger == .mouse && isMiddleButton:
            let committed = selection
            openTrigger = nil
            watchdog?.cancel()
            DispatchQueue.main.async { self.onCommit(committed) }
            return nil

        case .keyDown where openTrigger == nil && isHotkey(event)
            && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 && !frontmostIsIgnored:
            anchor = event.location
            selection = .none
            openTrigger = .hotkey
            armWatchdog()
            DispatchQueue.main.async { self.onBloom(self.anchor) }
            return nil   // consume so the key doesn't type

        case .keyDown where openTrigger == .hotkey
            && event.getIntegerValueField(.keyboardEventKeycode) == Int64(config.hotkeyKeyCode):
            return nil   // swallow autorepeats of the held key, even if the modifier was let go first

        case .keyUp where openTrigger == .hotkey
            && event.getIntegerValueField(.keyboardEventKeycode) == Int64(config.hotkeyKeyCode):
            let committed = selection
            openTrigger = nil
            watchdog?.cancel()
            DispatchQueue.main.async { self.onCommit(committed) }
            return nil

        case .mouseMoved where openTrigger == .hotkey:
            updateSelection(at: event.location)
            return Unmanaged.passUnretained(event)   // never consume: swallowing this freezes the cursor

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// True when the event's keycode and the watched modifiers match the configured hotkey exactly.
    private func isHotkey(_ event: CGEvent) -> Bool {
        guard config.hotkeyEnabled else { return false }
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(config.hotkeyKeyCode) else { return false }
        let watched: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        return event.flags.intersection(watched) == config.hotkeyModifiers.intersection(watched)
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
            case .hotkey:
                stillHeld = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(self.config.hotkeyKeyCode))
            case .mouse:
                stillHeld = CGEventSource.buttonState(.combinedSessionState, button: .center)
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

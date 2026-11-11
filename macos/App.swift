import AppKit
import ApplicationServices
import Carbon

final class AppController: NSObject, NSApplicationDelegate {
  let storage: PortableStorage
  var preferences: Preferences
  var pen = false, zoom = false, passthrough = false
  /// Capturing arms the pen only inside images; the rest of the desktop stays usable.
  var capturePenOnly = false
  var drawingOnCaptures: Bool { pen && capturePenOnly && !passthrough && !toolsSuspended && !selecting && !spotEditing }
  var pointer = NSEvent.mouseLocation
  var pulses: [ClickPulse] = []
  var overlays: [(QuietPanel, OverlayView)] = []
  var undoHistory: [UndoTarget] = []
  var toolbar: QuietPanel!
  var penPanel: QuietPanel!
  var settingsPanel: QuietPanel!
  var dockView: DockView!
  var settingsView: SettingsView!
  var penView: PenView!
  var timerPanel: QuietPanel!
  var capturePanel: QuietPanel!
  var phonePanel: QuietPanel!
  var qrPanel: QuietPanel!
  var qrView: QrView!
  var qrWindow: QuietPanel!
  var qrCard: QrCardView!
  var boardWindow: BoardWindow!
  var boardView: BoardView!
  var subtitleEditor: SubtitleEditor?
  var phoneVideoPicker: PhoneVideoPicker?
  var videoLibrary: VideoLibrary?
  let panelStack = PanelStack()
  var phoneView: PhoneView!
  var phone: PhoneLink!
  /// The teacher closed the phone window; do not reopen it until the phone is unplugged.
  var phoneDismissed = false
  var phoneWasReady = false
  /// The recorder is capturing, not still starting up.
  var recordingLive = false
  /// Prevent another recording request while the start notice or permission dialog is open.
  var recordingStartPending = false
  /// The lesson app that was in front before YelPoint took the keyboard, so it gets it back.
  var focusReturn: NSRunningApplication?
  var colorPanel: QuietPanel!
  var guide: GuideWindow?
  var spotPanel: QuietPanel!
  var miniPanel: QuietPanel!
  var clockPanel: QuietPanel!
  var clockView: ClockView!
  /// Synthesised for this app, see assets/pop.wav.
  private lazy var popSound: NSSound? = Bundle.main.url(forResource: "pop", withExtension: "wav")
    .flatMap { NSSound(contentsOf: $0, byReference: true) }
  var zoomPanel: QuietPanel!
  var zoomView: ZoomView!
  private var dragGrab = CGPoint.zero
  private var dragSide = 0
  private var dragFlipX: CGFloat = 0
  private var dragVisible = CGRect.zero
  var spotView: SpotView!
  var spot: SpotRegion?
  var spotShape: SpotShape?
  var spotDrag: SpotDrag?
  var colorView: ColorWheelView!
  var inkColor: NSColor {
    preferences.inkRGB.map { NSColor(rgb: $0) } ?? Look.ink[preferences.penColor]
  }
  var timerView: TimerView!
  var captureView: CaptureView!
  var countdown = Countdown()
  var selecting = false, hideHalo = false
  var stickers: [QuietPanel] = []
  var captureGeneration = 0
  var captureInteractionVersion = 0
  var lastCapture: CGImage?
  var recorder: ScreenRecorder?
  var capture = MagnifierCapture()
  var magnifiedImage: CGImage?
  var capturedDisplay: CGDirectDisplayID?
  var timer: Timer?
  var globalMouse: Any?, localMouse: Any?, globalKeys: Any?, localKeys: Any?
  var globalScroll: Any?, localScroll: Any?
  private var scrollRemainder: CGFloat = 0
  var hotkeys: [EventHotKeyRef] = []
  var escapeKey: EventHotKeyRef?
  var eventHandler: EventHandlerRef?
  var statusItem: NSStatusItem?
  var keyText: String?, keyUntil: TimeInterval = 0
  private var previousPoint = CGPoint(x: -99999, y: -99999)
  private var previousHUD = false
  private var previousBadge: String?
  private(set) var toolsSuspended = false
  var diagnosticExitCode: Int32 = 0
  init(storage: PortableStorage) {
    self.storage = storage
    preferences = storage.load()
    appEnglish = preferences.english == true
    super.init()
  }
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    let menu = NSMenu()
    let appItem = NSMenuItem()
    menu.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    let show = NSMenuItem(title: tr("도구막대 보기", "Show Toolbar"), action: #selector(showToolbar), keyEquivalent: "")
    show.target = self
    appMenu.addItem(show)
    let exit = NSMenuItem(title: tr("YelPoint 종료", "Quit YelPoint"), action: #selector(quit), keyEquivalent: "q")
    exit.target = self
    appMenu.addItem(exit)
    // Without these, ⌘V and friends do nothing in text fields (QR address, board text, notes).
    let editItem = NSMenuItem()
    menu.addItem(editItem)
    let editMenu = NSMenu(title: tr("편집", "Edit"))
    editItem.submenu = editMenu
    for (title, action, key, shift) in [
      (tr("실행 취소", "Undo"), Selector(("undo:")), "z", false), (tr("실행 복귀", "Redo"), Selector(("redo:")), "z", true),
      (tr("오려두기", "Cut"), #selector(NSText.cut(_:)), "x", false), (tr("복사하기", "Copy"), #selector(NSText.copy(_:)), "c", false),
      (tr("붙여넣기", "Paste"), #selector(NSText.paste(_:)), "v", false), (tr("모두 선택", "Select All"), #selector(NSText.selectAll(_:)), "a", false),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      if shift { item.keyEquivalentModifierMask = [.command, .shift] }
      editMenu.addItem(item)
    }
    NSApp.mainMenu = menu
    toolbar = panel(
      size: DockView.wide,
      level: .init(rawValue: NSWindow.Level.statusBar.rawValue + 2))
    toolbar.hasShadow = true
    dockView = DockView(controller: self)
    toolbar.contentView = dockView
    penPanel = panel(size: CGSize(width: 407, height: 48), level: toolbar.level)
    penPanel.hasShadow = true
    penView = PenView(controller: self)
    penPanel.contentView = penView
    settingsPanel = panel(
      size: CGSize(width: SettingsView.width, height: SettingsView.height), level: .init(rawValue: toolbar.level.rawValue + 1))
    settingsPanel.hasShadow = true
    settingsView = SettingsView(controller: self)
    settingsPanel.contentView = settingsView
    timerPanel = panel(size: CGSize(width: 388, height: 48), level: toolbar.level, typing: true)
    timerPanel.hasShadow = true
    timerView = TimerView(controller: self)
    timerPanel.contentView = timerView
    capturePanel = panel(size: CGSize(width: 516, height: 48), level: toolbar.level)
    capturePanel.hasShadow = true
    captureView = CaptureView(controller: self)
    capturePanel.contentView = captureView
    colorPanel = panel(size: CGSize(width: 196, height: 232), level: toolbar.level)
    colorPanel.hasShadow = true
    colorView = ColorWheelView(controller: self)
    colorPanel.contentView = colorView
    spotPanel = panel(size: CGSize(width: 360, height: 48), level: toolbar.level)
    spotPanel.hasShadow = true
    spotView = SpotView(controller: self)
    spotPanel.contentView = spotView
    miniPanel = panel(size: CGSize(width: 46, height: 46), level: toolbar.level)
    miniPanel.hasShadow = true
    miniPanel.contentView = MiniView(controller: self)
    clockPanel = panel(size: CGSize(width: 196, height: 76), level: toolbar.level)
    clockPanel.hasShadow = true
    clockView = ClockView(controller: self)
    clockView.autoresizingMask = [.width, .height]
    clockPanel.contentView = clockView
    zoomPanel = panel(size: CGSize(width: 286, height: 48), level: toolbar.level)
    zoomPanel.hasShadow = true
    zoomView = ZoomView(controller: self)
    zoomPanel.contentView = zoomView
    phone = PhoneLink(storage: storage)
    phonePanel = panel(size: PhoneView.size, level: toolbar.level)
    phonePanel.hasShadow = true
    phoneView = PhoneView(controller: self)
    phonePanel.contentView = phoneView
    phone.onChange = { [weak self] in self?.phoneChanged() }
    phone.onClosed = { [weak self] early in self?.phoneClosed(early: early) }
    phone.onRecorded = { [weak self] url in self?.phoneRecorded(url) }
    qrPanel = panel(size: QrView.size, level: toolbar.level, typing: true)
    qrPanel.hasShadow = true
    qrView = QrView(controller: self)
    qrPanel.contentView = qrView
    qrWindow = panel(size: CGSize(width: 600, height: 670), level: toolbar.level)
    qrWindow.hasShadow = true
    qrCard = QrCardView(controller: self)
    qrWindow.contentView = qrCard
    boardWindow = BoardWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
    boardWindow.isOpaque = false
    boardWindow.backgroundColor = .clear
    boardWindow.hasShadow = true
    boardWindow.level = NSWindow.Level(rawValue: toolbar.level.rawValue - 1)
    boardWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    boardWindow.isReleasedWhenClosed = false
    boardView = BoardView(controller: self)
    boardView.autoresizingMask = [.width, .height]
    boardWindow.contentView = boardView
    rebuildScreens()
    NotificationCenter.default.addObserver(
      self, selector: #selector(rebuildScreens),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(toolbarMoved), name: NSWindow.didMoveNotification, object: toolbar)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(screenWillSleep), name: NSWorkspace.willSleepNotification,
      object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(screenWillSleep), name: NSWorkspace.screensDidSleepNotification,
      object: nil)
    installHotkeys()
    let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    globalMouse = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in
      self?.clicked(e)
    }
    localMouse = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
      self?.clicked(e)
      return e
    }
    globalScroll = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
      self?.scrolled(e)
    }
    localScroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
      self?.scrolled(e)
      return e
    }
    installHUDMonitor()
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 40, repeats: true) { [weak self] _ in
      self?.tick()
    }
    RunLoop.main.add(timer!, forMode: .common)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem?.button?.image = NSImage(
      systemSymbolName: "cursorarrow.rays", accessibilityDescription: "YelPoint")
    let sm = NSMenu()
    for (t, a) in [
      (tr("도구막대 보기", "Show Toolbar"), #selector(showToolbar)), (tr("사용법", "How to Use"), #selector(showHelp)), (tr("종료", "Quit"), #selector(quit)),
    ] {
      let item = NSMenuItem(title: t, action: a, keyEquivalent: "")
      item.target = self
      sm.addItem(item)
    }
    statusItem?.menu = sm
    refreshTools()
    if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.quit() }
    }
    if ProcessInfo.processInfo.arguments.contains("--capture-self-test") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.runLiveCaptureTest() }
    }
    if ProcessInfo.processInfo.arguments.contains("--ui-self-test") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.runUISelfTest() }
    }
  }
  func panel(size: CGSize, level: NSWindow.Level, typing: Bool = false) -> QuietPanel {
    let frame = CGRect(origin: .zero, size: size)
    let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    let w =
      typing
      ? TypingPanel(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
      : QuietPanel(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.level = level
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    w.hidesOnDeactivate = false
    w.isReleasedWhenClosed = false
    w.isRestorable = false
    w.animationBehavior = .none
    return w
  }
  @objc func rebuildScreens() {
    finishStrokes()
    selecting = false
    spotShape = nil
    spotDrag = nil
    let old = Dictionary(
      uniqueKeysWithValues: overlays.map { ($0.1.screen.displayID, $0.1.strokes) })
    for (w, _) in overlays {
      w.orderOut(nil)
      w.close()
    }
    overlays = []
    for s in NSScreen.screens {
      let w = panel(
        size: s.frame.size, level: .init(rawValue: NSWindow.Level.statusBar.rawValue + 1))
      w.setFrame(s.frame, display: false)
      w.ignoresMouseEvents = true
      let v = OverlayView(screen: s, controller: self)
      v.strokes = old[s.displayID] ?? []
      w.contentView = v
      if !toolsSuspended { w.orderFrontRegardless() }
      overlays.append((w, v))
    }
    capturedDisplay = nil
    if zoom { refreshCapture() }
    if toolbar != nil { placeToolbar() }
  }
  /// The way back if the toolbar is lost: unhide it at the default spot.
  @objc func showToolbar() {
    guard !toolsSuspended, toolbar != nil else { return }
    setToolbarShape(vertical: false)
    centerToolbar()
    setToolbarHidden(false)
  }
  private func centerToolbar() {
    guard
      let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
        ?? NSScreen.main
    else { return }
    let f = screen.visibleFrame
    toolbar.setFrameOrigin(CGPoint(x: f.midX - toolbar.frame.width / 2, y: f.minY + 18))
  }
  /// Restores the spot and hidden state the user left.
  func placeToolbar() {
    guard !toolsSuspended else { return }
    setToolbarShape(vertical: preferences.toolbarVertical == true)
    if let x = preferences.toolbarX, let y = preferences.toolbarY {
      toolbar.setFrameOrigin(CGPoint(x: x, y: y))
    } else {
      centerToolbar()
    }
    setToolbarHidden(preferences.toolbarHidden == true)
  }
  private func setToolbarShape(vertical: Bool) {
    preferences.toolbarVertical = vertical ? true : nil
    dockView.layoutTools(vertical: vertical)
    toolbar.setContentSize(dockView.frame.size)
  }
  func beginToolbarDrag(at p: CGPoint) {
    dragGrab = CGPoint(x: p.x - toolbar.frame.minX, y: p.y - toolbar.frame.minY)
    dragVisible = visibleFrame(around: CGRect(origin: p, size: CGSize(width: 1, height: 1)))
    dragFlipX = p.x
    dragSide = dockView.vertical ? (toolbar.frame.midX < dragVisible.midX ? -1 : 1) : 0
  }
  /// The bar stands up the moment it reaches a side edge and lies flat again once pulled inward.
  func dragToolbar(to p: CGPoint) {
    let visible = visibleFrame(around: CGRect(origin: p, size: CGSize(width: 1, height: 1)))
    if dragSide != 0 {
      if visible == dragVisible,
        !toolbarLiesFlat(side: dragSide, flipX: dragFlipX, pointerX: p.x)
      {
        pinToolbar(to: visible, pointerY: p.y)
        return
      }
      setToolbarShape(vertical: false)
      let origin = flatToolbarOrigin(pointer: p, size: toolbar.frame.size, visible: visible)
      toolbar.setFrameOrigin(origin)
      dragGrab = CGPoint(x: p.x - origin.x, y: p.y - origin.y)
      dragSide = 0
      return
    }
    toolbar.setFrameOrigin(CGPoint(x: p.x - dragGrab.x, y: p.y - dragGrab.y))
    let edge = toolbarEdge(frame: toolbar.frame, pointerX: p.x, visible: visible)
    guard edge != 0 else { return }
    setToolbarShape(vertical: true)
    dragSide = edge
    dragFlipX = p.x
    dragVisible = visible
    pinToolbar(to: visible, pointerY: p.y)
  }
  private func pinToolbar(to visible: CGRect, pointerY y: CGFloat) {
    let size = toolbar.frame.size
    let x = dragSide < 0 ? visible.minX + 8 : visible.maxX - size.width - 8
    toolbar.setFrameOrigin(
      clampedOrigin(CGPoint(x: x, y: y - size.height / 2), size: size, visible: visible))
  }
  func endToolbarDrag() {
    keepToolbarOnScreen()
    positionChildren()
  }
  func setToolbarHidden(_ hidden: Bool) {
    preferences.toolbarHidden = hidden ? true : nil
    if hidden {
      hideToolPanels()
      miniPanel.setFrameOrigin(CGPoint(x: toolbar.frame.minX, y: toolbar.frame.minY + 8))
      keepMiniOnScreen()
      toolbar.orderOut(nil)
      miniPanel.orderFrontRegardless()
    } else {
      miniPanel.orderOut(nil)
      keepToolbarOnScreen()
      toolbar.orderFrontRegardless()
      positionChildren()
    }
    refreshTools()
  }
  private func visibleFrame(around frame: CGRect) -> CGRect {
    func overlap(_ screen: NSScreen) -> CGFloat {
      let shared = screen.frame.intersection(frame)
      return shared.isNull ? 0 : shared.width * shared.height
    }
    return (NSScreen.screens.max { overlap($0) < overlap($1) } ?? NSScreen.main)?.visibleFrame
      ?? frame
  }
  func keepToolbarOnScreen() {
    let frame = toolbar.frame
    let origin = clampedOrigin(frame.origin, size: frame.size, visible: visibleFrame(around: frame))
    if origin != frame.origin { toolbar.setFrameOrigin(origin) }
  }
  func keepMiniOnScreen() {
    let frame = miniPanel.frame
    moveMini(to: clampedOrigin(frame.origin, size: frame.size, visible: visibleFrame(around: frame)))
  }
  /// The hidden toolbar follows, so tools keep choosing the display the user is on.
  func moveMini(to origin: CGPoint) {
    miniPanel.setFrameOrigin(origin)
    toolbar.setFrameOrigin(CGPoint(x: origin.x, y: origin.y - 8))
  }
  @objc func toolbarMoved() {
    preferences.toolbarX = toolbar.frame.minX
    preferences.toolbarY = toolbar.frame.minY
    positionChildren()
    if countdown.isActive { invalidateAll() }
  }
  func positionChildren() {
    guard let toolbar else { return }
    let screen = toolbar.screen ?? NSScreen.main
    let visible = screen?.visibleFrame ?? toolbar.frame.insetBy(dx: -400, dy: -400)
    let place = dockView.vertical ? clampedSideOrigin : clampedChildOrigin
    // Standing bar: every panel stands too, in a narrow column. The settings card already does.
    let columns: [(NSPanel?, String, CGFloat?)] = [
      (penPanel, "pen", 140), (settingsPanel, "settings", nil), (timerPanel, "timer", 140), (capturePanel, "capture", 116),
      (spotPanel, "spot", 102), (zoomPanel, "zoom", 128), (phonePanel, "phone", 212), (qrPanel, "qr", 232),
    ]
    for (panel, name, width) in columns {
      guard let child = panel else { continue }
      if let width, let view = child.contentView {
        panelStack.apply(view, vertical: dockView.vertical, width: width)
        if child.frame.size != view.frame.size { child.setContentSize(view.frame.size) }
      }
      let opener = dockView.buttons[name].map { toolbar.convertToScreen(dockView.convert($0.frame, to: nil)) }
      child.setFrameOrigin(place(toolbar.frame, child.frame.size, visible, opener))
    }
    if let colorPanel, let penPanel {
      colorPanel.setFrameOrigin(
        place(toolbar.frame.union(penPanel.frame), colorPanel.frame.size, visible, nil))
    }
  }
  /// Opens a panel against the toolbar with a short slide, so it clicks into place.
  func present(_ child: NSPanel) {
    guard !child.isVisible else {
      child.orderFrontRegardless()
      return
    }
    let final = child.frame.origin
    let testing = ProcessInfo.processInfo.arguments.contains("--ui-self-test")
    guard !testing, let toolbar else {
      child.orderFrontRegardless()
      return
    }
    // Starts a little inside the toolbar's side and slides out to its place.
    let toward: CGVector =
      dockView.vertical
      ? CGVector(dx: final.x > toolbar.frame.midX ? -12 : 12, dy: 0)
      : CGVector(dx: 0, dy: final.y > toolbar.frame.midY ? -12 : 12)
    child.alphaValue = 0
    child.setFrameOrigin(CGPoint(x: final.x + toward.dx, y: final.y + toward.dy))
    child.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.14
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      child.animator().setFrameOrigin(final)
      child.animator().alphaValue = 1
    }
  }
  func toggle(_ name: String) {
    guard !toolsSuspended else { return }
    captureInteractionVersion += 1
    switch name {
    case "highlight":
      preferences.highlight.toggle()
      preferencesChanged()
    case "zoom":
      if zoom {
        zoom = false
        capture.stop()
        capturedDisplay = nil
        magnifiedImage = nil
      } else {
        guard ensureScreenAccess() else { return }
        finishStrokes()
        pen = false
        zoom = true
        hideToolPanels()
        refreshCapture()
      }
    case "pen":
      finishStrokes()
      pen.toggle()
      capturePenOnly = false
      if pen {
        zoom = false
        capture.stop()
        capturedDisplay = nil
        magnifiedImage = nil
      }
      hideToolPanels()
    case "settings":
      if settingsPanel.isVisible {
        settingsPanel.orderOut(nil)
      } else {
        finishStrokes()
        pen = false
        hideToolPanels()
        settingsView.refresh()
        present(settingsPanel)
      }
    case "timer":
      if timerPanel.isVisible {
        timerPanel.orderOut(nil)
      } else {
        finishStrokes()
        pen = false
        hideToolPanels()
        timerView.refresh()
        present(timerPanel)
      }
    case "spot":
      if spotPanel.isVisible {
        spotShape = nil
        spotPanel.orderOut(nil)
      } else {
        finishStrokes()
        pen = false
        hideToolPanels()
        present(spotPanel)
      }
    case "hide":
      setToolbarHidden(preferences.toolbarHidden != true)
    case "board":
      if boardWindow.isVisible { closeBoard() } else { openBoard() }
      return
    case "qr":
      if qrPanel.isVisible || qrWindow.isVisible {
        closeQr()
      } else {
        finishStrokes()
        pen = false
        hideToolPanels()
        qrView.field.stringValue = preferences.qrText ?? ""
        present(qrPanel)
        qrPanel.makeKey()
        qrPanel.makeFirstResponder(qrView.field)
        qrView.field.currentEditor()?.selectAll(nil)
      }
    case "phone":
      if phonePanel.isVisible {
        phonePanel.orderOut(nil)
      } else {
        finishStrokes()
        pen = false
        hideToolPanels()
        phoneView.refresh()
        present(phonePanel)
      }
    case "capture":
      // Make photo and video capture equally discoverable. ⌃⌥5 remains the quick photo path.
      if capturePanel.isVisible {
        capturePanel.orderOut(nil)
      } else {
        finishStrokes()
        pen = false
        zoom = false
        capture.stop()
        capturedDisplay = nil
        magnifiedImage = nil
        hideToolPanels()
        captureView.refresh()
        present(capturePanel)
      }
    default: break
    }
    refreshTools()
    invalidateAll()
  }
  func toggleColorPanel() {
    if colorPanel.isVisible {
      colorPanel.orderOut(nil)
    } else {
      colorView.sync()
      positionChildren()
      colorPanel.orderFrontRegardless()
    }
  }
  /// Scrolling resizes only with Control held or over the highlight button.
  func scrolled(_ event: NSEvent) {
    guard !toolsSuspended else { return }
    let p = NSEvent.mouseLocation
    let button = dockView.buttons["highlight"]?.frame ?? .zero
    let overButton =
      toolbar.isVisible
      && button.offsetBy(dx: toolbar.frame.minX, dy: toolbar.frame.minY).contains(p)
    guard overButton || event.modifierFlags.contains(.control) else {
      scrollRemainder = 0
      return
    }
    let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
    scrollRemainder += delta / (event.hasPreciseScrollingDeltas ? 12 : 1)
    let steps = Int(scrollRemainder)
    guard steps != 0 else { return }
    scrollRemainder -= CGFloat(steps)
    resizeFocus(steps: steps)
  }
  /// The largest thing on screen wins: shape spot, then the dimming circle, then the pointer.
  func resizeFocus(steps: Int) {
    if var region = spot {
      region.rect = spotScaled(region.rect, steps: steps)
      spot = region
    } else if preferences.spotlight {
      preferences.resizeDimming(steps: steps)
    } else {
      preferences.resizePointer(steps: steps)
    }
    invalidateAll()
  }
  func togglePenOptions() {
    guard !toolsSuspended else { return }
    if penPanel.isVisible {
      penPanel.orderOut(nil)
      colorPanel.orderOut(nil)
    } else {
      if !pen { toggle("pen") }
      present(penPanel)
    }
  }
  func hideToolPanels() {
    if selecting { NSCursor.arrow.set() }
    selecting = false
    spotShape = nil
    spotDrag = nil
    for (_, view) in overlays { view.selection = nil }
    for window in [penPanel, colorPanel, settingsPanel, timerPanel, capturePanel, spotPanel, phonePanel, qrPanel] { window?.orderOut(nil) }
  }
  func setZoom(_ level: CGFloat) {
    preferences.zoom = level
    preferencesChanged()
  }
  /// Every view takes its text at launch, so a language change restarts the app.
  func setLanguage(english: Bool) {
    guard english != appEnglish else { return }
    preferences.english = english ? true : nil
    preferencesChanged()
    relaunch()
  }
  func setTimer(minutes: Int) {
    countdown.set(minutes: minutes)
    timerChanged()
  }
  func timerStartPause() {
    countdown.startOrPause(now: Date().timeIntervalSinceReferenceDate)
    timerChanged()
  }
  func timerReset() {
    countdown.reset()
    timerChanged()
  }
  func updateClock(now: TimeInterval = Date().timeIntervalSinceReferenceDate) {
    guard let badge = countdown.badge(now: now) else {
      clockPanel.orderOut(nil)
      return
    }
    clockView.text = badge.text
    clockView.alert = badge.alert
    clockView.pop = countdown.popProgress(now: now)
    if !clockPanel.isVisible && !toolsSuspended {
      placeClock()
      clockPanel.orderFrontRegardless()
    }
    clockView.needsDisplay = true
  }
  /// Where the user left it, or the top-right corner of the toolbar's display.
  private func placeClock() {
    let scale = preferences.clockScale ?? 1
    let size = CGSize(width: 196 * scale, height: 76 * scale)
    let visible = (toolbar.screen ?? NSScreen.main)?.visibleFrame ?? .zero
    let origin =
      preferences.clockX.flatMap { x in preferences.clockY.map { CGPoint(x: x, y: $0) } }
      ?? CGPoint(x: visible.maxX - size.width - 24, y: visible.maxY - size.height - 16)
    let frame = CGRect(origin: origin, size: size)
    clockPanel.setFrame(
      CGRect(
        origin: clampedOrigin(origin, size: size, visible: visibleFrame(around: frame)), size: size),
      display: false)
  }
  func clockMoved() {
    let frame = clockPanel.frame
    clockPanel.setFrameOrigin(
      clampedOrigin(frame.origin, size: frame.size, visible: visibleFrame(around: frame)))
    preferences.clockX = clockPanel.frame.minX
    preferences.clockY = clockPanel.frame.minY
    preferences.clockScale = clockPanel.frame.width / 196
    preferencesChanged()
  }
  func timerChanged() {
    updateClock()
    timerView.refresh()
    dockView.refresh()
    invalidateAll()
  }
  func refreshTools() {
    guard dockView != nil else { return }
    dockView.refresh()
    penView.refresh()
    captureView.refresh()
    spotView.refresh()
    phoneView.refresh()
    phone.watch(phonePanel.isVisible || preferences.phoneAuto == true)
    if !pen || toolsSuspended || preferences.toolbarHidden == true {
      penPanel.orderOut(nil)
      if !toolsSuspended { colorPanel.orderOut(nil) }
    }
    if zoom && !toolsSuspended && preferences.toolbarHidden != true {
      zoomView.refresh()
      present(zoomPanel)
    } else {
      zoomPanel.orderOut(nil)
    }
    updateEscape()
    updatePassthrough()
  }
  func updatePassthrough() {
    setPassthrough(NSEvent.modifierFlags.contains(.option))
  }
  func setPassthrough(_ value: Bool) {
    let entering = value && !passthrough
    passthrough = value
    if entering {
      finishStrokes(notify: false)
    }
    for (w, v) in overlays {
      let ignores = toolsSuspended || !(selecting || spotEditing || (pen && !capturePenOnly && !passthrough))
      if w.ignoresMouseEvents != ignores {
        w.ignoresMouseEvents = ignores
        w.invalidateCursorRects(for: v)
        v.needsDisplay = true
      }
    }
    for case let view as StickerView in stickers.map({ $0.contentView }) { view.updateDrawingInput() }
  }
  func finishStrokes(notify: Bool = true) {
    for (_, v) in overlays { v.finishStroke(notify: notify) }
    for case let view as StickerView in stickers.map({ $0.contentView }) {
      view.finishStroke(notify: notify)
    }
  }
  func preferencesChanged() {
    preferences.validate()
    do { try storage.save(preferences) } catch {
      showMessage(tr("설정 저장 실패", "Could not save settings"), tr("저장 공간이 남아 있는지 확인해 주세요.\n", "Check the drive connection and free space.\n") + error.localizedDescription)
    }
    refreshTools()
    invalidateAll()
  }
  func changeSetting(_ i: Int) {
    if i == 0 {
      if !preferences.keyboardHUD && !AXIsProcessTrusted() {
        withToolsSuspended {
          _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
          presentAlert(
            tr("단축키 표시", "Show shortcut keys"),
            tr("시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 YelPoint를 허용한 뒤 이 옵션을 다시 켜 주세요. 일반 글자는 표시하지 않고 ⌘C 같은 키 조합만 잠깐 보여 드려요.", "Allow YelPoint in System Settings → Privacy & Security → Accessibility, then turn this on again. Only combinations like ⌘C are shown, never ordinary typing.")
          )
        }
      } else {
        preferences.keyboardHUD.toggle()
        installHUDMonitor()
      }
    } else if i == 1 {
      preferences.fadingInk.toggle()
    } else {
      preferences.spotlight.toggle()
    }
    settingsView.refresh()
    preferencesChanged()
  }
  func clicked(_ event: NSEvent) {
    // Dismiss transient options without consuming the click intended for the other app.
    let clickPoint = NSEvent.mouseLocation
    if !toolsSuspended && ![toolbar, penPanel, colorPanel, capturePanel].contains(where: {
      $0?.isVisible == true && $0!.frame.contains(clickPoint)
    }) {
      penPanel.orderOut(nil)
      colorPanel.orderOut(nil)
      capturePanel.orderOut(nil)
    }
    guard !toolsSuspended, preferences.highlight, !pen, !selecting, !spotEditing else { return }
    let p = NSEvent.mouseLocation
    if [toolbar, penPanel, settingsPanel, timerPanel, capturePanel, colorPanel, spotPanel, miniPanel, zoomPanel, clockPanel, phonePanel, qrPanel, qrWindow]
      .contains(where: {
      $0?.isVisible == true && $0!.frame.contains(p)
    }) {
      return
    }
    pulses.append(
      ClickPulse(
        point: p, created: ProcessInfo.processInfo.systemUptime,
        right: event.type == .rightMouseDown))
    if pulses.count > 20 { pulses.removeFirst() }
    invalidateAll()
  }
  func tick() {
    guard !toolsSuspended else { return }
    let now = ProcessInfo.processInfo.systemUptime
    pointer = NSEvent.mouseLocation
    updatePassthrough()
    // Other apps reset the cursor as it passes over them, so keep claiming it.
    if selecting { captureCursor.set() }
    let clock = Date().timeIntervalSinceReferenceDate
    let wasActive = countdown.isActive
    let wasLocked = countdown.isLocked
    if countdown.update(now: clock) { popSound?.play() }
    if wasActive != countdown.isActive || wasLocked != countdown.isLocked {
      timerView.refresh()
      dockView.refresh()
    }
    let badge = countdown.badge(now: clock).map { "\($0.text)|\($0.alert)" }
    if badge != previousBadge || countdown.popProgress(now: clock) != nil {
      updateClock(now: clock)
      previousBadge = badge
    }
    let moved = pointer != previousPoint
    let animated = !pulses.isEmpty
    pulses.removeAll { $0.progress(at: now) >= 1 }
    let hud = keyText != nil && now < keyUntil
    for (_, v) in overlays {
      let oldCount = v.strokes.count
      v.strokes.removeAll { $0.alpha(at: now) <= 0 }
      let fading = v.strokes.contains { $0.expires && now >= $0.created + 3.4 }
      if moved && preferences.spotlight || animated || fading
        || oldCount != v.strokes.count || hud != previousHUD
      {
        v.needsDisplay = true
      } else if moved && preferences.highlight {
        let a = v.local(previousPoint)
        let b = v.local(pointer)
        let r = preferences.pointerRadius + 7
        v.setNeedsDisplay(CGRect(x: a.x - r, y: a.y - r, width: r * 2, height: r * 2))
        v.setNeedsDisplay(CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2))
      }
      if moved && zoom {
        for p in [previousPoint, pointer] where v.screen.frame.contains(p) {
          let r = clampedLens(center: p, screen: v.screen.frame)
            .offsetBy(dx: -v.screen.frame.minX, dy: -v.screen.frame.minY)
          v.setNeedsDisplay(r.insetBy(dx: -22, dy: -22))
        }
      }
    }
    if zoom {
      capture.update(pointer: pointer, zoom: preferences.zoom)
      refreshCapture()
    }
    previousPoint = pointer
    previousHUD = hud
  }
  func refreshCapture() {
    guard !toolsSuspended else { return }
    guard zoom, let s = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) else {
      return
    }
    guard capturedDisplay != s.displayID else { return }
    capturedDisplay = s.displayID
    magnifiedImage = nil
    capture.update(pointer: pointer, zoom: preferences.zoom)
    capture.start(
      screen: s,
      onFrame: { [weak self] image in
        guard let self, !self.toolsSuspended, self.zoom else { return }
        self.magnifiedImage = image
        for (_, view) in self.overlays where view.screen.frame.contains(self.pointer) {
          let r = clampedLens(center: self.pointer, screen: view.screen.frame)
            .offsetBy(dx: -view.screen.frame.minX, dy: -view.screen.frame.minY)
          view.setNeedsDisplay(r.insetBy(dx: -22, dy: -22))
        }
      },
      onError: { [weak self] message in
        guard let self else { return }
        self.zoom = false
        self.capture.stop()
        self.capturedDisplay = nil
        self.magnifiedImage = nil
        self.refreshTools()
        self.invalidateAll()
        self.showMessage(tr("돋보기를 켜지 못했어요", "Could not start the magnifier"), message)
      })
  }
  func invalidateAll() { for (_, v) in overlays { v.needsDisplay = true } }
  func undo() {
    undoing: while let target = undoHistory.popLast() {
      switch target {
      case .display(let id):
        if let v = overlays.first(where: { $0.1.screen.displayID == id })?.1, !v.strokes.isEmpty {
          v.strokes.removeLast()
          v.needsDisplay = true
          break undoing
        }
      case .sticker(let view):
        if view.window != nil, view.undoLast() {
          clip(view)
          break undoing
        }
      case .cleared(let saved):
        for (id, strokes) in saved.displays {
          if let v = overlays.first(where: { $0.1.screen.displayID == id })?.1 {
            v.strokes = strokes + v.strokes
            v.needsDisplay = true
          }
        }
        for (view, ink) in saved.stickers where view.window != nil { view.ink = ink }
        undoHistory = saved.history
        toast(tr("지운 필기를 되살렸어요", "Ink restored"))
        break undoing
      }
    }
    refreshTools()
  }
  /// Undo brings everything back, so one stray click on the trash button costs nothing.
  func clear() {
    finishStrokes()
    let saved = ClearedInk(
      displays: overlays.compactMap { $0.1.strokes.isEmpty ? nil : ($0.1.screen.displayID, $0.1.strokes) },
      stickers: stickers.compactMap { ($0.contentView as? StickerView).flatMap { $0.hasInk ? ($0, $0.ink) : nil } },
      history: undoHistory)
    for (_, v) in overlays {
      v.strokes = []
      v.activeStroke = nil
      v.needsDisplay = true
    }
    for case let view as StickerView in stickers.map({ $0.contentView }) { view.clearInk() }
    undoHistory = saved.displays.isEmpty && saved.stickers.isEmpty ? [] : [.cleared(saved)]
    if !undoHistory.isEmpty { toast(tr("모두 지웠어요 · 되돌리기로 되살릴 수 있어요", "Cleared · Undo brings it back")) }
    refreshTools()
  }
  func installHUDMonitor() {
    if let globalKeys { NSEvent.removeMonitor(globalKeys) }
    globalKeys = nil
    if let localKeys { NSEvent.removeMonitor(localKeys) }
    localKeys = nil
    guard preferences.keyboardHUD, AXIsProcessTrusted() else {
      keyText = nil
      keyUntil = 0
      invalidateAll()
      return
    }
    globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
      self?.showKey(e)
    }
    localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
      self?.showKey(e)
      return e
    }
  }
  func showKey(_ e: NSEvent) {
    guard !toolsSuspended, preferences.keyboardHUD else { return }
    let flags = e.modifierFlags.intersection([.control, .option, .command, .shift])
    guard !flags.intersection([.control, .option, .command]).isEmpty, !e.isARepeat else { return }
    guard let text = e.charactersIgnoringModifiers?.uppercased(), text.count == 1,
      let scalar = text.unicodeScalars.first, scalar.value >= 32, scalar.value < 0xF700
    else { return }
    keyText =
      (flags.contains(.control) ? "⌃ " : "") + (flags.contains(.option) ? "⌥ " : "")
      + (flags.contains(.shift) ? "⇧ " : "") + (flags.contains(.command) ? "⌘ " : "") + text
    keyUntil = ProcessInfo.processInfo.systemUptime + 1.5
    invalidateAll()
  }
  func installHotkeys() {
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var key = EventHotKeyID()
        let status = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &key)
        if status != noErr { return status }
        let c = Unmanaged<AppController>.fromOpaque(userData).takeUnretainedValue()
        guard !c.toolsSuspended else { return OSStatus(eventNotHandledErr) }
        if key.id == 99 {
          c.returnToPointer()
        } else if key.id == 5 {
          if c.selecting { c.returnToPointer() } else { c.beginSelection() }
        } else if key.id >= 1 && key.id <= 7 {
          c.toggle(["highlight", "zoom", "pen", "timer", "capture", "spot", "hide"][Int(key.id) - 1])
        }
        return noErr
      }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    for (index, code) in [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_0]
      .enumerated()
    {
      var ref: EventHotKeyRef?
      let id = EventHotKeyID(signature: 0x5350_4F54, id: UInt32(index + 1))
      if RegisterEventHotKey(
        UInt32(code), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &ref)
        == noErr, let ref
      {
        hotkeys.append(ref)
      } else {
        settingsView.message.stringValue = tr("단축키 일부가 다른 앱과 겹쳐요.\n도구막대 버튼으로 사용할 수 있어요.", "Some shortcuts clash with another app.\nYou can use the toolbar buttons instead.")
      }
    }
  }
  func updateEscape() {
    if !toolsSuspended
      // Only while a mode holds the mouse; an open panel must not take Esc from slideshows or videos.
      && ((pen && !capturePenOnly) || zoom || selecting || spotEditing || qrWindow.isVisible)
    {
      if escapeKey == nil {
        RegisterEventHotKey(
          UInt32(kVK_Escape), 0, EventHotKeyID(signature: 0x5350_4F54, id: 99),
          GetApplicationEventTarget(), 0, &escapeKey)
      }
    } else if let escapeKey {
      UnregisterEventHotKey(escapeKey)
      self.escapeKey = nil
    }
  }
  func returnToPointer() {
    captureInteractionVersion += 1
    hideHalo = false
    finishStrokes()
    pen = false
    zoom = false
    capture.stop()
    capturedDisplay = nil
    magnifiedImage = nil
    hideToolPanels()
    qrWindow.orderOut(nil)
    refreshTools()
    invalidateAll()
  }
  @objc func screenWillSleep() {
    finishStrokes()
    stopRecording()
    zoom = false
    pen = false
    capture.stop()
    capturedDisplay = nil
    magnifiedImage = nil
    refreshTools()
    invalidateAll()
  }
  @objc func showHelp() {
    if guide == nil {
      guide = GuideWindow(level: .init(rawValue: toolbar.level.rawValue + 2))
    }
    if let guide {
      takeFocus()
      guide.onClose = { [weak self] in DispatchQueue.main.async { self?.giveFocusBack() } }
      guide.show()
      return
    }
    showMessage(
      tr("YelPoint 사용법", "How to Use YelPoint"),
      tr("강조: 커서 주변 링과 좌우 클릭 표시\nControl+스크롤: 위로 크게, 아래로 작게 (스팟 → 주변 어둡게 원 → 포인터 순서)\n돋보기: 커서 부근 실시간 확대, 1.5~5배 선택\n펜: 색 3개와 색상환 · 굵기 슬라이더(1~30) · 되돌리기 · 지우기\n타이머: 1~60분 카운트다운. 분 직접 입력, 시계는 끌어서 이동하고 모서리로 크기 조절\n캡처: 영역을 고르면 편집창에서 바로 필기·복사·저장. 옆 ▾에서 저장·그림 붙이기·화면 녹화\n스팟: 사각·원·타원으로 드래그하면 빨간 선으로 표시. 선을 끌어 크기 조절, 바깥 클릭으로 완료\n\n⌃⌥1 강조 · 2 돋보기 · 3 펜 · 4 타이머 · 5 캡처 · 6 스팟\nEsc: 조작 모드로 돌아오기 (필기는 유지)\nOption을 누르는 동안: 필기 중 클릭·스크롤 통과\n도구막대는 버튼을 잡고 끌어도 어디든 옮겨져요. 왼쪽·오른쪽 끝에 닿으면 바로 세로로 서요. 눈 버튼이나 ⌃⌥0으로 숨길 수 있어요.\n\n저장한 캡처·녹화 위치: ", "Highlight: a ring around the pointer and left/right click marks\nControl+scroll: up larger, down smaller (spot, then dim circle, then pointer)\nZoom: live magnifier, choose 1.5× to 5×\nPen: 3 colors and a color wheel, width slider, undo, clear\nTimer: 1 to 60 minute countdown. Type minutes; drag the clock to move it, drag its corner to resize\nCapture: select an area, then annotate, copy and save in the editor. Use ▾ for save, pin, or recording\nSpot: drag a rectangle, circle or ellipse to mark it with a red line\n\n⌃⌥1 Highlight · 2 Zoom · 3 Pen · 4 Timer · 5 Capture · 6 Spot · 0 Hide bar\nEsc: back to normal use\nHold Option: clicks pass through while drawing\nDrag the toolbar to move it. At a side edge it stands up.\n\nSaved captures and recordings: ") + storage.capturesLabel
    )
  }
  func showMessage(_ title: String, _ text: String) {
    guard !toolsSuspended else { return }
    withToolsSuspended { presentAlert(title, text) }
  }
  func withToolsSuspended(_ action: () -> Void) {
    guard !toolsSuspended else {
      action()
      return
    }
    finishStrokes()
    toolsSuspended = true
    let panels =
      [toolbar, penPanel, settingsPanel, timerPanel, capturePanel, colorPanel, spotPanel, miniPanel, zoomPanel, clockPanel, phonePanel, qrPanel, qrWindow, boardWindow]
      .compactMap { $0 } + stickers + stickers.compactMap { ($0.contentView as? StickerView)?.bar } + [guide?.window].compactMap { $0 }
    let visiblePanels = panels.filter { $0.isVisible }
    capture.stop()
    capturedDisplay = nil
    for (window, _) in overlays {
      window.orderOut(nil)
      window.ignoresMouseEvents = true
    }
    for window in panels { window.orderOut(nil) }
    updateEscape()
    defer {
      toolsSuspended = false
      for (window, _) in overlays { window.orderFrontRegardless() }
      for window in visiblePanels { window.orderFrontRegardless() }
      refreshTools()
      invalidateAll()
      if zoom { refreshCapture() }
    }
    action()
  }
  private func presentAlert(_ title: String, _ text: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    alert.addButton(withTitle: tr("확인", "OK"))
    takeFocus()
    alert.runModal()
    giveFocusBack()
  }
  /// YelPoint comes forward only for an alert, the board or a window; the lesson app is remembered.
  func takeFocus() {
    if !NSApp.isActive, let front = NSWorkspace.shared.frontmostApplication,
      front.processIdentifier != ProcessInfo.processInfo.processIdentifier
    {
      focusReturn = front
    }
    NSApp.activate(ignoringOtherApps: true)
  }
  /// Hands the keyboard back, so arrow keys and clickers move the slides again.
  func giveFocusBack() {
    guard boardWindow?.isVisible != true, subtitleEditor == nil, phoneVideoPicker == nil, videoLibrary == nil, guide?.isVisible != true,
      let app = focusReturn
    else { return }
    focusReturn = nil
    if !app.isTerminated { app.activate() }
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    setToolbarHidden(false)
    return true
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  @objc func quit() {
    let testing = ProcessInfo.processInfo.arguments.contains { $0 == "--ui-self-test" || $0 == "--smoke-test" }
    let inkOnScreen = overlays.contains { !$0.1.strokes.isEmpty } || !stickers.isEmpty
    guard !testing, inkOnScreen || recorder != nil || phone.running else {
      NSApp.terminate(nil)
      return
    }
    // The power button sits beside hide; one slip must not wipe the lesson's ink.
    let ask = NSAlert()
    ask.messageText = tr("YelPoint를 종료할까요?", "Quit YelPoint?")
    ask.informativeText =
      recorder != nil
      ? tr("녹화는 저장하고 끝내요. 화면의 필기와 붙인 이미지는 사라져요.", "The recording is saved first. Ink and pinned images on screen will be gone.")
      : tr("화면의 필기와 붙인 이미지가 사라져요. 잠깐 치우려면 눈 버튼으로 숨기세요.", "Ink and pinned images on screen will be gone. To tuck it away, use the eye button instead.")
    ask.addButton(withTitle: tr("종료", "Quit"))
    ask.addButton(withTitle: tr("취소", "Cancel"))
    var choice = NSApplication.ModalResponse.alertSecondButtonReturn
    withToolsSuspended {
      takeFocus()
      choice = ask.runModal()
      if choice != .alertFirstButtonReturn { giveFocusBack() }
    }
    if choice == .alertFirstButtonReturn { NSApp.terminate(nil) }
  }
  func applicationWillTerminate(_ notification: Notification) {
    timer?.invalidate()
    finishRecordingBeforeQuit()
    phone.shutdown()
    capture.stop()
    for m in [globalMouse, localMouse, globalKeys, localKeys, globalScroll, localScroll]
      .compactMap({ $0 })
    {
      NSEvent.removeMonitor(m)
    }
    for key in hotkeys { UnregisterEventHotKey(key) }
    if let escapeKey { UnregisterEventHotKey(escapeKey) }
    if let eventHandler { RemoveEventHandler(eventHandler) }
    for (w, _) in overlays { w.orderOut(nil) }
    try? storage.save(preferences)
  }
}

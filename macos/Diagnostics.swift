import AVFoundation
import AppKit
import Carbon

private struct DiagnosticFailure: Error { let description: String }

extension AppController {
  /// Exercises our own handlers and views without injecting input into other apps.
  func runUISelfTest() {
    // Keep clipboard regression checks from replacing the user's current clipboard.
    let savedClipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
      item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
    }
    func restoreClipboard() {
      let items = savedClipboard.map { entries -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in entries { item.setData(data, forType: type) }
        return item
      }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects(items)
    }
    do {
      func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
        if !condition() { throw DiagnosticFailure(description: name) }
      }
      try check(toolbar.isVisible && !overlays.isEmpty, "toolbar and display overlays")
      try check(overlays.allSatisfy { $0.0.ignoresMouseEvents }, "initial click-through")
      func hotkey(_ id: UInt32) throws {
        var event: EventRef?
        var key = EventHotKeyID(signature: 0x5350_4F54, id: id)
        try check(
          CreateEvent(
            nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
            GetCurrentEventTime(), 0, &event) == noErr, "create own hotkey event")
        guard let event else { throw DiagnosticFailure(description: "hotkey event") }
        defer { ReleaseEvent(event) }
        try check(
          SetEventParameter(
            event, EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &key) == noErr,
          "own hotkey event parameter")
        try check(
          SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr,
          "own hotkey event dispatch")
      }
      dockView.buttons["pen"]?.callback?()
      try check(pen && !penPanel.isVisible, "toolbar pen draws without opening options")
      dockView.buttons["penOptions"]?.callback?()
      try check(penPanel.isVisible, "explicit options arrow opens the palette")
      dockView.buttons["penOptions"]?.callback?()
      refreshTools()
      try check(pen && !penPanel.isVisible, "right click dismisses options without disabling pen")
      dockView.buttons["pen"]?.callback?()
      try check(!pen && !penPanel.isVisible, "repeated toolbar click exits pen")
      dockView.buttons["capture"]?.callback?()
      try check(selecting && !capturePanel.isVisible, "toolbar capture goes directly to selection")
      dockView.buttons["capture"]?.callback?()
      try check(!selecting && overlays.allSatisfy { $0.0.ignoresMouseEvents }, "repeated capture click cancels")
      dockView.buttons["captureOptions"]?.callback?()
      try check(capturePanel.isVisible, "right click exposes recording and save")
      returnToPointer()
      try hotkey(3)
      preferences.fadingInk = true
      try check(pen && !penPanel.isVisible, "keyboard pen never opens the palette")
      refreshTools()
      try check(!penPanel.isVisible, "refresh never opens the palette")
      togglePenOptions()
      try check(penPanel.isVisible, "explicit options click opens the palette")
      togglePenOptions()
      refreshTools()
      try check(!penPanel.isVisible, "dismissed palette stays closed")
      try check(escapeKey != nil, "Escape shortcut registration")
      passthrough = false
      let first = overlays[0].1
      func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(
          with: type, location: point, modifierFlags: [], timestamp: 0,
          windowNumber: overlays[0].0.windowNumber, context: nil, eventNumber: 0,
          clickCount: 1, pressure: 1)!
      }
      first.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 70, y: 80)))
      first.activeStroke?.created = ProcessInfo.processInfo.systemUptime - 10
      try check(
        first.activeStroke?.alpha(at: ProcessInfo.processInfo.systemUptime, inProgress: true) == 1,
        "long active ink remains visible")
      first.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 140, y: 100)))
      first.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 140, y: 100)))
      try check(
        first.strokes.count == 1 && first.strokes[0].points.count == 2,
        "freehand input commits one stroke")
      try check(
        first.strokes[0].alpha(at: ProcessInfo.processInfo.systemUptime) == 1
          && ProcessInfo.processInfo.systemUptime - first.strokes[0].created < 1,
        "fading countdown starts when drawing finishes")
      try hotkey(99)
      try check(!pen && !zoom && !penPanel.isVisible, "Escape returns to pointer")
      try check(
        first.strokes.count == 1 && overlays.allSatisfy { $0.0.ignoresMouseEvents },
        "pointer keeps annotations and passes clicks")
      undo()
      try check(first.strokes.isEmpty, "undo removes last stroke")
      toggle("pen")
      first.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 100, y: 110)))
      try check(first.activeStroke != nil, "active stroke before display change")
      setPassthrough(true)
      try check(
        first.activeStroke == nil && first.strokes.count == 1
          && overlays.allSatisfy { $0.0.ignoresMouseEvents },
        "Option commits stroke before passing input")
      setPassthrough(false)
      first.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 160, y: 130)))
      rebuildScreens()
      try check(overlays[0].1.strokes.count == 2, "display reconfiguration preserves active ink")
      withToolsSuspended {
        diagnosticExitCode =
          (toolsSuspended && !toolbar.isVisible
            && overlays.allSatisfy {
              !$0.0.isVisible && $0.0.ignoresMouseEvents
            }) ? 0 : 1
        tick()
      }
      try check(
        diagnosticExitCode == 0 && toolbar.isVisible && !toolsSuspended,
        "modal suspension hides tools, pauses input, and restores them")
      let inkBeforeClear = overlays.reduce(0) { $0 + $1.1.strokes.count }
      clear()
      try check(overlays.allSatisfy { $0.1.strokes.isEmpty }, "clear all ink")
      if inkBeforeClear > 0 {
        try check(penView.undo.isEnabled, "undo is offered after clear all")
        undo()
        try check(overlays.reduce(0) { $0 + $1.1.strokes.count } == inkBeforeClear, "undo brings cleared ink back")
        clear()
      }
      try check(
        NSApp.mainMenu?.items.contains { $0.submenu?.items.contains { $0.action == #selector(NSText.paste(_:)) } == true } == true,
        "Edit menu gives text fields ⌘V")
      returnToPointer()
      toggle("settings")
      try check(settingsPanel.isVisible, "settings open")
      returnToPointer()
      try check(!settingsPanel.isVisible && escapeKey == nil, "Escape releases its shortcut")
      let home = toolbar.frame.origin
      toolbar.setFrameOrigin(CGPoint(x: -9000, y: -9000))
      keepToolbarOnScreen()
      try check(
        NSScreen.screens.contains { $0.visibleFrame.contains(toolbar.frame) },
        "toolbar dragged off screen comes back")
      guard let top = toolbar.screen?.visibleFrame else {
        throw DiagnosticFailure(description: "toolbar has a screen")
      }
      toolbar.setFrameOrigin(CGPoint(x: top.minX, y: top.maxY - toolbar.frame.height))
      toggle("timer")
      try check(timerPanel.frame.maxY <= toolbar.frame.minY, "panels open below a toolbar at the top")
      returnToPointer()
      try check(
        preferences.toolbarX == toolbar.frame.minX && preferences.toolbarY == toolbar.frame.minY,
        "toolbar spot is remembered")
      toolbar.setFrameOrigin(CGPoint(x: top.midX - 300, y: top.midY))
      beginToolbarDrag(at: CGPoint(x: top.midX, y: top.midY))
      dragToolbar(to: CGPoint(x: top.minX + 300, y: top.midY))
      try check(
        toolbar.frame.size == DockView.standing && toolbar.frame.minX == top.minX + 8
          && preferences.toolbarVertical == true,
        "toolbar stands up the moment it reaches the left edge, before release")
      dragToolbar(to: CGPoint(x: top.minX + 250, y: top.midY - 40))
      try check(
        toolbar.frame.size == DockView.standing && toolbar.frame.minX == top.minX + 8,
        "standing toolbar stays at the edge and follows up and down")
      endToolbarDrag()
      toggle("capture")
      try check(!selecting && capturePanel.isVisible, "the capture button shows photo and recording choices beside the standing bar")
      try check(capturePanel.frame.minX >= toolbar.frame.maxX, "panels open beside a standing toolbar")
      try check(
        capturePanel.frame.width < capturePanel.frame.height && phonePanel.frame.width <= 212
          && capturePanel.frame.minX - toolbar.frame.maxX <= attachGap + 0.5,
        "a standing toolbar's panels stand too and sit right against it")
      // One picture of every standing panel, side by side, for a look.
      zoomView.refresh()
      let standing = [penPanel, timerPanel, capturePanel, spotPanel, zoomPanel, phonePanel, qrPanel].compactMap { $0?.contentView }
      let sheetSize = CGSize(width: standing.map(\.frame.width).reduce(0, +) + CGFloat(standing.count + 1) * 12, height: (standing.map(\.frame.height).max() ?? 0) + 24)
      if let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(sheetSize.width), pixelsHigh: Int(sheetSize.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
        NSColor(white: 0.93, alpha: 1).setFill()
        CGRect(origin: .zero, size: sheetSize).fill()
        var x: CGFloat = 12
        for view in standing {
          if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            rep.draw(in: CGRect(x: x, y: sheetSize.height - 12 - view.frame.height, width: view.frame.width, height: view.frame.height))
          }
          x += view.frame.width + 12
        }
        NSGraphicsContext.restoreGraphicsState()
        try? sheet.representation(using: .png, properties: [:])?.write(to: storage.root.appendingPathComponent("standing-panels.png"))
      }
      returnToPointer()
      beginToolbarDrag(at: CGPoint(x: top.minX + 40, y: top.midY))
      dragToolbar(to: CGPoint(x: top.minX + 200, y: top.midY))
      try check(
        toolbar.frame.size == DockView.wide && preferences.toolbarVertical == nil,
        "pulled inward the toolbar lies flat again, before release")
      try check(toolbar.frame.minX >= top.minX + 60, "flat toolbar lands clear of the edge")
      dragToolbar(to: CGPoint(x: top.minX + 260, y: top.midY))
      try check(toolbar.frame.size == DockView.wide, "flat toolbar does not snap straight back")
      endToolbarDrag()
      toolbar.setFrameOrigin(CGPoint(x: top.midX, y: top.midY))
      let grip = CGPoint(x: toolbar.frame.minX + 12, y: top.midY)
      beginToolbarDrag(at: grip)
      dragToolbar(to: CGPoint(x: top.maxX - toolbar.frame.width + 12, y: top.midY))
      try check(
        toolbar.frame.size == DockView.standing && toolbar.frame.maxX == top.maxX - 8
          && dockView.buttons["hide"]?.frame.maxX ?? 999 <= 104
          && dockView.buttons["quit"].map { dockView.bounds.contains($0.frame) } == true,
        "bar touching the right edge stands up with the pointer far from it")
      // Well past the 120-point hysteresis from where it stood up, whatever the bar's width.
      dragToolbar(to: CGPoint(x: top.midX - 300, y: top.midY))
      endToolbarDrag()
      try check(toolbar.frame.size == DockView.wide, "dragged back to the middle it is flat")
      try check(
        dockView.buttons["quit"].map { dockView.bounds.contains($0.frame) && !$0.isHidden } == true,
        "the quit button sits on the flat toolbar")
      toggle("pen")
      try hotkey(7)
      try check(
        !toolbar.isVisible && miniPanel.isVisible && !penPanel.isVisible && pen,
        "hiding leaves only the small button and keeps the pen on")
      try check(toolbar.screen != nil, "hidden toolbar still names a display")
      moveMini(to: CGPoint(x: top.minX + 200, y: top.minY + 200))
      try check(toolbar.frame.minX == top.minX + 200, "hidden toolbar follows the small button")
      try hotkey(7)
      try check(toolbar.isVisible && !miniPanel.isVisible && !penPanel.isVisible, "toolbar comes back without reopening palette")
      returnToPointer()
      withToolsSuspended { diagnosticExitCode = miniPanel.isVisible ? 1 : 0 }
      toolbar.setFrameOrigin(home)
      let startingRadius = preferences.pointerRadius
      preferences.resizePointer(steps: 1)
      try check(preferences.pointerRadius == startingRadius + 2, "pointer size changes")
      preferences.haloRadius = nil
      toggle("pen")
      let startingWidth = preferences.penWidth
      penView.widthSlider.pick(x: 1000)
      try check(preferences.penWidth == 30, "dragging right reaches the thickest pen")
      penView.widthSlider.pick(x: -1000)
      try check(preferences.penWidth == 1, "dragging left reaches the thinnest pen")
      preferences.penWidth = startingWidth
      preferences.inkRGB = 0xFF00FF
      toggleColorPanel()
      try check(colorPanel.isVisible, "color wheel opens from the pen bar")
      try check(
        colorPanel.frame.minY >= penPanel.frame.maxY || colorPanel.frame.maxY <= penPanel.frame.minY,
        "color wheel does not cover the pen bar")
      colorView.pick(CGPoint(x: 98 + 84, y: 134))
      try check(preferences.inkRGB == 0xFF0000, "wheel rim picks a full color")
      first.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 30, y: 40)))
      try check(
        first.activeStroke?.color == NSColor(rgb: 0xFF0000) && !colorPanel.isVisible,
        "pen draws with the picked color and closes the wheel")
      first.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 30, y: 40)))
      clear()
      preferences.inkRGB = nil
      toggleColorPanel()
      returnToPointer()
      try check(!colorPanel.isVisible, "leaving the pen closes the wheel")
      try hotkey(6)
      try check(spotPanel.isVisible, "spot shortcut opens its panel")
      beginSpot(.circle)
      try check(overlays.allSatisfy { !$0.0.ignoresMouseEvents }, "spot editing takes the mouse")
      first.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 200, y: 200)))
      first.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 300, y: 260)))
      first.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 300, y: 260)))
      try check(
        spot?.rect == CGRect(x: 200, y: 200, width: 100, height: 100) && spotEditing,
        "circle stays round and stays editable after release")
      first.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 300, y: 250)))
      first.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 350, y: 250)))
      first.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 350, y: 250)))
      try check(spot?.rect.width == 150 && spot?.rect.height == 150, "dragging the line resizes")
      first.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 275, y: 275)))
      first.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 285, y: 265)))
      first.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 285, y: 265)))
      try check(spot?.rect.origin == CGPoint(x: 210, y: 165), "dragging inside moves the spot")
      beginSpot(.ellipse)
      try check(spot?.shape == .ellipse, "shape button changes the existing spot")
      first.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 20, y: 20)))
      first.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 20, y: 20)))
      try check(
        spot?.rect.width == 150 && !spotEditing && overlays.allSatisfy { $0.0.ignoresMouseEvents },
        "click outside keeps the spot and restores click-through")
      let before = spot?.rect ?? .zero
      resizeFocus(steps: 2)
      try check(
        (spot?.rect.width ?? 0) > before.width && abs((spot?.rect.midX ?? 0) - before.midX) < 0.01,
        "Control scroll grows the shape spot about its centre")
      clearSpot()
      returnToPointer()
      try check(spot == nil && !spotPanel.isVisible, "spot turns off")
      let dimmed = preferences.spotlight
      let pointerBefore = preferences.pointerRadius
      preferences.spotlight = true
      resizeFocus(steps: -1)
      try check(
        preferences.dimmingRadius == 97 && preferences.pointerRadius == pointerBefore,
        "Control scroll resizes the dimming circle first")
      preferences.spotlight = dimmed
      preferences.spotlightRadius = nil
      zoom = true
      refreshTools()
      try check(zoomPanel.isVisible, "zoom levels appear with the magnifier")
      let startingZoom = preferences.zoom
      setZoom(4)
      try check(preferences.zoom == 4, "zoom level is chosen")
      preferences.zoom = startingZoom
      zoom = false
      refreshTools()
      try check(!zoomPanel.isVisible, "zoom levels leave with the magnifier")
      try hotkey(4)
      try check(timerPanel.isVisible, "timer shortcut opens its panel")
      timerView.minutesField.stringValue = "37"
      timerView.minutesTyped()
      try check(countdown.minutes == 37, "typed minutes set the timer")
      timerView.minutesField.stringValue = "abc"
      timerView.minutesTyped()
      try check(countdown.minutes == 37 && timerView.minutesField.stringValue == "37", "nonsense is ignored")
      setTimer(minutes: 99)
      try check(countdown.minutes == 60, "timer stops at 60 minutes")
      timerStartPause()
      try check(countdown.isRunning && timerView.start.symbol == "pause.fill", "timer starts")
      try check(
        clockPanel.isVisible && !controlWindowIDs.contains(CGWindowID(clockPanel.windowNumber)),
        "clock floats on its own and is kept in recordings")
      let clockHome = clockPanel.frame
      clockPanel.setFrame(resizedClock(clockHome, dx: 196), display: true)
      clockMoved()
      try check(preferences.clockScale == clockPanel.frame.width / 196 && clockPanel.frame.width > 196, "clock grows and remembers it")
      preferences.clockScale = nil
      preferences.clockX = nil
      preferences.clockY = nil
      clockPanel.setFrame(clockHome, display: true)
      setTimer(minutes: 3)
      try check(countdown.minutes == 60, "running timer keeps its length")
      timerReset()
      try check(!countdown.isActive && !clockPanel.isVisible, "timer resets and the clock leaves")
      toggle("pen")
      toggle("capture")
      try check(capturePanel.isVisible && !selecting && !timerPanel.isVisible && !pen && !penPanel.isVisible,
        "Capture opens the photo and video menu without area selection or an overlapping pen palette")
      try check(captureView.record.superview === captureView
        && captureView.record.title == tr("화면 녹화", "Record") && captureView.record.isEnabled
        && captureView.bounds.contains(captureView.record.frame),
        "the recording button is visible and enabled in the capture menu")
      // Exercise the real Record button, but cancel the notice before any capture starts.
      let beforeRecordingFiles = (try? FileManager.default.contentsOfDirectory(atPath: capturesFolder.path)) ?? []
      var sawRecordingNotice = false
      let cancelRecordingNotice = Timer(timeInterval: 0.1, repeats: false) { _ in
        sawRecordingNotice = self.recordingStartPending && self.toolsSuspended && NSApp.modalWindow != nil
        self.captureView.record.callback?() // A repeated click must not open a second notice.
        NSApp.abortModal()
      }
      RunLoop.main.add(cancelRecordingNotice, forMode: .modalPanel)
      captureView.record.callback?()
      cancelRecordingNotice.invalidate()
      let afterRecordingFiles = (try? FileManager.default.contentsOfDirectory(atPath: capturesFolder.path)) ?? []
      try check(sawRecordingNotice && !recordingStartPending && recorder == nil && !recordingLive
        && capturePanel.isVisible && Set(beforeRecordingFiles) == Set(afterRecordingFiles),
        "Record opens its notice and cancel restores the menu without recording or creating files")
      let photoButton = captureView.subviews.compactMap { $0 as? ToolButton }.first
      try check(photoButton?.title == tr("사진 캡처", "Photo"), "photo capture is labelled separately from recording")
      toggle("capture")
      try check(!capturePanel.isVisible && !selecting, "clicking Capture again dismisses its menu")
      toggle("capture")
      try check(capturePanel.isVisible, "the photo and video menu can reopen")
      photoButton?.callback?()
      try check(selecting && !capturePanel.isVisible, "choosing a photo closes the menu and selects an area")
      toggle("capture")
      try check(!selecting && capturePanel.isVisible, "Capture returns from area selection to the photo and video menu")
      try hotkey(5)
      try check(selecting && !timerPanel.isVisible && !capturePanel.isVisible, "the capture key goes straight to choosing an area")
      try hotkey(5)
      try check(!selecting, "the quick capture key can cancel area selection")
      try hotkey(5)
      finishSelection(screen: NSScreen.main!, rect: .zero)
      try check(!capturePanel.isVisible && !selecting, "a click without dragging cancels without opening a menu")
      toggle("pen")
      try check(pen && !capturePanel.isVisible, "pen closes capture panel")
      returnToPointer()
      selecting = true
      refreshTools()
      try check(captureCursor.image.size == CGSize(width: 32, height: 32), "capture cursor is ready")
      try check(
        overlays.allSatisfy { !$0.0.ignoresMouseEvents } && escapeKey != nil,
        "selection receives the drag and Esc")
      overlays[0].1.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 10, y: 20)))
      overlays[0].1.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 110, y: 70)))
      try check(
        overlays[0].1.selectionRect == CGRect(x: 10, y: 20, width: 100, height: 50),
        "selection follows the drag")
      returnToPointer()
      try check(
        !selecting && overlays[0].1.selection == nil
          && overlays.allSatisfy { $0.0.ignoresMouseEvents },
        "Esc cancels selection and restores click-through")
      let picture = NSImage(size: CGSize(width: 40, height: 30), flipped: false) { rect in
        NSColor.systemTeal.setFill()
        rect.fill()
        return true
      }
      addSticker(picture)
      try check(stickers.count == 1 && stickers[0].isVisible, "sticker appears")
      if let bar = (stickers[0].contentView as? StickerView)?.bar {
        try check(
          bar.isVisible && bar.level.rawValue > overlays[0].0.level.rawValue
            && (abs(bar.frame.maxY + 6 - stickers[0].frame.minY) < 1 || abs(bar.frame.minY - 6 - stickers[0].frame.maxY) < 1),
          "a pinned image has its button bar right next to it, above the pen layer")
      } else {
        throw DiagnosticFailure(description: "pinned image button bar")
      }
      try check(
        stickers[0].level.rawValue < overlays[0].0.level.rawValue,
        "ink overlay stays above sticker")
      withToolsSuspended { diagnosticExitCode = stickers[0].isVisible ? 1 : 0 }
      try check(diagnosticExitCode == 0 && stickers[0].isVisible, "alert hides and restores sticker")
      removeSticker(stickers[0])
      try check(stickers.isEmpty, "sticker closes")
      lastCapture = picture.cgImage(forProposedRect: nil, context: nil, hints: nil)
      guard let saved = saveCapture() else { throw DiagnosticFailure(description: "save capture") }
      try check(NSImage(contentsOf: saved) != nil, "saved PNG reads back")
      try FileManager.default.removeItem(at: saved)
      lastCapture = nil
      // The display test rebuilt the overlays, so draw on the live one.
      let canvas = overlays[0].1
      let origin = canvas.screen.frame.origin
      let inkBefore = canvas.strokes.count
      addSticker(picture, at: CGRect(x: origin.x + 300, y: origin.y + 300, width: 120, height: 90))
      try check(
        stickers.last?.frame.origin == CGPoint(x: origin.x + 300, y: origin.y + 300),
        "capture is pinned where it was taken")
      try check(
        pixelAligned(CGRect(x: 100.4, y: 50.6, width: 200.7, height: 80.2), scale: 1)
          == CGRect(x: 100, y: 51, width: 201, height: 80)
          && pixelAligned(CGRect(x: 10.3, y: 10.3, width: 5.5, height: 5.5), scale: 2)
          == CGRect(x: 10.5, y: 10.5, width: 5.5, height: 5.5),
        "capture area snaps to whole pixels")
      let clipBefore = NSPasteboard.general.changeCount
      if !pen { toggle("pen") }
      canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 320, y: 320)))
      canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 380, y: 350)))
      canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 380, y: 350)))
      guard let pinned = stickers.last?.contentView as? StickerView else {
        throw DiagnosticFailure(description: "pinned capture view")
      }
      try check(
        pinned.strokes.count == 1 && pinned.strokes[0].points.first == CGPoint(x: 20, y: 20)
          && canvas.strokes.count == inkBefore,
        "ink drawn on a capture belongs to the capture")
      try check(
        NSPasteboard.general.changeCount > clipBefore && NSImage(pasteboard: NSPasteboard.general) != nil,
        "ink on a capture is copied right away")
      try check(penView.undo.isEnabled, "undo is offered for ink on a capture")
      pinned.menuPoint = CGPoint(x: 10, y: 40)
      pinned.beginNote(color: .systemRed)
      pinned.editor?.stringValue = "메모 note"
      pinned.commitNote()
      try check(
        pinned.notes.count == 1 && pinned.notes[0].text == "메모 note" && pinned.editor == nil,
        "typed text lands on the capture")
      undo()
      try check(pinned.notes.isEmpty && pinned.strokes.count == 1, "undo removes the text first")
      let merged = pinned.composite()
      try check(merged?.width == 40 && merged?.height == 30, "saved capture keeps its own resolution")
      try check(
        sticker(at: CGPoint(x: origin.x + 310, y: origin.y + 310)) === pinned
          && pinned.menu?.items.filter({ !$0.isSeparatorItem }).count == 5,
        "right-click finds the capture and offers text, copy, paste, save and close")
      guard let annotated = saveCapture(from: pinned) else { throw DiagnosticFailure(description: "save annotated") }
      try FileManager.default.removeItem(at: annotated)
      undo()
      try check(pinned.strokes.isEmpty, "undo removes ink from the capture")
      canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 320, y: 320)))
      canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 330, y: 330)))
      clear()
      try check(pinned.strokes.isEmpty, "clear all also clears ink on a capture")
      canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 20, y: 20)))
      canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 40, y: 30)))
      try check(canvas.strokes.count == 1 && pinned.strokes.isEmpty, "ink off the capture stays on screen")
      clear()
      // The grip and ✕ still work while the pen layer lies over the image.
      if !pen { toggle("pen") }
      let pinnedWindow = stickers[stickers.count - 1]
      let start = pinnedWindow.frame.origin
      let gripAt = CGPoint(x: start.x - origin.x + pinned.gripFrame.midX, y: start.y - origin.y + pinned.gripFrame.midY)
      canvas.mouseDown(with: mouse(.leftMouseDown, gripAt))
      canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: gripAt.x + 30, y: gripAt.y + 20)))
      canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: gripAt.x + 30, y: gripAt.y + 20)))
      try check(pinned.strokes.isEmpty && canvas.strokes.isEmpty, "the grip moves without drawing")
      let moved = pinnedWindow.frame.origin
      try check(moved == CGPoint(x: start.x + 30, y: start.y + 20), "the grip moves a capture while the pen is on")
      let closeAt = CGPoint(x: moved.x - origin.x + pinned.closeFrame.midX, y: moved.y - origin.y + pinned.closeFrame.midY)
      canvas.mouseDown(with: mouse(.leftMouseDown, closeAt))
      canvas.mouseUp(with: mouse(.leftMouseUp, closeAt))
      try check(
        !stickers.contains { $0 === pinnedWindow } && canvas.strokes.isEmpty,
        "✕ closes a capture while the pen is on")
      returnToPointer()
      // Captures use their own input surface, not the full-screen pen overlay.
      let captureFrame = CGRect(x: origin.x + 300, y: origin.y + 300, width: 120, height: 90)
      store(picture.cgImage(forProposedRect: nil, context: nil, hints: nil)!, scale: 1, frame: captureFrame)
      try check(stickers.isEmpty && !pen && !penPanel.isVisible && !capturePanel.isVisible
        && overlays.allSatisfy { $0.0.ignoresMouseEvents } && escapeKey == nil
        && NSPasteboard.general.types?.contains(.png) == true,
        "capture copies PNG without windows, drawing mode or desktop interception")
      for _ in 0..<3 {
        store(picture.cgImage(forProposedRect: nil, context: nil, hints: nil)!, scale: 1, frame: captureFrame)
      }
      try check(stickers.isEmpty && !penPanel.isVisible && !capturePanel.isVisible,
        "repeated capture never creates or reopens windows")
      toggle("timer")
      store(picture.cgImage(forProposedRect: nil, context: nil, hints: nil)!, scale: 1, frame: captureFrame)
      try check(timerPanel.isVisible, "late capture completion preserves a newer tool panel")
      returnToPointer()
      hideHalo = true
      beginSelection()
      finishSelection(screen: NSScreen.main!, rect: .zero)
      try check(!hideHalo && !selecting, "cancelled replacement capture restores pointer halo")
      toggle("pen")
      canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 20, y: 20)))
      store(picture.cgImage(forProposedRect: nil, context: nil, hints: nil)!, scale: 1)
      try check(canvas.activeStroke != nil && pen, "late capture leaves newer active handwriting intact")
      returnToPointer()
      clear()
      // Pinning and annotating remain available only when explicitly requested.
      addSticker(picture, at: captureFrame)
      pen = true
      capturePenOnly = true
      refreshTools()
      guard let localInk = stickers.last?.contentView as? StickerView,
        let localWindow = localInk.window as? QuietPanel else { throw DiagnosticFailure(description: "capture-only pen") }
      func imageMouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(
          with: type, location: localInk.convert(point, to: nil), modifierFlags: [], timestamp: 0,
          windowNumber: localWindow.windowNumber, context: nil, eventNumber: 0,
          clickCount: 1, pressure: 1)!
      }
      try check(pen && capturePenOnly && !penPanel.isVisible && drawingOnCaptures,
        "capture keeps the pen ready on images")
      try check(overlays.allSatisfy { $0.0.ignoresMouseEvents } && localWindow.becomesKeyOnlyIfNeeded && escapeKey == nil,
        "capture pen leaves other apps clickable without taking their keyboard")
      let outsideCount = canvas.strokes.count
      canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 20, y: 20)))
      canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 20, y: 20)))
      try check(canvas.strokes.count == outsideCount, "capture pen never draws outside the image")
      let autoCopyBefore = NSPasteboard.general.changeCount
      localInk.mouseDown(with: imageMouse(.leftMouseDown, CGPoint(x: 20, y: 20)))
      localInk.mouseDragged(with: imageMouse(.leftMouseDragged, CGPoint(x: 80, y: 50)))
      localInk.mouseUp(with: imageMouse(.leftMouseUp, CGPoint(x: 80, y: 50)))
      try check(localInk.strokes.count == 1 && localInk.strokes[0].points.count == 2
        && NSPasteboard.general.changeCount > autoCopyBefore && pen && drawingOnCaptures,
        "image-local strokes auto-copy and keep the pen ready")
      localInk.mouseDown(with: imageMouse(.leftMouseDown, CGPoint(x: 30, y: 20)))
      try check(copySticker(localInk, announce: false) && localInk.activeStroke == nil
        && localInk.strokes.count == 2 && pen && !penPanel.isVisible
        && overlays.allSatisfy { $0.0.ignoresMouseEvents },
        "copy finishes an active stroke without turning off the pen or blocking the desktop")
      for _ in 0..<3 { try check(copySticker(localInk, announce: false), "repeat copy succeeds") }
      try check(localInk.strokes.count == 2, "repeated copies never duplicate ink")
      undo()
      try check(localInk.strokes.count == 1 && pen, "undo works after capture copy")
      localInk.mouseDown(with: imageMouse(.leftMouseDown, CGPoint(x: 40, y: 30)))
      setPassthrough(true)
      try check(localInk.activeStroke == nil && localInk.strokes.count == 2 && !drawingOnCaptures,
        "Option commits image-local ink before switching to move")
      setPassthrough(false)
      localInk.menuPoint = CGPoint(x: 10, y: 40)
      localInk.beginNote(color: .systemRed)
      localInk.editor?.stringValue = "복사 전 입력"
      try check(copySticker(localInk, announce: false) && localInk.notes.last?.text == "복사 전 입력"
        && localInk.editor == nil && pen,
        "copy commits unfinished text while keeping the capture pen")
      withToolsSuspended { diagnosticExitCode = localWindow.isVisible ? 1 : 0 }
      try check(diagnosticExitCode == 0 && localWindow.isVisible && drawingOnCaptures
        && overlays.allSatisfy { $0.0.ignoresMouseEvents }, "capture pen survives modal restoration")
      toggle("pen")
      toggle("pen")
      try check(pen && !capturePenOnly && overlays.allSatisfy { !$0.0.ignoresMouseEvents },
        "choosing the regular pen still enables full-screen drawing")
      try check(copySticker(localInk, announce: false) && pen && capturePenOnly
        && overlays.allSatisfy { $0.0.ignoresMouseEvents },
        "copy from full-screen pen keeps drawing on images and releases the desktop")
      removeSticker(stickers.last!)
      returnToPointer()
      preferences.fadingInk = false
      toggle("phone")
      try check(
        phonePanel.isVisible && dockView.buttons["phone"]?.selected == true && phone.isWatching,
        "phone panel opens from the toolbar and watches for a device")
      try check(phone.available, "bundled scrcpy is executable")
      try check(phone.adb(["version"])?.contains("Android Debug Bridge") == true, "bundled adb runs")
      let picker = PhoneVideoPicker(controller: self)
      picker.present(phoneVideos(fromContentQuery: "Row: 0 _display_name=v.mp4, _data=/sdcard/DCIM/Camera/v.mp4, date_added=1793961854, _size=12299884, duration=5707"), loading: false)
      try check(
        picker.videos.count == 1 && picker.status.stringValue.contains(tr("최근", "newest"))
          && phonePanel.contentView?.frame.width == PhoneView.size.width,
        "phone video picker lists gallery videos")
      picker.window.close()
      try check(
        phoneVideoFileName("20261106_194415.mp4") == "YelPoint-phone-video-20261106_194415.mp4"
          && phoneVideoFileName("../../x.mp4") == "YelPoint-phone-video-.._.._x.mp4"
          && phoneVideoFileName("a:b?\\c\u{0}\n.MOV") == "YelPoint-phone-video-a_b__c__.MOV"
          && phoneVideoFileName("/\u{301}..") == "YelPoint-phone-video-_\u{301}.mp4"
          && phoneVideoFileName("run.command") == "YelPoint-phone-video-run.command.mp4"
          && phoneVideoFileName(" .. ") == "YelPoint-phone-video-video.mp4"
          && capturesFolder.appendingPathComponent(phoneVideoFileName("a/../../b")).standardizedFileURL
            .deletingLastPathComponent().path == capturesFolder.standardizedFileURL.path,
        "phone video names stay inside the captures folder as a video file")
      _ = phone.adb(["devices"])
      try check(
        phone.adbLogFolder.map { folder in
          (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.contains { $0.hasPrefix("adb.") } == true
        } == true, "adb writes its log inside YelPoint's data folder")
      phoneView.refresh()
      try check(
        phone.state == .none && !phoneView.screenButton.isEnabled
          && phoneView.status.stringValue.contains(tr("꽂아", "Plug in")),
        "no phone: the panel asks to plug one in")
      toggle("phone")
      try check(!phonePanel.isVisible && dockView.buttons["phone"]?.selected == false, "phone panel closes")
      phone.shutdown()
      toggle("qr")
      try check(qrPanel.isVisible && !qrWindow.isVisible, "QR panel opens from the toolbar and waits for Enter")
      try check(dockView.buttons["qr"]?.selected == true, "QR toolbar button lights up")
      let address = "https://blog.naver.com/PostList.naver?blogId=yelsam_lab&from=menu"
      showQr(address)
      try check(qrWindow.isVisible && !qrPanel.isVisible && preferences.qrText == address, "QR window shows the address")
      qrCard.layoutSubtreeIfNeeded()
      guard let qrBitmap = qrCard.bitmapImageRepForCachingDisplay(in: qrCard.bounds) else {
        throw DiagnosticFailure(description: "QR card bitmap")
      }
      qrCard.cacheDisplay(in: qrCard.bounds, to: qrBitmap)
      let reader = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
      let decoded = CIImage(bitmapImageRep: qrBitmap).flatMap { reader?.features(in: $0).first as? CIQRCodeFeature }?.messageString
      try check(decoded == address, "the big QR code reads back as the address")
      returnToPointer()
      try check(!qrWindow.isVisible, "Esc closes the QR window")
      let credit = dockView.creditRect
      let power = dockView.buttons["quit"]?.frame ?? .zero
      try check(
        abs(credit.midX - power.midX) < 8 && credit.maxY <= power.minY && credit.minY >= 0
          && credit.maxX <= dockView.bounds.maxX,
        "the © mark sits centered under the power button")
      try check(
        creditMenu().items.count == 3 && suggestURL.absoluteString.hasPrefix("mailto:bongbiyobi@gmail.com"),
        "the © popup offers the blog and a suggestion mail")
      toggle("board")
      try check(boardWindow.isVisible && dockView.buttons["board"]?.selected == true && !pen, "chalkboard opens from the toolbar")
      boardView.wipe()
      boardView.drawStroke((0...40).map { CGPoint(x: 100 + CGFloat($0) * 8, y: 200 + CGFloat($0 % 5) * 6) })
      try check(boardView.inkCoverage(in: CGRect(x: 120, y: 190, width: 260, height: 40)) > 0.05, "chalk strokes leave grainy marks")
      boardView.color = 1
      boardView.writeText("안녕 Hello", at: CGPoint(x: 100, y: 300))
      try check(chalkFont(40).fontName == "NanumPen", "the chalk handwriting font is bundled")
      let textCoverage = boardView.inkCoverage(in: CGRect(x: 100, y: 300, width: 260, height: 70))
      try check(textCoverage > 0.03 && textCoverage < 0.7, "Korean and English text is written in chalk")
      boardView.color = 0
      boardView.thick = true
      boardView.writeText("지구는 태양을 돌아요", at: CGPoint(x: 520, y: 120))
      boardView.thick = false
      boardView.color = 4
      boardView.fontStyle = 1
      boardView.writeText("고딕 Sans 123", at: CGPoint(x: 100, y: 420))
      boardView.fontStyle = 2
      boardView.writeText("명조 Serif ABC", at: CGPoint(x: 100, y: 520))
      boardView.fontStyle = 0
      try check(
        chalkFont(40, style: 1).fontName == "NanumGothicBold" && chalkFont(40, style: 2).fontName == "NanumMyeongjoBold",
        "the board's sans and serif fonts are bundled")
      for y in [420.0, 520.0] {
        let coverage = boardView.inkCoverage(in: CGRect(x: 100, y: y, width: 300, height: 60))
        try check(coverage > 0.03 && coverage < 0.7, "sans and serif text is written in chalk")
      }
      boardView.color = 3
      var circle: [CGPoint] = []
      for i in 0...60 {
        let angle = CGFloat(i) / 60 * 2 * .pi
        circle.append(CGPoint(x: 900 + 120 * cos(angle), y: 420 + 120 * sin(angle)))
      }
      boardView.drawStroke(circle)
      if let preview = boardView.bitmapImageRepForCachingDisplay(in: boardView.bounds) {
        boardView.cacheDisplay(in: boardView.bounds, to: preview)
        try? preview.representation(using: .png, properties: [:])?.write(to: storage.root.appendingPathComponent("board-preview.png"))
      }
      try? boardView.pngData()?.write(to: storage.root.appendingPathComponent("board-export.png"))
      for _ in 0..<5 { boardView.undo() }
      try check(boardView.marks.count == 1 && boardView.inkCoverage(in: CGRect(x: 100, y: 300, width: 260, height: 70)) < 0.01, "undo removes the text")
      let boardFile = saveBoard()
      try check(boardFile.map { FileManager.default.fileExists(atPath: $0.path) } == true, "the board saves as a PNG")
      if let boardFile { try? FileManager.default.removeItem(at: boardFile) }
      boardView.wipe()
      try check(boardView.marks.isEmpty, "wipe clears the board")
      toggle("board")
      try check(!boardWindow.isVisible, "the board closes from the toolbar")
      try recorderWritesVideo()
      try subtitlesBurnIn()
      try guideOpensAndPlays()
      try renderOwnViews()
      print(
        "PASS: subtitles burn-in/SRT/editor, chalkboard draw/text/fonts/undo/PNG, © popup, QR window reads back, phone panel and bundled scrcpy/adb, native UI startup, pen input, pointer click-through, undo/clear, display rebuild, modal restoration, Esc, settings, timer, selection, sticker, toolbar move and hide, zoom levels, typed minutes, floating clock, pointer size, pen width slider, color wheel, shape spot, Control scroll, ink on captures (auto-copied, pixel-snapped), text on captures, capture menu, PNG save, MP4 video and audio writer, usage video chapters, native view PNG"
      )
    } catch {
      diagnosticExitCode = 1
      print("FAIL: \(error)")
    }
    restoreClipboard()
    if diagnosticExitCode != 0 {
      applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
      exit(diagnosticExitCode)
    }
    quit()
  }

  private func guideOpensAndPlays() throws {
    showHelp()
    guard let guide, guide.isVisible else {
      throw DiagnosticFailure(description: "usage video opens")
    }
    let asset = AVURLAsset(url: guide.url)
    if abs(asset.duration.seconds - 102) > 1 || GuideWindow.chapters.count != 13 {
      throw DiagnosticFailure(description: "usage video is the expected length")
    }
    let reader = AVAssetImageGenerator(asset: asset)
    reader.requestedTimeToleranceBefore = .zero
    reader.requestedTimeToleranceAfter = .zero
    for chapter in GuideWindow.chapters {
      let time = CMTime(seconds: chapter.start + 1, preferredTimescale: 600)
      guard (try? reader.copyCGImage(at: time, actualTime: nil)) != nil else {
        throw DiagnosticFailure(description: "chapter decodes: \(chapter.title)")
      }
    }
    guide.jump(3)
    guide.skip(1)
    if guide.currentIndex != 4 { throw DiagnosticFailure(description: "next section") }
    guide.skip(-2)
    if guide.currentIndex != 2 { throw DiagnosticFailure(description: "previous section") }
    guide.jump(GuideWindow.chapters.count - 1)
    guide.skip(1)
    if guide.currentIndex != GuideWindow.chapters.count - 1 {
      throw DiagnosticFailure(description: "last section stays put")
    }
    guide.jump(3)
    let view = guide.sidebar
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
      view.cacheDisplay(in: view.bounds, to: bitmap)
      try bitmap.representation(using: .png, properties: [:])?.write(
        to: storage.root.appendingPathComponent("guide-sidebar.png"))
    }
    guide.window.close()
    if guide.player.rate != 0 { throw DiagnosticFailure(description: "closing pauses the video") }
  }

  /// Feeds synthetic frames through the real writer, so no capture permission is needed.
  /// A two-second grey test video, subtitles burned in, and the frames checked.
  private func subtitlesBurnIn() throws {
    let source = storage.root.appendingPathComponent("subtitle-self-test.mp4")
    let output = storage.root.appendingPathComponent("subtitle-self-test.subtitled.mp4")
    for url in [source, output] { try? FileManager.default.removeItem(at: url) }
    let writer = try AVAssetWriter(outputURL: source, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 360,
    ])
    writer.add(input)
    guard writer.startWriting() else { throw DiagnosticFailure(description: "subtitle test video") }
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<60 {
      while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
      var buffer: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
      guard let buffer else { throw DiagnosticFailure(description: "subtitle test frame") }
      CVPixelBufferLockBaseAddress(buffer, [])
      memset(CVPixelBufferGetBaseAddress(buffer), 110, CVPixelBufferGetDataSize(buffer))
      CVPixelBufferUnlockBaseAddress(buffer, [])
      adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
    }
    input.markAsFinished()
    let written = DispatchSemaphore(value: 0)
    writer.finishWriting { written.signal() }
    written.wait()
    let cues = [Cue(start: 0.2, end: 1.2, text: "자막 시험 Subtitle")]
    var failure: Error?
    let burned = DispatchSemaphore(value: 0)
    Task.detached {
      do { try await SubtitleWork.burn(cues, into: source, output: output, style: SubtitleStyle(size: 0.054)) } catch { failure = error }
      burned.signal()
    }
    while burned.wait(timeout: .now()) == .timedOut { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    if let failure { throw DiagnosticFailure(description: "subtitle export: \(failure)") }
    let frames = AVAssetImageGenerator(asset: AVURLAsset(url: output))
    frames.requestedTimeToleranceBefore = .zero
    frames.requestedTimeToleranceAfter = .zero
    func bottomSpread(at seconds: Double) throws -> Int {
      let image = try frames.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
      let rep = NSBitmapImageRep(cgImage: image)
      var low = 255, high = 0
      for x in stride(from: 160, to: 480, by: 4) {
        for y in stride(from: rep.pixelsHigh - 70, to: rep.pixelsHigh - 20, by: 3) {
          let v = Int((rep.colorAt(x: x, y: y)?.brightnessComponent ?? 0) * 255)
          low = min(low, v)
          high = max(high, v)
        }
      }
      return high - low
    }
    let during = try bottomSpread(at: 0.7), after = try bottomSpread(at: 1.7)
    if !(during > 120 && after < 30) { throw DiagnosticFailure(description: "the subtitle shows only during its time (\(during), \(after))") }
    let editor = SubtitleEditor(url: source, controller: self)
    editor.setCues(cues)
    editor.saveSRT()
    let written2 = try String(contentsOf: source.deletingPathExtension().appendingPathExtension("srt"), encoding: .utf8)
    if !(written2.contains("00:00:00,200 --> 00:00:01,200") && FileManager.default.fileExists(atPath: editor.sidecar.path)) {
      throw DiagnosticFailure(description: "SRT and the editable subtitle list are saved")
    }
    editor.show()
    // Main-actor tasks cannot run inside this synchronous test, so give the editor the size directly.
    if let track = AVURLAsset(url: source).tracks(withMediaType: .video).first { editor.videoSize = track.naturalSize }
    let before = editor.cues.count
    editor.entry.stringValue = "직접 쓴 자막"
    editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: editor.entry))
    let shown = editor.stage.videoRect
    if editor.preview.isHidden || shown.isEmpty || !shown.insetBy(dx: -1, dy: -1).contains(editor.preview.frame) {
      throw DiagnosticFailure(description: "typed subtitle preview sits inside the video (\(editor.preview.frame) in \(shown))")
    }
    // Drag the subtitle up and to the left, then pull its corner out to make it bigger.
    func stageEvent(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent {
      NSEvent.mouseEvent(
        with: type, location: editor.stage.convert(p, to: nil), modifierFlags: [], timestamp: 0,
        windowNumber: editor.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    let boxBefore = editor.preview.frame
    let grab = CGPoint(x: boxBefore.midX, y: boxBefore.midY)
    editor.stage.mouseDown(with: stageEvent(.leftMouseDown, grab))
    editor.stage.mouseDragged(with: stageEvent(.leftMouseDragged, CGPoint(x: grab.x - 40, y: grab.y + 60)))
    editor.stage.mouseUp(with: stageEvent(.leftMouseUp, CGPoint(x: grab.x - 40, y: grab.y + 60)))
    let movedBox = editor.preview.frame
    if !(abs(movedBox.midX - (boxBefore.midX - 40)) < 2 && abs(movedBox.midY - (boxBefore.midY + 60)) < 2 && preferences.subtitleStyle == editor.style) {
      throw DiagnosticFailure(description: "dragging the subtitle moves it and remembers the place (\(boxBefore) → \(movedBox))")
    }
    let corner = CGPoint(x: editor.stage.handle.midX, y: editor.stage.handle.midY)
    let oldSize = editor.style.size
    editor.stage.mouseDown(with: stageEvent(.leftMouseDown, corner))
    editor.stage.mouseDragged(with: stageEvent(.leftMouseDragged, CGPoint(x: corner.x + 60, y: corner.y - 20)))
    editor.stage.mouseUp(with: stageEvent(.leftMouseUp, CGPoint(x: corner.x + 60, y: corner.y - 20)))
    if !(editor.style.size > oldSize && editor.preview.frame.width > movedBox.width) {
      throw DiagnosticFailure(description: "dragging the corner makes the subtitle bigger")
    }
    preferences.subtitleStyle = nil
    // 내 영상 lists saved videos, newest first, and says what each one is.
    try? FileManager.default.createDirectory(at: capturesFolder, withIntermediateDirectories: true)
    let listed = capturesFolder.appendingPathComponent("YelPoint-phone-video-selftest.mp4")
    try? FileManager.default.removeItem(at: listed)
    try FileManager.default.copyItem(at: source, to: listed)
    let library = VideoLibrary(controller: self)
    library.reload()
    library.window.setFrame(CGRect(x: 0, y: 0, width: 660, height: 540), display: true)
    if let view = library.window.contentView, let shot = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
      view.cacheDisplay(in: view.bounds, to: shot)
      try? shot.representation(using: .png, properties: [:])?.write(to: storage.root.appendingPathComponent("video-library.png"))
    }
    let found = library.videos.first == listed && videoKind(listed.lastPathComponent) == tr("폰에서 가져온 영상", "From the phone")
    library.window.close()
    try? FileManager.default.removeItem(at: listed)
    if !found { throw DiagnosticFailure(description: "내 영상 lists the newest saved video first") }
    editor.commitEntry()
    if !(editor.cues.count == before + 1 && editor.cues.contains { $0.text == "직접 쓴 자막" && $0.end > $0.start } && editor.entry.stringValue.isEmpty) {
      throw DiagnosticFailure(description: "typing under the video and pressing Enter adds a line")
    }
    editor.player.pause()
    if let view = editor.window.contentView, let shot = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
      view.cacheDisplay(in: view.bounds, to: shot)
      try? shot.representation(using: .png, properties: [:])?.write(to: storage.root.appendingPathComponent("subtitle-editor.png"))
    }
    editor.window.close()
    for url in [source, output, source.deletingPathExtension().appendingPathExtension("srt"), editor.sidecar] { try? FileManager.default.removeItem(at: url) }
  }
  private func recorderWritesVideo() throws {
    let url = storage.root.appendingPathComponent("recorder-self-test.mp4")
    try? FileManager.default.removeItem(at: url)
    let active = ScreenRecorder()
    try active.prepare(url: url, width: 64, height: 48, audio: true)
    var pixels: CVPixelBuffer?
    CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32BGRA, nil, &pixels)
    var format: CMVideoFormatDescription?
    guard let pixels,
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: nil, imageBuffer: pixels, formatDescriptionOut: &format) == noErr, let format
    else { throw DiagnosticFailure(description: "recorder test frame") }
    for _ in 0..<8 {
      var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30),
        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
        decodeTimeStamp: .invalid)
      var sample: CMSampleBuffer?
      CMSampleBufferCreateReadyWithImageBuffer(
        allocator: nil, imageBuffer: pixels, formatDescription: format, sampleTiming: &timing,
        sampleBufferOut: &sample)
      if let sample { active.append(sample) }
      active.appendAudio(try silence())
      Thread.sleep(forTimeInterval: 0.03)
    }
    let done = DispatchSemaphore(value: 0)
    var outcome: Result<URL, Error>?
    active.stop {
      outcome = $0
      done.signal()
    }
    guard done.wait(timeout: .now() + 10) == .success, case .success? = outcome else {
      throw DiagnosticFailure(description: "recorder finishes MP4")
    }
    let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber) ?? 0
    if size.intValue < 200 { throw DiagnosticFailure(description: "MP4 has content") }
    let asset = AVURLAsset(url: url)
    if asset.tracks(withMediaType: .video).count != 1 || asset.tracks(withMediaType: .audio).count != 1 {
      throw DiagnosticFailure(description: "MP4 has video and audio tracks")
    }
    try FileManager.default.removeItem(at: url)
  }

  /// Silent PCM in the same format the microphone output is configured to deliver.
  private func silence() throws -> CMSampleBuffer {
    var description = AudioStreamBasicDescription(
      mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
      mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
      mBitsPerChannel: 16, mReserved: 0)
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(
      allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0,
      magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
    let frames = 1440
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(
      allocator: nil, memoryBlock: nil, blockLength: frames * 2, blockAllocator: nil,
      customBlockSource: nil, offsetToData: 0, dataLength: frames * 2,
      flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
    guard let format, let block,
      CMBlockBufferFillDataBytes(
        with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: frames * 2) == noErr
    else { throw DiagnosticFailure(description: "recorder test audio") }
    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 48000),
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
    var size = 2
    var sample: CMSampleBuffer?
    CMSampleBufferCreate(
      allocator: nil, dataBuffer: block, dataReady: true, makeDataReadyCallback: nil,
      refcon: nil, formatDescription: format, sampleCount: frames, sampleTimingEntryCount: 1,
      sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
      sampleBufferOut: &sample)
    guard let sample else { throw DiagnosticFailure(description: "recorder test audio sample") }
    return sample
  }

  private func renderOwnViews() throws {
    let destination = storage.root.appendingPathComponent("macos-native-ui.png")
    preferences.highlight = true
    pen = true
    dockView.refresh()
    penView.refresh()
    settingsView.refresh()
    timerView.refresh()
    captureView.refresh()
    colorView.sync()
    spotView.refresh()
    zoomView.refresh()
    phoneView.refresh()
    let views: [NSView] = [
      dockView, penView, settingsView, timerView, captureView, colorView, spotView, zoomView, phoneView,
    ]
    let snapshots = try views.map { view -> NSBitmapImageRep in
      view.layoutSubtreeIfNeeded()
      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw DiagnosticFailure(description: "native view bitmap")
      }
      view.cacheDisplay(in: view.bounds, to: bitmap)
      return bitmap
    }
    let canvas = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 1340, pixelsHigh: 450,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
    Look.paper.setFill()
    CGRect(x: 0, y: 0, width: 1340, height: 450).fill()
    let rects = [
      CGRect(x: 35, y: 370, width: DockView.wide.width, height: DockView.wide.height),
      CGRect(x: 83, y: 175, width: 407, height: 48),
      CGRect(x: 810, y: 60, width: 286, height: 261),
      CGRect(x: 35, y: 115, width: 388, height: 48),
      CGRect(x: 35, y: 55, width: 516, height: 48),
      CGRect(x: 1115, y: 60, width: 196, height: 232),
      CGRect(x: 430, y: 5, width: 360, height: 48),
      CGRect(x: 430, y: 115, width: 286, height: 48),
      CGRect(x: 35, y: 250, width: PhoneView.size.width, height: PhoneView.size.height),
    ]
    for (snapshot, rect) in zip(snapshots, rects) {
      let image = NSImage(size: rect.size)
      image.addRepresentation(snapshot)
      image.draw(in: rect)
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = canvas.representation(using: .png, properties: [:]) else {
      throw DiagnosticFailure(description: "native preview encoding")
    }
    try png.write(to: destination)
    print("Native view preview: \(destination.path)")
  }
}

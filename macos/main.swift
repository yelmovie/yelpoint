import AppKit

if CommandLine.arguments.contains("--self-test") {
  var p = Preferences()
  p.penColor = 99
  p.penWidth = 100
  p.zoom = 0
  p.validate()
  precondition(p.penColor == 2 && p.penWidth == 4 && p.zoom == 1.5)
  let now = ProcessInfo.processInfo.systemUptime
  let stroke = InkStroke(points: [.zero], color: .red, width: 4, created: now, expires: true)
  precondition(stroke.alpha(at: now) == 1 && stroke.alpha(at: now + 5) == 0)
  precondition(stroke.alpha(at: now + 10, inProgress: true) == 1)
  let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
  precondition(screen.contains(clampedLens(center: CGPoint(x: -5, y: 5), screen: screen)))
  for frame in [
    screen, CGRect(x: 0, y: -1200, width: 1600, height: 1200),
    CGRect(x: -50, y: -50, width: 180, height: 120),
  ] {
    for point in [
      frame.origin, CGPoint(x: frame.maxX, y: frame.maxY),
      CGPoint(x: frame.midX, y: frame.midY),
    ] {
      precondition(frame.contains(clampedLens(center: point, screen: frame)))
    }
  }
  let visible = CGRect(x: -1920, y: 20, width: 1920, height: 1060)
  let child = CGSize(width: 286, height: 231)
  let origin = clampedChildOrigin(
    toolbar: CGRect(x: -200, y: 1030, width: 358, height: 62),
    child: child, visible: visible)
  precondition(visible.contains(CGRect(origin: origin, size: child)))
  let encoded = try JSONEncoder().encode(p)
  let decoded = try JSONDecoder().decode(Preferences.self, from: encoded)
  precondition(decoded.penColor == p.penColor && decoded.zoom == p.zoom)
  let older = try JSONDecoder().decode(
    Preferences.self,
    from: Data(
      #"{"highlight":false,"fadingInk":false,"keyboardHUD":false,"spotlight":false,"penColor":1,"penWidth":7,"zoom":2}"#
        .utf8))
  precondition(!older.highlight && older.penColor == 1 && older.pointerRadius == 16)
  precondition(penWidth(atFraction: -1) == 1 && penWidth(atFraction: 2) == 30)
  precondition(penWidth(atFraction: 0.5) == 16)
  var thick = Preferences()
  thick.penWidth = 23
  thick.validate()
  precondition(thick.penWidth == 23)
  var pointer = Preferences()
  pointer.resizePointer(steps: 100)
  precondition(pointer.pointerRadius == 48)
  pointer.resizePointer(steps: -100)
  precondition(pointer.pointerRadius == 6)
  pointer.inkRGB = 0x1000000
  pointer.validate()
  precondition(pointer.inkRGB == nil)
  precondition(hsvToRGB(hue: 0, saturation: 1, value: 1) == 0xFF0000)
  precondition(hsvToRGB(hue: 1.0 / 3, saturation: 1, value: 1) == 0x00FF00)
  precondition(hsvToRGB(hue: 2.0 / 3, saturation: 1, value: 0.5) == 0x000080)
  precondition(hsvToRGB(hue: 0.4, saturation: 0, value: 1) == 0xFFFFFF)
  let rim = wheelPick(dx: 0, dy: -200, radius: 100)
  precondition(rim.hue == 0.75 && rim.saturation == 1)
  var dimming = Preferences()
  dimming.resizeDimming(steps: -1)
  precondition(dimming.dimmingRadius == 97)
  dimming.resizeDimming(steps: -100)
  precondition(dimming.dimmingRadius == 30)
  dimming.resizeDimming(steps: 1000)
  precondition(dimming.dimmingRadius == 400)
  let desk = CGRect(x: 0, y: 40, width: 1920, height: 1040)
  let bar = CGSize(width: 676, height: 62)
  precondition(clampedOrigin(CGPoint(x: -500, y: -500), size: bar, visible: desk) == CGPoint(x: 0, y: 40))
  precondition(clampedOrigin(CGPoint(x: 5000, y: 5000), size: bar, visible: desk) == CGPoint(x: 1244, y: 1018))
  precondition(clampedOrigin(CGPoint(x: 300, y: 400), size: bar, visible: desk) == CGPoint(x: 300, y: 400))
  let high = clampedChildOrigin(
    toolbar: CGRect(x: 300, y: 1018, width: 676, height: 62), child: CGSize(width: 388, height: 48),
    visible: desk)
  precondition(high.y + 48 <= 1018)
  let flat = CGRect(x: 600, y: 300, width: 676, height: 62)
  precondition(toolbarEdge(frame: flat, pointerX: 30, visible: desk) == -1)
  precondition(toolbarEdge(frame: flat, pointerX: 1890, visible: desk) == 1)
  precondition(toolbarEdge(frame: flat, pointerX: 960, visible: desk) == 0)
  // Held by its left end: the bar touches the right edge with the pointer far away.
  let touching = CGRect(x: 1244, y: 159, width: 676, height: 62)
  precondition(toolbarEdge(frame: touching, pointerX: 1260, visible: desk) == 1)
  precondition(toolbarEdge(frame: CGRect(x: 0, y: 159, width: 676, height: 62), pointerX: 660, visible: desk) == -1)
  precondition(toolbarEdge(frame: CGRect(x: 8, y: 300, width: 104, height: 356), pointerX: 60, visible: desk) == -1)
  precondition(toolbarEdge(frame: CGRect(x: 200, y: 300, width: 104, height: 356), pointerX: 250, visible: desk) == 0)
  precondition(!toolbarLiesFlat(side: 1, flipX: 1260, pointerX: 1200))
  precondition(toolbarLiesFlat(side: 1, flipX: 1260, pointerX: 1140))
  precondition(!toolbarLiesFlat(side: 1, flipX: 1260, pointerX: 1900))
  precondition(toolbarLiesFlat(side: -1, flipX: 30, pointerX: 150))
  let released = flatToolbarOrigin(pointer: CGPoint(x: 150, y: 500), size: bar, visible: desk)
  precondition(toolbarEdge(frame: CGRect(origin: released, size: bar), pointerX: 150, visible: desk) == 0)
  let releasedRight = flatToolbarOrigin(pointer: CGPoint(x: 1770, y: 500), size: bar, visible: desk)
  precondition(toolbarEdge(frame: CGRect(origin: releasedRight, size: bar), pointerX: 1770, visible: desk) == 0)
  let beside = clampedSideOrigin(
    toolbar: CGRect(x: 8, y: 300, width: 104, height: 356), child: CGSize(width: 388, height: 48),
    visible: desk)
  precondition(beside.x == 116 && beside.y == 454)
  let opened = clampedSideOrigin(
    toolbar: CGRect(x: 8, y: 300, width: 104, height: 356), child: CGSize(width: 140, height: 120),
    visible: desk, opener: CGRect(x: 14, y: 560, width: 80, height: 43))
  precondition(opened.x == 116 && opened.y + 120 == 603)
  let besideRight = clampedSideOrigin(
    toolbar: CGRect(x: 1808, y: 300, width: 104, height: 356), child: CGSize(width: 388, height: 48),
    visible: desk)
  precondition(besideRight.x + 388 <= 1808)
  let box = CGRect(x: 100, y: 100, width: 200, height: 100)
  let grown = spotScaled(box, steps: 2)
  precondition(abs(grown.width - 220) < 0.01 && abs(grown.height - 110) < 0.01)
  precondition(abs(grown.midX - box.midX) < 0.01 && abs(grown.midY - box.midY) < 0.01)
  precondition(abs(min(spotScaled(box, steps: -100).width, spotScaled(box, steps: -100).height) - 24) < 0.01)
  precondition(spotHandle(at: CGPoint(x: 301, y: 201), shape: .rectangle, rect: box) == 4)
  precondition(spotHandle(at: CGPoint(x: 200, y: 100), shape: .rectangle, rect: box) == 1)
  precondition(spotHandle(at: CGPoint(x: 200, y: 150), shape: .rectangle, rect: box) == nil)
  precondition(spotHandle(at: CGPoint(x: 300, y: 150), shape: .ellipse, rect: box) == 3)
  precondition(spotHandle(at: CGPoint(x: 200, y: 100), shape: .ellipse, rect: box) == 1)
  precondition(spotHandle(at: CGPoint(x: 200, y: 150), shape: .ellipse, rect: box) == nil)
  precondition(
    spotResized(box, handle: 3, to: CGPoint(x: 500, y: 150), square: false)
      == CGRect(x: 100, y: 100, width: 400, height: 100))
  precondition(spotResized(box, handle: 3, to: CGPoint(x: 0, y: 0), square: false).width == 24)
  let round = CGRect(x: 100, y: 100, width: 100, height: 100)
  precondition(
    spotResized(round, handle: 3, to: CGPoint(x: 160, y: 150), square: true)
      == CGRect(x: 100, y: 120, width: 60, height: 60))
  let corner = spotResized(round, handle: 4, to: CGPoint(x: 400, y: 220), square: true)
  precondition(corner.width == corner.height && corner.width == 300 && corner.minX == 100)
  let circle = spotRect(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 10, y: 80), square: true)
  precondition(circle == CGRect(x: 10, y: 50, width: 40, height: 40))
  precondition(spotContains(.ellipse, rect: box, point: CGPoint(x: 200, y: 150)))
  precondition(!spotContains(.ellipse, rect: box, point: CGPoint(x: 105, y: 105)))
  precondition(spotContains(.rectangle, rect: box, point: CGPoint(x: 105, y: 105)))
  var zoomed = Preferences()
  zoomed.zoom = 9
  zoomed.validate()
  precondition(zoomed.zoom == 5 && Preferences().zoom == 2 && zoomLevels.last == 5)
  precondition(tr("가", "a") == "가")
  appEnglish = true
  precondition(tr("가", "a") == "a")
  appEnglish = false
  precondition(blogURL.host == "blog.naver.com" && blogURL.query?.contains("blogId=yelsam_lab") == true)
  precondition(scrcpyArguments(serial: "A", mode: .screen, rotation: 0, light: false, title: "T", record: "/x/p.mp4").last == "--record=/x/p.mp4")
  precondition(!scrcpyArguments(serial: "A", mode: .screen, rotation: 0, light: false, title: "T").contains { $0.hasPrefix("--record") })
  precondition(suggestURL.scheme == "mailto" && suggestURL.absoluteString.hasPrefix("mailto:bongbiyobi@gmail.com?subject="))
  var countdown = Countdown()
  countdown.set(minutes: 99)
  precondition(countdown.minutes == 60)
  countdown.set(minutes: 0)
  precondition(countdown.minutes == 1)
  countdown.set(minutes: 60)
  countdown.startOrPause(now: 100)
  precondition(countdown.badge(now: 100)?.text == "60:00")
  precondition(countdown.badge(now: 100.5)?.text == "60:00")
  precondition(countdown.badge(now: 101)?.text == "59:59")
  countdown.set(minutes: 5)
  precondition(countdown.minutes == 60)
  countdown.startOrPause(now: 160)
  precondition(countdown.badge(now: 900)?.text == "59:00" && !countdown.update(now: 9000))
  countdown.startOrPause(now: 1000)
  precondition(!countdown.update(now: 4539) && countdown.update(now: 4540))
  let style = SubtitleStyle()
  precondition(videoKind("YelPoint-phone-video-a.mp4") == "폰에서 가져온 영상" && videoKind("YelPoint-phone-20261108-1.mp4") == "폰 화면 녹화"
    && videoKind("YelPoint-20261108-1.subtitled.mp4") == "자막 넣은 영상" && videoKind("YelPoint-20261108-1.mp4") == "화면 녹화" && videoKind("x.mp4") == "영상")
  precondition(style.frame(box: CGSize(width: 200, height: 40), in: CGSize(width: 1000, height: 500)) == CGRect(x: 400, y: 30, width: 200, height: 40))
  precondition(SubtitleStyle(size: 0.04, x: 0.99, y: 0.99).frame(box: CGSize(width: 200, height: 40), in: CGSize(width: 1000, height: 500)) == CGRect(x: 800, y: 460, width: 200, height: 40))
  let moved = style.centred(at: CGPoint(x: 250, y: 400), box: CGSize(width: 200, height: 40), in: CGSize(width: 1000, height: 500))
  precondition(moved.frame(box: CGSize(width: 200, height: 40), in: CGSize(width: 1000, height: 500)) == CGRect(x: 150, y: 380, width: 200, height: 40))
  let gallery = phoneVideos(fromContentQuery: """
Row: 0 _display_name=a, b.mp4, _data=/storage/emulated/0/DCIM/Camera/a, b.mp4, date_added=1793961854, _size=12299884, duration=5707
Row: 1 _display_name=new.mp4, _data=/storage/emulated/0/Movies/new.mp4, date_added=1793999999, _size=63007066, duration=NULL
junk line
""")
  precondition(gallery.count == 2 && gallery[0].name == "new.mp4" && gallery[1].path.hasSuffix("/a, b.mp4") && gallery[1].seconds == 5.707 && gallery[0].seconds == 0)
  precondition(phoneVideoLabel(gallery[1]).hasSuffix(" · 6초 · 12MB"))
  precondition(countdown.badge(now: 4540.2)?.text == "시간 끝!" && countdown.popProgress(now: 4540.2) == 0)
  precondition(!countdown.update(now: 4544) && countdown.badge(now: 4544)?.text == "시간 끝!")
  precondition((countdown.popProgress(now: 4545.2) ?? 0) > 0)
  precondition(!countdown.update(now: 4546) && !countdown.isActive && countdown.badge(now: 4546) == nil)
  let big = resizedClock(CGRect(x: 100, y: 100, width: 196, height: 76), dx: 196)
  precondition(big.width == 392 && big.height == 152 && big.maxY == 176)
  precondition(resizedClock(big, dx: -10000).width == 118 && resizedClock(big, dx: 10000).width == 1176)
  precondition(!countdown.update(now: 4548) && !countdown.isActive)
  precondition(stickerSize(CGSize(width: 2000, height: 500), limit: CGSize(width: 1000, height: 800))
    == CGSize(width: 1000, height: 250))
  precondition(stickerSize(CGSize(width: 200, height: 100), limit: CGSize(width: 1000, height: 800))
    == CGSize(width: 200, height: 100))
  let recording = recordingSize(CGSize(width: 5121, height: 2881))
  precondition(recording.width == 3840 && recording.height % 2 == 0)
  precondition(
    mediaFileName(extension: "png", date: Date(timeIntervalSince1970: 0)).hasPrefix("YelPoint-19"))
  precondition(phoneState(fromADB: "List of devices attached\n") == .none)
  precondition(phoneState(fromADB: "List of devices attached\nR5CT1 unauthorized usb:1-1 transport_id:1\n") == .unauthorized)
  precondition(
    phoneState(fromADB: "List of devices attached\nR5CT1 unauthorized usb:1-1\nR3CW9 device usb:1-2 product:dm3q model:SM_S918N device:dm3q transport_id:2\n")
      == .ready(serial: "R3CW9", name: "SM S918N"))
  precondition(phoneState(fromADB: "* daemon started successfully\nList of devices attached\nX offline\n") == .offline)
  let cameraArgs = scrcpyArguments(serial: "R3CW9", mode: .camera, rotation: -90, light: true, title: "t")
  precondition(cameraArgs.contains("--video-source=camera") && cameraArgs.contains("--camera-torch")
    && cameraArgs.contains("--display-orientation=270") && cameraArgs.contains("--no-audio"))
  let screenArgs = scrcpyArguments(serial: "R3CW9", mode: .screen, rotation: 450, light: true, title: "t")
  precondition(screenArgs.contains("--display-orientation=90") && !screenArgs.contains("--camera-torch")
    && screenArgs.contains("--stay-awake"))
  print("PASS: phone detection and scrcpy arguments")
  let words: [(text: String, start: Double, duration: Double)] = [
    ("안녕하세요", 0.2, 0.6), ("오늘은", 0.9, 0.4), ("태양계를", 1.4, 0.5), ("배워요", 2.0, 0.5),
    ("지구는", 4.0, 0.4), ("세", 4.5, 0.2), ("번째", 4.8, 0.3), ("행성이에요", 5.2, 0.6),
  ]
  let cues = cuesFromWords(words, maxCharacters: 12)
  precondition(cues.map(\.text) == ["안녕하세요 오늘은", "태양계를 배워요", "지구는 세 번째", "행성이에요"] && cues[2].start == 4.0)
  precondition(cues[0].end == cues[1].start && cue(at: 4.3, in: cues)?.text == "지구는 세 번째" && cue(at: 3.6, in: cues) == nil)
  precondition(srt([Cue(start: 61.5, end: 63, text: "가")]) == "1\n00:01:01,500 --> 00:01:03,000\n가\n")
  print("PASS: subtitle lines and SRT")
  print("PASS: preferences, fading ink, multi-display lens bounds, JSON round trip, older settings, pointer size, color wheel, spot geometry, toolbar bounds, 60-minute countdown, sticker and recording sizes")
  exit(0)
}

do {
  let storage = try PortableStorage()
  let app = NSApplication.shared
  if let bundle = Bundle.main.bundleIdentifier,
    let other = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first(
      where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier })
  {
    other.activate(options: [.activateAllWindows])
    exit(0)
  }
  let controller = AppController(storage: storage)
  app.delegate = controller
  app.run()
  withExtendedLifetime(controller) {}
  if controller.diagnosticExitCode != 0 { exit(controller.diagnosticExitCode) }
} catch {
  if CommandLine.arguments.contains("--smoke-test")
    || CommandLine.arguments.contains("--ui-self-test")
  {
    fputs("YelPoint diagnostic startup failed: \(error.localizedDescription)\n", stderr)
    exit(1)
  }
  let app = NSApplication.shared
  app.setActivationPolicy(.regular)
  let alert = NSAlert()
  alert.messageText = "YelPoint를 시작하지 못했어요 / YelPoint could not start"
  alert.informativeText = error.localizedDescription
  alert.runModal()
  exit(1)
}

import AppKit

/// Shows an Android phone or tablet plugged in over USB, either its screen or its back
/// camera as a document camera. Runs the bundled scrcpy and adb (Apache 2.0,
/// see THIRD-PARTY-NOTICES.txt). Their keys, logs and temp files live in YelPoint's data folder.
final class PhoneLink {
  private let tools: URL?
  private let environment: [String: String]
  private var watcher: Timer?
  private var polling = false
  private var adbStarted = false
  private var startedAt = Date.distantPast
  private(set) var state: PhoneState = .none
  private(set) var mirror: Process?
  private(set) var mode: PhoneMode = .screen
  var rotation = 0
  var light = false
  var onChange: (() -> Void)?
  /// Called when the scrcpy window closes by itself. `early` means it never really started.
  var onClosed: ((_ early: Bool) -> Void)?
  /// Called once a phone recording is finished and its MP4 is complete.
  var onRecorded: ((URL) -> Void)?
  /// The MP4 the running scrcpy is recording to, if any.
  private(set) var recordingURL: URL?
  var recording: Bool { recordingURL != nil && running }

  init(storage: PortableStorage) {
    // adb and scrcpy are signed helpers in Contents/Helpers; the server jar is a resource.
    tools = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
    let home = storage.root.appendingPathComponent("android", isDirectory: true)
    let temp = home.appendingPathComponent("tmp", isDirectory: true)
    try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    var env = ProcessInfo.processInfo.environment
    // adb keeps its key in $HOME/.android and its log in $TMPDIR.
    env["HOME"] = home.path
    env["ANDROID_USER_HOME"] = home.appendingPathComponent(".android").path
    env["TMPDIR"] = temp.path + "/"
    if let tools {
      env["ADB"] = tools.appendingPathComponent("adb").path
      env["SCRCPY_SERVER_PATH"] = Bundle.main.url(forResource: "scrcpy-server", withExtension: nil)?.path
    }
    environment = env
  }
  var available: Bool {
    guard let tools else { return false }
    return FileManager.default.isExecutableFile(atPath: tools.appendingPathComponent("scrcpy").path)
  }
  var running: Bool { mirror?.isRunning == true }
  var isWatching: Bool { watcher != nil }

  func watch(_ on: Bool) {
    if on, watcher == nil, available {
      poll()
      watcher = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
    } else if !on, let watcher {
      watcher.invalidate()
      self.watcher = nil
    }
  }
  private func poll() {
    guard !polling, let tools else { return }
    polling = true
    adbStarted = true
    let env = environment
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let output = PhoneLink.run(tools.appendingPathComponent("adb"), ["devices", "-l"], env)
      DispatchQueue.main.async {
        guard let self else { return }
        self.polling = false
        let next = phoneState(fromADB: output ?? "")
        if next != self.state {
          self.state = next
          self.onChange?()
        }
      }
    }
  }
  /// The phone's gallery videos, newest first. nil when no phone is ready or adb fails.
  func listVideos(_ done: @escaping ([PhoneVideo]?) -> Void) {
    guard case .ready(let serial, _) = state, let tools else { return done(nil) }
    let env = environment
    DispatchQueue.global(qos: .userInitiated).async {
      let output = PhoneLink.run(
        tools.appendingPathComponent("adb"),
        ["-s", serial, "shell", "content", "query", "--uri", "content://media/external/video/media",
         "--projection", "_display_name:_data:date_added:_size:duration"], env)
      DispatchQueue.main.async { done(output.map { Array(phoneVideos(fromContentQuery: $0).prefix(60)) }) }
    }
  }
  /// Copies one gallery video to `target` unchanged. Skips the copy when the same file is already there.
  func pull(_ video: PhoneVideo, to target: URL, _ done: @escaping (Bool) -> Void) {
    guard case .ready(let serial, _) = state, let tools else { return done(false) }
    let size = (try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int64) ?? nil
    if size == video.bytes { return done(true) }
    let env = environment
    DispatchQueue.global(qos: .userInitiated).async {
      let partial = target.appendingPathExtension("part")
      try? FileManager.default.removeItem(at: partial)
      _ = PhoneLink.run(tools.appendingPathComponent("adb"), ["-s", serial, "pull", video.path, partial.path], env)
      let info = try? FileManager.default.attributesOfItem(atPath: partial.path)
      let got = info?[.size] as? Int64
      // A phone path that is really a folder pulls a whole folder; only a plain file counts.
      var ok = info?[.type] as? FileAttributeType == .typeRegular && got != nil && got! > 0
      if ok {
        try? FileManager.default.removeItem(at: target)
        ok = (try? FileManager.default.moveItem(at: partial, to: target)) != nil
      } else {
        try? FileManager.default.removeItem(at: partial)
      }
      DispatchQueue.main.async { done(ok) }
    }
  }
  /// Runs the bundled adb once and waits for it. Used by the self-test.
  func adb(_ args: [String]) -> String? {
    guard let tools else { return nil }
    adbStarted = true
    return PhoneLink.run(tools.appendingPathComponent("adb"), args, environment)
  }
  var adbLogFolder: URL? { environment["TMPDIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } }
  private static func run(_ tool: URL, _ args: [String], _ env: [String: String]) -> String? {
    let task = Process()
    task.executableURL = tool
    task.arguments = args
    task.environment = env
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return String(data: data, encoding: .utf8)
  }

  @discardableResult func start(_ mode: PhoneMode, record: URL? = nil) -> Bool {
    guard case .ready(let serial, let name) = state, let tools else { return false }
    stop(notify: false)
    self.mode = mode
    let task = Process()
    task.executableURL = tools.appendingPathComponent("scrcpy")
    let title = mode == .screen ? "YelPoint · \(name)" : tr("YelPoint · 실물화상기", "YelPoint · Document camera")
    task.arguments = scrcpyArguments(serial: serial, mode: mode, rotation: rotation, light: light, title: title, record: record?.path)
    task.environment = environment
    task.standardOutput = FileHandle.nullDevice
    let log = URL(fileURLWithPath: environment["TMPDIR"] ?? NSTemporaryDirectory()).appendingPathComponent("scrcpy.log")
    FileManager.default.createFile(atPath: log.path, contents: nil)
    task.standardError = (try? FileHandle(forWritingTo: log)) ?? FileHandle.nullDevice
    task.terminationHandler = { [weak self] finished in
      DispatchQueue.main.async {
        guard let self, self.mirror === finished else { return }
        self.mirror = nil
        // The window was closed while recording: scrcpy has already finished the file.
        if let url = self.recordingURL {
          self.recordingURL = nil
          self.onRecorded?(url)
        }
        self.onClosed?(Date().timeIntervalSince(self.startedAt) < 5)
        self.onChange?()
      }
    }
    do { try task.run() } catch { return false }
    mirror = task
    recordingURL = record
    startedAt = Date()
    onChange?()
    return true
  }
  func restart() {
    guard running else { return }
    start(mode)
  }
  func stop(notify: Bool = true) {
    let task = mirror
    mirror = nil
    if task?.isRunning == true { task?.terminate() }
    if let task, let url = recordingURL {
      recordingURL = nil
      finish(task, url)
    }
    if notify { onChange?() }
  }
  /// Ends the recording and keeps showing the phone. scrcpy writes the end of the MP4 as it quits,
  /// so the window reopens only after it has exited (the camera cannot be opened twice).
  func stopRecording() {
    guard let task = mirror, let url = recordingURL else { return }
    let mode = self.mode
    mirror = nil
    recordingURL = nil
    if task.isRunning { task.terminate() }
    onChange?()
    finish(task, url) { [weak self] in self?.start(mode) }
  }
  private func finish(_ task: Process, _ url: URL, then next: (() -> Void)? = nil) {
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      task.waitUntilExit()
      DispatchQueue.main.async {
        self?.onRecorded?(url)
        next?()
      }
    }
  }
  /// The scrcpy window's content area in AppKit screen coordinates, without its title bar.
  func windowFrame() -> CGRect? {
    guard let pid = mirror?.processIdentifier,
      let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]],
      let main = NSScreen.screens.first
    else { return nil }
    for window in list where (window[kCGWindowOwnerPID as String] as? Int).map(pid_t.init) == pid {
      guard let dict = window[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: dict), bounds.width > 80, bounds.height > 80
      else { continue }
      let titleBar: CGFloat = 28
      return CGRect(
        x: bounds.minX, y: main.frame.maxY - bounds.maxY,
        width: bounds.width, height: bounds.height - titleBar)
    }
    return nil
  }
  func shutdown() {
    // Give a recording a moment to be written before the app quits.
    let task = recording ? mirror : nil
    stop(notify: false)
    if let task {
      let deadline = Date().addingTimeInterval(4)
      while task.isRunning && Date() < deadline { usleep(50_000) }
    }
    watch(false)
    guard adbStarted, let tools else { return }
    _ = PhoneLink.run(tools.appendingPathComponent("adb"), ["kill-server"], environment)
  }
}

final class PhoneView: NSView {
  weak var controller: AppController?
  let status = NSTextField(labelWithString: "")
  private var auto: ToolButton!
  private var recordButton: ToolButton!
  private(set) var screenButton: ToolButton!
  private var cameraButton: ToolButton!
  private var rotateButton: ToolButton!
  private var lightButton: ToolButton!
  private var freezeButton: ToolButton!
  private var closeButton: ToolButton!
  private var importButton: ToolButton!
  static let size = CGSize(width: 790, height: 86)
  init(controller: AppController) {
    self.controller = controller
    super.init(frame: CGRect(origin: .zero, size: PhoneView.size))
    wantsLayer = true
    layer?.backgroundColor = Look.dock.cgColor
    layer?.cornerRadius = 14
    status.frame = CGRect(x: 14, y: 56, width: 566, height: 20)
    status.font = .systemFont(ofSize: 13, weight: .medium)
    status.textColor = Look.paper
    status.lineBreakMode = .byTruncatingTail
    addSubview(status)
    func add(_ x: CGFloat, _ width: CGFloat, _ title: String, _ symbol: String, _ tip: String, _ action: @escaping (AppController) -> Void) -> ToolButton {
      let b = ToolButton(frame: CGRect(x: x, y: 6, width: width, height: 40), title: title, symbol: symbol) {
        [weak controller] in
        if let controller { action(controller) }
      }
      b.toolTip = tip
      addSubview(b)
      return b
    }
    screenButton = add(8, 82, tr("화면", "Screen"), "candybarphone", tr("폰 화면 띄우기", "Show the phone screen")) { $0.showPhone(.screen) }
    cameraButton = add(92, 92, tr("카메라", "Camera"), "camera", tr("폰 카메라를 실물화상기로", "Use the phone camera as a document camera")) { $0.showPhone(.camera) }
    rotateButton = add(186, 82, tr("회전", "Rotate"), "rotate.right", tr("90도 돌리기", "Rotate 90°")) { $0.rotatePhone() }
    lightButton = add(270, 82, tr("조명", "Light"), "flashlight.on.fill", tr("카메라 플래시 켜고 끄기", "Turn the camera light on or off")) { $0.togglePhoneLight() }
    freezeButton = add(354, 82, tr("멈춤", "Freeze"), "pause.fill", tr("지금 장면을 멈춰 두고 그 위에 필기", "Freeze this view and write on it")) { $0.freezePhone() }
    recordButton = add(438, 82, tr("녹화", "Record"), "record.circle", tr("폰 화면만 MP4로 녹화", "Record just the phone to an MP4")) { $0.togglePhoneRecording() }
    closeButton = add(522, 82, tr("끄기", "Close"), "xmark", tr("폰 창 닫기", "Close the phone window")) { $0.closePhone() }
    importButton = add(606, 128, tr("영상 가져오기", "Get Videos"), "square.and.arrow.down", tr("폰 갤러리 영상을 원본 그대로 가져와서 자막 넣기", "Copy a gallery video from the phone and add subtitles")) { $0.showPhoneVideos() }
    _ = add(736, 46, "", "questionmark.circle", tr("처음 연결하는 방법", "How to connect the first time")) { $0.phoneHelp() }
    // A lime pill when on, so it reads at a glance on the dark panel.
    auto = ToolButton(
      frame: CGRect(x: 590, y: 50, width: 190, height: 30), title: tr("꽂으면 바로 띄우기", "Open when plugged in"), symbol: "circle"
    ) { [weak self] in self?.autoChanged() }
    auto.toolTip = tr("다음부터 케이블만 꽂으면 폰 화면이 바로 떠요", "Next time, the phone screen opens as soon as you plug in")
    addSubview(auto)
  }
  required init?(coder: NSCoder) { fatalError() }
  private func autoChanged() {
    guard let c = controller else { return }
    c.preferences.phoneAuto = c.preferences.phoneAuto != true
    c.preferencesChanged()
    refresh()
  }
  func refresh() {
    guard let c = controller, let link = c.phone else { return }
    var ready = false
    switch link.state {
    case _ where !link.available:
      status.stringValue = tr("폰 연결 도구를 찾지 못했어요. 앱을 다시 설치해 주세요.", "The phone tools are missing. Reinstall the app.")
    case .none:
      status.stringValue = tr("안드로이드 폰·태블릿을 USB 케이블로 꽂아 주세요. 처음이면 ?를 눌러 주세요.", "Plug in an Android phone or tablet. First time? Press ?.")
    case .unauthorized:
      status.stringValue = tr("폰에 뜬 ‘USB 디버깅 허용’에서 ‘허용’을 눌러 주세요.", "Tap Allow on the phone’s USB debugging prompt.")
    case .offline:
      status.stringValue = tr("연결을 확인하는 중이에요. 안 되면 케이블을 뺐다 꽂아 보세요.", "Checking the connection. If it hangs, replug the cable.")
    case .ready(_, let name):
      ready = true
      if link.recording {
        status.stringValue = tr("● 녹화 중 · 정지하면 ", "● Recording · Stop saves it to ") + c.storage.capturesLabel + tr("에 저장돼요", "")
      } else if link.running {
        status.stringValue = link.mode == .screen
          ? tr("\(name) 화면을 보여 주는 중이에요.", "Showing \(name).")
          : tr("카메라를 실물화상기로 쓰는 중이에요. 멈춤을 누르면 그 위에 필기할 수 있어요.", "Document camera on. Freeze to write on it.")
      } else {
        status.stringValue = tr("\(name) 연결됨 · 화면이나 카메라를 눌러 주세요.", "\(name) connected · choose Screen or Camera.")
      }
    }
    screenButton.isEnabled = ready
    cameraButton.isEnabled = ready
    screenButton.selected = link.running && link.mode == .screen
    cameraButton.selected = link.running && link.mode == .camera
    rotateButton.isEnabled = link.running
    freezeButton.isEnabled = link.running
    closeButton.isEnabled = link.running
    importButton.isEnabled = ready
    lightButton.isEnabled = link.running && link.mode == .camera
    lightButton.selected = link.light && link.mode == .camera && link.running
    let autoOn = c.preferences.phoneAuto == true
    auto.selected = autoOn
    auto.symbol = autoOn ? "checkmark.circle" : "circle"
    recordButton.isEnabled = link.running
    recordButton.selected = link.recording
    recordButton.title = link.recording ? tr("정지", "Stop") : tr("녹화", "Record")
    recordButton.symbol = link.recording ? "stop.fill" : "record.circle"
  }
}

extension AppController {
  func phoneChanged() {
    phoneView.refresh()
    dockView.refresh()
    // Only the moment a phone becomes ready (plugged in, or allowed) opens it by itself.
    // Closing the window, a recording ending or a cable on its way out never reopens it.
    var ready = false
    if case .ready = phone.state { ready = true }
    if ready, !phoneWasReady, preferences.phoneAuto == true, !phone.running, !phoneDismissed {
      showPhone(.screen)
    }
    phoneWasReady = ready
    if case .none = phone.state { phoneDismissed = false }
  }
  func showPhone(_ mode: PhoneMode) {
    if mode == .screen { phone.light = false }
    guard phone.start(mode) else {
      showMessage(tr("폰을 띄우지 못했어요", "Could not open the phone"), tr("케이블을 다시 꽂고 한 번 더 눌러 주세요.", "Replug the cable and try again."))
      return
    }
    phoneDismissed = false
    if preferences.phoneAuto == nil {
      preferences.phoneAuto = true
      preferencesChanged()
    }
    toast(mode == .screen ? tr("폰 화면을 띄웠어요", "Phone screen is open") : tr("실물화상기를 켰어요", "Document camera is on"))
  }
  func rotatePhone() {
    phone.rotation = (phone.rotation + 90) % 360
    phone.restart()
  }
  func togglePhoneLight() {
    phone.light.toggle()
    phone.restart()
  }
  func togglePhoneRecording() {
    if phone.recording {
      phone.stopRecording()
      return
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    try? FileManager.default.createDirectory(at: capturesFolder, withIntermediateDirectories: true)
    let url = capturesFolder.appendingPathComponent("YelPoint-phone-\(formatter.string(from: Date())).mp4")
    guard phone.start(phone.mode, record: url) else {
      showMessage(tr("녹화를 시작하지 못했어요", "Could not start recording"), tr("케이블을 다시 꽂고 한 번 더 눌러 주세요.", "Replug the cable and try again."))
      return
    }
    toast(tr("폰 화면 녹화를 시작했어요", "Recording the phone"))
  }
  func phoneRecorded(_ url: URL) {
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    guard size > 0 else {
      try? FileManager.default.removeItem(at: url)
      showMessage(tr("폰 녹화를 저장하지 못했어요", "Could not save the phone recording"), tr("폰 화면이 너무 짧게 열렸거나 연결이 끊겼어요. 다시 녹화해 주세요.", "The phone was open too briefly or got unplugged. Please record again."))
      return
    }
    toast(tr("폰 녹화를 저장했어요 · ", "Phone recording saved · ") + storage.capturesLabel)
    offerSubtitles(for: url)
  }
  func closePhone() {
    phoneDismissed = true
    phone.stop()
  }
  func phoneClosed(early: Bool) {
    // Closed with the window's own button counts as "not now", the same as 끄기.
    phoneDismissed = true
    guard early, phone.mode == .camera else {
      toast(tr("폰 창이 닫혔어요", "The phone window closed"))
      return
    }
    showMessage(
      tr("카메라를 열지 못했어요", "Could not open the camera"),
      tr("폰 카메라 연결은 안드로이드 12 이상에서 돼요. 다른 앱이 카메라를 쓰고 있으면 닫고 다시 눌러 주세요.",
        "Camera mode needs Android 12 or later. Close any app using the camera and try again."))
  }
  /// Pins the current phone view as a capture, so it can be written on and saved.
  func freezePhone() {
    guard ensureScreenAccess(), let frame = phone.windowFrame(),
      let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) })
    else { return }
    finishSelection(screen: screen, rect: frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY))
  }
  func phoneHelp() {
    guard !toolsSuspended else { return }
    let alert = NSAlert()
    alert.messageText = tr("안드로이드 폰·태블릿 처음 연결하기", "Connecting an Android phone or tablet")
    alert.addButton(withTitle: tr("연결 방법 보기", "Open Guide"))
    alert.addButton(withTitle: tr("확인", "OK"))
    alert.informativeText =
      tr(
        "★ 폰마다 설정 방법이 달라요. 아래대로 안 되면 ‘내 폰 이름 + USB 디버깅’(예: ‘갤럭시 Z폴드5 USB 디버깅’)으로 검색해 보세요.\n\n처음 한 번만 하면 돼요. 단, 개발자 옵션과 USB 디버깅은 켜 둔 채로 두세요. 아래는 갤럭시 기준이에요.\n\n1. 폰 설정 → 휴대전화 정보 → 소프트웨어 정보 → ‘빌드번호’를 7번 눌러 주세요. 화면은 그대로이고 ‘개발자 모드를 켰습니다’ 알림만 잠깐 떠요.\n2. 설정 첫 화면 맨 아래에 새로 생긴 ‘개발자 옵션’ → ‘USB 디버깅’을 켜 주세요.\n3. 폰 기본 케이블로 컴퓨터에 바로 꽂고, 폰에 뜬 ‘USB 디버깅 허용’에서 ‘항상 허용’을 눌러 주세요.\n\n그다음부터는 꽂기만 해도 폰 화면이 바로 떠요.\n\n안 될 때\n· USB 디버깅이 회색이면: 설정 → 보안 및 개인정보 보호 → ‘자동 차단’을 꺼 주세요.\n· 아무 반응이 없으면: 충전 전용 케이블이거나 허브·어댑터를 거친 경우예요. 폰 기본 케이블로 컴퓨터에 바로 꽂아 주세요.\n· 허용 창이 안 뜨면: 폰 잠금을 풀고 케이블을 뺐다 다시 꽂아 주세요.\n· 전에는 됐는데 다시 안 되면: 폰 잠금을 풀고 개발자 옵션 → USB 디버깅이 켜져 있는지 봐 주세요. 꺼져 있으면 다시 켜고 케이블을 다시 꽂은 뒤 ‘항상 허용’을 눌러 주세요.\n\n실물화상기: ‘카메라’를 누르고 폰을 거치대에 아래로 향하게 두세요. 회전·조명·멈춤으로 맞춰 주세요. 안드로이드 12 이상에서 돼요.\n학교에서 관리하는 기기는 개발자 옵션이 막혀 있을 수 있어요.\n\n사진과 함께 보는 자세한 방법은 옐샘 블로그에 있어요. ‘연결 방법 보기’를 눌러 주세요.",
        "★ Every phone sets this up a little differently. If these steps do not match, search for your phone's name plus \"USB debugging\" (for example \"Galaxy Z Fold5 USB debugging\").\n\nOnly once, as long as developer options and USB debugging stay on. These steps are for a Galaxy phone.\n\n1. Settings → About phone → Software information → tap Build number 7 times. The screen stays the same; a short note says developer mode is on.\n2. At the bottom of Settings, open the new Developer options → turn on USB debugging.\n3. Plug the phone straight into the computer with its own cable and tap Always allow on the phone.\n\nAfter that the screen opens as soon as you plug in.\n\nIf it does not work\n· USB debugging greyed out: Settings → Security and privacy → turn off Auto Blocker.\n· Nothing happens: the cable may be charge-only, or a hub or adapter is in the way. Plug straight in with the phone's own cable.\n· No Allow prompt: unlock the phone, then unplug and plug in again.\n· Worked before but not now: unlock the phone and check that Developer options → USB debugging is still on. If it is off, turn it on, plug in again and tap Always allow.\n\nDocument camera: press Camera and point the phone down from a stand. Use Rotate, Light and Freeze. Needs Android 12 or later.\nSchool-managed devices may block developer options.\n\nA step-by-step guide with photos is on Yelsam's blog (in Korean). Press Open Guide.")
    var open = false
    withToolsSuspended {
      takeFocus()
      open = alert.runModal() == .alertFirstButtonReturn
      if !open { giveFocusBack() }
    }
    if open { NSWorkspace.shared.open(phoneGuideURL) }
  }
}

/// Lists the phone's gallery videos in big rows; one press copies the chosen one and opens subtitles.
final class PhoneVideoPicker: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
  weak var controller: AppController?
  let window: NSWindow
  private let table = NSTableView()
  let status = NSTextField(labelWithString: "")
  private let getButton = NSButton()
  private(set) var videos: [PhoneVideo] = []
  private var busy = false

  init(controller: AppController) {
    self.controller = controller
    window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 600, height: 470), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    super.init()
    window.title = tr("폰 영상 가져오기", "Get Videos from the Phone")
    window.isReleasedWhenClosed = false
    window.delegate = self
    guard let content = window.contentView else { return }
    let heading = NSTextField(labelWithString: tr("자막을 넣을 영상을 고르세요", "Choose a video to add subtitles to"))
    heading.font = .systemFont(ofSize: 18, weight: .semibold)
    heading.frame = CGRect(x: 20, y: 424, width: 560, height: 28)
    content.addSubview(heading)
    status.font = .systemFont(ofSize: 13)
    status.textColor = .secondaryLabelColor
    status.frame = CGRect(x: 20, y: 398, width: 560, height: 20)
    content.addSubview(status)
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("video"))
    column.width = 540
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 40
    table.usesAlternatingRowBackgroundColors = true
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.doubleAction = #selector(getSelected)
    let scroll = NSScrollView(frame: CGRect(x: 20, y: 70, width: 560, height: 318))
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    content.addSubview(scroll)
    getButton.title = tr("가져와서 자막 넣기", "Get it and add subtitles")
    getButton.bezelStyle = .rounded
    getButton.keyEquivalent = "\r"
    getButton.target = self
    getButton.action = #selector(getSelected)
    getButton.font = .systemFont(ofSize: 15, weight: .semibold)
    getButton.sizeToFit()
    getButton.frame = CGRect(x: 580 - getButton.frame.width - 24, y: 18, width: getButton.frame.width + 24, height: 36)
    content.addSubview(getButton)
    let close = NSButton(title: tr("닫기", "Close"), target: window, action: #selector(NSWindow.performClose(_:)))
    close.bezelStyle = .rounded
    close.sizeToFit()
    close.frame = CGRect(x: getButton.frame.minX - close.frame.width - 24, y: 18, width: close.frame.width + 16, height: 36)
    content.addSubview(close)
  }
  func show() {
    window.center()
    controller?.takeFocus()
    window.makeKeyAndOrderFront(nil)
    present(nil, loading: true)
    controller?.phone.listVideos { [weak self] list in self?.present(list, loading: false) }
  }
  /// Fills the list. nil while loading or when the phone could not be read.
  func present(_ list: [PhoneVideo]?, loading: Bool) {
    videos = list ?? []
    table.reloadData()
    if !videos.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    getButton.isEnabled = !videos.isEmpty
    status.stringValue =
      loading ? tr("폰에서 영상 목록을 읽는 중이에요…", "Reading the phone's videos…")
      : list == nil ? tr("폰을 읽지 못했어요. 폰 잠금을 풀고 케이블을 다시 꽂아 주세요.", "Could not read the phone. Unlock it and plug it in again.")
      : videos.isEmpty ? tr("폰에 영상이 없어요.", "There are no videos on the phone.")
      : tr("맨 위가 가장 최근 영상이에요. 고른 뒤 ‘가져와서 자막 넣기’를 눌러 주세요.", "The newest is at the top. Choose one, then press Get it.")
  }
  func numberOfRows(in tableView: NSTableView) -> Int { videos.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let label = NSTextField(labelWithString: phoneVideoLabel(videos[row]))
    label.font = .systemFont(ofSize: 15, weight: .medium)
    let cell = NSTableCellView()
    label.frame = CGRect(x: 10, y: 9, width: 520, height: 22)
    cell.addSubview(label)
    return cell
  }
  @objc func getSelected() {
    guard !busy, let controller, table.selectedRow >= 0, table.selectedRow < videos.count else { return }
    let video = videos[table.selectedRow]
    busy = true
    getButton.isEnabled = false
    status.stringValue = tr("가져오는 중이에요… 영상이 크면 조금 걸려요.", "Copying… big videos take a little while.")
    try? FileManager.default.createDirectory(at: controller.capturesFolder, withIntermediateDirectories: true)
    let target = controller.capturesFolder.appendingPathComponent(phoneVideoFileName(video.name))
    controller.phone.pull(video, to: target) { [weak self] ok in
      guard let self else { return }
      self.busy = false
      self.getButton.isEnabled = true
      guard ok else {
        self.status.stringValue = tr("가져오지 못했어요. 폰 잠금을 풀고 케이블을 확인한 뒤 다시 눌러 주세요.", "Could not copy it. Unlock the phone, check the cable and try again.")
        return
      }
      self.window.close()
      controller.toast(tr("폰 영상을 가져왔어요 · ", "Video copied · ") + controller.storage.capturesLabel)
      controller.openSubtitles(target)
    }
  }
  func windowWillClose(_ notification: Notification) {
    controller?.phoneVideoPicker = nil
    DispatchQueue.main.async { [weak controller] in controller?.giveFocusBack() }
  }
}

extension AppController {
  func showPhoneVideos() {
    guard case .ready = phone.state else {
      showMessage(tr("폰을 먼저 연결해 주세요", "Connect the phone first"), tr("폰을 케이블로 꽂으면 ‘영상 가져오기’를 쓸 수 있어요.", "Plug in the phone to get its videos."))
      return
    }
    if phoneVideoPicker == nil { phoneVideoPicker = PhoneVideoPicker(controller: self) }
    phoneVideoPicker?.show()
  }
}

import AppKit
import Foundation

var appEnglish = false
func tr(_ korean: String, _ english: String) -> String { appEnglish ? english : korean }
let zoomLevels: [CGFloat] = [1.5, 2, 3, 4, 5]

let blogURL = URL(string: "https://blog.naver.com/profile/intro.naver?blogId=yelsam_lab")!
let suggestAddress = "bongbiyobi@gmail.com"
/// Yelsam's blog post with photos on connecting a phone.
let phoneGuideURL = URL(string: "https://blog.naver.com/yelsam_lab/224469355120")!
/// A new mail to Yelsam with the subject filled in.
var suggestURL: URL {
  var parts = URLComponents()
  parts.scheme = "mailto"
  parts.path = suggestAddress
  parts.queryItems = [URLQueryItem(name: "subject", value: tr("YelPoint 제안", "YelPoint suggestion"))]
  return parts.url!
}

enum Look {
  static let dock = NSColor(srgbRed: 0.125, green: 0.17, blue: 0.145, alpha: 1)
  static let lime = NSColor(srgbRed: 0.84, green: 0.94, blue: 0.67, alpha: 1)
  static let paper = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.95, alpha: 1)
  static let spotLine = NSColor(srgbRed: 0.90, green: 0.12, blue: 0.12, alpha: 1)
  static let ink = [
    NSColor(srgbRed: 0.93, green: 0.41, blue: 0.31, alpha: 1),
    NSColor(srgbRed: 0.19, green: 0.47, blue: 0.87, alpha: 1),
    NSColor(srgbRed: 0.14, green: 0.58, blue: 0.40, alpha: 1),
  ]
}

struct Preferences: Codable {
  var highlight = true
  var fadingInk = false
  var keyboardHUD = false
  var spotlight = false
  var penColor = 0
  var penWidth: CGFloat = 4
  var zoom: CGFloat = 2
  var english: Bool?
  // Optional so settings.json files written before these options still decode.
  var haloRadius: CGFloat?
  var inkRGB: Int?
  var spotlightRadius: CGFloat?
  var toolbarX: CGFloat?
  var toolbarY: CGFloat?
  var toolbarHidden: Bool?
  var toolbarVertical: Bool?
  var clockX: CGFloat?
  var clockY: CGFloat?
  var clockScale: CGFloat?
  /// Set after the first phone connection, so later plug-ins open the phone screen straight away.
  var phoneAuto: Bool?
  var subtitleStyle: SubtitleStyle?
  var qrText: String?
  var pointerRadius: CGFloat { haloRadius ?? 16 }
  var dimmingRadius: CGFloat { spotlightRadius ?? 105 }
  mutating func resizeDimming(steps: Int) {
    spotlightRadius = min(400, max(30, dimmingRadius + CGFloat(steps) * 8))
  }
  mutating func resizePointer(steps: Int) {
    haloRadius = min(48, max(6, pointerRadius + CGFloat(steps) * 2))
  }
  mutating func validate() {
    penColor = min(2, max(0, penColor))
    penWidth = (1...30).contains(penWidth) ? penWidth.rounded() : 4
    zoom = min(5, max(1.5, zoom))
    haloRadius = haloRadius.map { min(48, max(6, $0)) }
    spotlightRadius = spotlightRadius.map { min(400, max(30, $0)) }
    clockScale = clockScale.map { min(6, max(0.6, $0)) }
    if let rgb = inkRGB, !(0...0xFFFFFF).contains(rgb) { inkRGB = nil }
  }
}

/// On a writable external drive everything stays beside the app. An installed copy
/// uses the user's Library and Movies folders instead.
final class PortableStorage {
  let root: URL
  let file: URL
  let captures: URL
  private let installed: Bool
  var capturesLabel: String {
    installed ? tr("동영상/YelPoint", "Movies/YelPoint") : "data/captures"
  }
  init() throws {
    let env = ProcessInfo.processInfo.environment
    let folder = Bundle.main.bundleURL.deletingLastPathComponent()
    let values = try folder.resourceValues(forKeys: [.volumeIsInternalKey, .volumeIsReadOnlyKey])
    if let custom = env["YELPOINT_DATA_DIR"] {
      root = URL(fileURLWithPath: custom, isDirectory: true)
      captures = root.appendingPathComponent("captures", isDirectory: true)
      installed = false
    } else if values.volumeIsInternal == false, values.volumeIsReadOnly != true {
      root = folder.appendingPathComponent("data", isDirectory: true)
      captures = root.appendingPathComponent("captures", isDirectory: true)
      installed = false
    } else {
      // Read before CFFIXED_USER_HOME below redirects the home folder.
      let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      root = home.appendingPathComponent("Library/Application Support/YelPoint", isDirectory: true)
      captures = home.appendingPathComponent("Movies/YelPoint", isDirectory: true)
      installed = true
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for path in ["tmp", "cache", "home"] {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent(path), withIntermediateDirectories: true)
    }
    setenv("TMPDIR", root.appendingPathComponent("tmp").path + "/", 1)
    setenv("CFFIXED_USER_HOME", root.appendingPathComponent("home").path, 1)
    setenv("XDG_CACHE_HOME", root.appendingPathComponent("cache").path, 1)
    file = root.appendingPathComponent("settings.json")
  }
  func load() -> Preferences {
    guard let data = try? Data(contentsOf: file),
      var p = try? JSONDecoder().decode(Preferences.self, from: data)
    else { return Preferences() }
    p.validate()
    return p
  }
  func save(_ preferences: Preferences) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(preferences).write(to: file, options: .atomic)
  }
}

enum CountdownPhase: Equatable {
  case idle
  case running(until: TimeInterval)
  case paused(left: TimeInterval)
  case finished(at: TimeInterval)
}

/// Times come from the caller, so a sleeping Mac still counts real minutes.
struct Countdown {
  static let maxMinutes = 60
  /// "Time's up!" stays this long so a class with the sound off still sees it.
  static let holdSeconds: TimeInterval = 5
  /// Long enough for the pop, then the clock is gone.
  static let alertSeconds: TimeInterval = 0.45
  private(set) var minutes = 10
  private(set) var phase = CountdownPhase.idle
  var isRunning: Bool {
    if case .running = phase { return true }
    return false
  }
  var isLocked: Bool {
    if case .paused = phase { return true }
    return isRunning
  }
  var isActive: Bool { phase != .idle }
  mutating func set(minutes value: Int) {
    guard !isLocked else { return }
    minutes = min(Countdown.maxMinutes, max(1, value))
    phase = .idle
  }
  mutating func startOrPause(now: TimeInterval) {
    switch phase {
    case .idle, .finished: phase = .running(until: now + TimeInterval(minutes * 60))
    case .running(let until): phase = .paused(left: max(0, until - now))
    case .paused(let left): phase = .running(until: now + left)
    }
  }
  mutating func reset() { phase = .idle }
  /// Returns true once, at the moment the time runs out.
  mutating func update(now: TimeInterval) -> Bool {
    switch phase {
    case .running(let until) where now >= until:
      phase = .finished(at: now)
      return true
    case .finished(let at) where now >= at + Countdown.holdSeconds + Countdown.alertSeconds:
      phase = .idle
      return false
    default: return false
    }
  }
  /// 0 to 1 through the pop that ends the countdown, nil otherwise.
  func popProgress(now: TimeInterval) -> CGFloat? {
    guard case .finished(let at) = phase else { return nil }
    return CGFloat(min(1, max(0, (now - at - Countdown.holdSeconds) / Countdown.alertSeconds)))
  }
  func badge(now: TimeInterval) -> (text: String, alert: Bool)? {
    func clock(_ left: TimeInterval) -> String {
      let seconds = Int(max(0, left).rounded(.up))
      return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
    switch phase {
    case .idle: return nil
    case .running(let until): return (clock(until - now), false)
    case .paused(let left): return (clock(left), false)
    case .finished: return (tr("시간 끝!", "Time's up!"), true)
    }
  }
}

func penWidth(atFraction fraction: CGFloat) -> CGFloat {
  1 + (min(1, max(0, fraction)) * 29).rounded()
}

func hsvToRGB(hue: Double, saturation: Double, value: Double) -> Int {
  let h = (hue - floor(hue)) * 6
  let sector = Int(h) % 6
  let f = h - floor(h)
  let p = value * (1 - saturation)
  let q = value * (1 - saturation * f)
  let t = value * (1 - saturation * (1 - f))
  let (r, g, b) = [
    (value, t, p), (q, value, p), (p, value, t), (p, q, value), (t, p, value), (value, p, q),
  ][sector]
  func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
  return byte(r) << 16 | byte(g) << 8 | byte(b)
}

/// `dy` points up. Beyond the rim the pick stays on the rim.
func wheelPick(dx: Double, dy: Double, radius: Double) -> (hue: Double, saturation: Double) {
  let angle = atan2(dy, dx) / (2 * Double.pi)
  return (angle < 0 ? angle + 1 : angle, min(1, hypot(dx, dy) / radius))
}

enum SpotShape { case rectangle, circle, ellipse }

struct SpotRegion {
  var shape: SpotShape
  var rect: CGRect
  let display: CGDirectDisplayID
}

let spotMinimumSize: CGFloat = 24

/// The part of the outline under `p`. Parts walk round from the low-x, low-y corner,
/// alternating corner and edge, so 0 is a corner, 1 an edge, up to 7.
func spotHandle(at p: CGPoint, shape: SpotShape, rect r: CGRect) -> Int? {
  let reach: CGFloat = 10
  if shape == .rectangle {
    guard r.insetBy(dx: -reach, dy: -reach).contains(p) else { return nil }
    let column = abs(p.x - r.minX) <= reach ? 0 : abs(p.x - r.maxX) <= reach ? 2 : 1
    let row = abs(p.y - r.minY) <= reach ? 0 : abs(p.y - r.maxY) <= reach ? 2 : 1
    let grid: [[Int?]] = [[0, 1, 2], [7, nil, 3], [6, 5, 4]]
    return grid[row][column]
  }
  guard r.width > 0, r.height > 0 else { return nil }
  let x = (p.x - r.midX) / (r.width / 2)
  let y = (p.y - r.midY) / (r.height / 2)
  guard abs(hypot(x, y) - 1) * min(r.width, r.height) / 2 <= reach else { return nil }
  var angle = atan2(y, x) * 180 / .pi
  if angle < 0 { angle += 360 }
  return [3, 4, 5, 6, 7, 0, 1, 2][Int((angle / 45).rounded()) % 8]
}

func spotContains(_ shape: SpotShape, rect r: CGRect, point p: CGPoint) -> Bool {
  guard shape != .rectangle else { return r.contains(p) }
  guard r.width > 0, r.height > 0 else { return false }
  let x = (p.x - r.midX) / (r.width / 2)
  let y = (p.y - r.midY) / (r.height / 2)
  return x * x + y * y <= 1
}

func spotRect(from a: CGPoint, to b: CGPoint, square: Bool) -> CGRect {
  var dx = b.x - a.x
  var dy = b.y - a.y
  if square {
    let side = max(abs(dx), abs(dy))
    dx = dx < 0 ? -side : side
    dy = dy < 0 ? -side : side
  }
  return CGRect(x: min(a.x, a.x + dx), y: min(a.y, a.y + dy), width: abs(dx), height: abs(dy))
}

/// Grows or shrinks about the centre, keeping the proportions.
func spotScaled(_ r: CGRect, steps: Int) -> CGRect {
  let scale = max(1 + 0.05 * CGFloat(steps), spotMinimumSize / max(1, min(r.width, r.height)))
  let width = r.width * scale
  let height = r.height * scale
  return CGRect(x: r.midX - width / 2, y: r.midY - height / 2, width: width, height: height)
}

func spotResized(_ r: CGRect, handle: Int, to p: CGPoint, square: Bool) -> CGRect {
  let lowX = [0, 6, 7].contains(handle)
  let highX = [2, 3, 4].contains(handle)
  let lowY = [0, 1, 2].contains(handle)
  let highY = [4, 5, 6].contains(handle)
  var x0 = r.minX
  var x1 = r.maxX
  var y0 = r.minY
  var y1 = r.maxY
  if lowX { x0 = min(p.x, x1 - spotMinimumSize) }
  if highX { x1 = max(p.x, x0 + spotMinimumSize) }
  if lowY { y0 = min(p.y, y1 - spotMinimumSize) }
  if highY { y1 = max(p.y, y0 + spotMinimumSize) }
  if square {
    let movesX = lowX || highX
    let movesY = lowY || highY
    let side =
      movesX && movesY ? max(x1 - x0, y1 - y0) : movesX ? x1 - x0 : y1 - y0
    if lowX {
      x0 = x1 - side
    } else if highX {
      x1 = x0 + side
    } else {
      x0 = (x0 + x1 - side) / 2
      x1 = x0 + side
    }
    if lowY {
      y0 = y1 - side
    } else if highY {
      y1 = y0 + side
    } else {
      y0 = (y0 + y1 - side) / 2
      y1 = y0 + side
    }
  }
  return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
}

/// The clock grows from its top-left corner and keeps its proportions.
func resizedClock(_ frame: CGRect, dx: CGFloat) -> CGRect {
  let width = min(196 * 6, max(118, frame.width + dx))
  let height = width * 76 / 196
  return CGRect(x: frame.minX, y: frame.maxY - height, width: width, height: height)
}

func stickerSize(_ image: CGSize, limit: CGSize) -> CGSize {
  guard image.width > 0, image.height > 0 else { return CGSize(width: 80, height: 80) }
  let ratio = min(1, limit.width / image.width, limit.height / image.height)
  return CGSize(width: image.width * ratio, height: image.height * ratio)
}

func recordingSize(_ pixels: CGSize, maxWidth: CGFloat = 3840) -> (width: Int, height: Int) {
  let ratio = min(1, maxWidth / max(1, pixels.width))
  return (Int(pixels.width * ratio) & ~1, Int(pixels.height * ratio) & ~1)
}

/// What a saved video is, from its file name, for the 내 영상 list.
func videoKind(_ name: String) -> String {
  if name.hasSuffix(".subtitled.mp4") { return tr("자막 넣은 영상", "Video with subtitles") }
  if name.hasPrefix("YelPoint-phone-video-") { return tr("폰에서 가져온 영상", "From the phone") }
  if name.hasPrefix("YelPoint-phone-") { return tr("폰 화면 녹화", "Phone recording") }
  if name.hasPrefix("YelPoint-") { return tr("화면 녹화", "Screen recording") }
  return tr("영상", "Video")
}

func mediaFileName(extension ext: String, date: Date) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.dateFormat = "yyyyMMdd-HHmmss"
  return "YelPoint-\(formatter.string(from: date)).\(ext)"
}

struct InkStroke {
  var points: [CGPoint]
  let color: NSColor
  let width: CGFloat
  var created: TimeInterval
  let expires: Bool
  func alpha(at now: TimeInterval, inProgress: Bool = false) -> CGFloat {
    guard expires && !inProgress else { return 1 }
    return min(1, max(0, CGFloat((created + 4 - now) / 0.6)))
  }
  func touches(_ point: CGPoint) -> Bool {
    points.contains { hypot($0.x - point.x, $0.y - point.y) < 18 }
  }
}

struct ClickPulse {
  let point: CGPoint
  let created: TimeInterval
  let right: Bool
  func progress(at now: TimeInterval) -> CGFloat { CGFloat((now - created) / 0.55) }
}

func clampedLens(center: CGPoint, screen: CGRect, size: CGSize = CGSize(width: 240, height: 164))
  -> CGRect
{
  let marginX = min(12, screen.width / 4)
  let marginY = min(12, screen.height / 4)
  let width = min(size.width, screen.width - marginX * 2)
  let height = min(size.height, screen.height - marginY * 2)
  let x = min(screen.maxX - width - marginX, max(screen.minX + marginX, center.x + 28))
  let minY = min(screen.maxY - height - marginY, screen.minY + 86)
  let y = min(screen.maxY - height - marginY, max(minY, center.y - height - 20))
  return CGRect(x: x, y: y, width: width, height: height)
}

func clampedOrigin(_ origin: CGPoint, size: CGSize, visible: CGRect) -> CGPoint {
  CGPoint(
    x: min(visible.maxX - size.width, max(visible.minX, origin.x)),
    y: min(visible.maxY - size.height, max(visible.minY, origin.y)))
}

/// -1 or 1 when a dragged toolbar is released at the left or right edge, otherwise 0.
/// The bar itself counts: held by its far end, it reaches the edge long before the pointer.
func toolbarEdge(frame: CGRect, pointerX x: CGFloat, visible: CGRect) -> Int {
  let left = frame.minX <= visible.minX + 24 || x <= visible.minX + 60
  let right = frame.maxX >= visible.maxX - 24 || x >= visible.maxX - 60
  if left && right { return x < visible.midX ? -1 : 1 }
  return left ? -1 : right ? 1 : 0
}

/// A standing toolbar waits this far inward before lying flat, so it cannot flicker at the edge.
func toolbarLiesFlat(side: Int, flipX: CGFloat, pointerX x: CGFloat) -> Bool {
  (side < 0 ? x - flipX : flipX - x) >= 120
}

/// Under the pointer but clear of both side edges, so it does not stand straight back up.
func flatToolbarOrigin(pointer p: CGPoint, size: CGSize, visible: CGRect) -> CGPoint {
  CGPoint(
    x: min(visible.maxX - size.width - 60, max(visible.minX + 60, p.x - size.width / 2)),
    y: p.y - size.height / 2)
}

/// Beside a standing toolbar, on the side with more room.
/// Panels sit right against the toolbar, like magnets.
let attachGap: CGFloat = 4

/// Beside a standing toolbar, on the side with more room, its top level with the button that opened it.
func clampedSideOrigin(toolbar: CGRect, child: CGSize, visible: CGRect, opener: CGRect? = nil) -> CGPoint {
  let x = toolbar.midX < visible.midX ? toolbar.maxX + attachGap : toolbar.minX - child.width - attachGap
  let y = opener.map { $0.maxY - child.height } ?? toolbar.midY - child.height / 2
  return clampedOrigin(CGPoint(x: x, y: y), size: child, visible: visible)
}

/// Above a flat toolbar (below it when there is no room), centred on the button that opened it.
func clampedChildOrigin(toolbar: CGRect, child: CGSize, visible: CGRect, opener: CGRect? = nil) -> CGPoint {
  let centre = (opener ?? toolbar).midX
  let x = min(visible.maxX - child.width, max(visible.minX, centre - child.width / 2))
  let above = toolbar.maxY + attachGap
  let proposedY = above + child.height <= visible.maxY ? above : toolbar.minY - child.height - attachGap
  let y = min(visible.maxY - child.height, max(visible.minY, proposedY))
  return CGPoint(x: x, y: y)
}

extension NSColor {
  convenience init(rgb: Int) {
    self.init(
      srgbRed: CGFloat(rgb >> 16 & 255) / 255, green: CGFloat(rgb >> 8 & 255) / 255,
      blue: CGFloat(rgb & 255) / 255, alpha: 1)
  }
}

extension NSScreen {
  var displayID: CGDirectDisplayID {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
      ?? CGMainDisplayID()
  }
}

// ---- Android phone or tablet over USB (scrcpy) ----
enum PhoneState: Equatable {
  case none
  /// Plugged in with USB debugging on, waiting for "Allow" on the phone.
  case unauthorized
  case offline
  case ready(serial: String, name: String)
}
enum PhoneMode: Equatable { case screen, camera }

/// Reads `adb devices -l`. A ready device wins over one still waiting for permission.
/// One video in the phone's gallery, from Android's media list.
struct PhoneVideo: Equatable {
  let name: String
  let path: String
  let added: Date
  let bytes: Int64
  let seconds: Double
}

/// Reads `adb shell content query --uri content://media/external/video/media` output, newest first.
func phoneVideos(fromContentQuery output: String) -> [PhoneVideo] {
  let pattern = try! NSRegularExpression(
    pattern: #"^Row: \d+ _display_name=(.*), _data=(/.*), date_added=(\d+), _size=(\d+), duration=(\S*)$"#)
  var videos: [PhoneVideo] = []
  for line in output.split(whereSeparator: \.isNewline).map(String.init) {
    let range = NSRange(line.startIndex..., in: line)
    guard let m = pattern.firstMatch(in: line, range: range), m.numberOfRanges == 6 else { continue }
    func group(_ i: Int) -> String { Range(m.range(at: i), in: line).map { String(line[$0]) } ?? "" }
    let path = group(2)
    guard !path.isEmpty else { continue }
    videos.append(
      PhoneVideo(
        name: group(1), path: path, added: Date(timeIntervalSince1970: Double(group(3)) ?? 0),
        bytes: Int64(group(4)) ?? 0, seconds: (Double(group(5)) ?? 0) / 1000))
  }
  return videos.sorted { $0.added > $1.added }
}

/// The local file name for a phone video. The name comes from the phone, so it may not reach outside
/// the captures folder, use characters Windows or exFAT refuse, or end in anything but a video type.
func phoneVideoFileName(_ name: String) -> String {
  var safe = String.UnicodeScalarView()
  for s in name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
    safe.append(s.value < 32 || s.value == 127 || "<>:\"/\\|?*".unicodeScalars.contains(s) ? "_" : s)
  }
  var file = String(safe)
  while file.hasSuffix(".") || file.hasSuffix(" ") { file.removeLast() }
  if file.isEmpty { file = "video.mp4" }
  if !["mp4", "m4v", "mov", "3gp", "3g2", "mkv", "webm"].contains((file as NSString).pathExtension.lowercased()) { file += ".mp4" }
  return "YelPoint-phone-video-" + file
}

/// "11월 6일 오후 7:44 · 1분 5초 · 63MB", short enough to read at a glance.
func phoneVideoLabel(_ v: PhoneVideo) -> String {
  let date = DateFormatter()
  date.locale = Locale(identifier: appEnglish ? "en_US" : "ko_KR")
  date.setLocalizedDateFormatFromTemplate("MMMd jmm")
  let total = Int(v.seconds.rounded())
  let length = total >= 60
    ? tr("\(total / 60)분 \(total % 60)초", "\(total / 60) min \(total % 60) s") : tr("\(total)초", "\(total) s")
  let megabytes = max(1, Int((Double(v.bytes) / 1_000_000).rounded()))
  return "\(date.string(from: v.added)) · \(length) · \(megabytes)MB"
}

func phoneState(fromADB output: String) -> PhoneState {
  var waiting = false
  var offline = false
  for line in output.split(whereSeparator: \.isNewline) {
    let fields = line.split(separator: " ", omittingEmptySubsequences: true)
    guard fields.count >= 2, !line.hasPrefix("List of devices"), !line.hasPrefix("*") else { continue }
    let serial = String(fields[0])
    switch fields[1] {
    case "device":
      let model = fields.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)) }
      let name = (model ?? serial).replacingOccurrences(of: "_", with: " ")
      return .ready(serial: serial, name: name)
    case "unauthorized": waiting = true
    case "offline": offline = true
    default: continue
    }
  }
  return waiting ? .unauthorized : offline ? .offline : .none
}

/// One scrcpy window per mode. The camera turns into a document camera: back lens, no sound.
func scrcpyArguments(serial: String, mode: PhoneMode, rotation: Int, light: Bool, title: String, record: String? = nil) -> [String] {
  var args = [
    "--serial=\(serial)", "--window-title=\(title)", "--always-on-top",
    "--display-orientation=\(((rotation % 360) + 360) % 360)", "--max-size=1920",
  ]
  switch mode {
  case .screen:
    args += ["--stay-awake"]
  case .camera:
    args += ["--video-source=camera", "--camera-facing=back", "--no-audio", "--camera-fps=30"]
    if light { args.append("--camera-torch") }
  }
  // Records what the window shows (and the phone's sound on Android 11+) to an MP4.
  if let record { args.append("--record=\(record)") }
  return args
}

// ---- Subtitles for a recording ----
/// Where burned subtitles sit and how big they are, as shares of the video, so one setting fits any video.
struct SubtitleStyle: Codable, Equatable {
  /// Letter height ÷ video width.
  var size = 0.042
  /// Centre of the box, 0 = left edge, 1 = right edge.
  var x = 0.5
  /// Bottom of the box, 0 = bottom edge, 1 = top edge.
  var y = 0.06
  static let sizes = 0.02...0.1
  /// The box inside `area` (bottom-left origin), kept fully on the picture.
  func frame(box: CGSize, in area: CGSize) -> CGRect {
    let w = min(box.width, area.width), h = min(box.height, area.height)
    let left = min(max(0, CGFloat(x) * area.width - w / 2), area.width - w)
    let bottom = min(max(0, CGFloat(y) * area.height), area.height - h)
    return CGRect(x: left, y: bottom, width: w, height: h)
  }
  /// The style that puts a box of `box` size with its centre at `point` inside `area`.
  func centred(at point: CGPoint, box: CGSize, in area: CGSize) -> SubtitleStyle {
    var next = self
    next.x = Double(min(max(0, point.x / area.width), 1))
    next.y = Double(min(max(0, (point.y - box.height / 2) / area.height), 1))
    return next
  }
}
struct Cue: Codable, Equatable {
  var start: Double
  var end: Double
  var text: String
}
/// Joins recognised words into readable lines: a new line after a pause or when it gets long.
func cuesFromWords(_ words: [(text: String, start: Double, duration: Double)], maxCharacters: Int = 26, pause: Double = 0.8) -> [Cue] {
  var cues: [Cue] = []
  var line: [String] = []
  var start = 0.0
  var end = 0.0
  func flush() {
    if !line.isEmpty { cues.append(Cue(start: start, end: max(end, start + 1), text: line.joined(separator: " "))) }
    line = []
  }
  for word in words where !word.text.trimmingCharacters(in: .whitespaces).isEmpty {
    let length = line.joined(separator: " ").count + word.text.count + 1
    if !line.isEmpty && (word.start - end > pause || length > maxCharacters) { flush() }
    if line.isEmpty { start = word.start }
    line.append(word.text)
    end = word.start + word.duration
  }
  flush()
  // A line stays up until the next begins, if that is soon, so it does not flicker.
  for i in cues.indices.dropLast() where cues[i + 1].start - cues[i].end < 0.6 { cues[i].end = cues[i + 1].start }
  return cues
}
func cue(at time: Double, in cues: [Cue]) -> Cue? { cues.first { time >= $0.start && time < $0.end } }
/// SubRip text, which most players and YouTube read.
func srt(_ cues: [Cue]) -> String {
  func stamp(_ t: Double) -> String {
    let ms = Int((max(0, t) * 1000).rounded())
    return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
  }
  return cues.sorted { $0.start < $1.start }.enumerated().map { i, c in
    "\(i + 1)\n\(stamp(c.start)) --> \(stamp(c.end))\n\(c.text)\n"
  }.joined(separator: "\n")
}

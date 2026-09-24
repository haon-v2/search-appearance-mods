import AppKit
import Combine
import CoreText
import SwiftUI

/// The host’s edge-rail renderer is presentation only: Search owns all Tab and PageView lifetimes.
struct EdgeRailGeometry {
  var width: Double, height: Double, leading: Double
  let top = 26.0, thickness = 32.0
  var radius: Double
  var right: Double { width - 24 }
  var straight: Double { max(0, right - radius - leading) }
  var arc: Double { radius * .pi / 2 }
  var vertical: Double { max(0, height - 24 - top - radius) }
  var length: Double { straight + arc + vertical }
  func point(_ distance: Double) -> (x: Double, y: Double, angle: Double) {
    let d = min(length, max(0, distance))
    if d <= straight { return (leading + d, top, 0) }
    if d <= straight + arc {
      let a = (d - straight) / radius
      return (right - radius + radius * sin(a), top + radius * (1 - cos(a)), a)
    }
    return (right, top + radius + d - straight - arc, .pi / 2)
  }
  func nearest(_ p: NSPoint) -> (distance: Double, error: Double) {
    var best = (distance: 0.0, error: Double.infinity)
    for i in 0...Int(ceil(length / 2)) {
      let d = min(length, Double(i) * 2)
      let q = point(d)
      let error = hypot(p.x - q.x, p.y - q.y)
      if error < best.error { best = (d, error) }
    }
    return best
  }
}

struct EdgeRailPageShape: Shape {
  var curved: Bool
  var radius: Double
  func path(in rect: CGRect) -> Path {
    guard curved else { return Path(rect) }
    // Concentric with the outer rail: same gap all the way around the bend.
    let r = min(radius - 24, min(rect.width, rect.height) / 2)
    var p = Path()
    p.move(to: CGPoint(x: 12, y: 0))
    p.addLine(to: CGPoint(x: rect.maxX - r, y: 0))
    p.addArc(
      center: CGPoint(x: rect.maxX - r, y: r), radius: r, startAngle: .degrees(-90),
      endAngle: .degrees(0), clockwise: false)
    p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 12))
    p.addQuadCurve(
      to: CGPoint(x: rect.maxX - 12, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
    p.addLine(to: CGPoint(x: 12, y: rect.maxY))
    p.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - 12), control: CGPoint(x: 0, y: rect.maxY))
    p.addLine(to: CGPoint(x: 0, y: 12))
    p.addQuadCurve(to: CGPoint(x: 12, y: 0), control: .zero)
    p.closeSubpath()
    return p
  }
}

struct EdgeRailChrome: View {
  @ObservedObject var browser: Browser
  var configuration: AppearanceMod.Rail
  var overlay = false
  @State private var leading: CGFloat = 320
  var body: some View {
    ZStack(alignment: .topLeading) {
      if overlay {
        Palette.ground.frame(height: Metrics.strip)
        HStack {
          Spacer()
          Palette.ground.frame(width: 48)
        }
      }
      DragStrip().frame(height: Metrics.strip)
      EdgeRail(browser: browser, leading: leading, configuration: configuration)
      HStack(spacing: 3) {
        Helm(browser: browser)
        Door(icon: "magnifyingglass", help: "Search or enter address · ⌘L") { browser.edit() }
        ExtensionSlot()
        Door(icon: "bookmark", help: "Bookmarks") { browser.bookmarksOpen.toggle() }
          .popover(isPresented: $browser.bookmarksOpen, arrowEdge: .bottom) {
            BookmarksDropdown(browser: browser, bookmarks: browser.bookmarks)
          }
        Door(icon: "gearshape", help: "Settings") { browser.tuning = true }
      }
      .fixedSize()
      .background(
        GeometryReader { g in
          Color.clear.onAppear { leading = g.size.width + Metrics.lights + 16 }.onChange(
            of: g.size.width
          ) { _, w in leading = w + Metrics.lights + 16 }
        }
      )
      .frame(height: Metrics.strip)
      .padding(.leading, Metrics.lights)
    }
    .onDrop(of: [.url, .text], isTargeted: nil) { browser.take($0) }
  }
}

struct EdgeRail: NSViewRepresentable {
  @ObservedObject var browser: Browser
  var leading: CGFloat
  var configuration: AppearanceMod.Rail
  func makeNSView(context: Context) -> EdgeRailView { EdgeRailView() }
  func updateNSView(_ view: EdgeRailView, context: Context) {
    view.configuration = configuration
    view.bind(browser, leading: leading)
  }
  static func dismantleNSView(_ view: EdgeRailView, coordinator: ()) { view.stop() }
}

final class EdgeRailView: NSView {
  weak var browser: Browser?
  var leading = 320.0
  var offset = 0.0, targetOffset = 0.0
  private var timer: Timer?
  private var tracking: NSTrackingArea?
  private var subscriptions: [AnyCancellable] = []
  private var ids: [UUID] = []
  private var active: UUID?
  private var hover: Int?
  private var dragged: UUID?
  private var down = NSPoint.zero
  private var moving = false
  var configuration: AppearanceMod.Rail?
  var tabLength: Double { configuration?.tabLength ?? 180 }
  var gap: Double { configuration?.gap ?? 8 }
  var pitch: Double { tabLength + gap }
  var geometry: EdgeRailGeometry {
    .init(
      width: bounds.width, height: bounds.height, leading: min(leading, bounds.width - 130),
      radius: configuration?.cornerRadius ?? 64)
  }
  var total: Double { Double(browser?.tabs.count ?? 0) * pitch + 40 }
  var maximum: Double { max(0, total - geometry.length) }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  func bind(_ browser: Browser, leading: Double) {
    self.browser = browser
    self.leading = leading
    let next = browser.tabs.map(\.id)
    if next != ids {
      ids = next
      // Only observe metadata. Never read tab.web while drawing the rail.
      subscriptions = browser.tabs.map { tab in
        tab.objectWillChange.sink { [weak self] _ in
          DispatchQueue.main.async { self?.needsDisplay = true }
        }
      }
    }
    if active != browser.activeID {
      active = browser.activeID
      reveal()
    }
    setOffset(targetOffset, animated: false)
    needsDisplay = true
  }
  func stop() {
    timer?.invalidate()
    timer = nil
    subscriptions = []
  }
  deinit { timer?.invalidate() }
  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    reveal()
    needsDisplay = true
  }
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self)
    addTrackingArea(area)
    tracking = area
  }
  override func hitTest(_ point: NSPoint) -> NSView? {
    let p = convert(point, from: superview)
    let hit = geometry.nearest(p)
    guard bounds.contains(p), hit.error <= 20, hit.distance + offset < total else { return nil }
    return self
  }
  func path(_ start: Double, _ end: Double) -> NSBezierPath {
    let path = NSBezierPath()
    let p = geometry.point(start)
    path.move(to: NSPoint(x: p.x, y: p.y))
    if end > start {
      for d in stride(from: start + 2, through: end, by: 2) {
        let q = geometry.point(d)
        path.line(to: NSPoint(x: q.x, y: q.y))
      }
    }
    let q = geometry.point(end)
    path.line(to: NSPoint(x: q.x, y: q.y))
    path.lineWidth = 32
    path.lineCapStyle = .round
    return path
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let browser else { return }
    for (index, tab) in browser.tabs.enumerated() {
      let start = Double(index) * pitch - offset
      let end = start + tabLength
      guard end > 16, start < geometry.length - 16 else { continue }
      let selected = tab.id == browser.activeID
      (selected
        ? Palette.NS.wash
        : (hover == index ? Palette.NS.hover : Palette.NS.hairline.withAlphaComponent(0.45)))
        .setStroke()
      path(max(0, start + 16), min(geometry.length, end - 16)).stroke()
      guard start >= 0, end <= geometry.length else { continue }
      drawIcon(tab, at: start + 23)
      drawTitle(tab.label, at: start + 42, width: tabLength - 80, active: selected)
      let q = geometry.point(end - 21)
      let cross = NSBezierPath()
      if tab.pin != nil {
        Palette.NS.muted.setFill()
        NSBezierPath(ovalIn: NSRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5)).fill()
      } else {
        cross.move(to: NSPoint(x: q.x - 3, y: q.y - 3))
        cross.line(to: NSPoint(x: q.x + 3, y: q.y + 3))
        cross.move(to: NSPoint(x: q.x + 3, y: q.y - 3))
        cross.line(to: NSPoint(x: q.x - 3, y: q.y + 3))
        Palette.NS.muted.setStroke()
        cross.lineWidth = 1.2
        cross.stroke()
      }
    }
    let d = Double(browser.tabs.count) * pitch + 12 - offset
    if d >= 0 && d <= geometry.length {
      let p = geometry.point(d)
      Palette.NS.wash.setFill()
      NSBezierPath(ovalIn: NSRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)).fill()
      let line = NSBezierPath()
      line.move(to: NSPoint(x: p.x - 5, y: p.y))
      line.line(to: NSPoint(x: p.x + 5, y: p.y))
      line.move(to: NSPoint(x: p.x, y: p.y - 5))
      line.line(to: NSPoint(x: p.x, y: p.y + 5))
      Palette.NS.ink.setStroke()
      line.lineWidth = 1.2
      line.stroke()
    }
  }
  func titleInk(at distance: Double) -> NSColor { Palette.NS.ink }
  func drawIcon(_ tab: Tab, at distance: Double) {
    guard
      let image = tab.icon
        ?? NSImage(
          systemSymbolName: tab.shy ? "hand.raised" : "globe", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(paletteColors: [Palette.NS.muted]))
    else { return }
    let p = geometry.point(distance)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let transform = NSAffineTransform()
    transform.translateX(by: p.x, yBy: p.y)
    transform.rotate(byRadians: p.angle)
    transform.concat()
    image.draw(
      in: NSRect(x: -8, y: -8, width: 16, height: 16), from: .zero, operation: .sourceOver,
      fraction: 1, respectFlipped: true, hints: nil)
  }
  func drawTitle(_ title: String, at start: Double, width: Double, active: Bool) {
    let font = NSFont.systemFont(ofSize: 13, weight: active ? .medium : .regular)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: titleInk(at: start + width / 2).withAlphaComponent(active ? 1 : 0.62),
    ]
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: title, attributes: attributes))
    let token = CTLineCreateWithAttributedString(
      NSAttributedString(string: "…", attributes: attributes))
    let fitted = CTLineCreateTruncatedLine(line, width, .end, token) ?? line
    let textWidth = CTLineGetTypographicBounds(fitted, nil, nil, nil)
    let textStart = start + max(0, (width - textWidth) / 2)
    let inkBounds = CTLineGetBoundsWithOptions(fitted, .useGlyphPathBounds)
    let baseline = -inkBounds.midY
    let middleAngle = geometry.point(textStart + textWidth / 2).angle
    let reverse = middleAngle > .pi / 2 + 0.05 && middleAngle < 3 * .pi / 2 + 0.05
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    for run in CTLineGetGlyphRuns(fitted) as! [CTRun] {
      let count = CTRunGetGlyphCount(run)
      var glyphs = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      var advances = [CGSize](repeating: .zero, count: count)
      CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
      CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
      CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
      let attrs = CTRunGetAttributes(run) as NSDictionary
      let runFont = attrs[kCTFontAttributeName] as! CTFont
      for i in 0..<count {
        let halfAdvance = advances[i].width / 2
        let glyphCenter = positions[i].x + halfAdvance
        let glyphDistance = textStart + (reverse ? textWidth - glyphCenter : glyphCenter)
        let p = geometry.point(glyphDistance)
        context.setFillColor(
          titleInk(at: glyphDistance).withAlphaComponent(active ? 1 : 0.62).cgColor)
        context.saveGState()
        context.translateBy(x: p.x, y: p.y)
        context.rotate(by: p.angle - (reverse ? .pi : 0))
        context.scaleBy(x: 1, y: -1)
        var glyph = glyphs[i]
        var position = CGPoint(x: -halfAdvance, y: baseline + positions[i].y)
        CTFontDrawGlyphs(runFont, &glyph, &position, 1, context)
        context.restoreGState()
      }
    }
  }

  func reveal() {
    guard let browser, let i = browser.tabs.firstIndex(where: { $0.id == browser.activeID }) else {
      return
    }
    let start = Double(i) * pitch
    let end = start + tabLength
    var value = targetOffset
    if start < value { value = start }
    if end > value + geometry.length { value = end - geometry.length }
    setOffset(value, animated: false)
  }
  func setOffset(_ value: Double, animated: Bool = true) {
    targetOffset = min(maximum, max(0, value))
    timer?.invalidate()
    timer = nil
    guard animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      offset = targetOffset
      needsDisplay = true
      return
    }
    let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] t in
      guard let self else {
        t.invalidate()
        return
      }
      self.offset += (self.targetOffset - self.offset) * 0.3
      if abs(self.offset - self.targetOffset) < 0.2 {
        self.offset = self.targetOffset
        t.invalidate()
        self.timer = nil
      }
      self.needsDisplay = true
    }
    timer = t
    RunLoop.main.add(t, forMode: .common)
  }
  override func scrollWheel(with event: NSEvent) {
    setOffset(
      targetOffset
        + (abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
          ? event.scrollingDeltaX : event.scrollingDeltaY)
        * (event.hasPreciseScrollingDeltas ? 1 : 12))
  }
  private func target(_ event: NSEvent) -> (Tab, Double)? {
    let hit = geometry.nearest(convert(event.locationInWindow, from: nil))
    let d = hit.distance + offset
    let i = Int(d / pitch)
    guard hit.error <= 20, let browser, browser.tabs.indices.contains(i),
      d - Double(i) * pitch <= tabLength
    else { return nil }
    return (browser.tabs[i], d - Double(i) * pitch)
  }
  override func mouseDown(with event: NSEvent) {
    guard let browser else { return }
    let p = convert(event.locationInWindow, from: nil)
    let hit = geometry.nearest(p)
    let plus = Double(browser.tabs.count) * pitch + 12 - offset
    if abs(hit.distance - plus) < 16 && hit.error < 18 {
      browser.newTab()
      return
    }
    guard let (tab, along) = target(event) else { return }
    if along > tabLength - 38 {
      browser.close(tab)
      return
    }
    dragged = tab.id
    down = p
    moving = false
    browser.select(tab)
    if event.clickCount == 2 { browser.edit() }
  }
  override func mouseDragged(with event: NSEvent) {
    guard let browser, let id = dragged, let tab = browser.tabs.first(where: { $0.id == id }) else {
      return
    }
    let p = convert(event.locationInWindow, from: nil)
    guard moving || hypot(p.x - down.x, p.y - down.y) > 6 else { return }
    moving = true
    let near = geometry.nearest(p)
    if near.distance < 25 { setOffset(targetOffset - 14, animated: false) }
    if near.distance > geometry.length - 25 { setOffset(targetOffset + 14, animated: false) }
    browser.move(
      tab, to: min(browser.tabs.count - 1, max(0, Int((near.distance + offset) / pitch))))
  }
  override func mouseUp(with event: NSEvent) {
    dragged = nil
    moving = false
  }
  override func otherMouseDown(with event: NSEvent) {
    if event.buttonNumber == 2, let (tab, _) = target(event) { browser?.close(tab) }
  }
  override func mouseMoved(with event: NSEvent) {
    hover = target(event).flatMap { target in
      browser?.tabs.firstIndex(where: { $0.id == target.0.id })
    }
    needsDisplay = true
  }
  override func mouseExited(with event: NSEvent) {
    hover = nil
    needsDisplay = true
  }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 123 || event.keyCode == 126 {
      browser?.step(-1)
    } else if event.keyCode == 124 || event.keyCode == 125 {
      browser?.step(1)
    } else {
      super.keyDown(with: event)
    }
  }
  override func menu(for event: NSEvent) -> NSMenu? {
    guard let (tab, _) = target(event), let browser else { return nil }
    let menu = NSMenu()
    menu.autoenablesItems = false
    for (title, action) in [
      ("Reload Tab", "reload"), (tab.pin == nil ? "Pin Tab" : "Unpin Tab", "pin"),
      ("Rename Tab…", "rename"), ("Duplicate Tab", "duplicate"), ("Copy Address", "copy"),
      ("Copy as Markdown Link", "markdown"), (tab.muted ? "Unmute Tab" : "Mute Tab", "mute"),
      ("Close Other Tabs", "others"), ("Close Tab", "close"), ("Reopen Closed Tab", "reopen"),
    ] {
      let item = NSMenuItem(title: title, action: #selector(performMenu(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = ["id": tab.id.uuidString, "action": action]
      if ["copy", "markdown", "duplicate"].contains(action) || (action == "pin" && tab.pin == nil) {
        item.isEnabled = !tab.isBlank
      }
      if action == "reopen" { item.isEnabled = !browser.ghosts.isEmpty }
      if action == "others" { item.isEnabled = browser.tabs.count > 1 }
      menu.addItem(item)
    }
    return menu
  }
  @objc private func performMenu(_ sender: NSMenuItem) {
    guard let info = sender.representedObject as? [String: String], let browser,
      let tab = browser.tabs.first(where: { $0.id.uuidString == info["id"] })
    else { return }
    switch info["action"] {
    case "rename":
      guard let window else { return }
      let alert = NSAlert()
      alert.messageText = "Rename Tab"
      alert.informativeText = "Leave the name empty to use the website’s title."
      let field = NSTextField(string: tab.label)
      field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
      alert.accessoryView = field
      alert.addButton(withTitle: "Save")
      alert.addButton(withTitle: "Cancel")
      alert.window.initialFirstResponder = field
      alert.beginSheetModal(for: window) { [weak browser, weak tab] response in
        guard response == .alertFirstButtonReturn, let browser, let tab else { return }
        browser.beginTabRename(tab)
        browser.tabDraft = field.stringValue
        browser.commitTabEdit()
      }
    case "copy":
      browser.select(tab)
      browser.copyAddress()
    case "markdown":
      browser.select(tab)
      browser.copyMarkdownLink()
    case "mute": tab.toggleMute()
    case "reopen": browser.reopen()
    case "reload": tab.reload()
    case "pin": if tab.pin == nil { browser.pin(tab) } else { browser.unpin(tab) }
    case "duplicate":
      browser.select(tab)
      browser.duplicate()
    case "others": browser.closeOthers(but: tab)
    case "close": browser.close(tab)
    default: break
    }
  }
}

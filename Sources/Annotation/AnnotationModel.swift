import SwiftUI
import AppKit

/// Text metrics shared by the model (sizing the bubble) and the renderer (laying
/// out lines + the caret). Measuring and drawing use the *same* font so the caret
/// lands exactly at the end of the typed text.
enum AnnotationText {
    static func font(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: .semibold)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size) else { return base }
        return rounded
    }

    static func lineHeight(size: CGFloat) -> CGFloat {
        let f = font(size: size)
        return ceil(f.ascender - f.descender + f.leading)
    }

    static func lineWidth(_ line: String, size: CGFloat) -> CGFloat {
        guard !line.isEmpty else { return 0 }
        return ceil((line as NSString).size(withAttributes: [.font: font(size: size)]).width)
    }

    /// Bounding size of `text` laid out line-by-line (handles a trailing newline,
    /// so the box grows the moment Return is pressed).
    static func measure(_ text: String, size: CGFloat) -> CGSize {
        let lines = text.isEmpty ? [""] : text.components(separatedBy: "\n")
        let w = lines.map { lineWidth($0, size: size) }.max() ?? 0
        return CGSize(width: w, height: lineHeight(size: size) * CGFloat(lines.count))
    }
}

/// A corner of an object's bounding box (canvas coords: y increases downward).
enum BoxCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var opposite: BoxCorner {
        switch self {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomLeft: return .topRight
        case .bottomRight: return .topLeft
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }
}

/// A draggable resize handle on the selected object.
struct AnnotationHandle {
    enum Role: Equatable {
        case endpoint(Int)   // line/arrow start (0) or end (1)
        case corner(BoxCorner)
    }
    let role: Role
    let position: CGPoint
}

/// One drawn item. Freehand tools store every point; shape tools store
/// `[start, current]`. Objects are mutable: they can be moved, restyled,
/// resized, and deleted after creation.
struct DrawnShape: Identifiable {
    let id = UUID()
    var tool: AnnotationTool
    var colorHex: String
    var lineWidth: CGFloat
    var filled: Bool
    var points: [CGPoint]
    /// Pen strokes drawn in one session share a group so a hand-written letter
    /// behaves as a single object for select / move / delete.
    var groupID: UUID?
    /// Auto-incremented label for the Counter tool.
    var counterNumber: Int?
    /// Typed content for the Text callout. `points[0]` is the text's top-left;
    /// `points[1]` (optional) is the speech-bubble tail tip.
    var text: String
    /// Cached measured size of `text` — kept in sync by the model on every edit.
    var textSize: CGSize

    init(tool: AnnotationTool, colorHex: String, lineWidth: CGFloat,
         filled: Bool = false, points: [CGPoint], groupID: UUID? = nil,
         counterNumber: Int? = nil, text: String = "") {
        self.tool = tool
        self.colorHex = colorHex
        self.lineWidth = lineWidth
        self.filled = filled
        self.points = points
        self.groupID = groupID
        self.counterNumber = counterNumber
        self.text = text
        self.textSize = tool == .text ? AnnotationText.measure(text, size: max(15, lineWidth * 4)) : .zero
    }

    var color: Color { Color(hex: colorHex) }

    /// Radius of the counter badge (scales with line weight).
    var counterRadius: CGFloat { max(14, lineWidth * 3.5) }

    /// Point size of callout text, scaled off the line-weight slider.
    var fontSize: CGFloat { max(15, lineWidth * 4) }

    /// Padding between the text and the bubble edge — scales with the font so big
    /// text doesn't look cramped.
    var textPadH: CGFloat { max(16, fontSize * 0.55) }
    var textPadV: CGFloat { max(10, fontSize * 0.34) }

    /// Rounded-rect bubble that wraps the text (with a sensible minimum so an
    /// empty box being typed into is still visible). `points[0]` is the text's
    /// top-left; the bubble is that, expanded by the padding.
    var textBubbleRect: CGRect {
        guard let origin = points.first else { return .zero }
        let w = max(textSize.width, fontSize * 0.6)
        let h = max(textSize.height, AnnotationText.lineHeight(size: fontSize))
        return CGRect(x: origin.x - textPadH, y: origin.y - textPadV,
                      width: w + textPadH * 2, height: h + textPadV * 2)
    }

    /// Tight bounding box of the points (no stroke padding) — used for handles.
    var rawBounds: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Bounding box padded by the stroke half-width (for selection outline / hit-test).
    var bounds: CGRect {
        if tool == .text { return textBubbleRect.insetBy(dx: -2, dy: -2) }
        if tool == .counter, let center = points.first {
            let r = counterRadius
            var box = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            if points.count >= 2 { box = box.union(CGRect(origin: points[1], size: .zero)) }
            return box.insetBy(dx: -2, dy: -2)
        }
        let pad = lineWidth / 2 + 2
        return rawBounds.insetBy(dx: -pad, dy: -pad)
    }

    /// Whether `point` should select this shape. Thin objects (lines, strokes)
    /// use a tolerance band so they're not pixel-precise to click.
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let band = tolerance + lineWidth / 2
        switch tool {
        case .select:
            return false
        case .rectangle, .ellipse, .spotlight, .text:
            // Select by bounding box — easy to click.
            return bounds.contains(point)
        case .counter:
            guard let center = points.first else { return false }
            return hypot(point.x - center.x, point.y - center.y) <= counterRadius + tolerance
        case .line, .arrow:
            guard points.count >= 2 else { return false }
            return Self.distanceToSegment(point, points[0], points[points.count - 1]) <= band
        case .pen, .highlighter:
            return Self.distanceToPolyline(point, points) <= band + (tool == .highlighter ? lineWidth : 0)
        }
    }

    mutating func translate(by delta: CGSize) {
        points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
    }

    // MARK: Geometry

    static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
        t = max(0, min(1, t))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    static func distanceToPolyline(_ p: CGPoint, _ pts: [CGPoint]) -> CGFloat {
        guard pts.count >= 2 else {
            return pts.first.map { hypot(p.x - $0.x, p.y - $0.y) } ?? .greatestFiniteMagnitude
        }
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0..<(pts.count - 1) {
            best = min(best, distanceToSegment(p, pts[i], pts[i + 1]))
        }
        return best
    }
}

/// Holds the committed shapes plus the in-progress one, the current selection,
/// and the editing actions the canvas and toolbar drive. Shapes persist across
/// show/hide — only Clear empties them.
@MainActor
final class AnnotationModel: ObservableObject {
    @Published private(set) var shapes: [DrawnShape] = []
    @Published private(set) var current: DrawnShape?
    @Published private(set) var selectedID: UUID?
    /// The text callout currently being typed into, if any.
    @Published private(set) var editingTextID: UUID?

    private let settings: SettingsStore
    /// Shared group id for the current run of pen strokes (until ESC / tool change).
    private var penGroup: UUID?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var canUndo: Bool { !shapes.isEmpty }
    var hasContent: Bool { !shapes.isEmpty || current != nil }
    var selectedShape: DrawnShape? { shapes.first { $0.id == selectedID } }

    /// Appends a finished shape (used by seeding and tests).
    func add(_ shape: DrawnShape) { shapes.append(shape) }

    // MARK: Drawing

    func begin(at point: CGPoint) {
        var shape = DrawnShape(
            tool: settings.annotationTool,
            colorHex: settings.annotationColorHex,
            lineWidth: settings.annotationLineWidth,
            filled: settings.annotationFilled,
            points: [point]
        )
        if shape.tool == .counter { shape.counterNumber = nextCounterNumber() }
        current = shape
    }

    private func nextCounterNumber() -> Int {
        shapes.filter { $0.tool == .counter }.count + 1
    }

    func extend(to point: CGPoint) {
        guard var shape = current else { return }
        if shape.tool.isFreehand {
            shape.points.append(point)
        } else {
            shape.points = [shape.points.first ?? point, point]
        }
        current = shape
    }

    func end() {
        defer { current = nil }
        guard var shape = current else { return }
        switch shape.tool {
        case .counter:
            // Placeable with a single click; give it a default down-left tail.
            if shape.points.count < 2, let c = shape.points.first {
                shape.points = [c, CGPoint(x: c.x - 26, y: c.y + 26)]
            }
        case .pen:
            guard shape.points.count >= 2 else { return }
            if penGroup == nil { penGroup = UUID() }   // group consecutive pen strokes
            shape.groupID = penGroup
        default:
            guard shape.points.count >= 2 else { return }
        }
        shapes.append(shape)
        selectedID = shape.id   // auto-select, so style tweaks apply immediately
    }

    /// Ends the current pen run; the next pen stroke starts a fresh group.
    func endPenSession() { penGroup = nil }

    // MARK: Text editing

    var isEditingText: Bool { editingTextID != nil }

    /// Places a new (empty) text callout and starts editing it. Any text already
    /// being edited is committed first.
    func beginTextEditing(at point: CGPoint) {
        commitTextEditing()
        let fontSize = max(15, settings.annotationLineWidth * 4)
        var shape = DrawnShape(
            tool: .text,
            colorHex: settings.annotationColorHex,
            lineWidth: settings.annotationLineWidth,
            // Short, proportional speech-bubble tail pointing down-left by default.
            points: [point, CGPoint(x: point.x + fontSize * 0.4, y: point.y + fontSize * 3)]
        )
        recomputeTextSize(&shape)
        shapes.append(shape)
        selectedID = shape.id
        editingTextID = shape.id
    }

    /// Re-enters editing of an existing text callout.
    func editTextShape(id: UUID) {
        commitTextEditing()
        guard shapes.contains(where: { $0.id == id }) else { return }
        selectedID = id
        editingTextID = id
    }

    func insertText(_ string: String) { mutateEditingText { $0.text += string } }
    func insertTextNewline() { mutateEditingText { $0.text += "\n" } }
    func deleteTextCharacter() {
        mutateEditingText { if !$0.text.isEmpty { $0.text.removeLast() } }
    }

    /// Finishes editing. An all-whitespace callout is discarded so stray clicks
    /// don't litter the canvas with empty bubbles.
    @discardableResult
    func commitTextEditing() -> Bool {
        guard let id = editingTextID, let index = shapes.firstIndex(where: { $0.id == id }) else {
            editingTextID = nil
            return false
        }
        editingTextID = nil
        if shapes[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shapes.remove(at: index)
            if selectedID == id { selectedID = nil }
            return false
        }
        return true
    }

    private func mutateEditingText(_ change: (inout DrawnShape) -> Void) {
        guard let id = editingTextID, let index = shapes.firstIndex(where: { $0.id == id }) else { return }
        change(&shapes[index])
        recomputeTextSize(&shapes[index])
    }

    private func recomputeTextSize(_ shape: inout DrawnShape) {
        shape.textSize = AnnotationText.measure(shape.text, size: shape.fontSize)
    }

    // MARK: Selection & editing

    /// Top-most shape under `point` (last drawn wins for overlaps).
    func hitTest(_ point: CGPoint, tolerance: CGFloat = 10) -> DrawnShape? {
        for shape in shapes.reversed() where shape.hitTest(point, tolerance: tolerance) {
            return shape
        }
        return nil
    }

    @discardableResult
    func selectShape(at point: CGPoint) -> Bool {
        if let hit = hitTest(point) {
            selectedID = hit.id
            return true
        }
        selectedID = nil
        return false
    }

    func deselect() { selectedID = nil }

    /// Indices of the selected object plus any grouped siblings (pen strokes).
    private var selectionIndices: [Int] {
        guard let shape = selectedShape else { return [] }
        if let group = shape.groupID {
            return shapes.indices.filter { shapes[$0].groupID == group }
        }
        return selectedIndex.map { [$0] } ?? []
    }

    /// Bounding box of the whole current selection (group-aware).
    var selectionBounds: CGRect? {
        let rects = selectionIndices.map { shapes[$0].bounds }
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    func translateSelected(by delta: CGSize) {
        for index in selectionIndices { shapes[index].translate(by: delta) }
    }

    // MARK: Resize handles

    /// Raw (unpadded) bounding box of the whole selection.
    private var selectionRawBounds: CGRect? {
        let rects = selectionIndices.map { shapes[$0].rawBounds }
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Handles for the current selection: endpoint handles for a single
    /// line/arrow, otherwise the four corners of the bounding box.
    var selectionHandles: [AnnotationHandle] {
        let indices = selectionIndices
        if indices.count == 1 {
            let shape = shapes[indices[0]]
            if (shape.tool == .line || shape.tool == .arrow), shape.points.count >= 2 {
                return [
                    AnnotationHandle(role: .endpoint(0), position: shape.points[0]),
                    AnnotationHandle(role: .endpoint(1), position: shape.points[shape.points.count - 1]),
                ]
            }
            // Counter / Text: one handle on the tail tip to re-aim it.
            if (shape.tool == .counter || shape.tool == .text), shape.points.count >= 2 {
                return [AnnotationHandle(role: .endpoint(1), position: shape.points[1])]
            }
        }
        guard let box = selectionRawBounds else { return [] }
        return BoxCorner.allCases.map { AnnotationHandle(role: .corner($0), position: $0.point(in: box)) }
    }

    func moveHandle(_ role: AnnotationHandle.Role, to point: CGPoint) {
        switch role {
        case .endpoint(let end):
            guard let index = selectedIndex else { return }
            if end == 0 { shapes[index].points[0] = point }
            else { shapes[index].points[shapes[index].points.count - 1] = point }
        case .corner(let corner):
            resizeSelection(grabbing: corner, to: point)
        }
    }

    /// Scales every point of the selection so the dragged corner follows the
    /// cursor while the opposite corner stays fixed.
    private func resizeSelection(grabbing corner: BoxCorner, to point: CGPoint) {
        guard let box = selectionRawBounds else { return }
        let anchor = corner.opposite.point(in: box)
        let moving = corner.point(in: box)

        let minScaled: CGFloat = 8
        var sx: CGFloat = 1, sy: CGFloat = 1
        if moving.x - anchor.x != 0 {
            sx = (point.x - anchor.x) / (moving.x - anchor.x)
            if abs(box.width * sx) < minScaled { sx = (sx < 0 ? -1 : 1) * minScaled / max(box.width, 1) }
        }
        if moving.y - anchor.y != 0 {
            sy = (point.y - anchor.y) / (moving.y - anchor.y)
            if abs(box.height * sy) < minScaled { sy = (sy < 0 ? -1 : 1) * minScaled / max(box.height, 1) }
        }

        for index in selectionIndices {
            shapes[index].points = shapes[index].points.map {
                CGPoint(x: anchor.x + ($0.x - anchor.x) * sx,
                        y: anchor.y + ($0.y - anchor.y) * sy)
            }
        }
    }

    func deleteSelected() {
        guard let shape = selectedShape else { return }
        if let group = shape.groupID {
            shapes.removeAll { $0.groupID == group }
        } else {
            shapes.removeAll { $0.id == shape.id }
        }
        selectedID = nil
    }

    /// Applies a style change to the selected shape if there is one; the caller
    /// is responsible for updating the default (settings) when nothing's selected.
    func setSelectedColor(_ hex: String) { mutateSelected { $0.colorHex = hex } }
    func setSelectedWidth(_ width: CGFloat) { mutateSelected { $0.lineWidth = width } }
    func setSelectedFilled(_ filled: Bool) { mutateSelected { $0.filled = filled } }

    /// Advances the color one step through the preset palette — the selected
    /// object's color if there is one, otherwise the default for new objects.
    func cycleColor() {
        let presets = AnnotationPalette.presets
        guard !presets.isEmpty else { return }
        func next(after hex: String) -> String {
            let index = presets.firstIndex { $0.caseInsensitiveCompare(hex) == .orderedSame }
            return presets[((index ?? -1) + 1) % presets.count]
        }
        if selectedID != nil, let current = selectedShape?.colorHex {
            setSelectedColor(next(after: current))
        } else {
            settings.annotationColorHex = next(after: settings.annotationColorHex)
        }
    }

    /// Toggles fill on the selected object, or the default for new objects.
    func toggleFill() {
        if selectedID != nil, let current = selectedShape?.filled {
            setSelectedFilled(!current)
        } else {
            settings.annotationFilled.toggle()
        }
    }

    func undo() {
        guard !shapes.isEmpty else { return }
        let removed = shapes.removeLast()
        if removed.id == selectedID { selectedID = nil }
    }

    func clear() {
        shapes.removeAll()
        current = nil
        selectedID = nil
    }

    private var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return shapes.firstIndex { $0.id == id }
    }

    private func mutateSelected(_ change: (inout DrawnShape) -> Void) {
        for index in selectionIndices {
            change(&shapes[index])
            // Width changes the font size, so the text box must be re-measured.
            if shapes[index].tool == .text { recomputeTextSize(&shapes[index]) }
        }
    }

    // MARK: Debug

    func debugSeed() {
        let hex = settings.annotationColorHex
        let squiggle = stride(from: 0.0, to: 360.0, by: 12.0).map { (a: Double) -> CGPoint in
            CGPoint(x: 250 + a, y: 300 + 60 * sin(a / 24))
        }
        shapes = [
            DrawnShape(tool: .pen, colorHex: hex, lineWidth: 4, points: squiggle),
            DrawnShape(tool: .arrow, colorHex: "#34C759", lineWidth: 5, points: [CGPoint(x: 300, y: 450), CGPoint(x: 620, y: 560)]),
            DrawnShape(tool: .rectangle, colorHex: "#FF9500", lineWidth: 4, points: [CGPoint(x: 700, y: 300), CGPoint(x: 920, y: 440)]),
            DrawnShape(tool: .ellipse, colorHex: "#0A84FF", lineWidth: 4, filled: true, points: [CGPoint(x: 700, y: 470), CGPoint(x: 920, y: 600)]),
            DrawnShape(tool: .highlighter, colorHex: "#FFD60A", lineWidth: 6, points: [CGPoint(x: 260, y: 660), CGPoint(x: 640, y: 660)]),
            DrawnShape(tool: .counter, colorHex: "#30D158", lineWidth: 5, points: [CGPoint(x: 1000, y: 320), CGPoint(x: 960, y: 370)], counterNumber: 1),
            DrawnShape(tool: .counter, colorHex: "#30D158", lineWidth: 5, points: [CGPoint(x: 1080, y: 460), CGPoint(x: 1130, y: 510)], counterNumber: 2),
            DrawnShape(tool: .spotlight, colorHex: "#000000", lineWidth: 2, points: [CGPoint(x: 360, y: 760), CGPoint(x: 720, y: 980)]),
            DrawnShape(tool: .text, colorHex: "#0BA678", lineWidth: 4,
                       points: [CGPoint(x: 1000, y: 640), CGPoint(x: 980, y: 800)],
                       text: "Text\ncan be multi lines"),
        ]
        selectedID = shapes[1].id   // select the arrow to show endpoint handles
    }
}

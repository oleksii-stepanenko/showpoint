import SwiftUI

/// Full-screen drawing surface plus the floating toolbar.
struct AnnotationRootView: View {
    @ObservedObject var model: AnnotationModel
    @ObservedObject var settings: SettingsStore
    let onDone: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            AnnotationCanvas(model: model, settings: settings)

            AnnotationToolbar(model: model, settings: settings, onDone: onDone)
                .padding(.bottom, 28)
        }
        .ignoresSafeArea()
        // Leaving the pen tool ends the current pen group.
        .onChange(of: settings.annotationTool) { _, newTool in
            if newTool != .pen { model.endPenSession() }
        }
    }
}

// MARK: - Canvas

private struct AnnotationCanvas: View {
    @ObservedObject var model: AnnotationModel
    @ObservedObject var settings: SettingsStore

    private enum DragMode: Equatable { case undecided, drawing, moving, resizing(AnnotationHandle.Role), idle }

    @State private var mode: DragMode = .undecided
    @State private var lastPoint: CGPoint = .zero

    private let handleHitRadius: CGFloat = 12

    var body: some View {
        Canvas { context, size in
            var spotlights = model.shapes.filter { $0.tool == .spotlight && $0.points.count >= 2 }
            if let current = model.current, current.tool == .spotlight, current.points.count >= 2 {
                spotlights.append(current)
            }
            AnnotationRender.drawSpotlightDim(spotlights, size: size, in: &context)

            // Spotlights are realized by the dim layer above, not stroked here.
            for shape in model.shapes where shape.tool != .spotlight {
                AnnotationRender.draw(shape, in: &context)
            }
            if let current = model.current, current.tool != .spotlight {
                AnnotationRender.draw(current, in: &context)
            }
            if let bounds = model.selectionBounds {
                AnnotationRender.drawSelection(bounds, in: &context)
                AnnotationRender.drawHandles(model.selectionHandles, in: &context)
            }
        }
        .background(Color.black.opacity(0.001))   // makes the whole area hit-testable
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if mode == .undecided { decideMode(at: value.startLocation) }
                    continueDrag(value)
                }
                .onEnded { _ in
                    if mode == .drawing { model.end() }
                    mode = .undecided
                }
        )
    }

    /// Decide what a fresh drag does: resize a handle, move/select an object, or
    /// draw with the current tool. Works the same for every tool — clicking an
    /// object always grabs it; clicking empty draws (or, with Select, deselects).
    private func decideMode(at point: CGPoint) {
        lastPoint = point

        // 1. A resize handle of the current selection?
        if let handle = model.selectionHandles.first(where: {
            hypot($0.position.x - point.x, $0.position.y - point.y) <= handleHitRadius
        }) {
            mode = .resizing(handle.role)
            return
        }

        // 2. An existing object?
        if model.hitTest(point) != nil {
            model.selectShape(at: point)
            mode = .moving
            return
        }

        // 3. Empty space.
        if settings.annotationTool.drawsObjects {
            model.deselect()
            model.begin(at: point)
            mode = .drawing
        } else {
            model.deselect()
            mode = .idle
        }
    }

    private func continueDrag(_ value: DragGesture.Value) {
        switch mode {
        case .drawing:
            model.extend(to: value.location)
        case .moving:
            let delta = CGSize(width: value.location.x - lastPoint.x,
                               height: value.location.y - lastPoint.y)
            model.translateSelected(by: delta)
            lastPoint = value.location
        case .resizing(let role):
            model.moveHandle(role, to: value.location)
        case .undecided, .idle:
            break
        }
    }
}

// MARK: - Rendering

enum AnnotationRender {
    static func draw(_ shape: DrawnShape, in context: inout GraphicsContext) {
        guard let first = shape.points.first else { return }
        let last = shape.points.last ?? first
        let style = StrokeStyle(lineWidth: shape.lineWidth, lineCap: .round, lineJoin: .round)

        switch shape.tool {
        case .select:
            break
        case .pen:
            context.stroke(freehandPath(shape.points), with: .color(shape.color), style: style)
        case .highlighter:
            context.stroke(freehandPath(shape.points),
                           with: .color(shape.color.opacity(0.35)),
                           style: StrokeStyle(lineWidth: shape.lineWidth * 3, lineCap: .round, lineJoin: .round))
        case .line:
            context.stroke(linePath(first, last), with: .color(shape.color), style: style)
        case .arrow:
            drawArrow(first, last, weight: shape.lineWidth, color: shape.color, in: &context)
        case .rectangle:
            let path = Path(rect(first, last))
            if shape.filled { context.fill(path, with: .color(shape.color.opacity(0.5))) }
            context.stroke(path, with: .color(shape.color), style: style)
        case .ellipse:
            let path = Path(ellipseIn: rect(first, last))
            if shape.filled { context.fill(path, with: .color(shape.color.opacity(0.5))) }
            context.stroke(path, with: .color(shape.color), style: style)
        case .counter:
            drawCounter(shape, in: &context)
        case .spotlight:
            break   // realized by the dim layer
        }
    }

    /// Dims the whole canvas, punching a clear hole for each spotlight ellipse.
    static func drawSpotlightDim(_ spots: [DrawnShape], size: CGSize, in context: inout GraphicsContext) {
        guard !spots.isEmpty else { return }

        var dim = Path(CGRect(origin: .zero, size: size))
        for spot in spots { dim.addEllipse(in: spot.rawBounds) }
        context.fill(dim, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))

        for spot in spots {
            context.stroke(Path(ellipseIn: spot.rawBounds),
                           with: .color(.white.opacity(0.35)), lineWidth: 1.5)
        }
    }

    /// A filled badge with a pointer tail and a centered number (Shottr-style).
    private static func drawCounter(_ shape: DrawnShape, in context: inout GraphicsContext) {
        guard let center = shape.points.first else { return }
        let tip = shape.points.count >= 2 ? shape.points[1] : center
        let r = shape.counterRadius
        let color = shape.color

        // Tail toward the tip (only if it points meaningfully outside the badge).
        if hypot(tip.x - center.x, tip.y - center.y) > r * 0.7 {
            let angle = atan2(tip.y - center.y, tip.x - center.x)
            let spread: CGFloat = 0.5
            var tail = Path()
            tail.move(to: CGPoint(x: center.x + r * cos(angle - spread), y: center.y + r * sin(angle - spread)))
            tail.addLine(to: tip)
            tail.addLine(to: CGPoint(x: center.x + r * cos(angle + spread), y: center.y + r * sin(angle + spread)))
            tail.closeSubpath()
            context.fill(tail, with: .color(color))
        }

        context.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                     with: .color(color))

        let number = Text("\(shape.counterNumber ?? 1)")
            .font(.system(size: r, weight: .bold, design: .rounded))
            .foregroundColor(.white)
        context.draw(number, at: center, anchor: .center)
    }

    static func drawSelection(_ bounds: CGRect, in context: inout GraphicsContext) {
        let r = bounds.insetBy(dx: -5, dy: -5)
        let path = Path(roundedRect: r, cornerRadius: 5)
        context.stroke(path, with: .color(.white.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        context.stroke(path, with: .color(.accentColor),
                       style: StrokeStyle(lineWidth: 1.5, dash: [6, 4], dashPhase: 6))
    }

    static func drawHandles(_ handles: [AnnotationHandle], in context: inout GraphicsContext) {
        let s: CGFloat = 10
        for handle in handles {
            let rect = CGRect(x: handle.position.x - s / 2, y: handle.position.y - s / 2, width: s, height: s)
            let path = Path(roundedRect: rect, cornerRadius: 2)
            context.fill(path, with: .color(.white))
            context.stroke(path, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5))
        }
    }

    /// A clean arrow: a shaft that stops at the head, plus a filled triangle tip.
    private static func drawArrow(_ a: CGPoint, _ b: CGPoint, weight: CGFloat,
                                  color: Color, in context: inout GraphicsContext) {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let headLength = max(16, weight * 4)
        let headWidth = max(13, weight * 3.4)

        // Shaft stops short so it doesn't poke through the filled head.
        let shaftEnd = CGPoint(x: b.x - headLength * 0.82 * cos(angle),
                               y: b.y - headLength * 0.82 * sin(angle))
        context.stroke(linePath(a, shaftEnd), with: .color(color),
                       style: StrokeStyle(lineWidth: weight, lineCap: .round))

        let base = CGPoint(x: b.x - headLength * cos(angle), y: b.y - headLength * sin(angle))
        let perp = angle + .pi / 2
        var head = Path()
        head.move(to: b)
        head.addLine(to: CGPoint(x: base.x + headWidth / 2 * cos(perp), y: base.y + headWidth / 2 * sin(perp)))
        head.addLine(to: CGPoint(x: base.x - headWidth / 2 * cos(perp), y: base.y - headWidth / 2 * sin(perp)))
        head.closeSubpath()
        context.fill(head, with: .color(color))
    }

    private static func freehandPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }

    private static func linePath(_ a: CGPoint, _ b: CGPoint) -> Path {
        var path = Path(); path.move(to: a); path.addLine(to: b); return path
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

// MARK: - Toolbar

private struct AnnotationToolbar: View {
    @ObservedObject var model: AnnotationModel
    @ObservedObject var settings: SettingsStore
    let onDone: () -> Void

    @State private var showColorPopover = false

    /// Shottr dual-role: editing a selection mutates it; otherwise sets the default.
    private var effectiveColorHex: String {
        model.selectedShape?.colorHex ?? settings.annotationColorHex
    }
    private var effectiveWidth: Binding<Double> {
        Binding(
            get: { model.selectedShape.map { Double($0.lineWidth) } ?? settings.annotationLineWidth },
            set: { newValue in
                if model.selectedID != nil { model.setSelectedWidth(CGFloat(newValue)) }
                else { settings.annotationLineWidth = newValue }
            }
        )
    }
    private var effectiveFilled: Binding<Bool> {
        Binding(
            get: { model.selectedShape?.filled ?? settings.annotationFilled },
            set: { newValue in
                if model.selectedID != nil { model.setSelectedFilled(newValue) }
                else { settings.annotationFilled = newValue }
            }
        )
    }

    private func applyColor(_ hex: String) {
        if model.selectedID != nil { model.setSelectedColor(hex) }
        else { settings.annotationColorHex = hex }
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AnnotationTool.allCases) { tool in
                toolButton(tool)
            }

            Divider().frame(height: 26)

            colorButton
            Slider(value: effectiveWidth, in: 1...24).frame(width: 80)
            actionButton("square.fill", key: "F", help: "Fill (F)", active: effectiveFilled.wrappedValue) {
                model.toggleFill()
            }

            Divider().frame(height: 26)

            actionButton("arrow.uturn.backward", key: "⌘Z", help: "Undo (⌘Z)", enabled: model.canUndo) { model.undo() }
            actionButton("trash", key: "⌫", help: "Delete selected (⌫)", enabled: model.selectedID != nil) { model.deleteSelected() }
            actionButton("trash.slash", key: "⇧⌫", help: "Clear all (⇧⌫)", enabled: model.hasContent) { model.clear() }

            Divider().frame(height: 26)

            Button(action: onDone) { Text("Done").fontWeight(.semibold) }
                .buttonStyle(.borderedProminent)
                .help("Exit annotation (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(radius: 16, y: 6)
        .font(.system(size: 15))
    }

    private func toolButton(_ tool: AnnotationTool) -> some View {
        let active = settings.annotationTool == tool
        return Button { settings.annotationTool = tool } label: {
            VStack(spacing: 1) {
                Image(systemName: tool.systemImage).frame(height: 18)
                Text(tool.shortcutLabel)
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(active ? 1 : 0.5)
            }
            .frame(width: 26)
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.accentColor : .primary)
        .help("\(tool.label) (\(tool.shortcutLabel))")
    }

    /// An icon button with the shortcut key shown beneath it (matches the tools),
    /// so the shortcut is always visible — not just on hover.
    private func actionButton(_ icon: String, key: String, help: String,
                              enabled: Bool = true, active: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon).frame(height: 18)
                Text(key).font(.system(size: 8, weight: .semibold)).opacity(0.55)
            }
            .frame(width: 30)
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.accentColor : .primary)
        .disabled(!enabled)
        .help(help)
    }

    private var colorButton: some View {
        Button { showColorPopover.toggle() } label: {
            VStack(spacing: 1) {
                Circle().fill(Color(hex: effectiveColorHex))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1.5))
                Text("⇥").font(.system(size: 8, weight: .semibold)).opacity(0.55)
            }
            .frame(width: 26)
        }
        .buttonStyle(.plain)
        .help("Color (Tab)")
        .popover(isPresented: $showColorPopover, arrowEdge: .bottom) {
            ColorPalettePopover(selectedHex: effectiveColorHex, onPick: applyColor)
        }
    }
}

/// Preset swatches + a Custom picker, matching Shottr's color popover.
private struct ColorPalettePopover: View {
    let selectedHex: String
    let onPick: (String) -> Void

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 10), count: 4)

    @State private var customColor: Color = .white

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(AnnotationPalette.presets, id: \.self) { hex in
                    Button { onPick(hex) } label: {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(hex: hex))
                            .frame(width: 34, height: 34)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.accentColor, lineWidth: hex == selectedHex ? 3 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            ColorPicker("Custom", selection: $customColor, supportsOpacity: false)
                .onChange(of: customColor) { _, newValue in onPick(newValue.hexString) }
                .font(.system(size: 13))
        }
        .padding(14)
        .frame(width: 196)
    }
}

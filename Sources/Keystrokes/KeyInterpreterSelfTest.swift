import AppKit

/// Drives the real `KeyInterpreter` through scripted event sequences and prints
/// PASS/FAIL. Run with the `PRESENTER_SELFTEST=1` environment variable; the app
/// runs this at launch and exits. Pure logic — no event tap, no permissions.
@MainActor
enum KeyInterpreterSelfTest {
    /// One scripted modifier/key event.
    private struct Step {
        let type: CGEventType
        let keyCode: UInt16
        let flags: NSEvent.ModifierFlags
        let chars: String?
        init(_ type: CGEventType, keyCode: UInt16 = 0, flags: NSEvent.ModifierFlags = [], chars: String? = nil) {
            self.type = type; self.keyCode = keyCode; self.flags = flags; self.chars = chars
        }
    }

    private struct Case {
        let name: String
        let steps: [Step]
        let expected: [String]
    }

    static func run() -> Never {
        let cmd: NSEvent.ModifierFlags = .command
        let shiftCmd: NSEvent.ModifierFlags = [.shift, .command]

        let cases: [Case] = [
            Case(name: "plain letter",
                 steps: [Step(.keyDown, keyCode: 0, chars: "a")],
                 expected: ["A"]),

            Case(name: "bare ⌘ tap",
                 steps: [Step(.flagsChanged, keyCode: 55, flags: cmd),
                         Step(.flagsChanged, keyCode: 55, flags: [])],
                 expected: ["⌘"]),

            Case(name: "⌘C combo → single capsule",
                 steps: [Step(.flagsChanged, keyCode: 55, flags: cmd),
                         Step(.keyDown, keyCode: 8, flags: cmd, chars: "c"),
                         Step(.flagsChanged, keyCode: 55, flags: [])],
                 expected: ["⌘ C"]),

            Case(name: "⇧⌘A combo → single capsule",
                 steps: [Step(.flagsChanged, keyCode: 56, flags: .shift),
                         Step(.flagsChanged, keyCode: 55, flags: shiftCmd),
                         Step(.keyDown, keyCode: 0, flags: shiftCmd, chars: "a"),
                         Step(.flagsChanged, keyCode: 55, flags: .shift),
                         Step(.flagsChanged, keyCode: 56, flags: [])],
                 expected: ["⇧⌘ A"]),

            // The regression we just fixed: typing a plain key must NOT suppress
            // a following bare-modifier tap.
            Case(name: "plain key then bare ⌘",
                 steps: [Step(.keyDown, keyCode: 0, chars: "a"),
                         Step(.flagsChanged, keyCode: 55, flags: cmd),
                         Step(.flagsChanged, keyCode: 55, flags: [])],
                 expected: ["A", "⌘"]),
        ]

        var allPassed = true
        for c in cases {
            let interpreter = KeyInterpreter()
            var got: [String] = []
            for s in c.steps {
                let raw = RawKeyEvent(type: s.type, keyCode: s.keyCode, modifierFlags: s.flags, chars: s.chars)
                if let item = interpreter.interpret(raw, showModifiers: true, showMouseClicks: true) {
                    got.append(item.text)
                }
            }
            let ok = got == c.expected
            allPassed = allPassed && ok
            print("\(ok ? "PASS" : "FAIL") — \(c.name): got \(got), expected \(c.expected)")
        }

        allPassed = runDoubleTapTests() && allPassed
        allPassed = runAnnotationTests() && allPassed

        print(allPassed ? "ALL PASSED" : "SOME FAILED")
        exit(allPassed ? 0 : 1)
    }

    // MARK: Annotation object model (selection / move / delete / z-order)

    private static func check(_ name: String, _ got: Bool, _ expected: Bool) -> Bool {
        let pass = got == expected
        print("\(pass ? "PASS" : "FAIL") — \(name)")
        return pass
    }

    private static func runAnnotationTests() -> Bool {
        var ok = true

        // Hit-testing geometry.
        let r = DrawnShape(tool: .rectangle, colorHex: "#fff", lineWidth: 4, filled: true,
                           points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)])
        ok = check("rect hit inside", r.hitTest(CGPoint(x: 150, y: 150), tolerance: 10), true) && ok
        ok = check("rect miss outside", r.hitTest(CGPoint(x: 400, y: 400), tolerance: 10), false) && ok

        let line = DrawnShape(tool: .line, colorHex: "#fff", lineWidth: 4,
                              points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
        ok = check("line hit within tolerance band", line.hitTest(CGPoint(x: 50, y: 7), tolerance: 10), true) && ok
        ok = check("line miss far from band", line.hitTest(CGPoint(x: 50, y: 40), tolerance: 10), false) && ok

        // Model: z-order, move, delete.
        let model = AnnotationModel(settings: .shared)
        let a = DrawnShape(tool: .rectangle, colorHex: "#a", lineWidth: 4, filled: true,
                           points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)])
        let b = DrawnShape(tool: .rectangle, colorHex: "#b", lineWidth: 4, filled: true,
                           points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)])
        model.add(a); model.add(b)

        ok = check("z-order returns top-most", model.hitTest(CGPoint(x: 50, y: 50))?.id == b.id, true) && ok

        model.selectShape(at: CGPoint(x: 50, y: 50))             // selects b
        model.translateSelected(by: CGSize(width: 10, height: 20))
        let movedB = model.shapes.first { $0.id == b.id }!
        ok = check("translate moves selected", movedB.points[0] == CGPoint(x: 10, y: 20), true) && ok
        ok = check("translate leaves others", model.shapes.first { $0.id == a.id }!.points[0] == CGPoint(x: 0, y: 0), true) && ok

        model.deleteSelected()
        ok = check("delete removes selected", model.shapes.contains { $0.id == b.id }, false) && ok
        ok = check("delete keeps others", model.shapes.contains { $0.id == a.id }, true) && ok

        model.selectShape(at: CGPoint(x: 9999, y: 9999))         // empty
        ok = check("click empty deselects", model.selectedID == nil, true) && ok

        // Pen grouping: strokes in one group move/delete together.
        let g = UUID()
        let s1 = DrawnShape(tool: .pen, colorHex: "#1", lineWidth: 3,
                            points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 10)], groupID: g)
        let s2 = DrawnShape(tool: .pen, colorHex: "#1", lineWidth: 3,
                            points: [CGPoint(x: 10, y: 40), CGPoint(x: 30, y: 40)], groupID: g)
        let m2 = AnnotationModel(settings: .shared)
        m2.add(s1); m2.add(s2)
        m2.selectShape(at: CGPoint(x: 20, y: 10))                 // hits s1
        m2.translateSelected(by: CGSize(width: 5, height: 0))
        let movedBoth = m2.shapes.allSatisfy { $0.points[0].x == 15 }
        ok = check("group move shifts all strokes", movedBoth, true) && ok
        m2.deleteSelected()
        ok = check("group delete removes whole group", m2.shapes.isEmpty, true) && ok

        // Escape hierarchy: tool first, then annotation.
        ok = check("esc with draw tool exits tool", AnnotationEscape.outcome(tool: .pen) == .exitTool, true) && ok
        ok = check("esc with select exits annotation", AnnotationEscape.outcome(tool: .select) == .exitAnnotation, true) && ok

        // Resize: line/arrow expose endpoint handles, moved independently.
        let arrow = DrawnShape(tool: .arrow, colorHex: "#f", lineWidth: 4,
                               points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
        let ma = AnnotationModel(settings: .shared)
        ma.add(arrow)
        ma.selectShape(at: CGPoint(x: 50, y: 0))
        let handles = ma.selectionHandles
        let twoEndpoints = handles.count == 2 && handles.allSatisfy {
            if case .endpoint = $0.role { return true } else { return false }
        }
        ok = check("arrow exposes 2 endpoint handles", twoEndpoints, true) && ok
        ma.moveHandle(.endpoint(1), to: CGPoint(x: 100, y: 100))
        ok = check("arrow end moved", ma.shapes[0].points[1] == CGPoint(x: 100, y: 100), true) && ok
        ok = check("arrow start unchanged", ma.shapes[0].points[0] == CGPoint(x: 0, y: 0), true) && ok

        // Resize: rect exposes 4 corner handles and scales from the opposite corner.
        let box = DrawnShape(tool: .rectangle, colorHex: "#r", lineWidth: 4, filled: true,
                             points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)])
        let mr = AnnotationModel(settings: .shared)
        mr.add(box)
        mr.selectShape(at: CGPoint(x: 50, y: 50))
        ok = check("rect exposes 4 corner handles", mr.selectionHandles.count == 4, true) && ok
        mr.moveHandle(.corner(.bottomRight), to: CGPoint(x: 200, y: 100))   // anchor = topLeft
        let rb = mr.shapes[0].rawBounds
        ok = check("corner resize scales box", rb.width == 200 && rb.height == 100, true) && ok

        // Tool shortcuts: each tool maps to a distinct letter and resolves back.
        let letters = AnnotationTool.allCases.map { $0.shortcut }
        ok = check("tool shortcuts are unique", Set(letters).count == letters.count, true) && ok
        ok = check("'a' resolves to arrow", AnnotationTool.forShortcut("a") == .arrow, true) && ok
        ok = check("'l' resolves to line", AnnotationTool.forShortcut("l") == .line, true) && ok
        ok = check("unknown letter resolves to nil", AnnotationTool.forShortcut("z") == nil, true) && ok

        // Counter auto-numbering and single-click placement (default tail).
        let store = SettingsStore.shared
        let previousTool = store.annotationTool
        store.annotationTool = .counter
        let mc = AnnotationModel(settings: store)
        mc.begin(at: CGPoint(x: 100, y: 100)); mc.end()                         // click only
        mc.begin(at: CGPoint(x: 200, y: 100)); mc.extend(to: CGPoint(x: 230, y: 130)); mc.end()
        store.annotationTool = previousTool
        ok = check("counters auto-number 1,2", mc.shapes.compactMap { $0.counterNumber } == [1, 2], true) && ok
        ok = check("single-click counter gets a tail", mc.shapes[0].points.count == 2, true) && ok
        ok = check("counter hit-tests its badge", mc.shapes[0].hitTest(CGPoint(x: 100, y: 100), tolerance: 5), true) && ok

        // Text callout: placement, typing, multi-line growth, commit rules.
        store.annotationTool = .text
        let mt = AnnotationModel(settings: store)
        mt.beginTextEditing(at: CGPoint(x: 400, y: 300))
        ok = check("text begins in editing mode", mt.isEditingText, true) && ok
        ok = check("new text gets a default tail", mt.shapes.first?.points.count == 2, true) && ok
        mt.insertText("Hi"); mt.insertTextNewline(); mt.insertText("there")
        ok = check("typed text accumulates", mt.shapes.first?.text == "Hi\nthere", true) && ok
        mt.deleteTextCharacter()
        ok = check("backspace removes last char", mt.shapes.first?.text == "Hi\nther", true) && ok
        let twoLineHeight = mt.shapes.first?.textSize.height ?? 0
        let oneLine = AnnotationText.lineHeight(size: mt.shapes.first?.fontSize ?? 16)
        ok = check("multi-line box is taller than one line", twoLineHeight > oneLine * 1.5, true) && ok
        ok = check("committing non-empty text keeps it", mt.commitTextEditing(), true) && ok
        ok = check("not editing after commit", !mt.isEditingText, true) && ok
        ok = check("committed text hit-tests its bubble",
                   mt.shapes.first?.hitTest(CGPoint(x: 400, y: 300), tolerance: 0) == true, true) && ok
        ok = check("text exposes a tail handle", mt.selectionHandles.count == 1, true) && ok

        // An all-whitespace callout is discarded on commit (stray clicks don't litter).
        let mte = AnnotationModel(settings: store)
        mte.beginTextEditing(at: CGPoint(x: 10, y: 10))
        ok = check("empty callout discarded on commit", mte.commitTextEditing() == false && mte.shapes.isEmpty, true) && ok
        store.annotationTool = previousTool

        // Spotlight resizes via corner handles.
        let spot = DrawnShape(tool: .spotlight, colorHex: "#000", lineWidth: 2,
                              points: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 120)])
        let msp = AnnotationModel(settings: store)
        msp.add(spot)
        msp.selectShape(at: CGPoint(x: 100, y: 60))
        ok = check("spotlight selectable + 4 corner handles", msp.selectionHandles.count == 4, true) && ok

        // Color cycle advances through the palette and wraps around.
        let presets = AnnotationPalette.presets
        let mcol = AnnotationModel(settings: store)
        let s0 = DrawnShape(tool: .rectangle, colorHex: presets[0], lineWidth: 4,
                            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        mcol.add(s0)
        mcol.selectShape(at: CGPoint(x: 5, y: 5))
        mcol.cycleColor()
        ok = check("cycle color advances one step",
                   mcol.shapes[0].colorHex.caseInsensitiveCompare(presets[1]) == .orderedSame, true) && ok

        let sLast = DrawnShape(tool: .rectangle, colorHex: presets[presets.count - 1], lineWidth: 4,
                               points: [CGPoint(x: 20, y: 20), CGPoint(x: 30, y: 30)])
        let mwrap = AnnotationModel(settings: store)
        mwrap.add(sLast)
        mwrap.selectShape(at: CGPoint(x: 25, y: 25))
        mwrap.cycleColor()
        ok = check("cycle color wraps to first",
                   mwrap.shapes[0].colorHex.caseInsensitiveCompare(presets[0]) == .orderedSame, true) && ok

        // Toggle fill on the selected object.
        let mfill = AnnotationModel(settings: store)
        let sf = DrawnShape(tool: .rectangle, colorHex: "#f", lineWidth: 4, filled: false,
                            points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        mfill.add(sf)
        mfill.selectShape(at: CGPoint(x: 5, y: 5))
        mfill.toggleFill()
        ok = check("toggle fill flips selected", mfill.shapes[0].filled, true) && ok

        // Interceptor routes destructive/edit keys correctly.
        let intc = AnnotationKeyInterceptor()
        var del = 0, clr = 0, undo = 0, fill = 0
        intc.onDelete = { del += 1 }
        intc.onClearAll = { clr += 1 }
        intc.onUndo = { undo += 1 }
        intc.onToggleFill = { fill += 1 }
        func key(_ code: UInt16, _ flags: CGEventFlags = []) -> CGEvent {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
            e.flags = flags
            return e
        }
        _ = intc.handle(type: .keyDown, event: key(51))                 // Delete
        _ = intc.handle(type: .keyDown, event: key(51, .maskShift))     // ⇧Delete
        _ = intc.handle(type: .keyDown, event: key(6, .maskCommand))    // ⌘Z
        _ = intc.handle(type: .keyDown, event: key(3))                  // F
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        ok = check("Delete → delete selected", del == 1, true) && ok
        ok = check("⇧Delete → clear all", clr == 1, true) && ok
        ok = check("⌘Z → undo", undo == 1, true) && ok
        ok = check("F → toggle fill", fill == 1, true) && ok

        return ok
    }

    // MARK: Double-tap-Control detector

    private static func ctrlFlags(_ flags: CGEventFlags) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: 59, keyDown: true)!
        e.flags = flags
        return e
    }
    private static func plainKeyDown() -> CGEvent {
        CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)!
    }

    private static func tapControl(_ det: MultiTapControlDetector) {
        det.handle(type: .flagsChanged, event: ctrlFlags(.maskControl))
        det.handle(type: .flagsChanged, event: ctrlFlags([]))
    }

    /// Feeds tap sequences through the real detector and pumps the run loop past
    /// the flush timeout so the reported count can be observed.
    private static func runDoubleTapTests() -> Bool {
        var ok = true

        func report(_ taps: Int, combo: Bool = false) -> [Int] {
            var counts: [Int] = []
            let det = MultiTapControlDetector { counts.append($0) }
            if combo {
                det.handle(type: .flagsChanged, event: ctrlFlags(.maskControl))
                det.handle(type: .keyDown, event: plainKeyDown())
                det.handle(type: .flagsChanged, event: ctrlFlags([]))
            }
            for _ in 0..<taps { tapControl(det) }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.45))   // > flush timeout
            return counts
        }

        let cases: [(name: String, got: [Int], expected: [Int])] = [
            ("double-tap → reports 2 once",   report(2),            [2]),
            ("triple-tap → reports 3 once",   report(3),            [3]),
            ("triple does NOT also fire 2",   report(3).filter { $0 == 2 }, []),
            ("single tap → nothing",          report(1),            []),
            ("combo only → nothing",          report(0, combo: true), []),
        ]
        for c in cases {
            let pass = c.got == c.expected
            ok = ok && pass
            print("\(pass ? "PASS" : "FAIL") — \(c.name): got \(c.got), expected \(c.expected)")
        }
        return ok
    }
}

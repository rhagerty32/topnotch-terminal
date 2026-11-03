import AppKit
import SwiftTerm

/// Shift + arrows (+ Option/Command) grow the terminal selection like a Mac text field.
@MainActor
enum KeyboardSelection {
    private static let left: UInt16 = 123
    private static let right: UInt16 = 124
    private static let down: UInt16 = 125
    private static let up: UInt16 = 126

    static func handle(_ event: NSEvent, in view: TerminalView) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard mods.contains(.shift), !mods.contains(.control) else { return false }

        let direction: Direction
        switch event.keyCode {
        case left: direction = .left
        case right: direction = .right
        case up: direction = .up
        case down: direction = .down
        default: return false
        }

        let unit: Unit
        if mods.contains(.command) {
            unit = (direction == .up || direction == .down) ? .document : .line
        } else if mods.contains(.option) {
            unit = (direction == .up || direction == .down) ? .paragraph : .word
        } else {
            unit = .character
        }

        apply(to: view, unit: unit, direction: direction)
        return true
    }

    private static let backspaceKey: UInt16 = 51
    private static let forwardDeleteKey: UInt16 = 117

    /// Command-V, including Paste and Match Style. Control stays a literal terminal chord.
    static func isPasteShortcut(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard mods.contains(.command), !mods.contains(.control) else { return false }
        return (event.charactersIgnoringModifiers ?? "").lowercased() == "v"
    }

    private static var handlingPaste = false

    /// The key monitor runs before the Edit menu, and SwiftTerm drops `paste:`.
    /// `view` is the terminal when it is focused; nil pastes into the field editor.
    static func paste(_ event: NSEvent, into view: TerminalView?) -> Bool {
        guard isPasteShortcut(event) else { return false }
        if handlingPaste { return true }
        handlingPaste = true
        defer { handlingPaste = false }
        if let view, view.selection?.active == true, view.selection?.hasSelectionRange == true {
            deleteSelection(in: view)
        }
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        guard let view else { return false }
        view.paste(view)
        return true
    }

    /// Copy / cut / paste / delete against the highlighted input (not the PTY as raw keys).
    static func handleEditing(_ event: NSEvent, in view: TerminalView) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        let chars = event.charactersIgnoringModifiers ?? ""
        let command = mods.contains(.command) && !mods.contains(.option) && !mods.contains(.control)

        if command, chars == "a" {
            selectAllInput(in: view)
            return true
        }

        if paste(event, into: view) { return true }

        guard let selection = view.selection, selection.active, selection.hasSelectionRange else {
            return false
        }

        if command, chars == "c" {
            copySelection(in: view)
            return true
        }
        if command, chars == "x" {
            copySelection(in: view)
            deleteSelection(in: view)
            return true
        }
        if event.keyCode == backspaceKey || event.keyCode == forwardDeleteKey {
            deleteSelection(in: view)
            return true
        }
        // Left/right land on that side of the highlight. The text stays.
        if collapseToSide(event, in: view) { return true }
        if isPrintableReplacement(event) {
            deleteSelection(in: view)
            return false
        }
        return false
    }

    private enum Direction { case left, right, up, down }
    private enum Unit { case character, word, line, paragraph, document }
    private enum Kind { case space, word, other }

    private static func apply(to view: TerminalView, unit: Unit, direction: Direction) {
        let terminal = view.getTerminal()
        guard let selection = view.selection else { return }
        let yDisp = terminal.buffer.yDisp
        let cursor = Position(
            col: min(max(0, terminal.buffer.x), max(0, terminal.cols - 1)),
            row: min(max(0, terminal.buffer.y), max(0, terminal.rows - 1))
        )

        // Stay in character mode so word/line units are our Cocoa walk, not
        // SwiftTerm's mouse word-snap on top.
        selection.selectionMode = .character
        selection.selectingRows = false

        if !selection.active {
            selection.setSoftStart(row: cursor.row, col: cursor.col)
            selection.pivot = Position(col: cursor.col, row: cursor.row + yDisp)
        } else if selection.pivot == nil {
            selection.pivot = selection.start
        }

        var dest = move(from: head(of: selection, yDisp: yDisp), unit: unit, direction: direction, terminal: terminal)
        if let field = inputField(cursor: cursor, terminal: terminal) {
            dest = clamp(dest, to: field)
            if let pivot = selection.pivot {
                let pivotScreen = Position(col: pivot.col, row: max(0, pivot.row - yDisp))
                let clampedPivot = clamp(pivotScreen, to: field)
                selection.pivot = Position(col: clampedPivot.col, row: clampedPivot.row + yDisp)
            }
            selection.pivotExtend(row: dest.row, col: dest.col)
            restrict(selection, to: field, yDisp: yDisp)
        } else {
            selection.pivotExtend(row: dest.row, col: dest.col)
        }
        view.needsDisplay = true
    }

    /// Typed command only: after the prompt, through every wrapped input row.
    private static func inputField(cursor: Position, terminal: Terminal) -> (start: Position, end: Position)? {
        // Nearest real prompt at or above the cursor. Continuation rows have
        // no `/ %`, so we keep walking up (wrap flag optional — zsh may hard-wrap).
        var origin: Int?
        var startCol: Int?
        let top = max(0, cursor.row - 32)
        for row in stride(from: cursor.row, through: top, by: -1) {
            if let col = CommandLineReader.promptEndColumn(row: row, terminal: terminal) {
                origin = row
                startCol = col
                break
            }
            if row < cursor.row, lineIsBlank(row, terminal: terminal) {
                break
            }
        }
        guard let origin, let startCol else { return nil }

        var last = max(cursor.row, origin)
        while last < terminal.rows - 1, terminal.getLine(row: last + 1)?.isWrapped == true {
            last += 1
        }
        let start = Position(col: min(startCol, max(0, terminal.cols - 1)), row: origin)
        var end = Position(col: cursor.col, row: cursor.row)
        let tail = Position(col: max(startCol, lineEnd(row: last, terminal: terminal)), row: last)
        if Position.compare(tail, end) == .after {
            end = tail
        }
        if Position.compare(end, start) == .before {
            end = start
        }
        return (start, end)
    }

    private static func clamp(_ position: Position, to field: (start: Position, end: Position)) -> Position {
        if Position.compare(position, field.start) == .before { return field.start }
        if Position.compare(position, field.end) == .after { return field.end }
        return position
    }

    private static func restrict(
        _ selection: SelectionService,
        to field: (start: Position, end: Position),
        yDisp: Int
    ) {
        let minP = Position(col: field.start.col, row: field.start.row + yDisp)
        let maxP = Position(col: field.end.col, row: field.end.row + yDisp)
        var start = selection.start
        var end = selection.end
        if Position.compare(start, minP) == .before { start = minP }
        if Position.compare(end, minP) == .before { end = minP }
        if Position.compare(start, maxP) == .after { start = maxP }
        if Position.compare(end, maxP) == .after { end = maxP }
        if start != selection.start || end != selection.end {
            selection.setSelection(start: start, end: end)
        }
    }

    /// Screen-relative moving end. `start`/`end` are ordered; the pivot is the anchor.
    private static func head(of selection: SelectionService, yDisp: Int) -> Position {
        let bufferHead: Position
        if let pivot = selection.pivot, selection.start == pivot {
            bufferHead = selection.end
        } else if selection.pivot != nil {
            bufferHead = selection.start
        } else {
            bufferHead = selection.end
        }
        return Position(col: bufferHead.col, row: max(0, bufferHead.row - yDisp))
    }

    private static func move(
        from start: Position,
        unit: Unit,
        direction: Direction,
        terminal: Terminal
    ) -> Position {
        switch unit {
        case .character:
            return step(from: start, direction: direction, terminal: terminal)
        case .word:
            return direction == .left || direction == .up
                ? wordLeft(from: start, terminal: terminal)
                : wordRight(from: start, terminal: terminal)
        case .line:
            return direction == .left || direction == .up
                ? Position(col: 0, row: start.row)
                : Position(col: lineEnd(row: start.row, terminal: terminal), row: start.row)
        case .paragraph:
            return paragraph(from: start, direction: direction, terminal: terminal)
        case .document:
            if direction == .left || direction == .up {
                return Position(col: 0, row: 0)
            }
            let last = max(0, terminal.rows - 1)
            return Position(col: lineEnd(row: last, terminal: terminal), row: last)
        }
    }

    private static func step(from start: Position, direction: Direction, terminal: Terminal) -> Position {
        let lastRow = max(0, terminal.rows - 1)
        let lastCol = max(0, terminal.cols - 1)
        switch direction {
        case .left:
            if start.col > 0 { return Position(col: start.col - 1, row: start.row) }
            if start.row > 0 { return Position(col: lastCol, row: start.row - 1) }
            return start
        case .right:
            if start.col < lastCol { return Position(col: start.col + 1, row: start.row) }
            if start.row < lastRow { return Position(col: 0, row: start.row + 1) }
            return start
        case .up:
            return Position(col: start.col, row: max(0, start.row - 1))
        case .down:
            return Position(col: start.col, row: min(lastRow, start.row + 1))
        }
    }

    private static func wordLeft(from start: Position, terminal: Terminal) -> Position {
        var pos = start
        guard let first = stepLeft(pos, terminal: terminal) else { return pos }
        pos = first
        while kind(at: pos, terminal: terminal) == .space, let next = stepLeft(pos, terminal: terminal) {
            pos = next
        }
        let cls = kind(at: pos, terminal: terminal)
        while let next = stepLeft(pos, terminal: terminal), kind(at: next, terminal: terminal) == cls {
            pos = next
        }
        return pos
    }

    private static func wordRight(from start: Position, terminal: Terminal) -> Position {
        var pos = start
        let cls = kind(at: pos, terminal: terminal)
        if cls != .space {
            while let next = stepRight(pos, terminal: terminal), kind(at: pos, terminal: terminal) == cls {
                pos = next
            }
        }
        while kind(at: pos, terminal: terminal) == .space, let next = stepRight(pos, terminal: terminal) {
            pos = next
        }
        return pos
    }

    private static func paragraph(from start: Position, direction: Direction, terminal: Terminal) -> Position {
        let last = max(0, terminal.rows - 1)
        var row = start.row
        if direction == .left || direction == .up {
            if row > 0 { row -= 1 }
            while row > 0, !lineIsBlank(row, terminal: terminal) { row -= 1 }
            while row > 0, lineIsBlank(row, terminal: terminal) { row -= 1 }
            return Position(col: 0, row: row)
        }
        if row < last { row += 1 }
        while row < last, !lineIsBlank(row, terminal: terminal) { row += 1 }
        while row < last, lineIsBlank(row, terminal: terminal) { row += 1 }
        return Position(col: 0, row: row)
    }

    private static func stepLeft(_ pos: Position, terminal: Terminal) -> Position? {
        if pos.col > 0 { return Position(col: pos.col - 1, row: pos.row) }
        if pos.row > 0 { return Position(col: max(0, terminal.cols - 1), row: pos.row - 1) }
        return nil
    }

    private static func stepRight(_ pos: Position, terminal: Terminal) -> Position? {
        let lastCol = max(0, terminal.cols - 1)
        if pos.col < lastCol { return Position(col: pos.col + 1, row: pos.row) }
        if pos.row < terminal.rows - 1 { return Position(col: 0, row: pos.row + 1) }
        return nil
    }

    private static func lineEnd(row: Int, terminal: Terminal) -> Int {
        let lastCol = max(0, terminal.cols - 1)
        var end = lastCol
        while end > 0, kind(at: Position(col: end, row: row), terminal: terminal) == .space {
            end -= 1
        }
        if end < lastCol, kind(at: Position(col: end, row: row), terminal: terminal) != .space {
            end += 1
        }
        return end
    }

    private static func lineIsBlank(_ row: Int, terminal: Terminal) -> Bool {
        for col in 0..<terminal.cols {
            if kind(at: Position(col: col, row: row), terminal: terminal) != .space {
                return false
            }
        }
        return true
    }

    private static func kind(at pos: Position, terminal: Terminal) -> Kind {
        let ch = terminal.getCharacter(col: pos.col, row: pos.row) ?? " "
        if ch == "\0" || ch.isWhitespace { return .space }
        if ch.isLetter || ch.isNumber || ch == "_" { return .word }
        return .other
    }

    /// Arrow keys report a function-key scalar (>= 32), so they must not count as typing.
    private static func isPrintableReplacement(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard mods.isEmpty || mods == .shift else { return false }
        guard let chars = event.characters, !chars.isEmpty else { return false }
        return chars.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            if value < 32 || value == 127 { return false }
            if (0xF700...0xF8FF).contains(value) { return false }
            return true
        }
    }

    /// Left places the shell cursor at the start of the highlight, right at the end.
    private static func collapseToSide(_ event: NSEvent, in view: TerminalView) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .numericPad, .function])
        guard mods.isEmpty else { return false }
        let toEnd: Bool
        switch event.keyCode {
        case left: toEnd = false
        case right: toEnd = true
        default: return false
        }

        let terminal = view.getTerminal()
        guard let selection = view.selection else { return false }
        let yDisp = terminal.buffer.yDisp
        let cursor = screenCursor(terminal)
        guard let field = inputField(cursor: cursor, terminal: terminal) else { return false }

        var first = Position(col: selection.start.col, row: selection.start.row - yDisp)
        var last = Position(col: selection.end.col, row: selection.end.row - yDisp)
        if Position.compare(first, last) == .after { swap(&first, &last) }
        let outside = Position.compare(last, field.start) != .after
            || Position.compare(first, field.end) == .after
        guard !outside else { return false }

        let edge = clamp(toEnd ? last : first, to: field)
        let target = offset(of: edge, in: field, terminal: terminal)
        let cursorOffset = offset(of: clamp(cursor, to: field), in: field, terminal: terminal)
        let delta = target - cursorOffset
        if delta != 0 {
            var bytes: [UInt8] = []
            if delta > 0 {
                for _ in 0..<delta { bytes += [0x1b, 0x5b, 0x43] }
            } else {
                for _ in 0..<(-delta) { bytes += [0x1b, 0x5b, 0x44] }
            }
            view.send(bytes)
        }
        selection.active = false
        view.needsDisplay = true
        return true
    }

    private static func copySelection(in view: TerminalView) {
        guard let text = view.selection?.getSelectedText(), !text.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
    }

    private static func selectAllInput(in view: TerminalView) {
        let terminal = view.getTerminal()
        let cursor = screenCursor(terminal)
        guard let field = inputField(cursor: cursor, terminal: terminal),
              let selection = view.selection else { return }
        let yDisp = terminal.buffer.yDisp
        selection.selectionMode = .character
        selection.selectingRows = false
        selection.setSoftStart(row: field.end.row, col: field.end.col)
        selection.pivot = Position(col: field.end.col, row: field.end.row + yDisp)
        selection.pivotExtend(row: field.start.row, col: field.start.col)
        view.needsDisplay = true
    }

    private static func deleteSelection(in view: TerminalView) {
        let terminal = view.getTerminal()
        guard let selection = view.selection else { return }
        let yDisp = terminal.buffer.yDisp
        let cursor = screenCursor(terminal)
        defer {
            selection.active = false
            view.needsDisplay = true
        }
        guard let field = inputField(cursor: cursor, terminal: terminal) else { return }

        var first = Position(col: selection.start.col, row: selection.start.row - yDisp)
        var last = Position(col: selection.end.col, row: selection.end.row - yDisp)
        if Position.compare(first, last) == .after { swap(&first, &last) }
        first = clamp(first, to: field)
        last = clamp(last, to: field)

        let low = offset(of: first, in: field, terminal: terminal)
        let high = offset(of: last, in: field, terminal: terminal)
        let count = max(0, high - low)
        guard count > 0 else { return }

        let cursorOffset = offset(of: clamp(cursor, to: field), in: field, terminal: terminal)
        var bytes: [UInt8] = []
        let delta = high - cursorOffset
        if delta > 0 {
            for _ in 0..<delta { bytes += [0x1b, 0x5b, 0x43] }
        } else if delta < 0 {
            for _ in 0..<(-delta) { bytes += [0x1b, 0x5b, 0x44] }
        }
        bytes += Array(repeating: 0x7f, count: count)
        view.send(bytes)
    }

    private static func screenCursor(_ terminal: Terminal) -> Position {
        Position(
            col: min(max(0, terminal.buffer.x), max(0, terminal.cols - 1)),
            row: min(max(0, terminal.buffer.y), max(0, terminal.rows - 1))
        )
    }

    private static func offset(
        of target: Position,
        in field: (start: Position, end: Position),
        terminal: Terminal
    ) -> Int {
        if Position.compare(target, field.start) != .after { return 0 }
        var pos = field.start
        var count = 0
        while Position.compare(pos, target) == .before, Position.compare(pos, field.end) == .before {
            guard let next = stepRight(pos, terminal: terminal) else { break }
            pos = next
            count += 1
        }
        return count
    }
}

import QtQuick 2.15
import QtQuick.Controls 2.15

TerminalGlassPanel {
    id: root

    property string outputText: ""
    property string promptLabel: ""
    property bool viewportFocused: false
    property color textColor: "#D9E8FF"
    property string actionMessage: ""
    property bool actionError: false
    property bool selectionMode: false
    property int selectionAnchor: 0
    property int fontPixelSize: 16
    property bool timestampVisible: true

    // Prompt timestamps are viewport-only metadata. Each prompt occurrence
    // keeps its timestamp while output grows, but the timestamp is refreshed
    // when that prompt line changes from an idle prompt to a submitted command.
    property var promptTimestampCache: ({ "__lastRawLength": 0 })

    // The PTY remains a real xterm-256color stream. Render ANSI SGR here so
    // shell colors survive while control sequences never become visible text.
    readonly property var renderedOutput: renderAnsi(outputText, textColor)
    readonly property int indicatorPosition: terminalText.cursorPosition
    readonly property string indicatorLocation: lineAndColumn(terminalText.cursorPosition)

    signal copyRequested(string text)
    signal selectionCaptured(string text)

    focused: viewportFocused
    accentColor: root.accentColor
    strong: true
    padding: 18
    radius: 30

    function htmlEscape(value) {
        return String(value || "")
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .split(String.fromCharCode(34)).join("&quot;")
    }

    function htmlText(value) {
        return htmlEscape(value)
            .replace(/ /g, "&nbsp;")
            .replace(/\t/g, "&nbsp;&nbsp;&nbsp;&nbsp;")
    }

    function basicAnsiColor(index, bright) {
        var normal = ["#111827", "#FF5C70", "#49D17D", "#E7C65A",
                      "#57A8FF", "#C879FF", "#4ED8E8", "#D9E8FF"]
        var strong = ["#708090", "#FF7585", "#72EE9B", "#FFE27A",
                      "#79C2FF", "#DC98FF", "#7DEEFF", "#FFFFFF"]
        return (bright ? strong : normal)[Math.max(0, Math.min(7, Number(index || 0)))]
    }

    function ansi256Color(index) {
        var i = Math.max(0, Math.min(255, Number(index || 0)))
        if (i < 8) return basicAnsiColor(i, false)
        if (i < 16) return basicAnsiColor(i - 8, true)
        if (i >= 232) {
            var gray = 8 + (i - 232) * 10
            var gh = gray.toString(16)
            if (gh.length < 2) gh = "0" + gh
            return "#" + gh + gh + gh
        }
        var cube = i - 16
        var r = Math.floor(cube / 36)
        var g = Math.floor((cube % 36) / 6)
        var b = cube % 6
        function component(v) { return v === 0 ? 0 : 55 + v * 40 }
        function hx(v) {
            var h = component(v).toString(16)
            return h.length < 2 ? "0" + h : h
        }
        return "#" + hx(r) + hx(g) + hx(b)
    }

    function rgbAnsiColor(r, g, b) {
        function hx(value) {
            var h = Math.max(0, Math.min(255, Number(value || 0))).toString(16)
            return h.length < 2 ? "0" + h : h
        }
        return "#" + hx(r) + hx(g) + hx(b)
    }

    function renderAnsi(rawValue, defaultColor) {
        var raw = String(rawValue || "")
        var base = String(defaultColor || "#D9E8FF")
        var style = { fg: base, bg: "", bold: false, italic: false,
                      underline: false, reverse: false, explicitFg: false }
        var finalRuns = []
        var renderedLines = []
        var line = []
        var cursor = 0

        function cloneStyle() {
            return { fg: style.fg, bg: style.bg, bold: style.bold,
                     italic: style.italic, underline: style.underline,
                     reverse: style.reverse, explicitFg: style.explicitFg }
        }

        function sameStyle(a, b) {
            return a && b && a.fg === b.fg && a.bg === b.bg &&
                   a.bold === b.bold && a.italic === b.italic &&
                   a.underline === b.underline && a.reverse === b.reverse &&
                   a.explicitFg === b.explicitFg
        }

        function resetStyle() {
            style.fg = base
            style.bg = ""
            style.bold = false
            style.italic = false
            style.underline = false
            style.reverse = false
            style.explicitFg = false
        }

        function writeCharacter(ch) {
            while (line.length < cursor)
                line.push({ ch: " ", style: cloneStyle() })
            var cell = { ch: ch, style: cloneStyle() }
            if (cursor < line.length)
                line[cursor] = cell
            else
                line.push(cell)
            cursor += 1
        }

        function eraseLine(mode) {
            var value = Number(mode || 0)
            if (value === 2) {
                line = []
                cursor = 0
            } else if (value === 1) {
                var keep = line.slice(cursor + 1)
                line = []
                for (var n = 0; n <= cursor; ++n)
                    line.push({ ch: " ", style: cloneStyle() })
                line = line.concat(keep)
            } else {
                if (cursor < line.length)
                    line = line.slice(0, cursor)
            }
        }

        function appendLineRuns(withNewline) {
            var active = null
            var linePlain = ""
            var nonSpaceCount = 0
            var explicitColorCount = 0
            var artCharacterCount = 0
            var letterCount = 0
            var uppercaseCount = 0
            for (var c = 0; c < line.length; ++c) {
                var cell = line[c]
                linePlain += cell.ch
                if (cell.ch.trim().length > 0) {
                    ++nonSpaceCount
                    if (cell.style.explicitFg)
                        ++explicitColorCount
                    var characterCode = cell.ch.charCodeAt(0)
                    var uppercaseLetter = characterCode >= 65 && characterCode <= 90
                    var lowercaseLetter = characterCode >= 97 && characterCode <= 122
                    var numericCharacter = characterCode >= 48 && characterCode <= 57
                    if (!uppercaseLetter && !lowercaseLetter && !numericCharacter)
                        ++artCharacterCount
                    if (uppercaseLetter || lowercaseLetter) {
                        ++letterCount
                        if (uppercaseLetter)
                            ++uppercaseCount
                    }
                }
                if (!active || !sameStyle(active.style, cell.style)) {
                    active = { text: "", style: cell.style }
                    finalRuns.push(active)
                }
                active.text += cell.ch
            }

            renderedLines.push({
                plain: linePlain,
                nonSpaceCount: nonSpaceCount,
                explicitColorRatio: nonSpaceCount > 0 ? explicitColorCount / nonSpaceCount : 0,
                artRatio: nonSpaceCount > 0 ? artCharacterCount / nonSpaceCount : 0,
                uppercaseRatio: letterCount > 0 ? uppercaseCount / letterCount : 0
            })
            if (withNewline)
                finalRuns.push({ text: "\n", style: cloneStyle() })
            line = []
            cursor = 0
        }

        function applySgr(parameterText) {
            var params = parameterText.length ? parameterText.split(";") : ["0"]
            for (var p = 0; p < params.length; ++p) {
                var code = params[p] === "" ? 0 : Number(params[p])
                if (isNaN(code)) code = 0
                if (code === 0) { resetStyle(); continue }
                if (code === 1) { style.bold = true; continue }
                if (code === 3) { style.italic = true; continue }
                if (code === 4) { style.underline = true; continue }
                if (code === 7) { style.reverse = true; continue }
                if (code === 22) { style.bold = false; continue }
                if (code === 23) { style.italic = false; continue }
                if (code === 24) { style.underline = false; continue }
                if (code === 27) { style.reverse = false; continue }
                if (code === 39) { style.fg = base; style.explicitFg = false; continue }
                if (code === 49) { style.bg = ""; continue }
                if (code >= 30 && code <= 37) { style.fg = basicAnsiColor(code - 30, false); style.explicitFg = true; continue }
                if (code >= 90 && code <= 97) { style.fg = basicAnsiColor(code - 90, true); style.explicitFg = true; continue }
                if (code >= 40 && code <= 47) { style.bg = basicAnsiColor(code - 40, false); continue }
                if (code >= 100 && code <= 107) { style.bg = basicAnsiColor(code - 100, true); continue }
                if ((code === 38 || code === 48) && p + 1 < params.length) {
                    var foreground = code === 38
                    var mode = Number(params[++p])
                    if (mode === 5 && p + 1 < params.length) {
                        var indexed = ansi256Color(Number(params[++p]))
                        if (foreground) { style.fg = indexed; style.explicitFg = true } else style.bg = indexed
                    } else if (mode === 2 && p + 3 < params.length) {
                        var rgb = rgbAnsiColor(Number(params[++p]), Number(params[++p]), Number(params[++p]))
                        if (foreground) { style.fg = rgb; style.explicitFg = true } else style.bg = rgb
                    }
                }
            }
        }

        function applyCsi(parameters, finalChar) {
            var clean = String(parameters || "").replace(/^[?=>!]/, "")
            var parts = clean.length ? clean.split(";") : ["0"]
            var first = parts.length ? Number(parts[0] || 0) : 0
            if (isNaN(first)) first = 0

            if (finalChar === "m") { applySgr(clean); return }
            if (finalChar === "K") { eraseLine(first); return }
            if (finalChar === "J") {
                if (first === 2 || first === 3) {
                    finalRuns = []
                    line = []
                    cursor = 0
                }
                return
            }
            if (finalChar === "C") { cursor += Math.max(1, first || 1); return }
            if (finalChar === "D") { cursor = Math.max(0, cursor - Math.max(1, first || 1)); return }
            if (finalChar === "G" || finalChar === "`" ) { cursor = Math.max(0, (first || 1) - 1); return }
            if (finalChar === "H" || finalChar === "f") {
                var col = parts.length > 1 ? Number(parts[1] || 1) : 1
                cursor = Math.max(0, (isNaN(col) ? 1 : col) - 1)
                return
            }
            // Cursor shape, bracketed paste, mode toggles, device status and
            // other xterm controls are deliberately consumed rather than shown.
        }

        var i = 0
        while (i < raw.length) {
            var ch = raw.charAt(i)
            var cp = raw.charCodeAt(i)

            if (cp === 27) {
                if (i + 1 >= raw.length)
                    break
                var next = raw.charAt(i + 1)
                if (next === "[") {
                    var j = i + 2
                    while (j < raw.length) {
                        var finalCode = raw.charCodeAt(j)
                        if (finalCode >= 0x40 && finalCode <= 0x7E)
                            break
                        ++j
                    }
                    if (j >= raw.length)
                        break
                    applyCsi(raw.substring(i + 2, j), raw.charAt(j))
                    i = j + 1
                    continue
                }
                if (next === "]") {
                    var osc = i + 2
                    while (osc < raw.length) {
                        if (raw.charCodeAt(osc) === 7) { ++osc; break }
                        if (raw.charCodeAt(osc) === 27 && osc + 1 < raw.length && raw.charAt(osc + 1) === "\\") {
                            osc += 2
                            break
                        }
                        ++osc
                    }
                    i = osc
                    continue
                }
                i += 2
                continue
            }

            if (ch === "\r") { cursor = 0; ++i; continue }
            if (ch === "\n") { appendLineRuns(true); ++i; continue }
            if (ch === "\b") { cursor = Math.max(0, cursor - 1); ++i; continue }
            if (ch === "\t") {
                var target = (Math.floor(cursor / 8) + 1) * 8
                while (cursor < target) writeCharacter(" ")
                ++i
                continue
            }
            if (cp < 0x20 || cp === 0x7F) { ++i; continue }

            writeCharacter(ch)
            ++i
        }

        appendLineRuns(false)

        var plain = ""
        var html = ""
        var htmlLines = [""]
        for (var r = 0; r < finalRuns.length; ++r) {
            var run = finalRuns[r]
            if (run.text === "\n") {
                plain += "\n"
                html += "<br/>"
                htmlLines.push("")
                continue
            }
            plain += run.text
            var fg = run.style.reverse && run.style.bg.length ? run.style.bg : run.style.fg
            var bg = run.style.reverse ? run.style.fg : run.style.bg
            var css = "color:" + fg + ";"
            if (bg.length) css += "background-color:" + bg + ";"
            if (run.style.bold) css += "font-weight:700;"
            if (run.style.italic) css += "font-style:italic;"
            if (run.style.underline) css += "text-decoration:underline;"
            var span = "<span style=\"" + css + "\">" + htmlText(run.text) + "</span>"
            html += span
            htmlLines[htmlLines.length - 1] += span
        }

        function promptLine(value) {
            var trimmed = String(value || "").trim()
            if (trimmed.length === 0)
                return false
            var compactLine = trimmed.replace(/\s+/g, "")
            var compactPrompt = String(root.promptLabel || "").trim().replace(/\s+/g, "")
            if (compactPrompt.length > 0 && compactLine.indexOf(compactPrompt) === 0)
                return true
            return /^[^ \t\r\n]+@[^ \t\r\n]+(?:[ :][^$#>\r\n]*)?[$#>]\s*/.test(trimmed)
        }

        function detailOrPromptLine(value) {
            var trimmed = String(value || "").trim()
            if (trimmed.length === 0)
                return false
            if (trimmed.length <= 64 && /^[A-Za-z][A-Za-z0-9 _./-]*\s*:\s+\S/.test(trimmed))
                return true
            return promptLine(trimmed)
        }

        function promptTimestamp(ordinal, visibleLine) {
            var cache = root.promptTimestampCache

            // A shorter PTY buffer means the viewport was cleared/reset. Drop
            // old prompt times so a fresh session never inherits stale values.
            if (raw.length < Number(cache.__lastRawLength || 0)) {
                for (var key in cache) {
                    if (key !== "__lastRawLength")
                        delete cache[key]
                }
            }
            cache.__lastRawLength = raw.length

            var cacheKey = "prompt:" + ordinal
            var lineKey = String(visibleLine || "")
            var entry = cache[cacheKey]

            // The PTY first exposes an idle prompt, then rewrites that same
            // prompt line with the submitted command. That rewrite is the real
            // command-start boundary, so give it a fresh timestamp. Later
            // output does not change the prompt text and therefore keeps it.
            if (!entry || entry.line !== lineKey) {
                entry = {
                    line: lineKey,
                    time: Qt.formatTime(new Date(), "hh:mm:ss AP")
                }
                cache[cacheKey] = entry
            }
            return entry.time
        }

        // Stamp each real shell prompt inside the viewport. The timestamp is
        // inserted into the rendered history only; it never touches PS1,
        // .bashrc, the PTY stream, or command output. Because the timestamp is
        // cached by prompt occurrence + prompt-line state, command submission
        // gets its own start time and the returned prompt gets a new end time.
        var promptOrdinal = 0
        var stampedPlainLines = []
        for (var stampLine = 0; stampLine < renderedLines.length; ++stampLine) {
            var visibleLine = String(renderedLines[stampLine].plain || "")
            if (promptLine(visibleLine)) {
                var promptTime = promptTimestamp(promptOrdinal, visibleLine)
                var stamp = root.timestampVisible ? "[" + promptTime + "] " : ""
                if (stamp.length > 0) {
                    htmlLines[stampLine] = "<span style=\"color:#FFFFFF;\">" +
                                           htmlText(stamp) + "</span>" +
                                           htmlLines[stampLine]
                }
                stampedPlainLines.push(stamp + visibleLine)
                ++promptOrdinal
            } else {
                stampedPlainLines.push(visibleLine)
            }
        }
        plain = stampedPlainLines.join("\n")
        html = htmlLines.join("<br/>")

        // Treat everything emitted by the interactive shell before its first
        // real prompt as the startup presentation. This intentionally does not
        // inspect wording, ANSI colors, ASCII art, separator characters, or
        // .bashrc layout. A redesigned .bashrc therefore remains centered
        // automatically without requiring another TerminalViewport change.
        var firstContentLine = -1
        for (var lineIndex = 0; lineIndex < renderedLines.length; ++lineIndex) {
            if (renderedLines[lineIndex].nonSpaceCount > 0) {
                firstContentLine = lineIndex
                break
            }
        }

        var firstPromptLine = -1
        for (var promptCandidate = 0;
                promptCandidate < renderedLines.length; ++promptCandidate) {
            if (promptLine(renderedLines[promptCandidate].plain)) {
                firstPromptLine = promptCandidate
                break
            }
        }

        var startupStart = firstContentLine
        var startupEnd = firstPromptLine >= 0
                ? firstPromptLine - 1
                : renderedLines.length - 1

        // Ignore blank spacing immediately before the prompt. The .bashrc may
        // intentionally print it, but it should not enlarge the centered table
        // or alter where normal prompt/output history begins visually.
        while (startupEnd >= startupStart && startupEnd >= 0 &&
               renderedLines[startupEnd].nonSpaceCount === 0) {
            --startupEnd
        }

        // If the first actual content is already a prompt, Bash emitted no
        // startup presentation. Only in that case do we synthesize the red
        // underlined NeutronOS welcome fallback.
        var bannerDetected = startupStart >= 0 &&
                             startupEnd >= startupStart &&
                             (firstPromptLine < 0 || startupStart < firstPromptLine)
        var decoratedHtml = html
        var decoratedPlain = plain

        if (bannerDetected) {
            var beforeStartup = htmlLines.slice(0, startupStart).join("<br/>")
            var centeredStartup =
                    "<center><table cellspacing=\"0\" cellpadding=\"0\"><tr><td align=\"left\">" +
                    htmlLines.slice(startupStart, startupEnd + 1).join("<br/>") +
                    "</td></tr></table></center>"
            var afterStartup = htmlLines.slice(startupEnd + 1).join("<br/>")

            decoratedHtml =
                    (beforeStartup.length > 0 ? beforeStartup + "<br/>" : "") +
                    centeredStartup +
                    (afterStartup.length > 0 ? "<br/>" + afterStartup : "")
        } else {
            var fallbackText = "Welcome To NeutronOS Terminal"
            var fallbackHtml = "<div align=\"center\"><span style=\"color:#FF3048;font-size:30px;font-weight:700;text-decoration:underline;\">" +
                               "<u>" + htmlText(fallbackText) + "</u></span></div>"
            decoratedHtml = fallbackHtml + (html.length > 0 ? "<br/>" + html : "")
            decoratedPlain = fallbackText + (plain.length > 0 ? "\n" + plain : "")
        }

        return { plain: decoratedPlain, html: decoratedHtml, bannerDetected: bannerDetected }
    }

    function clampPosition(position) {
        return Math.max(0, Math.min(terminalText.length, Number(position || 0)))
    }

    function scrollToBottom() {
        if (!selectionMode)
            terminalText.cursorPosition = terminalText.length
        flick.contentY = Math.max(0, flick.contentHeight - flick.height)
    }

    function selectedText() {
        return terminalText.selectedText
    }

    function lineAndColumn(position) {
        var pos = Math.max(0, Math.min(root.renderedOutput.plain.length, Number(position || 0)))
        var before = root.renderedOutput.plain.substring(0, pos)
        var lineNumber = 1
        for (var i = 0; i < before.length; ++i) {
            if (before.charAt(i) === "\n")
                ++lineNumber
        }
        var lastBreak = before.lastIndexOf("\n")
        var column = pos - (lastBreak + 1) + 1
        return "LINE " + lineNumber + "  •  COL " + column
    }

    function targetForVerticalMove(position, direction) {
        var text = root.renderedOutput.plain
        var pos = Math.max(0, Math.min(text.length, Number(position || 0)))
        var lineStart = text.lastIndexOf("\n", Math.max(0, pos - 1)) + 1
        var column = pos - lineStart

        if (direction < 0) {
            if (lineStart <= 0)
                return -1
            var previousEnd = lineStart - 1
            var previousStart = text.lastIndexOf("\n", Math.max(0, previousEnd - 1)) + 1
            return Math.min(previousStart + column, previousEnd)
        }

        var currentEnd = text.indexOf("\n", pos)
        if (currentEnd < 0)
            return -1
        var nextStart = currentEnd + 1
        var nextEnd = text.indexOf("\n", nextStart)
        if (nextEnd < 0)
            nextEnd = text.length
        return Math.min(nextStart + column, nextEnd)
    }

    function revealIndicator() {
        var rect = terminalText.cursorRectangle
        var top = flick.contentY + 8
        var bottom = flick.contentY + flick.height - 8
        if (rect.y < top)
            flick.contentY = Math.max(0, rect.y - 18)
        else if (rect.y + rect.height > bottom)
            flick.contentY = Math.max(0, rect.y + rect.height - flick.height + 18)
    }

    function beginSelection() {
        selectionAnchor = clampPosition(terminalText.cursorPosition)
        selectionMode = true
        terminalText.deselect()
        terminalText.cursorPosition = selectionAnchor
        revealIndicator()
    }

    function cancelSelection() {
        var pos = clampPosition(terminalText.cursorPosition)
        selectionMode = false
        terminalText.deselect()
        terminalText.cursorPosition = pos
        revealIndicator()
    }

    function copyActiveSelection() {
        var text = terminalText.selectedText
        if (text.length > 0)
            root.copyRequested(text)
        cancelSelection()
        return text.length > 0
    }

    function moveIndicator(direction) {
        var text = root.renderedOutput.plain
        var current = clampPosition(terminalText.cursorPosition)
        var target = current

        if (direction === "left") {
            if (current <= 0) return false
            target = current - 1
        } else if (direction === "right") {
            if (current >= text.length) return false
            target = current + 1
        } else if (direction === "up") {
            target = targetForVerticalMove(current, -1)
            if (target < 0) return false
        } else if (direction === "down") {
            target = targetForVerticalMove(current, 1)
            if (target < 0) return false
        } else {
            return false
        }

        if (selectionMode)
            terminalText.select(selectionAnchor, target)
        else {
            terminalText.deselect()
            terminalText.cursorPosition = target
        }

        revealIndicator()
        return true
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, terminalText.implicitHeight)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        TextEdit {
            id: terminalText
            width: flick.width
            text: root.renderedOutput.html
            color: root.textColor
            selectedTextColor: "#02050A"
            selectionColor: root.selectionMode ? "#C56BFF" : root.accentColor
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.RichText
            font.family: "monospace"
            font.pixelSize: root.fontPixelSize

            onTextChanged: {
                if (!root.selectionMode)
                    cursorPosition = length
            }

            onSelectedTextChanged: {
                if (selectedText.length > 0)
                    root.selectionCaptured(selectedText)
            }

            Rectangle {
                x: terminalText.cursorRectangle.x
                y: terminalText.cursorRectangle.y
                width: root.selectionMode ? 3 : 2
                height: Math.max(16, terminalText.cursorRectangle.height)
                radius: 1
                visible: root.viewportFocused
                color: root.selectionMode ? "#D77CFF" : root.accentColor
                z: 50
                opacity: 0.95

                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 4
                    radius: 4
                    color: parent.color
                    opacity: 0.16
                    z: -1
                }
            }
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        width: 3
        height: Math.max(24, flick.visibleArea.heightRatio * parent.height)
        y: flick.visibleArea.yPosition * parent.height
        radius: 2
        color: root.selectionMode ? "#C56BFF" : root.accentColor
        opacity: 0.52
    }

    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 10
        anchors.bottomMargin: 11
        width: Math.max(0, parent.width - 300)
        visible: root.actionMessage.length > 0
        text: root.actionMessage
        color: root.actionError ? "#FF6B78" : "#27FF9A"
        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 0.5
        elide: Text.ElideRight
        z: 60
    }

    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 10
        anchors.bottomMargin: 8
        width: locationText.implicitWidth + 22
        height: 28
        radius: 14
        visible: root.viewportFocused
        color: root.selectionMode ? "#261035E8" : "#071727E8"
        border.width: 1
        border.color: root.selectionMode ? "#C56BFF" : root.accentColor

        Text {
            id: locationText
            anchors.centerIn: parent
            text: (root.selectionMode ? "SELECTING  •  " : "") + root.indicatorLocation
            color: root.selectionMode ? "#EABFFF" : "#B9EEFF"
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 1.0
        }
    }

    Keys.onPressed: function(event) {
        if (event.matches(StandardKey.Copy)) {
            root.copyRequested(terminalText.selectedText)
            event.accepted = true
        }
    }
}

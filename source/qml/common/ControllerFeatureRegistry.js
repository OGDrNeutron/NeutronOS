.pragma library

// User-facing controller gestures and their timing live here so Help and the
// Dashboard implementation cannot silently disagree.
var circleHomePressCount = 5
var circleHomeWindowMs = 1250
var dashboardManagerHoldMs = 650

var dashboardMappings = [
    { control: "PS / HOME", action: "Open or close the Dashboard tab selector from Desktop, System Overview, Security, Storage, Apps, Legacy, or a custom tab." },
    { control: "OPTIONS", action: "On Desktop, open the Apps / Widgets drawer. Outside Desktop, hold Options to open System Overview Manager." },
    { control: "CIRCLE x5", action: "Return once to the configured Home Dashboard Tab." },
    { control: "X", action: "Open, confirm, or apply the focused Dashboard action." },
    { control: "O / CIRCLE", action: "Close or cancel without committing a pending edit." },
    { control: "TRIANGLE", action: "On Desktop, enter quick move mode for the focused app or widget. Elsewhere, open details or preview." },
    { control: "SQUARE", action: "On Desktop, open app/widget details. Elsewhere, open actions; Running Apps includes Make App a Tab." },
    { control: "L1 / R1", action: "Change manager sections or Dashboard pages where shown." },
    { control: "D-PAD / STICKS", action: "Move deterministic controller focus. While the tab selector is open, Up/Down move only its highlight and underlying Dashboard, Legacy, and Notification actions are blocked." }
]

function dashboardHelpText() {
    var lines = []
    for (var index = 0; index < dashboardMappings.length; ++index)
        lines.push(dashboardMappings[index].control + "\n" + dashboardMappings[index].action)
    return lines.join("\n\n")
}

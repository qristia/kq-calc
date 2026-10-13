import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Live calculator: type an expression, see qalc's answer as you type.
// Enter copies the result and closes, Esc closes, Up/Down walk history.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool qalcMissing: false
  property string result: ""
  property string resultFor: ""
  property string runningFor: ""
  property bool acceptPending: false

  property var history: []
  property int historyPos: 0
  readonly property int historyLimit: 200
  readonly property string historyDir: Quickshell.env("HOME") + "/.local/state/kq-calc"

  // Shares the [menu] surface tokens, like the emoji picker and clipboard.
  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color answer: Commons.Color.accent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int rowHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(560), panel.width - Style.gapsOut * 2)

  readonly property string expression: input.text
  readonly property bool stale: root.resultFor !== root.expression

  function open(payloadJson) {
    root.opened = true
    root.acceptPending = false
    root.historyPos = root.history.length
    input.text = ""
    root.result = ""
    root.resultFor = ""
    Qt.callLater(function() { input.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "kq.calc")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function evaluate() {
    var expr = root.expression
    if (qalc.running || root.resultFor === expr) return
    if (!expr.trim()) {
      root.result = ""
      root.resultFor = expr
      return
    }
    root.runningFor = expr
    qalc.command = ["qalc", "-t", "--", expr]
    qalc.running = true
  }

  function finishEvaluation(output) {
    var lines = output.trim().split("\n")
    root.result = lines[lines.length - 1].trim()
    root.resultFor = root.runningFor
    if (root.acceptPending && !root.stale) root.accept()
    else Qt.callLater(root.evaluate)
  }

  function accept() {
    var expr = root.expression
    if (!expr.trim()) {
      root.dismiss()
      return
    }
    if (root.stale || qalc.running) {
      root.acceptPending = true
      debounce.stop()
      root.evaluate()
      return
    }
    root.acceptPending = false
    if (!root.result) return

    root.remember(expr)
    root.dismiss()
    Quickshell.execDetached(["wl-copy", "--", root.result])
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "Calculator", "-g", "󰃬", expr + " = " + root.result, "Copied to clipboard"])
  }

  function loadHistory(raw) {
    root.history = raw.split("\n").filter(function(line) { return line.trim() !== "" }).slice(-root.historyLimit)
    root.historyPos = root.history.length
  }

  function remember(expr) {
    if (root.history.length && root.history[root.history.length - 1] === expr) return
    root.history = root.history.concat([expr]).slice(-root.historyLimit)
    historyFile.setText(root.history.join("\n") + "\n")
  }

  function walkHistory(delta) {
    if (!root.history.length) return
    root.historyPos = Math.max(0, Math.min(root.history.length, root.historyPos + delta))
    input.text = root.historyPos < root.history.length ? root.history[root.historyPos] : ""
    input.cursorPosition = input.text.length
  }

  function deleteWordBack() {
    var left = input.text.slice(0, input.cursorPosition).replace(/\s+$/, "")
    var cut = left.lastIndexOf(" ") + 1
    input.remove(cut, input.cursorPosition)
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", root.historyDir])
    qalcCheck.running = true
  }

  Process {
    id: qalcCheck
    command: ["sh", "-c", "command -v qalc"]
    onExited: function(exitCode) { root.qalcMissing = exitCode !== 0 }
  }

  Process {
    id: qalc
    stdout: StdioCollector {
      onStreamFinished: root.finishEvaluation(text)
    }
  }

  Timer {
    id: debounce
    interval: 60
    onTriggered: root.evaluate()
  }

  FileView {
    id: historyFile
    path: root.historyDir + "/history"
    printErrors: false
    onLoaded: root.loadHistory(text())
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "kq-calc"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: card.contentTopInset + content.implicitHeight + card.contentBottomInset
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: input.forceActiveFocus() }

      Column {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        Item {
          width: parent.width
          height: root.rowHeight

          Text {
            id: icon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "󰃬"
            color: root.answer
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          TextInput {
            id: input
            anchors.left: icon.right
            anchors.leftMargin: Style.spacing.md
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: root.foreground
            selectionColor: Style.selectionFillFor(root.foreground, root.answer)
            selectedTextColor: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            clip: true
            focus: true

            onTextChanged: debounce.restart()

            Keys.onPressed: function(event) {
              var ctrl = event.modifiers & Qt.ControlModifier
              if (event.key === Qt.Key_Escape) {
                root.dismiss()
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.accept()
              } else if (event.key === Qt.Key_Up) {
                root.walkHistory(-1)
              } else if (event.key === Qt.Key_Down) {
                root.walkHistory(1)
              } else if (ctrl && event.key === Qt.Key_U) {
                input.text = ""
              } else if (ctrl && event.key === Qt.Key_W) {
                root.deleteWordBack()
              } else {
                return
              }
              event.accepted = true
            }

            Text {
              anchors.fill: parent
              verticalAlignment: Text.AlignVCenter
              visible: !input.text
              text: "Calculate…"
              color: root.foreground
              opacity: 0.58
              font: input.font
            }
          }
        }

        Text {
          width: parent.width
          visible: root.qalcMissing || (root.expression.trim() !== "" && root.result !== "")
          textFormat: Text.PlainText
          text: root.qalcMissing ? "qalc not found: install libqalculate" : "=  " + root.result
          color: root.qalcMissing ? Commons.Color.urgent : (root.stale ? root.foreground : root.answer)
          opacity: root.qalcMissing || !root.stale ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: !root.stale
          elide: Text.ElideRight
        }
      }
    }
  }
}

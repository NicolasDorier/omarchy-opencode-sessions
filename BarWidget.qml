import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root

    property var sessions: []
    readonly property color foreground: bar ? bar.barForeground : Color.foreground
    readonly property color idleColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.45)
    readonly property color busyColor: Color.accent
    readonly property color attentionColor: bar ? bar.urgent : Color.urgent
    readonly property string scanScript: decodeURIComponent(Qt.resolvedUrl("scripts/session-scan").toString().replace(/^file:\/\//, ""))

    function refresh() {
        if (!scanProcess.running)
            scanProcess.running = true;

    }

    function applySessions(output) {
        try {
            var parsed = JSON.parse(String(output || "[]"));
            sessions = Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            console.warn("opencode-sessions", "Ignoring invalid scanner output", e);
        }
    }

    function tooltip(session) {
        return String(session.title || "OpenCode session");
    }

    function focusSession(address) {
        if (!bar || !address)
            return ;

        var action = "hl.dsp.focus({ window = \"address:" + String(address) + "\" })";
        bar.run("hyprctl dispatch " + Util.shellQuote(action));
    }

    moduleName: "nicolasdorier.opencode-sessions"
    visible: sessions.length > 0
    implicitWidth: sessionGrid.implicitWidth
    implicitHeight: sessionGrid.implicitHeight

    Process {
        id: scanProcess

        command: [root.scanScript]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applySessions(text)
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (text.trim() !== "") {
                    console.warn("opencode-sessions", text.trim());
                }
            }
        }

    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Grid {
        id: sessionGrid

        anchors.centerIn: parent
        columns: root.vertical ? 1 : Math.max(1, root.sessions.length)
        spacing: Style.space(1)

        Repeater {
            model: root.sessions

            WidgetButton {
                id: sessionButton

                required property var modelData

                bar: root.bar
                text: ""
                labelVisible: false
                hasVisualContent: true
                fixedWidth: root.vertical ? root.barSize : Style.space(16)
                fixedHeight: root.vertical ? Style.space(16) : root.barSize
                tooltipText: root.tooltip(modelData)
                onPressed: root.focusSession(modelData.address)

                Item {
                    width: Style.space(10)
                    height: width
                    anchors.centerIn: parent

                    Rectangle {
                        anchors.fill: parent
                        visible: sessionButton.modelData.state === "attention"
                        radius: width / 2
                        color: "transparent"
                        border.width: Math.max(1, Style.space(1))
                        border.color: root.attentionColor
                    }

                    Rectangle {
                        width: Style.space(6)
                        height: width
                        anchors.centerIn: parent
                        radius: width / 2
                        color: sessionButton.modelData.state === "idle" ? "transparent" : (sessionButton.modelData.state === "attention" ? root.attentionColor : root.busyColor)
                        border.width: sessionButton.modelData.state === "idle" ? Math.max(1, Style.space(1)) : 0
                        border.color: root.idleColor
                    }

                }

            }

        }

    }

}

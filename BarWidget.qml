import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Panel {
    id: root

    property var sessions: []
    property var filteredSessions: []
    property string filterText: ""
    property int selectedIndex: 0
    readonly property bool vertical: bar ? bar.vertical : false
    readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal
    readonly property color foreground: bar ? bar.barForeground : Color.foreground
    readonly property color idleColor: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.45)
    readonly property color busyColor: Color.accent
    readonly property color attentionColor: bar ? bar.urgent : Color.urgent
    readonly property color menuBackground: Color.menu.background
    readonly property color menuForeground: Color.menu.text
    readonly property color menuBorder: Color.menu.border
    readonly property color menuScrim: Color.menu.scrim
    readonly property color selectedBackground: Color.menu.selectedBackground
    readonly property color selectedText: Color.menu.selectedText
    readonly property color selectedBorder: Color.menu.selectedBorder
    readonly property var menuBorderSpec: Border.surfaceSpec("menu", "border", menuBorder, Math.max(1, Style.space(2)))
    readonly property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
    readonly property int contentMargin: Style.spacing.panelPadding
    readonly property int contentSpacing: Style.spacing.md
    readonly property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
    readonly property int rowHeight: Math.max(Style.space(50), Style.font.body + Style.spacing.rowPaddingX * 2)
    readonly property int rowSpacing: Style.spacing.xs
    readonly property int rowsHeight: filteredSessions.length === 0 ? rowHeight : filteredSessions.length * rowHeight + Math.max(0, filteredSessions.length - 1) * rowSpacing
    readonly property string scanScript: decodeURIComponent(Qt.resolvedUrl("scripts/session-scan").toString().replace(/^file:\/\//, ""))

    function refresh() {
        if (!scanProcess.running)
            scanProcess.running = true;

    }

    function applySessions(output) {
        try {
            var parsed = JSON.parse(String(output || "[]"));
            sessions = Array.isArray(parsed) ? parsed : [];
            recomputeFiltered(false);
            if (sessions.length === 0)
                close();

        } catch (e) {
            console.warn("opencode-sessions", "Ignoring invalid scanner output", e);
        }
    }

    function recomputeFiltered(resetSelection) {
        var selectedAddress = "";
        if (!resetSelection && selectedIndex >= 0 && selectedIndex < filteredSessions.length)
            selectedAddress = String(filteredSessions[selectedIndex].address || "");

        var query = filterText.trim().toLowerCase();
        var result = [];
        for (var i = 0; i < sessions.length; i++) {
            var session = sessions[i];
            if (!query || String(session.title || "").toLowerCase().indexOf(query) >= 0)
                result.push(session);

        }
        result.sort(function(left, right) {
            var changed = Number(right.stateChangedAt || 0) - Number(left.stateChangedAt || 0);
            if (changed !== 0)
                return changed;

            return Number(right.startTime || 0) - Number(left.startTime || 0);
        });
        filteredSessions = result;
        if (resetSelection || result.length === 0) {
            selectedIndex = result.length > 0 ? 0 : -1;
            return ;
        }
        var preservedIndex = -1;
        for (var j = 0; j < result.length; j++) {
            if (String(result[j].address || "") === selectedAddress) {
                preservedIndex = j;
                break;
            }
        }
        selectedIndex = preservedIndex >= 0 ? preservedIndex : Math.min(Math.max(0, selectedIndex), result.length - 1);
    }

    function setFilter(value) {
        filterText = String(value || "");
        recomputeFiltered(true);
    }

    function select(delta) {
        if (filteredSessions.length === 0)
            return ;

        selectedIndex = ((selectedIndex + delta) % filteredSessions.length + filteredSessions.length) % filteredSessions.length;
        Qt.callLater(function() {
            sessionList.positionViewAtIndex(selectedIndex, ListView.Contain);
        });
    }

    function tooltip(session) {
        return String(session.title || "OpenCode session");
    }

    function focusSession(address, focusMenuNamespace) {
        if (!bar || !address)
            return ;

        close();
        var windowFocus = "hl.dsp.focus({ window = \"address:" + String(address) + "\" })";
        var action = focusMenuNamespace
            ? "function() hl.dispatch(hl.dsp.exec_raw(\"focuslayer\", \"omarchy-opencode-sessions-menu\")); hl.dispatch(" + windowFocus + ") end"
            : windowFocus;
        bar.run("hyprctl dispatch " + Util.shellQuote(action));
    }

    function activateIndex(index) {
        if (index >= 0 && index < filteredSessions.length)
            focusSession(filteredSessions[index].address, true);

    }

    function activateDefault() {
        activateIndex(selectedIndex);
    }

    moduleName: "nicolasdorier.opencode-sessions"
    ipcTarget: "nicolasdorier.opencode-sessions"
    visible: sessions.length > 0
    implicitWidth: sessionGrid.implicitWidth
    implicitHeight: sessionGrid.implicitHeight
    onOpenedChanged: {
        if (!opened)
            return ;

        setFilter("");
        Qt.callLater(function() {
            keyCatcher.forceActiveFocus();
        });
    }

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
                if (text.trim() !== "")
                    console.warn("opencode-sessions", text.trim());

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

                StateDot {
                    width: Style.space(10)
                    height: width
                    anchors.centerIn: parent
                    state: sessionButton.modelData.state
                }

            }

        }

    }

    PanelWindow {
        id: menuPanel

        visible: root.opened
        color: "transparent"
        WlrLayershell.namespace: "omarchy-opencode-sessions-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Rectangle {
            anchors.fill: parent
            color: root.menuScrim
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        BorderSurface {
            id: card

            width: Math.min(Style.space(360), menuPanel.width - Style.gapsOut * 2)
            height: Math.min(root.contentMargin * 2 + root.headerHeight + root.contentSpacing + root.rowsHeight, menuPanel.height - Style.gapsOut * 2)
            anchors.centerIn: parent
            radius: Style.cornerRadius
            color: root.menuBackground
            borderSpec: root.menuBorderSpec
            padding: root.contentMargin

            MouseArea {
                anchors.fill: parent
                onClicked: {
                }
            }

            Item {
                id: keyCatcher

                anchors.fill: parent
                anchors.topMargin: card.contentTopInset
                anchors.rightMargin: card.contentRightInset
                anchors.bottomMargin: card.contentBottomInset
                anchors.leftMargin: card.contentLeftInset
                focus: root.opened
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        if (root.filterText)
                            root.setFilter("");
                        else
                            root.close();
                        event.accepted = true;
                    } else if (Util.editsFilter(event, root.filterText)) {
                        root.setFilter(Util.editedFilter(event, root.filterText));
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        root.select(-1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        root.select(1);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activateDefault();
                        event.accepted = true;
                    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                        root.setFilter(root.filterText + event.text);
                        event.accepted = true;
                    }
                }

                Column {
                    anchors.fill: parent
                    spacing: root.contentSpacing

                    Item {
                        width: parent.width
                        height: root.headerHeight

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.filterText || "OpenCode Sessions..."
                            textFormat: Text.PlainText
                            color: root.menuForeground
                            opacity: root.filterText ? 1 : 0.58
                            font.family: Style.font.menuFamily
                            font.pixelSize: Style.font.heading
                            elide: Text.ElideRight
                        }

                    }

                    Item {
                        width: parent.width
                        height: Math.min(root.rowsHeight, keyCatcher.height - root.headerHeight - root.contentSpacing)

                        ListView {
                            id: sessionList

                            anchors.fill: parent
                            model: root.filteredSessions
                            spacing: root.rowSpacing
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: BorderSurface {
                                id: sessionRow

                                required property var modelData
                                required property int index
                                readonly property bool hasCursor: index === root.selectedIndex

                                width: sessionList.width
                                height: root.rowHeight
                                radius: Style.cornerRadius
                                color: hasCursor ? root.selectedBackground : "transparent"
                                borderSpec: hasCursor ? root.selectedBorderSpec : Border.none()

                                StateDot {
                                    id: rowState

                                    width: Style.space(10)
                                    height: width
                                    anchors.left: parent.left
                                    anchors.leftMargin: Style.space(18)
                                    anchors.verticalCenter: parent.verticalCenter
                                    state: sessionRow.modelData.state
                                }

                                Text {
                                    anchors.left: rowState.right
                                    anchors.leftMargin: Style.space(10)
                                    anchors.right: parent.right
                                    anchors.rightMargin: Style.space(18)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(sessionRow.modelData.title || "OpenCode session")
                                    textFormat: Text.PlainText
                                    color: sessionRow.hasCursor ? root.selectedText : root.menuForeground
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.heading
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.activateIndex(sessionRow.index)
                                }

                            }

                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.filteredSessions.length === 0
                            text: root.filterText ? "No matches for " + root.filterText : "Nothing here yet"
                            textFormat: Text.PlainText
                            color: root.menuForeground
                            opacity: 0.7
                            font.family: Style.font.menuFamily
                            font.pixelSize: Style.font.title
                        }

                    }

                }

            }

        }

    }

    component StateDot: Item {
        property string state: "idle"

        Rectangle {
            anchors.fill: parent
            visible: parent.state === "attention"
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
            color: parent.state === "idle" ? "transparent" : (parent.state === "attention" ? root.attentionColor : root.busyColor)
            border.width: parent.state === "idle" ? Math.max(1, Style.space(1)) : 0
            border.color: root.idleColor
        }

    }

}

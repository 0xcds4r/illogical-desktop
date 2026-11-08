import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.desktop

Item {
    id: root
    property var widgetData: ({})
    property var host: null

    readonly property color noteColor: {
        switch (widgetData.style) {
        case "pink": return "#F6C6D0";
        case "blue": return "#BFD8F2";
        case "green": return "#CBE7C4";
        default: return "#F6E39B";
        }
    }

    rotation: ((widgetData.id ?? "").length * 7 % 5) - 2

    // Persist only when the editor gives up focus, so the widget is not rebuilt
    // (and the caret not lost) on every keystroke.
    function persist() {
        if (editor.text !== (root.widgetData.text ?? ""))
            DesktopWidgets.update(root.widgetData.id, { text: editor.text });
    }

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: root.noteColor
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.15)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 6
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.06)
            radius: 4
        }
    }

    TextEdit {
        id: editor
        anchors {
            fill: parent
            margins: 16
            topMargin: 40
        }
        text: root.widgetData.text ?? ""
        color: "#2b2b2b"
        selectionColor: "#8a7a3a"
        selectedTextColor: "#ffffff"
        wrapMode: TextEdit.Wrap
        font.pixelSize: Appearance.font.pixelSize.small
        selectByMouse: true
        persistentSelection: true

        onActiveFocusChanged: {
            if (!activeFocus)
                root.persist();
        }
    }

    Component.onDestruction: root.persist()
}

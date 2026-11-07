import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.desktop

// Colour row with a live swatch, hex field and an expandable HSV picker.
ColumnLayout {
    id: root

    property string label: ""
    property string value: "#FFFFFF"
    property bool expanded: false

    signal changed(string newValue)

    readonly property var palette: [
        "#FFFFFF", "#E0E0E0", "#BDBDBD", "#9E9E9E", "#757575", "#424242", "#212121", "#000000",
        "#F44336", "#E91E63", "#9C27B0", "#673AB7", "#3F51B5", "#2196F3", "#03A9F4", "#00BCD4",
        "#009688", "#4CAF50", "#8BC34A", "#CDDC39", "#FFEB3B", "#FFC107", "#FF9800", "#FF5722",
        "#4A90D9", "#5C6BC0", "#26A69A", "#66BB6A", "#FFA726", "#EF5350", "#EC407A", "#AB47BC"
    ]

    readonly property color currentColor: Qt.color(root.value)
    readonly property real hue: currentColor.hsvHue < 0 ? 0 : currentColor.hsvHue
    readonly property real saturation: currentColor.hsvSaturation
    readonly property real brightness: currentColor.hsvValue

    function hexPart(channel) {
        const text = Math.max(0, Math.min(255, Math.round(channel * 255))).toString(16).toUpperCase();
        return text.length === 1 ? "0" + text : text;
    }

    function toHex(color) {
        return "#" + hexPart(color.r) + hexPart(color.g) + hexPart(color.b);
    }

    function pickSaturationValue(x, y, width, height) {
        const saturation = Math.max(0, Math.min(1, x / Math.max(1, width)));
        const value = 1 - Math.max(0, Math.min(1, y / Math.max(1, height)));
        root.changed(root.toHex(Qt.hsva(root.hue, saturation, value, 1)));
    }

    function pickHue(y, height) {
        const hue = Math.max(0, Math.min(1, y / Math.max(1, height)));
        root.changed(root.toHex(Qt.hsva(hue,
            root.saturation < 0.001 ? 1 : root.saturation,
            root.brightness < 0.001 ? 1 : root.brightness, 1)));
    }

    Layout.fillWidth: true
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        StyledText {
            Layout.preferredWidth: 200
            text: root.label
            color: Appearance.colors.colOnSecondaryContainer
        }

        Rectangle {
            implicitWidth: 52
            implicitHeight: 26
            radius: 8
            color: root.value
            border.width: 1
            border.color: Appearance.colors.colOnLayer2

            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: 6
                color: "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.25)
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 32
            radius: 8
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: hexField.acceptableInput ? Appearance.colors.colLayer0Border : Appearance.colors.colError

            TextInput {
                id: hexField
                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 10
                }
                verticalAlignment: TextInput.AlignVCenter
                text: root.value
                color: Appearance.colors.colOnLayer1
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
                selectByMouse: true

                validator: RegularExpressionValidator {
                    regularExpression: /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/
                }

                onEditingFinished: {
                    if (acceptableInput)
                        root.changed(text.toUpperCase());
                }
            }
        }

        Rectangle {
            implicitWidth: 30
            implicitHeight: 30
            radius: 15
            color: expandMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.expanded ? "expand_less" : "expand_more"
                iconSize: 20
                color: Appearance.colors.colOnLayer2
            }

            MouseArea {
                id: expandMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }
        }
    }

    RowLayout {
        visible: root.expanded
        Layout.fillWidth: true
        Layout.topMargin: 4
        spacing: 10

        // Saturation / value square.
        Rectangle {
            id: svSquare
            implicitWidth: 300
            implicitHeight: 160
            radius: 10
            clip: true
            color: Qt.hsva(root.hue, 1, 1, 1)

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#FFFFFF" }
                    GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 1.0; color: "#000000" }
                }
            }

            Rectangle {
                width: 16
                height: 16
                radius: 8
                x: Math.max(0, Math.min(svSquare.width - width, root.saturation * svSquare.width - width / 2))
                y: Math.max(0, Math.min(svSquare.height - height, (1 - root.brightness) * svSquare.height - height / 2))
                color: "transparent"
                border.width: 2
                border.color: "white"

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 6
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.45)
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                onPressed: mouse => root.pickSaturationValue(mouse.x, mouse.y, width, height)
                onPositionChanged: mouse => {
                    if (pressed)
                        root.pickSaturationValue(mouse.x, mouse.y, width, height);
                }
            }
        }

        // Hue strip.
        Rectangle {
            id: hueStrip
            implicitWidth: 20
            implicitHeight: 160
            radius: 10
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: "#FF0000" }
                GradientStop { position: 0.17; color: "#FFFF00" }
                GradientStop { position: 0.33; color: "#00FF00" }
                GradientStop { position: 0.5; color: "#00FFFF" }
                GradientStop { position: 0.67; color: "#0000FF" }
                GradientStop { position: 0.83; color: "#FF00FF" }
                GradientStop { position: 1.0; color: "#FF0000" }
            }

            Rectangle {
                width: parent.width + 4
                height: 10
                radius: 5
                x: -2
                y: Math.max(0, Math.min(hueStrip.height - height, root.hue * hueStrip.height - height / 2))
                color: Qt.hsva(root.hue, 1, 1, 1)
                border.width: 2
                border.color: "white"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeVerCursor
                onPressed: mouse => root.pickHue(mouse.y, height)
                onPositionChanged: mouse => {
                    if (pressed)
                        root.pickHue(mouse.y, height);
                }
            }
        }

        // Readout.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 6

            StyledText {
                text: root.value
                color: Appearance.colors.colOnLayer1
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.small
            }

            StyledText {
                text: `R ${Math.round(root.currentColor.r * 255)}  G ${Math.round(root.currentColor.g * 255)}  B ${Math.round(root.currentColor.b * 255)}`
                color: Appearance.colors.colOnLayer2
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            StyledText {
                text: `H ${Math.round(root.hue * 360)}°  S ${Math.round(root.saturation * 100)}%  V ${Math.round(root.brightness * 100)}%`
                color: Appearance.colors.colOnLayer2
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }

    // Preset palette.
    Flow {
        visible: root.expanded
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 6

        Repeater {
            model: root.palette

            delegate: Rectangle {
                width: 24
                height: 24
                radius: 12
                color: modelData
                border.width: root.value.toLowerCase() === modelData.toLowerCase() ? 2 : 1
                border.color: root.value.toLowerCase() === modelData.toLowerCase()
                    ? Appearance.colors.colPrimary
                    : Appearance.colors.colLayer0Border

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.changed(modelData)
                }
            }
        }
    }

    onValueChanged: {
        if (!hexField.activeFocus)
            hexField.text = root.value;
    }
}

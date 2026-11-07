import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.desktop

// Colour row with a live swatch, hex field and an expandable palette.
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
            radius: Appearance.rounding.verysmall
            color: root.value
            border.width: 1
            border.color: Appearance.colors.colOnLayer2

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expanded = !root.expanded
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 30
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: hexField.acceptableInput ? Appearance.colors.colLayer0Border : Appearance.colors.colError

            TextInput {
                id: hexField
                anchors {
                    fill: parent
                    leftMargin: 8
                    rightMargin: 8
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
            implicitWidth: 28
            implicitHeight: 28
            radius: 14
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

    Flow {
        visible: root.expanded
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 4

        Repeater {
            model: root.palette

            delegate: Rectangle {
                width: 26
                height: 26
                radius: 6
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

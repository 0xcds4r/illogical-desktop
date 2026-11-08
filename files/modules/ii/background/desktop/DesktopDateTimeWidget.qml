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

    ColumnLayout {
        visible: root.widgetData.style !== "inline"
        anchors.centerIn: parent
        spacing: 2

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(DesktopClock.now, "HH:mm")
            color: Appearance.colors.colOnLayer1
            font.pixelSize: 42
            font.weight: Font.DemiBold
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(DesktopClock.now, "dddd, d MMMM yyyy")
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    RowLayout {
        visible: root.widgetData.style === "inline"
        anchors.centerIn: parent
        spacing: 14

        StyledText {
            text: Qt.formatDateTime(DesktopClock.now, "HH:mm")
            color: Appearance.colors.colOnLayer1
            font.pixelSize: 34
            font.weight: Font.DemiBold
        }

        StyledText {
            text: Qt.formatDateTime(DesktopClock.now, "ddd, d MMM yyyy")
            color: Appearance.colors.colOnLayer2
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }
}

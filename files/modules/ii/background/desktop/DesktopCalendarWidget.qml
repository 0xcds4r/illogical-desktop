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

    readonly property date now: DesktopClock.now
    property var days: root.buildDays()

    function buildDays() {
        const today = root.now;
        const first = new Date(today.getFullYear(), today.getMonth(), 1);
        const startOffset = (first.getDay() + 6) % 7; // Monday first
        const daysInMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();
        const result = [];
        for (let i = 0; i < 42; i++) {
            const dayNumber = i - startOffset + 1;
            result.push({
                day: dayNumber,
                inMonth: dayNumber >= 1 && dayNumber <= daysInMonth,
                today: dayNumber === today.getDate()
            });
        }
        return result;
    }

    Connections {
        target: DesktopClock
        function onNowChanged() {
            const marker = root.now.getFullYear() * 10000 + (root.now.getMonth() + 1) * 100 + root.now.getDate();
            if (marker !== root._marker) {
                root._marker = marker;
                root.days = root.buildDays();
            }
        }
    }

    property int _marker: 0

    Component.onCompleted: {
        root._marker = root.now.getFullYear() * 10000 + (root.now.getMonth() + 1) * 100 + root.now.getDate();
        root.days = root.buildDays();
    }

    ColumnLayout {
        visible: root.widgetData.style !== "compact"
        anchors.fill: parent
        anchors.margins: 16
        spacing: 6

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(root.now, "MMMM yyyy")
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.large
            font.weight: Font.DemiBold
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            spacing: 0

            Repeater {
                model: ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
                delegate: StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: 10
                }
            }
        }

        Grid {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            columnSpacing: 0
            rowSpacing: 0

            Repeater {
                model: root.days
                delegate: Item {
                    width: parent.width / 7
                    height: parent.height / 6

                    Rectangle {
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        radius: 13
                        color: modelData.today ? Appearance.colors.colPrimary : "transparent"
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: modelData.inMonth ? String(modelData.day) : ""
                        color: modelData.today ? Appearance.colors.colOnPrimary
                             : modelData.inMonth ? Appearance.colors.colOnLayer1
                             : Appearance.colors.colOnLayer2
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }
    }

    RowLayout {
        visible: root.widgetData.style === "compact"
        anchors.centerIn: parent
        spacing: 14

        StyledText {
            text: Qt.formatDateTime(root.now, "d")
            color: Appearance.colors.colOnLayer1
            font.pixelSize: 48
            font.weight: Font.DemiBold
        }

        ColumnLayout {
            spacing: 0
            StyledText {
                text: Qt.formatDateTime(root.now, "dddd")
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.normal
            }
            StyledText {
                text: Qt.formatDateTime(root.now, "MMMM yyyy")
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }
    }
}

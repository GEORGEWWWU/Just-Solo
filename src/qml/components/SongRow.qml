import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// SongRow — 共享歌曲行组件
// model / index 由 ListView delegate 自动注入
// ============================================================
Rectangle {
    id: songRow
    width: parent ? parent.width : 200
    // 动态高度：排序时若作为放置目标，上方展开 58px 占位（50 灰卡 + 8 间距）
    implicitHeight: 50 + dropGap
    height: implicitHeight
    clip: false                      // 允许灰卡超出边界（初始展开时）

    property real dropGap: sortMode && showDropAbove ? 58 : 0
    Behavior on dropGap { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    property real placeholderH: sortMode && showDropAbove ? 50 : 0
    Behavior on placeholderH { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    property real placeholderOpacity: sortMode && showDropAbove ? 0.9 : 0
    Behavior on placeholderOpacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    radius: 8
    color: isDragged ? "#4a4a7a"
         : (sortMode ? "#2e2e50" : (isCurrent ? "#36365a"
         : (rowMouse.containsMouse ? "#2a2a48" : "#222236")))
    Behavior on color { ColorAnimation { duration: 150 } }

    // ---- 放置占位灰卡（排序模式，目标行上方） ----
    Rectangle {
        id: gapPlaceholder
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: placeholderH
        opacity: placeholderOpacity
        color: "#3a3a55"
        radius: 8
        border.color: "#555570"
        border.width: 1.5
        clip: true

        Label {
            anchors.centerIn: parent
            text: "放置到此处"
            font.family: songRow.fontFamily
            font.pixelSize: 14
            color: "#777"
            visible: parent.height > 20
        }
    }

    // ListView delegate 自动注入
    required property var    model
    required property int    index

    // 外部显式传入
    required property bool   isCurrent
    required property string fontFamily
    required property real   colCover
    required property real   colTitle
    required property real   colArtist
    required property real   colAlbum
    required property real   colDuration
    required property real   colPlay
    required property bool   sortMode
    required property bool   isDragged
    required property bool   showDropAbove
    required property bool   showDropBelow

    // 拖拽信号：通知 MusicListView 开始/移动/结束拖拽
    signal dragStarted(real mouseY)
    signal dragMoved(real mouseY)
    signal dragEnded()

    signal leftClicked()
    signal rightClicked()

    // 歌曲行内容区域（灰卡下方）
    RowLayout {
        id: rowContent
        anchors { top: gapPlaceholder.bottom; topMargin: sortMode && showDropAbove ? 13 : 5; left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 5; bottom: parent.bottom; bottomMargin: 5 }
        spacing: 0

        // ---- 拖拽手柄（排序模式可见） ----
        Item {
            Layout.preferredWidth: sortMode ? 28 : 0
            Layout.preferredHeight: parent.height
            Layout.alignment: Qt.AlignVCenter
            visible: sortMode

            Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            Image {
                anchors.centerIn: parent
                source: "qrc:/qt/qml/JustSolo/data/image/drag.png"
                width: 16; height: 16
                opacity: dragHandleMA.containsMouse ? 1.0 : 0.5
                Behavior on opacity { NumberAnimation { duration: 100 } }
            }

            MouseArea {
                id: dragHandleMA
                anchors.fill: parent
                cursorShape: Qt.SizeVerCursor
                hoverEnabled: true

                property bool active: false

                onPressed: function(mouse) {
                    active = true
                    var pt = mapToItem(songRow, mouse.x, mouse.y)
                    songRow.dragStarted(pt.y)
                }
                onPositionChanged: function(mouse) {
                    if (active) {
                        var pt = mapToItem(songRow, mouse.x, mouse.y)
                        songRow.dragMoved(pt.y)
                    }
                }
                onReleased: {
                    if (active) {
                        active = false
                        songRow.dragEnded()
                    }
                }
                onCanceled: {
                    if (active) {
                        active = false
                        songRow.dragEnded()
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: Math.min(songRow.colCover, 40)
            Layout.preferredHeight: 40
            Layout.maximumWidth: 40
            Layout.alignment: Qt.AlignVCenter
            radius: 6; color: "#3a3a55"
            Image {
                anchors.fill: parent; anchors.margins: 2
                sourceSize.width: 40; sourceSize.height: 40
                source: model.cover || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Label {
                anchors.centerIn: parent
                text: "\u266B"; font.family: songRow.fontFamily; font.pixelSize: 18; color: "#666"
                visible: !model.cover || model.cover === ""
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: songRow.colTitle
            Layout.preferredHeight: 40
            Layout.alignment: Qt.AlignVCenter
            Label {
                text: model.name || ""
                font.family: songRow.fontFamily; font.pixelSize: 14
                font.bold: true; color: "#d4d4d4"
                elide: Text.ElideRight
                width: parent.width
                anchors.top: parent.top; anchors.left: parent.left
            }
            Rectangle {
                visible: model.quality && model.quality !== ""
                width: Math.max(qualityText.contentWidth + 8, 20)
                height: 16; radius: 3; color: "#D4AF37"
                anchors.bottom: parent.bottom; anchors.left: parent.left
                Label {
                    id: qualityText
                    text: model.quality || ""
                    font.family: songRow.fontFamily; font.pixelSize: 10; font.bold: true
                    color: "white"; anchors.centerIn: parent
                }
            }
        }

        Label {
            text: model.artist || "未知"
            font.family: songRow.fontFamily; font.pixelSize: 14; color: "#969696"
            elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: songRow.colArtist
        }

        Label {
            text: model.album || ""
            font.family: songRow.fontFamily; font.pixelSize: 14; color: "#888888"
            elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: songRow.colAlbum
        }

        Label {
            text: model.durationText || ""
            font.family: songRow.fontFamily; font.pixelSize: 14; color: "#969696"
            verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
            Layout.fillHeight: true; Layout.preferredWidth: songRow.colDuration
        }

        Item {
            Layout.preferredWidth: songRow.colPlay
            Layout.preferredHeight: 20; Layout.alignment: Qt.AlignVCenter
            Image {
                anchors.centerIn: parent
                source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                width: 18; height: 18; opacity: 0.35
                visible: !songRow.isCurrent
            }
            Image {
                anchors.centerIn: parent
                source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                width: 18; height: 18
                visible: songRow.isCurrent && !musicManager.isPlaying
            }
            Image {
                anchors.centerIn: parent
                source: "qrc:/qt/qml/JustSolo/data/image/playing.png"
                width: 18; height: 18
                visible: songRow.isCurrent && musicManager.isPlaying
            }
        }
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent; hoverEnabled: true
        cursorShape: sortMode ? Qt.ArrowCursor : Qt.PointingHandCursor
        enabled: !sortMode
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton)
                songRow.rightClicked()
            else
                songRow.leftClicked()
        }
    }
}

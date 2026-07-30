// ============================================================
// MiniPlayer — 迷你播放小窗（300×100，无边框，独立于主窗口）
// ============================================================
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

Window {
    id: miniWindow
    width: 300
    height: 100
    minimumWidth: 300
    minimumHeight: 100
    maximumWidth: 300
    maximumHeight: 100
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: "Just Solo"

    required property string fontFamily

    // 退出小窗信号
    signal exitMiniMode()

    // ============================================================
    // 字体加载
    // ============================================================
    FontLoader {
        id: miniFont
        source: "qrc:/qt/qml/JustSolo/data/font/HarmonyOS_Sans_SC_Regular.ttf"
    }
    readonly property string _font: miniFont.name || fontFamily

    // ============================================================
    // 圆角背景（与主页内容区背景色一致 #181818）
    // ============================================================
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "#181818"
        clip: true
    }

    // ============================================================
    // 全窗口拖动（置于底层，按钮等交互元素不受影响）
    // ============================================================
    MouseArea {
        id: dragArea
        anchors.fill: parent
        z: -1
        cursorShape: Qt.OpenHandCursor
        onPressed: { miniWindow.startSystemMove() }
    }

    // ============================================================
    // 主布局
    // ============================================================
    RowLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 8

        // ---- 左侧：封面 ----
        Rectangle {
            Layout.preferredWidth: 76
            Layout.preferredHeight: 76
            Layout.alignment: Qt.AlignVCenter
            radius: 6
            color: "#3A3A3A"

            Image {
                id: coverImg
                anchors.fill: parent; anchors.margins: 1
                source: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentCover || "") : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: source !== ""
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: ShaderEffectSource {
                        sourceItem: Rectangle {
                            width: coverImg.width; height: coverImg.height; radius: 5
                        }
                    }
                }
            }
            Label {
                anchors.centerIn: parent
                text: "\u266B"
                font.family: _font; font.pixelSize: 28; color: "#666"
                visible: (typeof musicManager === "undefined" || !musicManager || !musicManager.currentCover)
            }
        }

        // ---- 右侧：标题 + 进度条 + 控制按钮 ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 2
            spacing: 2

            // ---- 歌曲标题（居中、放大） ----
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 2
                clip: true
                Layout.minimumHeight: 22

                property bool needsScroll: titleText.contentWidth > width

                Text {
                    id: titleText
                    text: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentTitle || "未在播放") : "未在播放"
                    font.family: _font; font.pixelSize: 20; font.bold: true; color: "#f0f0f0"
                    y: (parent.height - contentHeight) / 2
                    x: parent.needsScroll ? parent.width : (parent.width - contentWidth) / 2

                    SequentialAnimation on x {
                        running: titleText.parent && titleText.parent.needsScroll && miniWindow.visible
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: titleText.parent ? titleText.parent.width : 0
                            to: -titleText.contentWidth
                            duration: Math.max(5000, ((titleText.parent ? titleText.parent.width : 0) + titleText.contentWidth) * 10)
                            easing.type: Easing.Linear
                        }
                        PauseAnimation { duration: 600 }
                        PropertyAnimation { property: "x"; to: titleText.parent ? titleText.parent.width : 0; duration: 0 }
                    }
                }
            }

            // ---- 进度条 ----
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                Layout.topMargin: 1

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 3
                    radius: 1.5; color: "#3A3A3A"

                    Rectangle {
                        width: parent.width * (musicManager.duration > 0 ? musicManager.position / musicManager.duration : 0)
                        height: parent.height; radius: 1.5; color: "#3B82F6"
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                }

                MouseArea {
                    anchors.fill: parent; anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    function seek(mx) {
                        var ratio = Math.max(0, Math.min(1, mx / width))
                        if (musicManager.duration > 0) {
                            musicManager.seek(ratio * musicManager.duration)
                            if (!musicManager.isPlaying) musicManager.play()
                        }
                    }
                    onClicked: function(m) { seek(m.x) }
                    onPressed: function(m) { seek(m.x) }
                    onPositionChanged: function(m) { if (pressed) seek(m.x) }
                }
            }

            // ---- 底部控制栏（三大按钮居中） ----
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 1
                spacing: 0

                // ---- 左侧：循环模式 ----
                RowLayout {
                    spacing: 10

                    // 循环模式（带弹出菜单）
                    Item {
                        id: modeItem
                        Layout.preferredWidth: 20; Layout.preferredHeight: 20

                        property var modeIcons: ["mode_sequential.png", "mode_loop.png", "mode_single.png", "mode_shuffle.png", "mode_stop.png"]

                        Image {
                            anchors.centerIn: parent
                            source: {
                                var m = (typeof musicManager !== "undefined" && musicManager) ? musicManager.playMode : 0
                                return "qrc:/qt/qml/JustSolo/data/image/" + modeItem.modeIcons[m]
                            }
                            width: 18; height: 18; opacity: 0.8
                        }

                        Timer {
                            id: hideModeTimer
                            interval: 200
                            onTriggered: modePopup.close()
                        }
                        function showModePopup() { hideModeTimer.stop(); modePopup.open() }
                        function scheduleModeHide() { hideModeTimer.restart() }

                        MouseArea {
                            anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: modeItem.showModePopup()
                            onExited: modeItem.scheduleModeHide()
                        }

                        Popup {
                            id: modePopup
                            x: parent.width / 2 - width / 2
                            y: -height - 8
                            padding: 4

                            background: Rectangle {
                                radius: 6; color: "#222222"
                                border.color: "#3A3A3A"; border.width: 1
                            }

                            contentItem: Row {
                                spacing: 4
                                Repeater {
                                    model: 5
                                    Image {
                                        source: "qrc:/qt/qml/JustSolo/data/image/" + modeItem.modeIcons[index]
                                        sourceSize.width: 18; sourceSize.height: 18
                                        width: 18; height: 18
                                        fillMode: Image.PreserveAspectFit
                                        opacity: (itemMA.containsMouse || musicManager.playMode === index) ? 1.0 : 0.5
                                        Behavior on opacity { NumberAnimation { duration: 120 } }

                                        MouseArea {
                                            id: itemMA
                                            anchors.fill: parent; anchors.margins: -3
                                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onEntered: modeItem.showModePopup()
                                            onExited: modeItem.scheduleModeHide()
                                            onClicked: {
                                                if (typeof musicManager !== "undefined" && musicManager)
                                                    musicManager.playMode = index
                                                modePopup.close()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- 左侧弹性占位 ----
                Item { Layout.fillWidth: true }

                // ---- 中央：三大播放控制按钮 ----
                RowLayout {
                    spacing: 10
                    Layout.alignment: Qt.AlignHCenter

                    // 上一首
                    Item {
                        Layout.preferredWidth: 20; Layout.preferredHeight: 20
                        Image {
                            anchors.centerIn: parent
                            source: "qrc:/qt/qml/JustSolo/data/image/prve.png"
                            width: 20; height: 20; opacity: 0.8
                        }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { if (typeof musicManager !== "undefined" && musicManager) musicManager.previous() }
                        }
                    }

                    // 播放/暂停
                    Rectangle {
                        Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 14
                        color: "#3A3A3A"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Image {
                            anchors.centerIn: parent
                            source: {
                                if (typeof musicManager === "undefined" || !musicManager) return ""
                                return musicManager.isPlaying
                                    ? "qrc:/qt/qml/JustSolo/data/image/playing.png"
                                    : "qrc:/qt/qml/JustSolo/data/image/play.png"
                            }
                            width: 16; height: 16; anchors.horizontalCenterOffset: (!musicManager || !musicManager.isPlaying) ? 1 : 0
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof musicManager === "undefined" || !musicManager) return
                                if (musicManager.currentIndex < 0) return
                                if (musicManager.isPlaying) musicManager.pause()
                                else musicManager.play()
                            }
                        }
                    }

                    // 下一首
                    Item {
                        Layout.preferredWidth: 20; Layout.preferredHeight: 20
                        Image {
                            anchors.centerIn: parent
                            source: "qrc:/qt/qml/JustSolo/data/image/next.png"
                            width: 20; height: 20; opacity: 0.8
                        }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { if (typeof musicManager !== "undefined" && musicManager) musicManager.next() }
                        }
                    }
                }

                // ---- 右侧弹性占位 ----
                Item { Layout.fillWidth: true }

                // ---- 右侧：退出小窗 ----
                Item {
                    Layout.preferredWidth: 20; Layout.preferredHeight: 20
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/JustSolo/data/image/mini-exit.png"
                        width: 18; height: 18; opacity: 0.8
                    }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: miniWindow.exitMiniMode()
                    }
                }
            }
        }
    }
}

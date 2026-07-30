import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts

Item {
    id: root

    required property string fontFamily

    property bool opening: false
    property int _lastScroll: -1
    property int _pastIdx: -1  // 已播放到的歌词行索引（前进时增大，回退时重置）

    // 进入迷你小窗模式信号
    signal enterMiniMode()

    // 页面滑动偏移量（初始推至视口外，动画直接修改此值，避免绑定被 QML 重求值）
    property real _slideOffset: root.height

    opacity: 0
    visible: false

    // 使用位移来实现滑动，初始把整个页面向下推至视口外 (y: root.height)
    transform: Translate {
        id: slider
        y: _slideOffset
    }

    function fmtTime(ms) {
        if (ms <= 0) return "0:00"
        var s = Math.floor(ms / 1000)
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
    }

    function close() {
        if (!visible || opening) return
        closeAnim.start()
    }

    // 强制重新打开（处理意外隐藏/状态不同步的情况）
    function reopen() {
        openAnim.stop()
        closeAnim.stop()
        opening = true
        _lastScroll = -1
        if (visible) {
            // visible 仍为 true，但可能被动画中断导致 opacity=0 / _slideOffset=height
            // 直接重置状态并主动启动打开动画
            _slideOffset = root.height
            opacity = 0
            openAnim.start()
        } else {
            visible = true
            // onVisibleChanged 中将启动 openAnim.start()
        }
    }

    onVisibleChanged: {
        if (visible) {
            _lastScroll = -1
            opening = true
            openAnim.start() // 直接启动动画，不再等待毛玻璃渲染
        } else {
            openAnim.stop()
            closeAnim.stop()
        }
    }

    Connections {
        target: typeof musicManager !== "undefined" && musicManager ? musicManager : null
        function onCurrentLyricsChanged() {
            // 切换歌曲时重置已播索引，避免旧歌的 _pastIdx 污染新歌词的状态
            root._pastIdx = -1
        }
        function onLyricIndexChanged() {
            var idx = musicManager.lyricIndex
            if (lyricsView.count === 0) return
            // lyricIndex 回退（单曲循环回到开头 / 手动 seek 回退）→ 重置已播状态
            if (idx < root._pastIdx)
                root._pastIdx = -1
            if (idx < 0) return
            // 正常前进：_pastIdx 跟随当前行（只增大不收缩）
            if (idx > root._pastIdx)
                root._pastIdx = idx
            if (idx === root._lastScroll) return
            root._lastScroll = idx
            lyricsView.positionViewAtIndex(idx, ListView.Center)
        }
    }

    SequentialAnimation {
        id: openAnim
        ParallelAnimation {
            // 透明度：从 0 到 1
            OpacityAnimator { 
                target: root
                to: 1
                duration: 350
                easing.type: Easing.OutCubic // 非线性：先快后慢，平滑刹车
            }
            // 位置：从底部 (root.height) 滑动到正常位置 (0)
            NumberAnimation { 
                target: root
                property: "_slideOffset"
                from: root.height
                to: 0
                duration: 350
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction { script: root.opening = false }
    }

    SequentialAnimation {
        id: closeAnim
        ParallelAnimation {
            // 透明度：从 1 到 0
            OpacityAnimator { 
                target: root
                to: 0
                duration: 250
                easing.type: Easing.InCubic // 非线性：先慢后快，加速退出
            }
            // 位置：从 0 滑动回底部 (root.height)
            NumberAnimation { 
                target: root
                property: "_slideOffset"
                to: root.height
                duration: 250
                easing.type: Easing.InCubic 
            }
        }
        onFinished: {
            root.visible = false
        }
    }

    // 全屏事件屏蔽层（阻止所有操作穿透到下层）
    MouseArea {
        anchors.fill: parent
        anchors.bottomMargin: 75 // 放行底部 75px 的鼠标点击事件
        acceptedButtons: Qt.AllButtons
        hoverEnabled: false        // 无 hover 视觉反馈，关闭减少事件开销
        preventStealing: true
        propagateComposedEvents: false
        onWheel: function(w) { w.accepted = true }
        onPressed: function(m) { m.accepted = true }
    }

    // ============================================================
    // 背景
    // ============================================================
    Rectangle { 
        anchors.fill: parent
        anchors.bottomMargin: 75 // 让出底部的画面，露出 main.qml 的控制栏
        color: "#1E1E1E" 
    }

    // 迷你小窗按钮
    Rectangle {
        anchors.top: parent.top; anchors.right: closeBtn.left
        anchors.topMargin: 14; anchors.rightMargin: 8
        width: 36; height: 36; radius: 18
        color: miniEnterMA.containsMouse ? "#33ffffff" : "transparent"

        Image {
            anchors.centerIn: parent
            width: 20; height: 20
            source: "qrc:/qt/qml/JustSolo/data/image/mini-enter.png"
            fillMode: Image.PreserveAspectFit
        }

        MouseArea {
            id: miniEnterMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.enterMiniMode()
        }
    }

    // 关闭按钮
    Rectangle {
        id: closeBtn
        anchors.top: parent.top; anchors.right: parent.right
        anchors.topMargin: 14; anchors.rightMargin: 22
        width: 36; height: 36; radius: 18
        color: closeMA.containsMouse ? "#33ffffff" : "transparent"

        Image {
            anchors.centerIn: parent
            width: 18; height: 18
            source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='" 
                    + (closeMA.containsMouse ? "%23cccccc" : "%23777777") 
                    + "' stroke-width='2.5' stroke-linecap='round'><path d='M18 6L6 18M6 6l12 12'/></svg>"
            fillMode: Image.PreserveAspectFit
        }

        MouseArea { 
            id: closeMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.close() 
        }
    }

    // ============================================================
    // 主体
    // ============================================================
    Item {
        id: mainBody
        anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        anchors.topMargin: 46; anchors.bottomMargin: 75

        // 左：封面 + 歌名 + 歌手 + 专辑
        Item {
            id: coverArea
            anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: mainWindow.visibility === Window.Maximized ? 
                   parent.width * 0.4 : Math.min(parent.width * 0.45, 420)

            Rectangle {
                id: coverBox
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(0, parent.height * 0.04)
                width: Math.min(parent.width * 0.85, parent.height * 0.42)
                height: width; radius: 12; color: "#222222"

                Image {
                    id: coverImg
                    anchors.fill: parent; anchors.margins: 3
                    source: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentCover || "") : ""
                    fillMode: Image.PreserveAspectFit; asynchronous: true
                    visible: source !== ""
                    opacity: status === Image.Ready ? 1 : 0

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: ShaderEffectSource {
                            sourceItem: Rectangle {
                                width: coverImg.width
                                height: coverImg.height
                                radius: 9 // 背景的 radius(12) 减去 margins(3)
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent; font.family: root.fontFamily
                    text: "\u266B"; font.pixelSize: 42; color: "#333333"
                    visible: (typeof musicManager === "undefined" || !musicManager || musicManager.currentCover === "")
                }
            }

            // 歌名（超长时连续滚动：右侧滚入 → 左侧滚出 → 空一小下 → 新文字从右侧滚入）
            Item {
                id: songNameClip
                anchors.top: coverBox.bottom; anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24
                height: songNameText.implicitHeight
                clip: true

                property bool needsScroll: songNameText.contentWidth > width

                Text {
                    id: songNameText
                    text: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentTitle || "未在播放") : "未在播放"
                    font.family: root.fontFamily; font.pixelSize: 28; font.bold: true; color: "#f0f0f0"
                    x: songNameClip.needsScroll ? songNameClip.width : (songNameClip.width - songNameText.contentWidth) / 2

                    SequentialAnimation on x {
                        running: songNameClip.needsScroll && root.visible
                        loops: Animation.Infinite
                        // 从右侧视口外滚入 → 匀速滚到左侧滚出
                        NumberAnimation {
                            from: songNameClip.width
                            to: -songNameText.contentWidth
                            duration: Math.max(8000, (songNameClip.width + songNameText.contentWidth) * 10)
                            easing.type: Easing.Linear
                        }
                        // 滚出去了，空一小下
                        PauseAnimation { duration: 1000 }
                        // 瞬间回到右侧准备下一个循环
                        PropertyAnimation { property: "x"; to: songNameClip.width; duration: 0 }
                    }
                }
            }

            Text {
                id: artistName
                anchors.top: songNameClip.bottom; anchors.topMargin: 6
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24
                text: {
                    if (typeof musicManager === "undefined" || !musicManager) return "歌手：未知"
                    var a = (musicManager.currentArtist || "").replace(/[/;｜|]+/g, "、")
                    return a ? ("歌手：" + a) : "歌手：未知"
                }
                font.family: root.fontFamily; font.pixelSize: 18; color: "#999"
                elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
            }

            Text {
                anchors.top: artistName.bottom; anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24
                text: {
                    if (typeof musicManager === "undefined" || !musicManager) return ""
                    var a = musicManager.currentAlbum || ""
                    return a ? ("专辑：" + a) : ""
                }
                font.family: root.fontFamily; font.pixelSize: 15; color: "#bbb"
                elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                visible: text !== ""
            }
        }

        // 右：歌词（只展示 5 句，自动换行）
        Item {
            id: lyricsCol
            anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.left: coverArea.right; anchors.right: parent.right
            anchors.leftMargin: 20
            clip: true

            Text {
                anchors.centerIn: parent
                text: "暂无歌词"; font.family: root.fontFamily; font.pixelSize: 20; color: "#3B82F6"
                visible: lyricsView.count === 0
            }

            ListView {
                id: lyricsView
                anchors.fill: parent
                model: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentLyrics || []) : []
                spacing: 20
                // 上下留白让当前行居中，只展示约 5 句
                topMargin: parent.height * 0.38; bottomMargin: parent.height * 0.38
                clip: true; cacheBuffer: 400; reuseItems: true
                Behavior on contentY { NumberAnimation { duration: 1000; easing.type: Easing.InOutQuad } }

                delegate: Item {
                    id: lyricDelegate
                    width: lyricsView.width
                    height: mainContainer.height + 8

                    property bool isCurrent: (typeof musicManager !== "undefined" && musicManager) && index === musicManager.lyricIndex
                    property bool isPast: index < root._pastIdx
                    property bool hasTrans: (modelData.translation || "") !== ""

                    // 歌词主体（行高自适应，整段通过单色控制高亮）
                    Item {
                        id: mainContainer
                        anchors.left: parent.left; anchors.leftMargin: 4
                        anchors.top: parent.top
                        width: lyricsView.width - 8
                        height: mainCol.implicitHeight

                        Column {
                            id: mainCol
                            spacing: 4

                            // 主歌词行（高度自适应，超长自动换行）
                            Item {
                                width: mainContainer.width
                                height: Math.max(52, mainText.implicitHeight)
                                clip: true

                                Text {
                                    id: mainText
                                    anchors.left: parent.left
                                    y: (parent.height - height) / 2
                                    width: parent.width
                                    text: modelData.text || ""
                                    font.family: root.fontFamily
                                    font.pixelSize: lyricDelegate.isCurrent ? 58 : 36
                                    // 单层文本直接切换高亮色，无需 overlay 叠加
                                    color: lyricDelegate.isPast ? "#FFD700"
                                         : (lyricDelegate.isCurrent ? "#00d4ff" : "#6a9ac0")
                                    horizontalAlignment: Text.AlignLeft
                                    wrapMode: Text.WordWrap
                                    Behavior on font.pixelSize { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }

                            // 翻译行（高度自适应）
                            Item {
                                width: mainContainer.width
                                height: hasTrans ? Math.max(38, transText.implicitHeight) : 0
                                visible: hasTrans
                                clip: true

                                Text {
                                    id: transText
                                    anchors.left: parent.left
                                    y: (parent.height - height) / 2
                                    width: parent.width
                                    text: modelData.translation || ""
                                    font.family: root.fontFamily
                                    font.pixelSize: lyricDelegate.isCurrent ? 34 : 24
                                    color: lyricDelegate.isPast ? "#b8960f"
                                         : (lyricDelegate.isCurrent ? "#FFD700" : "#4a6a8a")
                                    horizontalAlignment: Text.AlignLeft
                                    wrapMode: Text.WordWrap
                                    Behavior on font.pixelSize { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

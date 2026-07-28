import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// 通用歌曲列表组件（全局复用）
// 所有音乐 / 自定义列表共用，通过 songList 切换数据源
// ============================================================
ColumnLayout {
    id: root
    spacing: 0
    clip: true

    // ESC 退出排序模式
    focus: root.manualSortMode
    Keys.onEscapePressed: {
        if (root.manualSortMode) root.toggleSortMode()
    }

    property int sidebarWidth: 230
    property int windowWidth: 1200
    property var rightClickedTrack: null
    property int rightClickedIndex: -1
    property string fontFamily: ""

    // 可重载：自定义列表时传入不同的歌曲列表
    property var songList: musicManager.library
    // 自定义列表索引（-1 = 普通模式，> = 自建列表）
    property int customPlaylistIndex: -1
    // 当前页面的列表索引（-1=未设置, 0=库, 1=收藏, 2=历史, 3+n=自定义）
    property int pageListIndex: -1
    // 搜索滚动
    property int scrollToIndex: -1
    // ---- 定制化接口 ----
    // 覆盖点击行为：function(index) { ... }。设了之后不走默认点击逻辑
    property var onLeftClick: undefined
    // 空列表提示文本
    property string emptyHint: "还没有音乐"
    property string emptySubHint: "点击上方「添加音乐」导入本地文件"
    // 额外右键菜单项：[{text, onClicked}, ...]
    property var contextMenuExtra: []
    // 是否显示默认右键菜单项（收藏/取消收藏、删除此歌曲）
    property bool showDefaultContextMenu: true

    // ---- 手动排序 ----
    property bool manualSortMode: false
    property bool supportsManualSort: true       // 页面是否支持手动排序
    property string manualSortDisabledMessage: "" // 不支持时的提示消息（为空则无反应）
    property int draggedIndex: -1
    property int dropTargetIndex: -1
    property var draggedTrack: null
    property real dragOffsetY: 0       // 鼠标在拖拽行内的偏移（相对行顶）
    property real dragOverlayY: 0      // 拖拽浮层的 Y 坐标（相对 musicListView）

    // ---- 拖拽自动滚动 ----
    property int _autoScrollDirection: 0  // -1=向上, 1=向下, 0=停止
    property real _dragEdgeY: 0           // 进入边缘区时的鼠标 Y（相对 musicListView）
    property real _dropIndicatorY: 0      // 浮动放置指示线 Y
    property int _autoScrollFinalIndex: -1 // 自动滚动期间计算的最终目标索引

    // 切换手动排序模式
    function toggleSortMode() {
        manualSortMode = !manualSortMode
        if (!manualSortMode) {
            draggedIndex = -1
            dropTargetIndex = -1
            draggedTrack = null
            dragOverlay.visible = false
            _autoScrollFinalIndex = -1
        }
    }

    // 根据页面上下文调用对应的 C++ 移动方法
    function reorderSong(fromIdx, toIdx) {
        if (fromIdx === toIdx) return
        if (fromIdx < 0 || toIdx < 0) return
        var list = songList
        if (!list || fromIdx >= list.length || toIdx >= list.length) return

        if (pageListIndex >= 3) {
            musicManager.moveSongInCustomPlaylist(pageListIndex - 3, fromIdx, toIdx)
        } else if (pageListIndex === 0) {
            musicManager.moveSongInLibrary(fromIdx, toIdx)
        } else if (pageListIndex === 1) {
            musicManager.moveSongInFavorites(fromIdx, toIdx)
        } else if (pageListIndex === 2) {
            musicManager.moveSongInHistory(fromIdx, toIdx)
        } else {
            // PlaylistPage 或未设置：根据当前播放来源判断
            var src = musicManager.playlistSource
            if (src === 1)
                musicManager.moveSongInFavorites(fromIdx, toIdx)
            else if (src === 2)
                musicManager.moveSongInHistory(fromIdx, toIdx)
            else if (src >= 3)
                musicManager.moveSongInCustomPlaylist(src - 3, fromIdx, toIdx)
            else
                musicManager.moveSongInPlaylist(fromIdx, toIdx)
        }
    }

    // 当前正在播放的歌曲路径（跨来源匹配）
    // 不受 trackCrossSource 影响，始终返回当前播放歌曲路径
    property string playingPath: {
        try {
            var ci = musicManager.currentIndex
            if (ci < 0) return ""
            var src = musicManager.playlistSource
            var list = src === 1 ? musicManager.favorites : (src === 2 ? musicManager.history : musicManager.playlist)
            if (!list || list.length === 0) return ""
            if (ci >= 0 && ci < list.length) return (list[ci].path || "")
        } catch (e) {}
        return ""
    }

    // ---- 列宽 (2:2:2:2:1) ----
    property int colPlay: 36
    property real _totalW: Math.max(400,
        (musicListView.width > 0 ? musicListView.width : windowWidth - sidebarWidth - 80) - 20 - colPlay)
    property real colCover:    Math.max(40, _totalW * 2 / 9)
    property real colTitle:    Math.max(60, _totalW * 2 / 9)
    property real colArtist:   Math.max(50, _totalW * 2 / 9)
    property real colAlbum:    Math.max(50, _totalW * 2 / 9)
    property real colDuration: Math.max(36, _totalW * 1 / 9)
    property int _pendingIndex: -1
    property string dialogMode: "home"   // "home" / "custom" / "switch"
    property int dialogTarget: -1        // "switch" 模式的目标 playlistSource

    // 切换到页面时若当前歌曲在此列表中，自动定位到该行
    property bool autoScrollEnabled: true

    onScrollToIndexChanged: {
        if (scrollToIndex >= 0 && scrollToIndex < songList.length) {
            Qt.callLater(function() {
                musicListView.positionViewAtIndex(scrollToIndex, ListView.Center)
            })
        }
    }

    Component.onCompleted: {
        if (autoScrollEnabled && musicManager.currentIndex >= 0) {
            scrollToPlaying()
        }
    }

    onVisibleChanged: {
        // 页面不可见时自动退出排序
        if (!visible && manualSortMode) toggleSortMode()
        if (autoScrollEnabled && visible && musicManager.currentIndex >= 0) {
            scrollToPlaying()
        }
    }

    // 同一 HomePage 实例切换 songList（所有音乐↔自定义列表）时触发定位
    onSongListChanged: {
        if (autoScrollEnabled && visible && musicManager.currentIndex >= 0) {
            Qt.callLater(function() { scrollToPlaying() })
        }
    }

    function scrollToPlaying() {
        if (!songList) return
        var p = playingPath
        if (p.length === 0) return
        // 只有当页面列表索引与当前播放列表索引一致时才定位
        if (pageListIndex >= 0 && pageListIndex !== musicManager.playingListIndex) return
        for (var i = 0; i < songList.length; i++) {
            if (songList[i] && songList[i].path === p) {
                var idx = i
                Qt.callLater(function() {
                    musicListView.positionViewAtIndex(idx, ListView.Center)
                })
                return
            }
        }
    }

    // 供子类调用：打开切换来源弹窗
    function openSwitchDialog(mode, target, index) {
        _pendingIndex = index
        dialogMode = mode
        dialogTarget = target
        switchSourceDialog.open()
    }

    // ---- 列标题 ----
    Rectangle {
        Layout.fillWidth: true; height: 32; color: "transparent"
        visible: songList.length > 0
        RowLayout {
            anchors.fill: parent; anchors.margins: 5; anchors.leftMargin: 8; spacing: 0
            Item { Layout.preferredWidth: root.colCover; Layout.maximumWidth: 40 }
            Label { text: "标题"; font.family: fontFamily; font.pixelSize: 15; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: root.colTitle; verticalAlignment: Text.AlignVCenter }
            Label { text: "歌手"; font.family: fontFamily; font.pixelSize: 15; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: root.colArtist; verticalAlignment: Text.AlignVCenter }
            Label { text: "专辑"; font.family: fontFamily; font.pixelSize: 15; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: root.colAlbum; verticalAlignment: Text.AlignVCenter }
            Label { text: "时长"; font.family: fontFamily; font.pixelSize: 15; color: "#969696"; Layout.preferredWidth: root.colDuration; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
            Item { Layout.preferredWidth: root.colPlay }
        }
    }
    Rectangle { Layout.fillWidth: true; height: 1; color: "#222222"; visible: songList.length > 0 }

    // ---- 排序模式提示条 ----
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: root.manualSortMode ? 30 : 0
        visible: root.manualSortMode
        color: "#2a3550"
        radius: 4
        clip: true
        Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12; anchors.rightMargin: 12
            spacing: 8
            Label {
                text: "⇅"
                font.family: fontFamily; font.pixelSize: 15; color: "#00d4ff"
            }
            Label {
                text: "排序模式 — 拖拽排序，拖到边缘自动滚动"
                font.family: fontFamily; font.pixelSize: 12; color: "#00d4ff"
                Layout.fillWidth: true
            }
            Label {
                text: "ESC 退出"
                font.family: fontFamily; font.pixelSize: 12; color: "#888"
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleSortMode()
                }
            }
        }
    }

    // ---- 歌曲列表 ----
    ListView {
        id: musicListView
        Layout.fillWidth: true; Layout.fillHeight: true
        spacing: 8; clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: songList.length > 0
        cacheBuffer: Math.min(height * 0.5, 400); reuseItems: true

        moveDisplaced: Transition {
            NumberAnimation { properties: "y"; duration: 250; easing.type: Easing.OutCubic }
        }

        displaced: Transition {
            NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic }
        }

        ScrollBar.vertical: ScrollBar {
            id: listScrollBar; policy: ScrollBar.AsNeeded; width: 10
            background: Rectangle { implicitWidth: 10; radius: 5; color: "#222222" }
            contentItem: Rectangle {
                implicitWidth: 10; radius: 5
                color: thumbHover.containsMouse ? "#777777" : "#3A3A3A"
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea { id: thumbHover; hoverEnabled: true; acceptedButtons: Qt.NoButton; propagateComposedEvents: true }
            }
        }

        model: songList

        delegate: SongRow {
            width: musicListView.width
            isCurrent: model.path === root.playingPath
            fontFamily: root.fontFamily
            colCover: root.colCover
            colTitle: root.colTitle
            colArtist: root.colArtist
            colAlbum: root.colAlbum
            colDuration: root.colDuration
            colPlay: root.colPlay
            sortMode: root.manualSortMode
            isDragged: root.manualSortMode && root.draggedIndex === index
            showDropAbove: root.manualSortMode && root.dropTargetIndex === index && root.draggedIndex !== index
            showDropBelow: false

            Behavior on opacity {
                NumberAnimation { duration: 0 }
            }

            onDragStarted: function(mouseY) {
                root.draggedIndex = index
                root.draggedTrack = model
                root.dragOffsetY = mouseY
                // 计算浮层在 musicListView 内的起始 Y
                var rowGlobal = mapToItem(musicListView, 0, 0)
                root.dragOverlayY = rowGlobal.y
                dragOverlay.visible = true
            }
            onDragMoved: function(mouseY) {
                var posInListView = mapToItem(musicListView, 0, mouseY)
                root.dragOverlayY = Math.max(0, Math.min(posInListView.y - root.dragOffsetY,
                    musicListView.height - 50))

                // 计算目标索引（viewport Y + contentY → content Y）
                var rowHeight = 50 + musicListView.spacing
                var targetY = posInListView.y + musicListView.contentY
                var targetIdx = Math.floor((targetY + rowHeight / 2) / rowHeight)
                targetIdx = Math.max(0, Math.min(targetIdx, musicListView.count - 1))
                if (targetIdx !== root.dropTargetIndex) {
                    root.dropTargetIndex = targetIdx
                }
                // 更新放置指示线位置（目标行顶边缘）
                root._dropIndicatorY = targetIdx * rowHeight - musicListView.contentY - 1

                // ---- 拖拽自动滚动（边缘检测） ----
                var edgeThreshold = 50
                var lvHeight = musicListView.height
                if (posInListView.y < edgeThreshold && musicListView.contentY > 0) {
                    root._autoScrollDirection = -1
                    root._dragEdgeY = Math.max(0, posInListView.y)
                    if (!autoScrollTimer.running) autoScrollTimer.start()
                } else if (posInListView.y > lvHeight - edgeThreshold
                           && musicListView.contentY < musicListView.contentHeight - lvHeight) {
                    root._autoScrollDirection = 1
                    root._dragEdgeY = Math.min(lvHeight, posInListView.y)
                    if (!autoScrollTimer.running) autoScrollTimer.start()
                } else {
                    if (autoScrollTimer.running) autoScrollTimer.stop()
                }
            }
            onDragEnded: {
                if (autoScrollTimer.running) autoScrollTimer.stop()
                var finalFrom = root.draggedIndex
                // 自动滚动结束时使用 _autoScrollFinalIndex（自动滚动期间不更新 dropTargetIndex）
                var finalTo = root._autoScrollFinalIndex >= 0 ? root._autoScrollFinalIndex : root.dropTargetIndex
                dragOverlay.visible = false
                root.draggedIndex = -1
                root.dropTargetIndex = -1
                root.draggedTrack = null
                root._autoScrollFinalIndex = -1

                if (finalFrom >= 0 && finalTo >= 0 && finalFrom !== finalTo) {
                    root.reorderSong(finalFrom, finalTo)
                }
            }

            opacity: (root.manualSortMode && root.draggedIndex === index) ? 0.4 : 1.0

            onLeftClicked: {
                if (root.onLeftClick) {
                    root.onLeftClick(index)
                } else if (root.customPlaylistIndex >= 0) {
                    var thisCustomIdx = 3 + root.customPlaylistIndex
                    if (musicManager.currentIndex < 0) {
                        musicManager.playCustomPlaylist(root.customPlaylistIndex, index)
                    } else if (musicManager.playingListIndex === thisCustomIdx) {
                        // 已经是此列表在播放
                        if (musicManager.currentIndex === index) {
                            if (musicManager.isPlaying) musicManager.pause()
                            else musicManager.play()
                        } else {
                            musicManager.playCustomPlaylist(root.customPlaylistIndex, index)
                        }
                    } else {
                        root._pendingIndex = index
                        root.dialogMode = "custom"
                        switchSourceDialog.open()
                    }
                } else if (musicManager.playlistSource === 0) {
                    if (model.path === root.playingPath) {
                        if (musicManager.isPlaying) musicManager.pause()
                        else musicManager.play()
                    } else {
                        musicManager.playIndex(index)
                    }
                } else if (musicManager.trackCrossSource) {
                    musicManager.playlistSource = 0
                    musicManager.playIndex(index)
                } else {
                    // 没有正在播放 → 直接播放，否则弹窗确认
                    if (musicManager.currentIndex < 0) {
                        musicManager.playlistSource = 0
                        musicManager.playIndex(index)
                    } else {
                        root._pendingIndex = index
                        root.dialogMode = "home"
                        switchSourceDialog.open()
                    }
                }
            }
            onRightClicked: {
                root.rightClickedTrack = model
                root.rightClickedIndex = index
                contextMenu.popup()
            }
        }

        // ---- 浮动放置指示线（自动滚动时平滑跟随） ----
        Rectangle {
            id: dropIndicator
            z: 998
            visible: dragOverlay.visible
            anchors.horizontalCenter: parent.horizontalCenter
            width: musicListView.width - 20
            height: 3
            radius: 1.5
            color: "#00d4ff"
            opacity: 0.85
            y: root._dropIndicatorY

            Behavior on y { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }

        // ---- 拖拽浮层（排序模式时跟随鼠标） ----
        Rectangle {
            id: dragOverlay
            z: 999
            visible: false
            anchors.horizontalCenter: parent.horizontalCenter
            width: musicListView.width
            height: 50
            radius: 8
            color: "#333333"
            border.color: "#00d4ff"
            border.width: 1.5
            opacity: 0.95
            y: root.dragOverlayY

            Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 5
                anchors.leftMargin: 8
                spacing: 0

                Item {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: parent.height
                    Layout.alignment: Qt.AlignVCenter
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/JustSolo/data/image/drag.png"
                        width: 16; height: 16
                        opacity: 1.0
                    }
                }

                Rectangle {
                    Layout.preferredWidth: Math.min(root.colCover, 40)
                    Layout.preferredHeight: 40; Layout.maximumWidth: 40
                    Layout.alignment: Qt.AlignVCenter
                    radius: 6; color: "#4a4a65"
                    Image {
                        anchors.fill: parent; anchors.margins: 2
                        sourceSize.width: 40; sourceSize.height: 40
                        source: (root.draggedTrack && root.draggedTrack.cover) ? root.draggedTrack.cover : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Label {
                        anchors.centerIn: parent
                        text: "\u266B"; font.family: root.fontFamily; font.pixelSize: 18; color: "#666"
                        visible: !root.draggedTrack || !root.draggedTrack.cover || root.draggedTrack.cover === ""
                    }
                }

                Item {
                    Layout.fillWidth: true; Layout.preferredWidth: root.colTitle
                    Layout.preferredHeight: 40; Layout.alignment: Qt.AlignVCenter
                    Label {
                        text: root.draggedTrack ? (root.draggedTrack.name || "") : ""
                        font.family: root.fontFamily; font.pixelSize: 15; font.bold: true
                        color: "#d4d4d4"; elide: Text.ElideRight; width: parent.width
                        anchors.top: parent.top; anchors.left: parent.left
                    }
                    Rectangle {
                        visible: root.draggedTrack && root.draggedTrack.quality && root.draggedTrack.quality !== ""
                        width: Math.max(qualityOverlayText.contentWidth + 8, 20)
                        height: 16; radius: 3; color: "#D4AF37"
                        anchors.bottom: parent.bottom; anchors.left: parent.left
                        Label {
                            id: qualityOverlayText
                            text: root.draggedTrack ? (root.draggedTrack.quality || "") : ""
                            font.family: root.fontFamily; font.pixelSize: 10; font.bold: true
                            color: "white"; anchors.centerIn: parent
                        }
                    }
                }

                Label {
                    text: root.draggedTrack ? (root.draggedTrack.artist || "未知") : ""
                    font.family: root.fontFamily; font.pixelSize: 15; color: "#969696"
                    elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: root.colArtist
                }

                Label {
                    text: root.draggedTrack ? (root.draggedTrack.album || "") : ""
                    font.family: root.fontFamily; font.pixelSize: 15; color: "#888888"
                    elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: root.colAlbum
                }

                Label {
                    text: root.draggedTrack ? (root.draggedTrack.durationText || "") : ""
                    font.family: root.fontFamily; font.pixelSize: 15; color: "#969696"
                    verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
                    Layout.fillHeight: true; Layout.preferredWidth: root.colDuration
                }

                Item { Layout.preferredWidth: root.colPlay; Layout.preferredHeight: 20; Layout.alignment: Qt.AlignVCenter }
            }
        }
    }

    // ---- 拖拽自动滚动定时器 ----
    Timer {
        id: autoScrollTimer
        interval: 30
        repeat: true
        onTriggered: {
            var step = root._autoScrollDirection * 8
            var newCY = musicListView.contentY + step
            newCY = Math.max(0, Math.min(newCY,
                Math.max(0, musicListView.contentHeight - musicListView.height)))
            musicListView.contentY = newCY

            // 保持浮层在边缘位置（不超出 ListView 可视区）
            root.dragOverlayY = Math.max(0, Math.min(root._dragEdgeY - root.dragOffsetY,
                musicListView.height - 50))

            // 重新计算放置目标（viewport Y + contentY → content Y）
            var rowHeight = 50 + musicListView.spacing
            var targetY = root._dragEdgeY + musicListView.contentY
            var targetIdx = Math.floor((targetY + rowHeight / 2) / rowHeight)
            targetIdx = Math.max(0, Math.min(targetIdx, musicListView.count - 1))
            // 自动滚动期间不修改 dropTargetIndex（避免触发 per-delegate 动画导致闪烁）
            root._autoScrollFinalIndex = targetIdx
            // 仅更新浮动指示线位置
            root._dropIndicatorY = targetIdx * rowHeight - musicListView.contentY - 1

            // 到达边界时停止
            if (root._autoScrollDirection < 0 && musicListView.contentY <= 0) {
                autoScrollTimer.stop()
            } else if (root._autoScrollDirection > 0
                       && musicListView.contentY >= musicListView.contentHeight - musicListView.height) {
                autoScrollTimer.stop()
            }
        }
    }

    // ---- 右键菜单 ----
    Menu {
        id: contextMenu
        background: Rectangle { color: "#222222"; border.color: "#3A3A3A"; radius: 6; implicitWidth: 150 }
        topPadding: 0; bottomPadding: 0

        // ---- 手动排序（第一位） ----
        MenuItem {
            visible: songList.length >= 2 && root.supportsManualSort
            height: songList.length >= 2 && root.supportsManualSort ? implicitHeight : 0
            text: root.manualSortMode ? "退出排序" : "手动排序"
            contentItem: Label {
                text: root.manualSortMode ? "退出排序" : "手动排序"
                font.family: fontFamily; font.pixelSize: 15; color: "#00d4ff"
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
            onClicked: {
                root.toggleSortMode()
                root.rightClickedTrack = null
            }
        }
        MenuSeparator {
            visible: songList.length >= 2 && root.supportsManualSort && root.showDefaultContextMenu
            height: songList.length >= 2 && root.supportsManualSort && root.showDefaultContextMenu ? implicitHeight : 0
            contentItem: Rectangle { implicitHeight: 1; implicitWidth: 130; color: "#3A3A3A" }
        }
        // 不支持排序时的提示按钮
        MenuItem {
            visible: songList.length >= 2 && !root.supportsManualSort && root.manualSortDisabledMessage !== ""
            height: songList.length >= 2 && !root.supportsManualSort && root.manualSortDisabledMessage !== "" ? implicitHeight : 0
            text: "手动排序"
            contentItem: Label {
                text: "手动排序"
                font.family: fontFamily; font.pixelSize: 15; color: "#666"
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
            onClicked: {
                manualSortTipDialog.open()
                root.rightClickedTrack = null
            }
        }
        MenuSeparator {
            visible: songList.length >= 2 && !root.supportsManualSort && root.manualSortDisabledMessage !== "" && root.showDefaultContextMenu
            height: songList.length >= 2 && !root.supportsManualSort && root.manualSortDisabledMessage !== "" && root.showDefaultContextMenu ? implicitHeight : 0
            contentItem: Rectangle { implicitHeight: 1; implicitWidth: 130; color: "#3A3A3A" }
        }

        MenuItem {
            id: menuItem
            visible: root.showDefaultContextMenu
            height: root.showDefaultContextMenu ? implicitHeight : 0
            text: root.rightClickedTrack ? (musicManager.isFavorite(root.rightClickedTrack) ? "取消收藏" : "收藏") : "收藏"
            onClicked: { if (root.rightClickedTrack) musicManager.toggleFavorite(root.rightClickedTrack) }
            contentItem: Label { text: menuItem.text; font.family: fontFamily; font.pixelSize: 15; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: menuItem.hovered ? "#333333" : "transparent"; radius: 4 }
        }
        MenuItem {
            visible: root.showDefaultContextMenu
            height: root.showDefaultContextMenu ? implicitHeight : 0
            text: "删除此歌曲"
            contentItem: Label { text: "删除此歌曲"; font.family: fontFamily; font.pixelSize: 15; color: "#e06666"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
            onClicked: deleteConfirmDialog.open()
        }
        MenuSeparator {
            visible: root.showDefaultContextMenu && root.contextMenuExtra.length > 0
            height: root.showDefaultContextMenu && root.contextMenuExtra.length > 0 ? implicitHeight : 0
            contentItem: Rectangle { implicitHeight: 1; implicitWidth: 130; color: "#3A3A3A" }
        }
        Instantiator {
            model: root.contextMenuExtra
            MenuItem {
                text: modelData.text || ""
                onClicked: { if (modelData.onClicked) modelData.onClicked(); root.rightClickedTrack = null }
                contentItem: Label { text: modelData.text || ""; font.family: fontFamily; font.pixelSize: 15; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
            }
            onObjectAdded: function(index, object) { contextMenu.insertItem(contextMenu.count, object) }
            onObjectRemoved: function(index, object) { contextMenu.removeItem(object) }
        }
    }

    // ---- 排序不支持提示弹窗 ----
    Dialog {
        id: manualSortTipDialog
        parent: root.Window.contentItem
        modal: true
        standardButtons: Dialog.Ok
        width: 320
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        background: Rectangle { color: "#222222"; border.color: "#3A3A3A"; radius: 8 }
        contentItem: Label {
            text: root.manualSortDisabledMessage
            font.family: fontFamily; font.pixelSize: 15; color: "#c0c0c0"
            wrapMode: Text.Wrap; topPadding: 20; bottomPadding: 10
            leftPadding: 20; rightPadding: 20
        }
    }

    // ---- 空列表提示 ----
    Column {
        Layout.alignment: Qt.AlignCenter; spacing: 14
        visible: songList.length === 0
        Label { text: root.emptyHint; font.family: fontFamily; font.pixelSize: 16; color: "#757575"; anchors.horizontalCenter: parent.horizontalCenter }
        Label { text: root.emptySubHint; font.family: fontFamily; font.pixelSize: 13; color: "#666"; anchors.horizontalCenter: parent.horizontalCenter }
    }

    // ---- 切换来源对话框 ----
    Dialog {
        id: switchSourceDialog
        parent: Overlay.overlay
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 340
        padding: 28

        Overlay.modal: Rectangle { color: "transparent" }

        background: Rectangle {
            color: "#222222"
            radius: 10
            border.color: "#3A3A3A"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 14

            Label {
                text: root.dialogMode === "custom" ? "切换自定义列表"
                     : root.dialogMode === "switch" ? "切换播放来源"
                     : "切换播放列表"
                font.family: fontFamily
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
                Layout.bottomMargin: 4
            }

            Label {
                text: root.dialogMode === "custom"
                      ? "当前播放列表不是此列表，\n点击确定将改变播放列表并播放选定的歌曲。"
                      : root.dialogMode === "switch"
                      ? "当前播放来源不是此页面，\n点击确定将切换播放来源并播放选定的歌曲。"
                      : "当前播放来源不是首页，\n点击确定将从头播放选定的歌曲。"
                font.family: fontFamily
                font.pixelSize: 15
                lineHeight: 1.4
                color: "#cccccc"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12
                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: switchCancelMA.containsMouse ? "#333333" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: fontFamily; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: switchCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: switchSourceDialog.close()
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: switchConfirmMA.containsMouse ? "#4a6a8a" : "#3a5a7a"
                    Label { text: "确定"; anchors.centerIn: parent; font.family: fontFamily; font.pixelSize: 13; color: "#ddd" }
                    MouseArea {
                        id: switchConfirmMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.dialogMode === "custom") {
                                musicManager.playCustomPlaylist(root.customPlaylistIndex, root._pendingIndex)
                            } else if (root.dialogMode === "switch") {
                                musicManager.playlistSource = root.dialogTarget
                                musicManager.playIndex(root._pendingIndex)
                            } else {
                                musicManager.playlistSource = 0
                                musicManager.playIndex(root._pendingIndex)
                            }
                            switchSourceDialog.close()
                            Qt.callLater(function() { root.scrollToPlaying() })
                        }
                    }
                }
            }
        }
    }

    // ---- 删除歌曲确认弹窗 ----
    Dialog {
        id: deleteConfirmDialog
        parent: Overlay.overlay
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 380
        padding: 28

        Overlay.modal: Rectangle { color: "transparent" }

        background: Rectangle {
            color: "#222222"
            radius: 10
            border.color: "#3A3A3A"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 16

            RowLayout {
                spacing: 10
                Label {
                    text: "🗑"
                    font.pixelSize: 22
                    color: "#e06666"
                }
                Label {
                    text: "删除此歌曲"
                    font.family: fontFamily
                    font.pixelSize: 17
                    font.bold: true
                    color: "#dddddd"
                }
            }

            Label {
                text: "我们不会从磁盘删除此歌曲文件，可通过「添加本地音乐」或「从音乐库导入」重新加回。\n\n此操作会同步删除历史记录、播放列表、收藏及所有自定义列表中的此歌曲。"
                font.family: fontFamily
                font.pixelSize: 13
                lineHeight: 1.5
                color: "#aaaaaa"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 12
                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 80; radius: 6
                    color: delCancelMA.containsMouse ? "#333333" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: fontFamily; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: delCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: deleteConfirmDialog.close()
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 80; radius: 6
                    color: delConfirmMA.containsMouse ? "#cc5555" : "#994444"
                    Label { text: "删除"; anchors.centerIn: parent; font.family: fontFamily; font.pixelSize: 13; color: "#eee" }
                    MouseArea {
                        id: delConfirmMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.rightClickedTrack) {
                                musicManager.deleteSongByPath(root.rightClickedTrack.path || "")
                                root.rightClickedTrack = null
                            }
                            deleteConfirmDialog.close()
                        }
                    }
                }
            }
        }
    }
}

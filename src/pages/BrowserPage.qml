/****************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** Contact: Vesa-Matti Hartikainen <vesa-matti.hartikainen@jollamobile.com>
**
****************************************************************************/

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */


import QtQuick 2.0
import Sailfish.Silica 1.0
import Qt5Mozilla 1.0
import Sailfish.Browser 1.0
import org.nemomobile.connectivity 1.0
import "components" as Browser


Page {
    id: browserPage

    property Item firstUseOverlay
    property alias tabs: tabModel
    property alias favorites: favoriteModel
    property alias history: historyModel
    property alias viewLoading: webView.loading
    property alias currentTab: tab
    property string title
    property string url

    // Move this inside WebContainer
    readonly property bool fullscreenMode: (webView.chromeGestureEnabled && !webView.chrome) || webContainer.inputPanelVisible || !webContainer.foreground

    property string favicon
    property Item _contextMenu
    property bool _ctxMenuActive: _contextMenu != null && _contextMenu.active
    // As QML can't disconnect closure from a signal (but methods only)
    // let's keep auth data in this auxilary attribute whose sole purpose is to
    // pass arguments to openAuthDialog().
    property var _authData: null
    property var _deferredLoad: null
    property bool _deferredReload

    // Used by newTab function
    property bool newTabRequested

    function newTab(url, foreground, title) {
        if (foreground) {
            // This might be something that we don't want to have.
            if (webView.loading) {
                webView.stop()
            }
            tab.loadWhenTabChanges = true
            captureScreen()
        }
        // tabMovel.addTab does not trigger anymore navigateTo call. Always done via
        // QmlMozView onUrlChanged handler.
        // Loading newTabs seems to be broken. When an url that was already loaded is loaded again and still
        // active in one of the tabs, the tab containing the url is not brought to foreground.
        // This was broken already before this change. We need to add mapping between intented
        // load url and actual result url to TabModel::activateTab so that finding can be done.
        newTabRequested = true
        tabModel.addTab(url, foreground)
        load(url, title)
    }

    function closeTab(index, loadActive) {
        if (tabModel.count == 0) {
            return
        }

        if (webView.loading) {
            webView.stop()
        }

        tab.loadWhenTabChanges = loadActive
        tabModel.remove(index)
    }

    function closeActiveTab(loadActive) {
        if (tabModel.count === 0) {
            return
        }

        if (webView.loading) {
            webView.stop()
        }

        tab.loadWhenTabChanges = loadActive
        tabModel.closeActiveTab();

        if (tabModel.count === 0 && browserPage.status === PageStatus.Active) {
            browserPage.title = ""
            browserPage.url = ""
            pageStack.push(Qt.resolvedUrl("TabPage.qml"), {"browserPage" : browserPage, "initialSearchFocus": true })
        }
    }

    function reload() {
        var url = browserPage.url

        if (url.substring(0, 6) !== "about:" && url.substring(0, 5) !== "file:"
            && !browserPage._deferredReload
            && !connectionHelper.haveNetworkConnectivity()) {

            browserPage._deferredReload = true
            browserPage._deferredLoad = null
            connectionHelper.attemptToConnectNetwork()
            return
        }

        webView.reload()
    }

    function load(url, title, force) {
        if (url.substring(0, 6) !== "about:" && url.substring(0, 5) !== "file:"
            && !connectionHelper.haveNetworkConnectivity()
            && !browserPage._deferredLoad) {

            browserPage._deferredReload = false
            browserPage._deferredLoad = {
                "url": url,
                "title": title
            }
            connectionHelper.attemptToConnectNetwork()
            return
        }

        if (tabModel.count == 0) {
            newTabRequested = true
            tabModel.addTab(url, true)
        }

        if (title) {
            browserPage.title = title
        } else {
            browserPage.title = ""
        }

        // Always enable chrome when load is called.
        webView.chrome = true

        if ((url !== "" && webView.url != url) || force) {
            browserPage.url = url
            resourceController.firstFrameRendered = false
            webView.load(url)
        }
    }

    function loadTab(index, url, title) {
        if (webView.loading) {
            webView.stop()
        }

        if (url) {
            browserPage.url = url
        }

        if (title) {
            browserPage.title = title
        }

        tab.loadWhenTabChanges = true;
        tabModel.activateTab(index)
        // When tab is loaded we always pop back to BrowserPage.
        pageStack.pop(browserPage)
    }

    function deleteTabHistory() {
        historyModel.clear()
    }

    function captureScreen() {
        if (status == PageStatus.Active && resourceController.firstFrameRendered) {
            var size = Screen.width
            if (browserPage.isLandscape && !fullscreenMode) {
                size -= toolbarRow.height
            }

            tab.captureScreen(webView.url, 0, 0, size, size, browserPage.rotation)
        }
    }

    function closeAllTabs() {
        tabModel.clear()
    }

    function openAuthDialog(input) {
        var data = input !== undefined ? input : browserPage._authData
        var winid = data.winid

        if (browserPage._authData !== null) {
            auxTimer.triggered.disconnect(browserPage.openAuthDialog)
            browserPage._authData = null
        }

        var dialog = pageStack.push(Qt.resolvedUrl("components/AuthDialog.qml"),
                                    {
                                        "hostname": data.text,
                                        "realm": data.title,
                                        "username": data.defaultValue,
                                        "passwordOnly": data.passwordOnly
                                    })
        dialog.accepted.connect(function () {
            webView.sendAsyncMessage("authresponse",
                                     {
                                         "winid": winid,
                                         "accepted": true,
                                         "username": dialog.username,
                                         "password": dialog.password
                                     })
        })
        dialog.rejected.connect(function() {
            webView.sendAsyncMessage("authresponse",
                                     {"winid": winid, "accepted": false})
        })
    }

    function openContextMenu(linkHref, imageSrc, linkTitle, contentType) {
        var ctxMenuComp

        if (_contextMenu) {
            _contextMenu.linkHref = linkHref
            _contextMenu.linkTitle = linkTitle.trim()
            _contextMenu.imageSrc = imageSrc
            hideVirtualKeyboard()
            _contextMenu.show()
        } else {
            ctxMenuComp = Qt.createComponent(Qt.resolvedUrl("components/BrowserContextMenu.qml"))
            if (ctxMenuComp.status !== Component.Error) {
                _contextMenu = ctxMenuComp.createObject(browserPage,
                                                        {
                                                            "linkHref": linkHref,
                                                            "imageSrc": imageSrc,
                                                            "linkTitle": linkTitle.trim(),
                                                            "contentType": contentType,
                                                            "viewId": webView.uniqueID()
                                                        })
                hideVirtualKeyboard()
                _contextMenu.show()
            } else {
                console.log("Can't load BrowserContextMenu.qml")
            }
        }
    }

    function hideVirtualKeyboard() {
        if (Qt.inputMethod.visible) {
            browserPage.focus = true
        }
    }

    // Safety clipping. There is clipping in ApplicationWindow that should react upon focus changes.
    // This clipping can handle also clipping of QmlMozView. When this page is active we do not need to clip
    // if input method is not visible.
    clip: status != PageStatus.Active || webContainer.inputPanelVisible

    orientationTransitions: Transition {
        to: 'Portrait,Landscape,LandscapeInverted'
        from: 'Portrait,Landscape,LandscapeInverted'
        SequentialAnimation {
            PropertyAction {
                target: browserPage
                property: 'orientationTransitionRunning'
                value: true
            }
            ParallelAnimation {
                FadeAnimation {
                    target: webView
                    to: 0
                    duration: 150
                }
                FadeAnimation {
                    target: !fullscreenMode ? controlArea : null
                    to: 0
                    duration: 150
                }
            }
            PropertyAction {
                target: browserPage
                properties: 'width,height,rotation,orientation'
            }
            ScriptAction {
                script: {
                    // Restores the Bindings to width, height and rotation
                    _defaultTransition = false
                    webContainer.resetHeight(true)
                    _defaultTransition = true
                }
            }
            FadeAnimation {
                target: !fullscreenMode ? controlArea : null
                to: 1
                duration: 150
            }
            // End-2-end implementation for OnUpdateDisplayPort should
            // give better solution and reduce visible relayoutting.
            FadeAnimation {
                target: webView
                to: 1
                duration: 850
            }
            PropertyAction {
                target: browserPage
                property: 'orientationTransitionRunning'
                value: false
            }
        }
    }

    TabModel {
        id: tabModel
        currentTab: tab
        browsing: browserPage.status === PageStatus.Active
    }

    HistoryModel {
        id: historyModel

        tabId: tabModel.currentTabId
    }

    Tab {
        id: tab

        // Indicates whether the next url that is set to this Tab element will be loaded.
        // Used when new tabs are created, tabs are loaded, and with back and forward,
        // All of these actions load data asynchronously from the DB, and the changes
        // are reflected in the Tab element.
        property bool loadWhenTabChanges: false
        property bool backForwardNavigation: false

        onUrlChanged: {
            if (tab.valid && (loadWhenTabChanges || backForwardNavigation)) {
                // Both url and title are updated before url changed is emitted.
                load(url, title)
                // loadWhenTabChanges will be set to false when mozview says that url has changed
                // loadWhenTabChanges = false
            }
        }
    }

    Browser.DownloadRemorsePopup { id: downloadPopup }

    // TODO: Merge webContainer and QmlMozView into Sailfish Browser WebView.
    // It should contain all function defined at BrowserPage. BrowserPage
    // should only have call through function when needed e.g. by TabPage.
    // It should also handle title, url, forwardNavigation, backwardNavigation.
    // In addition, it should be fixed to fullscreen size and internally
    // it changes height for QmlMozView.
    WebContainer {
        id: webContainer

        width: parent.width
        height: browserPage.orientation === Orientation.Portrait ? Screen.height : Screen.width

        pageActive: browserPage.status == PageStatus.Active
        webView: webView

        foreground: Qt.application.active
        inputPanelHeight: window.pageStack.panelSize
        inputPanelOpenHeight: window.pageStack.imSize
        toolbarHeight: toolBarContainer.height

        Rectangle {
            id: background
            anchors.fill: parent
            color: webView.bgcolor ? webView.bgcolor : "white"
        }
    }

    Browser.ResourceController {
        id: resourceController
        webView: webView
        background: webContainer.background

        onWebViewSuspended: {
            connectionHelper.closeNetworkSession()
        }

        onFirstFrameRenderedChanged: {
            if (firstFrameRendered) {
                captureScreen()
            }
        }
    }

    QmlMozView {
        id: webView

        readonly property bool loaded: loadProgress === 100
        readonly property bool readyToLoad: viewReady && tabModel.loaded
        property bool userHasDraggedWhileLoading
        property bool viewReady


        visible: WebUtils.firstUseDone

        enabled: browserPage.status == PageStatus.Active
        // There needs to be enough content for enabling chrome gesture
        chromeGestureThreshold: toolBarContainer.height
        chromeGestureEnabled: contentHeight > webContainer.height + chromeGestureThreshold

        signal selectionRangeUpdated(variant data)
        signal selectionCopied(variant data)
        signal contextMenuRequested(variant data)

        focus: true
        width: browserPage.width
        state: ""

        onReadyToLoadChanged: {
            if (!WebUtils.firstUseDone) {
                return
            }

            if (WebUtils.initialPage !== "") {
                browserPage.load(WebUtils.initialPage)
            } else if (tabModel.count > 0) {
                // First tab is actived when tabs are loaded to the tabs model.
                browserPage.load(tab.url, tab.title)
            } else {
                browserPage.load(WebUtils.homePage)
            }
        }

        //{ // TODO
        // No resizes while page is not active
        // also contextmenu size
        //           if (browserPage.status == PageStatus.Active) {
        //               return (_contextMenu != null && (_contextMenu.height > tools.height)) ? browserPage.height - _contextMenu.height : browserPage.height - tools.height
        //               return (_contextMenu != null && (_contextMenu.height > tools.height)) ? 200 : 300

        // Order of onTitleChanged and onUrlChanged is unknown. Hence, use always browserPage.title and browserPage.url
        // as they are set in the load function of BrowserPage.
        onTitleChanged: {
            // This is always after url has changed
            browserPage.title = title
            tab.updateTab(browserPage.url, browserPage.title)
        }

        onUrlChanged: {
            browserPage.url = url

            if (!resourceController.isRejectedGeolocationUrl(url)) {
                resourceController.rejectedGeolocationUrl = ""
            }

            if (!resourceController.isAcceptedGeolocationUrl(url)) {
                resourceController.acceptedGeolocationUrl = ""
            }

            if (tab.backForwardNavigation) {
                tab.updateTab(browserPage.url, browserPage.title)
                tab.backForwardNavigation = false
            } else if (!browserPage.newTabRequested) {
                // Use browserPage.title here to avoid wrong title to blink.
                // browserPage.load() updates browserPage's title before load starts.
                // QmlMozView's title is not correct over here.
                tab.navigateTo(browserPage.url)
            }
            tab.loadWhenTabChanges = false
            browserPage.newTabRequested = false
        }

        onBgcolorChanged: {
            var bgLightness = WebUtils.getLightness(bgcolor)
            var dimmerLightness = WebUtils.getLightness(Theme.highlightDimmerColor)
            var highBgLightness = WebUtils.getLightness(Theme.highlightBackgroundColor)

            if (Math.abs(bgLightness - dimmerLightness) > Math.abs(bgLightness - highBgLightness)) {
                verticalScrollDecorator.color = Theme.highlightDimmerColor
                horizontalScrollDecorator.color = Theme.highlightDimmerColor
            } else {
                verticalScrollDecorator.color = Theme.highlightBackgroundColor
                horizontalScrollDecorator.color = Theme.highlightBackgroundColor
            }

            sendAsyncMessage("Browser:SelectionColorUpdate",
                             {
                                 "color": Theme.secondaryHighlightColor
                             })
        }

        onViewInitialized: {
            addMessageListener("chrome:linkadded")
            addMessageListener("embed:alert")
            addMessageListener("embed:confirm")
            addMessageListener("embed:prompt")
            addMessageListener("embed:auth")
            addMessageListener("embed:login")
            addMessageListener("embed:permissions")
            addMessageListener("Content:ContextMenu")
            addMessageListener("Content:SelectionRange");
            addMessageListener("Content:SelectionCopied");
            addMessageListener("embed:selectasync")

            loadFrameScript("chrome://embedlite/content/SelectAsyncHelper.js")
            loadFrameScript("chrome://embedlite/content/embedhelper.js")

            viewReady = true
        }

        onDraggingChanged: {
            if (dragging && loading) {
                userHasDraggedWhileLoading = true
            }
        }

        onLoadedChanged: {
            if (loaded) {
                if (url != "about:blank" && url) {
                    // This is always up-to-date in both link clicked and back/forward navigation
                    // captureScreen does not work here as we might have changed to TabPage.
                    // Tab icon clicked takes care of the rest.
                    tab.updateTab(browserPage.url, browserPage.title)
                }

                if (!userHasDraggedWhileLoading) {
                    webContainer.resetHeight(false)
                }
            }
        }

        onLoadingChanged: {
            if (loading) {
                userHasDraggedWhileLoading = false
                favicon = ""
                webView.chrome = true
                webContainer.resetHeight(false)
            }
        }
        onRecvAsyncMessage: {
            switch (message) {
            case "chrome:linkadded": {
                if (data.rel === "shortcut icon") {
                    favicon = data.href
                }
                break
            }
            case "embed:selectasync": {
                var dialog

                dialog = pageStack.push(Qt.resolvedUrl("components/SelectDialog.qml"),
                                        {
                                            "options": data.options,
                                            "multiple": data.multiple,
                                            "webview": webView
                                        })
                break;
            }
            case "embed:alert": {
                var winid = data.winid
                var dialog = pageStack.push(Qt.resolvedUrl("components/AlertDialog.qml"),
                                            {"text": data.text})
                // TODO: also the Async message must be sent when window gets closed
                dialog.done.connect(function() {
                    sendAsyncMessage("alertresponse", {"winid": winid})
                })
                break
            }
            case "embed:confirm": {
                var winid = data.winid
                var dialog = pageStack.push(Qt.resolvedUrl("components/ConfirmDialog.qml"),
                                            {"text": data.text})
                // TODO: also the Async message must be sent when window gets closed
                dialog.accepted.connect(function() {
                    sendAsyncMessage("confirmresponse",
                                     {"winid": winid, "accepted": true})
                })
                dialog.rejected.connect(function() {
                    sendAsyncMessage("confirmresponse",
                                     {"winid": winid, "accepted": false})
                })
                break
            }
            case "embed:prompt": {
                var winid = data.winid
                var dialog = pageStack.push(Qt.resolvedUrl("components/PromptDialog.qml"),
                                            {"text": data.text, "value": data.defaultValue})
                // TODO: also the Async message must be sent when window gets closed
                dialog.accepted.connect(function() {
                    sendAsyncMessage("promptresponse",
                                     {
                                         "winid": winid,
                                         "accepted": true,
                                         "promptvalue": dialog.value
                                     })
                })
                dialog.rejected.connect(function() {
                    sendAsyncMessage("promptresponse",
                                     {"winid": winid, "accepted": false})
                })
                break
            }
            case "embed:auth": {
                if (pageStack.busy) {
                    // User has just entered wrong credentials and webView wants
                    // user's input again immediately even thogh the accepted
                    // dialog is still deactivating.
                    browserPage._authData = data
                    // A better solution would be to connect to browserPage.statusChanged,
                    // but QML Page transitions keep corrupting even
                    // after browserPage.status === PageStatus.Active thus auxTimer.
                    auxTimer.triggered.connect(browserPage.openAuthDialog)
                    auxTimer.start()
                } else {
                    browserPage.openAuthDialog(data)
                }
                break
            }
            case "embed:permissions": {
                // Ask for location permission
                if (resourceController.isAcceptedGeolocationUrl(webView.url)) {
                    sendAsyncMessage("embedui:premissions", {
                                         allow: true,
                                         checkedDontAsk: false,
                                         id: data.id })
                } else if (resourceController.isRejectedGeolocationUrl(webView.url)) {
                    sendAsyncMessage("embedui:premissions", {
                                         allow: false,
                                         checkedDontAsk: false,
                                         id: data.id })
                } else {
                    var dialog = pageStack.push(Qt.resolvedUrl("components/LocationDialog.qml"), {})
                    dialog.accepted.connect(function() {
                        sendAsyncMessage("embedui:premissions", {
                                             allow: true,
                                             checkedDontAsk: false,
                                             id: data.id })
                        resourceController.acceptedGeolocationUrl = WebUtils.displayableUrl(webView.url)
                        resourceController.rejectedGeolocationUrl = ""
                    })
                    dialog.rejected.connect(function() {
                        sendAsyncMessage("embedui:premissions", {
                                             allow: false,
                                             checkedDontAsk: false,
                                             id: data.id })
                        resourceController.rejectedGeolocationUrl = WebUtils.displayableUrl(webView.url)
                        resourceController.acceptedGeolocationUrl = ""
                    })
                }
                break
            }
            case "embed:login": {
                pageStack.push(Qt.resolvedUrl("components/PasswordManagerDialog.qml"),
                               {
                                   "webView": webView,
                                   "requestId": data.id,
                                   "notificationType": data.name,
                                   "formData": data.formdata
                               })
                break
            }
            case "Content:ContextMenu": {
                webView.contextMenuRequested(data)
                if (data.types.indexOf("image") !== -1 || data.types.indexOf("link") !== -1) {
                    openContextMenu(data.linkURL, data.mediaURL, data.linkTitle, data.contentType)
                }
                break
            }
            case "Content:SelectionRange": {
                webView.selectionRangeUpdated(data)
                break
            }
            }
        }
        onRecvSyncMessage: {
            // sender expects that this handler will update `response` argument
            switch (message) {
            case "Content:SelectionCopied": {
                webView.selectionCopied(data)

                if (data.succeeded) {
                    //% "Copied to clipboard"
                    notification.show(qsTrId("sailfish_browser-la-selection_copied"))
                }
                break
            }
            }
        }

        // We decided to disable "text selection" until we understand how it
        // should look like in Sailfish.
        // TextSelectionController {}

        Rectangle {
            id: verticalScrollDecorator

            width: 5
            height: webView.verticalScrollDecorator.height
            y: webView.verticalScrollDecorator.y
            anchors.right: parent ? parent.right: undefined
            color: Theme.highlightDimmerColor
            smooth: true
            radius: 2.5
            visible: webView.contentHeight > webView.height && !webView.pinching && !_ctxMenuActive
            opacity: webView.moving ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { properties: "opacity"; duration: 400 } }
        }

        Rectangle {
            id: horizontalScrollDecorator
            width: webView.horizontalScrollDecorator.width
            height: 5
            x: webView.horizontalScrollDecorator.x
            y: browserPage.height - (fullscreenMode ? 0 : toolBarContainer.height) - height
            color: Theme.highlightDimmerColor
            smooth: true
            radius: 2.5
            visible: webView.contentWidth > webView.width && !webView.pinching && !_ctxMenuActive
            opacity: webView.moving ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { properties: "opacity"; duration: 400 } }
        }

        states: State {
            name: "boundHeightControl"
            when: webContainer.inputPanelVisible || !webContainer.foreground
            PropertyChanges {
                target: webView
                height: browserPage.height
            }
        }
    }

    Column {
        id: controlArea

        // This should be just a binding for progressBar.progress but currently progress is going up and down
        property real loadProgress: webView.loadProgress / 100.0

        anchors.bottom: webContainer.bottom
        width: parent.width

        visible: !_ctxMenuActive
        opacity: fullscreenMode ? 0.0 : 1.0
        Behavior on opacity { FadeAnimation { duration: webContainer.foreground ? 300 : 0 } }

        onLoadProgressChanged: {
            if (loadProgress > progressBar.progress) {
                progressBar.progress = loadProgress
            }
        }

        function openTabPage(focus, newTab, operationType) {
            if (browserPage.status === PageStatus.Active) {
                captureScreen()
                pageStack.push(Qt.resolvedUrl("TabPage.qml"),
                               {
                                   "browserPage" : browserPage,
                                   "initialSearchFocus": focus,
                                   "newTab": newTab
                               }, operationType)
            }
        }

        Browser.StatusBar {
            width: parent.width
            height: visible ? toolBarContainer.height * 3 : 0
            visible: isPortrait
            opacity: progressBar.opacity
            title: browserPage.title
            url: browserPage.url
            onSearchClicked: controlArea.openTabPage(true, false, PageStackAction.Animated)
            onCloseClicked: browserPage.closeActiveTab(true)
        }

        Browser.ToolBarContainer {
            id: toolBarContainer
            width: parent.width
            enabled: !fullscreenMode

            Browser.ProgressBar {
                id: progressBar
                anchors.fill: parent
                opacity: webView.loading ? 1.0 : 0.0
            }

            // ToolBar
            Row {
                id: toolbarRow

                anchors {
                    left: parent.left; leftMargin: Theme.paddingMedium
                    right: parent.right; rightMargin: Theme.paddingMedium
                    verticalCenter: parent.verticalCenter
                }

                // 5 icons, 4 spaces between
                spacing: isPortrait ? (width - (backIcon.width * 5)) / 4 : Theme.paddingSmall

                Browser.IconButton {
                    visible: isLandscape
                    source: "image://theme/icon-m-close"
                    onClicked: browserPage.closeActiveTab(true)
                }

                // Spacer
                Item {
                    visible: isLandscape
                    height: Theme.itemSizeSmall
                    width: browserPage.width
                           - toolbarRow.spacing * (toolbarRow.children.length - 1)
                           - backIcon.width * (toolbarRow.children.length - 1)
                           - parent.anchors.leftMargin
                           - parent.anchors.rightMargin

                    Browser.TitleBar {
                        url: browserPage.url
                        title: browserPage.title
                        height: parent.height
                        onClicked: controlArea.openTabPage(true, false, PageStackAction.Animated)
                        // Workaround for binding loop jb#15182
                        clip: true
                    }
                }

                Browser.IconButton {
                    id: backIcon
                    source: "image://theme/icon-m-back"
                    enabled: tab.canGoBack
                    onClicked: {
                        tab.backForwardNavigation = true
                        tab.goBack()
                    }
                }

                Browser.IconButton {
                    enabled: WebUtils.firstUseDone
                    property bool favorited: favorites.count > 0 && favorites.contains(tab.url)
                    source: favorited ? "image://theme/icon-m-favorite-selected" : "image://theme/icon-m-favorite"
                    onClicked: {
                        if (favorited) {
                            favorites.removeBookmark(tab.url)
                        } else {
                            favorites.addBookmark(tab.url, tab.title, favicon)
                        }
                    }
                }

                Browser.IconButton {
                    id: tabPageButton
                    source: "image://theme/icon-m-tabs"
                    onClicked: controlArea.openTabPage(false, false, PageStackAction.Animated)

                    Label {
                        visible: tabModel.count > 0
                        text: tabModel.count
                        x: (parent.width - contentWidth) / 2 - 5
                        y: (parent.height - contentHeight) / 2 - 5
                        font.pixelSize: Theme.fontSizeExtraSmall
                        font.bold: true
                        color: tabPageButton.down ? Theme.highlightDimmerColor : Theme.highlightColor
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Browser.IconButton {
                    enabled: WebUtils.firstUseDone
                    source: webView.loading ? "image://theme/icon-m-reset" : "image://theme/icon-m-refresh"
                    onClicked: webView.loading ? webView.stop() : browserPage.reload()
                }

                Browser.IconButton {
                    source: "image://theme/icon-m-forward"
                    enabled: tab.canGoForward
                    onClicked: {
                        tab.backForwardNavigation = true
                        tab.goForward()
                    }
                }
            }
        }
    }

    CoverActionList {
        enabled: browserPage.status === PageStatus.Active
        iconBackground: true

        CoverAction {
            iconSource: "image://theme/icon-cover-new"
            onTriggered: {
                controlArea.openTabPage(true, true, PageStackAction.Immediate)
                activate()
            }
        }

        CoverAction {
            iconSource: webView.loading ? "image://theme/icon-cover-cancel" : "image://theme/icon-cover-refresh"
            onTriggered: {
                if (webView.loading) {
                    webView.stop()
                } else {
                    browserPage.reload()
                }
            }
        }
    }

    onStatusChanged: {
        if (status === PageStatus.Inactive && !WebUtils.firstUseDone) {
            WebUtils.firstUseDone = true
        }
    }

    Connections {
        target: WebUtils
        onOpenUrlRequested: {
            if (url == "") {
                // User tapped on icon when browser was already open.
                // let's just bring the browser to front
                if (!window.applicationActive) {
                    window.activate()
                }
                return
            }
            if (webView.url != "") {
                captureScreen()
                if (!tabModel.activateTab(url)) {
                    // Not found in tabs list, create newtab and load
                    newTab(url, true)
                }
            } else {
                // New browser instance, just load the content
                if (WebUtils.firstUseDone) {
                    load(url)
                } else {
                    tabModel.addTab(url, false)
                }
            }
            if (browserPage.status !== PageStatus.Active) {
                pageStack.pop(browserPage, PageStackAction.Immediate)
            }
            if (!window.applicationActive) {
                window.activate()
            }
        }
        onFirstUseDoneChanged: {
            if (WebUtils.firstUseDone && firstUseOverlay) {
                firstUseOverlay.destroy()
            }
        }
    }

    Component.onCompleted: {
        if (!WebUtils.firstUseDone) {
            var component = Qt.createComponent(Qt.resolvedUrl("components/FirstUseOverlay.qml"))
            if (component.status == Component.Ready) {
                firstUseOverlay = component.createObject(browserPage, {"width": browserPage.width, "height": browserPage.height - toolBarContainer.height });
            } else {
                console.log("FirstUseOverlay create failed " + component.status)
            }
        }
    }

    Component.onDestruction: {
        connectionHelper.closeNetworkSession()
    }

    BookmarkModel {
        id: favoriteModel
    }

    Timer {
        id: auxTimer

        interval: 1000
    }

    Browser.BrowserNotification {
        id: notification
    }

    ConnectionHelper {
        id: connectionHelper

        onNetworkConnectivityEstablished: {
            var url
            var title

            if (browserPage._deferredLoad) {
                url = browserPage._deferredLoad["url"]
                title = browserPage._deferredLoad["title"]
                browserPage._deferredLoad = null

                browserPage.load(url, title, true)
            } else if (browserPage._deferredReload) {
                browserPage._deferredReload = false
                webView.reload()
            }
        }

        onNetworkConnectivityUnavailable: {
            browserPage._deferredLoad = null
            browserPage._deferredReload = false
        }
    }
}

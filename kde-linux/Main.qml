import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import QtWebChannel
import QtWebEngine
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root
    width: 920
    height: 680
    minimumWidth: 620
    minimumHeight: 520
    visible: true
    title: "XJAUS"
    objectName: "xjaus-main-window"

    property bool authenticated: false
    property bool loginStarting: false
    property bool polling: false
    property string attemptId: ""
    property string verificationUri: ""
    property string userCode: ""
    property string loginMessage: "Starting the Linux KDE frontend…"
    property int loginIntervalSeconds: 5
    property int loginExpiresSeconds: 0
    property double beginRequestId: 0
    property double pollRequestId: 0
    property double statusRequestId: 0
    property double logoutRequestId: 0
    property double consolesRequestId: 0
    property double serversRequestId: 0
    property double cloudRequestId: 0
    property double settingsLoadRequestId: 0
    property double settingsSaveRequestId: 0
    property double backendStatusRequestId: 0
    property string backendHealthMessage: "Backend health has not been checked."
    property string currentSection: "home"
    property bool playerPageReady: false
    property var pendingNativeLaunch: null
    property string nativeLaunchMessage: ""
    property string consoleMessage: "Consoles have not been loaded."
    property string serverMessage: "Streaming servers have not been loaded."
    property var smartConsoleRecords: []
    property string cloudMessage: "Load the Cloud catalog when ready."
    property string settingsMessage: "Settings have not been loaded."
    property var settings: ({
        resolution: "1920x1080", bitrate: 30000, codec: "auto",
        audio: "opus", audioGain: 1
    })

    WebChannel {
        id: nativeChannel
    }

    function launchNativeStream(kind, target, name, artwork, consoleItem) {
        if (!authenticated || !backend.available || !target) {
            nativeLaunchMessage = "Sign in and select an available streaming target first."
            return
        }
        pendingNativeLaunch = { kind, target, name, artwork, console: consoleItem }
        nativeLaunchMessage = "Opening the player…"
        currentSection = "player"
        if (playerPageReady)
            playerLaunchTimer.restart()
    }

    function dispatchNativeLaunch() {
        if (!pendingNativeLaunch || !playerPageReady)
            return
        const payload = JSON.stringify(pendingNativeLaunch)
        webPlayer.runJavaScript(
            "window.dispatchEvent(new CustomEvent('xjaus:native-launch',{detail:" + payload + "}));"
        )
        pendingNativeLaunch = null
        nativeLaunchMessage = "Connecting…"
    }

    function streamingTargetFor(consoleName) {
        const key = String(consoleName || "").toLocaleLowerCase()
        for (let i = 0; i < serverModel.count; ++i) {
            const server = serverModel.get(i)
            if (key && String(server.name || "").toLocaleLowerCase() === key)
                return server.serverId
        }
        if (consoleModel.count === 1 && serverModel.count === 1)
            return serverModel.get(0).serverId
        return ""
    }

    function startLogin() {
        if (!backend.available || loginStarting || polling)
            return
        attemptId = backend.createAttemptId()
        verificationUri = ""
        userCode = ""
        loginMessage = "Requesting a Microsoft sign-in code…"
        loginStarting = true
        beginRequestId = backend.invoke("begin_login_window", { "attemptId": attemptId })
    }

    function pollLogin() {
        if (!polling || !attemptId || pollRequestId !== 0)
            return
        pollRequestId = backend.invoke("poll_login", { "attemptId": attemptId })
    }

    function cancelLogin() {
        if (!attemptId)
            return
        pollTimer.stop()
        polling = false
        loginStarting = false
        backend.invoke("cancel_login", { "attemptId": attemptId })
        attemptId = ""
        userCode = ""
        verificationUri = ""
        loginMessage = "Sign-in cancelled."
    }

    function records(value) {
        if (Array.isArray(value))
            return value
        if (!value || typeof value !== "object")
            return []
        for (const key of ["result", "servers", "results", "devices", "consoles"]) {
            if (Array.isArray(value[key]))
                return value[key]
        }
        if (value.result && typeof value.result === "object")
            return root.records(value.result)
        return []
    }

    function rebuildConsoleModel() {
        const smart = smartConsoleRecords.filter(item => item && typeof item === "object")
        consoleModel.clear()
        if (smart.length > 0) {
            for (const item of smart) {
                consoleModel.append({
                    name: String(item.name || item.deviceName || "Xbox console"),
                    powerState: String(item.powerState || "Unknown"),
                    deviceId: String(item.id || "")
                })
            }
            consoleMessage = smart.length + " console record(s) returned."
            return
        }

        for (let index = 0; index < serverModel.count; ++index) {
            const server = serverModel.get(index)
            if (!server.serverId)
                continue
            consoleModel.append({
                name: server.name,
                powerState: "Unknown",
                deviceId: ""
            })
        }
        consoleMessage = consoleModel.count > 0
            ? "SmartGlass returned no consoles; showing Remote Play targets."
            : "No console or Remote Play records were returned."
    }

    function showSection(section) {
        currentSection = section
        if (section === "consoles")
            loadConsoles()
        else if (section === "cloud")
            loadCloud()
        else if (section === "settings")
            loadSettings()
    }

    function loadConsoles() {
        if (!authenticated || !backend.available)
            return
        consoleMessage = "Loading console presence…"
        serverMessage = "Loading Remote Play targets…"
        consolesRequestId = backend.invoke("list_consoles_smartglass")
        serversRequestId = backend.invoke("list_streaming_servers")
    }

    function loadCloud() {
        if (!authenticated || !backend.available)
            return
        cloudMessage = "Loading the Cloud catalog…"
        cloudRequestId = backend.invoke("list_cloud_titles")
    }

    function loadSettings() {
        if (!backend.available)
            return
        settingsMessage = "Loading saved settings…"
        settingsLoadRequestId = backend.invoke("load_settings")
    }

    function applyAuthStatus(result) {
        authenticated = result && result.authenticated === true
        if (authenticated) {
            loadSettings()
            loadConsoles()
            pollTimer.stop()
            polling = false
            loginStarting = false
            attemptId = ""
            userCode = ""
            verificationUri = ""
            loginMessage = "Signed in. Your session is stored in the system keyring."
        } else if (!polling && !loginStarting) {
            loginMessage = "Sign in to continue. Your session can be restored from the system keyring."
        }
    }

    function loadBackendStatus() {
        if (!backend.available)
            return
        backendHealthMessage = "Checking Rust service…"
        backendStatusRequestId = backend.invoke("backend_status")
    }

    Component.onCompleted: {
        const channelLibrary = WebEngine.script()
        channelLibrary.name = "xjaus-webchannel-library"
        channelLibrary.sourceUrl = "qrc:///qtwebchannel/qwebchannel.js"
        channelLibrary.injectionPoint = WebEngineScript.DocumentCreation
        channelLibrary.worldId = WebEngineScript.MainWorld

        const nativeBridge = WebEngine.script()
        nativeBridge.name = "xjaus-native-bridge"
        nativeBridge.sourceUrl = "qrc:/xjaus/webchannel-bridge.js"
        nativeBridge.injectionPoint = WebEngineScript.DocumentCreation
        nativeBridge.worldId = WebEngineScript.MainWorld

        webPlayer.userScripts.collection = [channelLibrary, nativeBridge]
        nativeChannel.registerObject("backend", backend)
        if (backend.frontendUrl.toString().length > 0)
            webPlayer.url = backend.frontendUrl
        if (backend.available) {
            statusRequestId = backend.invoke("load_session")
            loadBackendStatus()
        }
    }

    Connections {
        target: backend

        function onAvailableChanged() {
            if (backend.available) {
                loginMessage = "Backend ready. Checking sign-in status…"
                statusRequestId = backend.invoke("load_session")
                loadBackendStatus()
            } else {
                loginMessage = backend.statusMessage
            }
        }

        function onStatusMessageChanged() {
            if (!backend.available && !loginStarting && !polling)
                loginMessage = backend.statusMessage
        }

        function onRequestFinished(id, command, result, error) {
            if (command === "backend_status" && id === root.backendStatusRequestId) {
                if (error.length > 0) {
                    root.backendHealthMessage = "Rust service health query failed."
                    return
                }
                if (result.ready !== true) {
                    root.backendHealthMessage = "Rust service did not report ready."
                    return
                }
                const health = result.health || {}
                const session = health.session || {}
                const cleanup = health.cleanup || {}
                root.backendHealthMessage = "Rust ready · "
                    + String(health.authentication || "sign-in unknown")
                    + " · stream " + String(session.state || "unknown")
                    + " · cleanup " + String(cleanup.state || "unknown")
                    + " · v" + String(result.version || "?")
                return
            }

            if ((command === "auth_status" || command === "load_session") && id === root.statusRequestId) {
                if (error.length > 0) {
                    root.loginMessage = command === "load_session"
                        ? "Could not restore the saved session. Check the keyring and network, or sign in again."
                        : "Could not read sign-in status."
                    return
                }
                root.applyAuthStatus(result)
                if (command === "load_session")
                    root.loadBackendStatus()
                return
            }

            if (command === "logout" && id === root.logoutRequestId) {
                root.logoutRequestId = 0
                if (error.length > 0) {
                    root.loginMessage = "Sign-out could not be confirmed. Restart the app and sign in again."
                    return
                }
                root.authenticated = false
                root.loginMessage = "Signed out locally. This does not confirm server-side token revocation."
                root.statusRequestId = backend.invoke("auth_status")
                return
            }

            if (command === "list_consoles_smartglass" && id === root.consolesRequestId) {
                if (error.length > 0) {
                    root.consoleMessage = "Could not load console presence."
                    return
                }
                root.smartConsoleRecords = root.records(result)
                root.rebuildConsoleModel()
                return
            }

            if (command === "list_streaming_servers" && id === root.serversRequestId) {
                if (error.length > 0) {
                    root.serverMessage = "Could not load Remote Play targets."
                    serverModel.clear()
                    root.rebuildConsoleModel()
                    return
                }
                const items = root.records(result)
                serverModel.clear()
                for (let index = 0; index < items.length; ++index) {
                    const item = items[index]
                    if (!item || typeof item !== "object")
                        continue
                    serverModel.append({
                        name: String(item.name || item.deviceName || "Streaming target " + String(index + 1)),
                        serverId: String(item.serverId || item.id || "")
                    })
                }
                root.serverMessage = items.length
                    ? items.length + " Remote Play target(s) returned."
                    : "No Remote Play targets were returned."
                root.rebuildConsoleModel()
                return
            }

            if (command === "list_cloud_titles" && id === root.cloudRequestId) {
                if (error.length > 0) {
                    root.cloudMessage = "Could not load the Cloud catalog."
                    return
                }
                const items = root.records(result)
                cloudModel.clear()
                for (const item of items) {
                    if (!item || typeof item !== "object")
                        continue
                    const details = item.details || {}
                    const titleId = String(item.titleId || item.id || "")
                    if (!titleId)
                        continue
                    cloudModel.append({
                        name: String(item.name || details.title || details.name || titleId),
                        titleId
                    })
                }
                root.cloudMessage = items.length
                    ? items.length + " catalog record(s) returned."
                    : "No catalog records were returned."
                return
            }

            if (command === "load_settings" && id === root.settingsLoadRequestId) {
                if (error.length > 0) {
                    root.settingsMessage = "Could not load settings; defaults are shown."
                    return
                }
                const saved = result || {}
                root.settings = {
                    resolution: saved.resolution || "1920x1080",
                    bitrate: Number(saved.bitrate) || 30000,
                    codec: saved.codec || "auto",
                    audio: saved.audio || "opus",
                    audioGain: Number(saved.audioGain) || 1
                }
                resolutionControl.currentIndex = resolutionControl.find(root.settings.resolution)
                codecControl.currentIndex = codecControl.find(root.settings.codec)
                audioControl.currentIndex = audioControl.find(root.settings.audio)
                bitrateControl.value = root.settings.bitrate / 1000
                gainControl.value = root.settings.audioGain
                root.settingsMessage = "Settings loaded."
                return
            }

            if (command === "save_settings" && id === root.settingsSaveRequestId) {
                root.settingsSaveRequestId = 0
                root.settingsMessage = error.length > 0
                    ? "Could not save settings."
                    : "Settings saved."
                return
            }

            if (command === "begin_login_window" && id === root.beginRequestId) {
                root.loginStarting = false
                if (error.length > 0) {
                    root.loginMessage = "Could not start sign-in. Check the network and try again."
                    return
                }
                root.userCode = result.user_code || ""
                root.verificationUri = result.verification_uri || ""
                root.loginIntervalSeconds = Math.max(1, Number(result.interval) || 5)
                root.loginExpiresSeconds = Math.max(1, Number(result.expires_in) || 600)
                if (!root.userCode || !root.verificationUri) {
                    root.loginMessage = "The sign-in service returned an incomplete response."
                    return
                }
                root.polling = true
                root.loginMessage = "Enter the code in the browser, then return here."
                pollTimer.interval = root.loginIntervalSeconds * 1000
                expiryTimer.interval = root.loginExpiresSeconds * 1000
                expiryTimer.restart()
                pollTimer.restart()
                return
            }

            if (command === "poll_login" && id === root.pollRequestId) {
                root.pollRequestId = 0
                if (!root.polling)
                    return
                if (error.length === 0) {
                    root.applyAuthStatus(result)
                    return
                }
                if (error === "Waiting for user" || error === "slow_down") {
                    if (error === "slow_down") {
                        root.loginIntervalSeconds = Math.min(30, root.loginIntervalSeconds + 5)
                        pollTimer.interval = root.loginIntervalSeconds * 1000
                    }
                    root.loginMessage = "Waiting for Microsoft sign-in…"
                    pollTimer.restart()
                    return
                }
                pollTimer.stop()
                expiryTimer.stop()
                root.polling = false
                root.attemptId = ""
                root.userCode = ""
                root.verificationUri = ""
                root.loginMessage = error === "Device code expired"
                    ? "The sign-in code expired. Start again to get a new code."
                    : "Sign-in did not complete. Start again or check the connection."
            }
        }

        function onStreamStateChanged(active) {
            if (active) {
                root.nativeLaunchMessage = "Stream active."
            } else if (root.currentSection === "player") {
                root.pendingNativeLaunch = null
                root.currentSection = "home"
                root.nativeLaunchMessage = "Stream ended."
            }
        }
    }

    Timer {
        id: playerLaunchTimer
        interval: 250
        repeat: false
        onTriggered: root.dispatchNativeLaunch()
    }

    Timer {
        id: pollTimer
        repeat: false
        onTriggered: root.pollLogin()
    }

    Timer {
        id: expiryTimer
        repeat: false
        onTriggered: {
            if (root.polling) {
                root.cancelLogin()
                root.loginMessage = "The sign-in code expired. Start again to get a new code."
            }
        }
    }

    globalDrawer: Kirigami.GlobalDrawer {
        title: "XJAUS"
        isMenu: true
        enabled: root.authenticated && root.currentSection !== "player"
        actions: [
            Kirigami.Action {
                text: "Home"
                icon.name: "go-home"
                onTriggered: root.showSection("home")
            },
            Kirigami.Action {
                text: "Consoles"
                icon.name: "input-gaming"
                onTriggered: root.showSection("consoles")
            },
            Kirigami.Action {
                text: "Cloud Gaming"
                icon.name: "applications-games"
                onTriggered: root.showSection("cloud")
            },
            Kirigami.Action {
                text: "Settings"
                icon.name: "settings-configure"
                onTriggered: root.showSection("settings")
            }
        ]
    }

    ListModel { id: consoleModel }
    ListModel { id: serverModel }
    ListModel { id: cloudModel }

    pageStack.initialPage: Kirigami.Page {
        title: "XJAUS"
        padding: Kirigami.Units.largeSpacing

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 2 * Kirigami.Units.largeSpacing, 560)
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                source: "input-gaming"
                implicitWidth: 64
                implicitHeight: 64
            }

            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: "XJAUS"
                font.pixelSize: 30
                font.weight: Font.DemiBold
            }

            Controls.Label {
                Layout.alignment: Qt.AlignHCenter
                text: "Xbox Cloud Gaming and Remote Play"
                opacity: 0.8
            }

            Kirigami.Card {
                visible: !root.authenticated
                Layout.fillWidth: true

                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.mediumSpacing

                    Controls.Label {
                        Layout.fillWidth: true
                        text: root.authenticated
                            ? "Signed in"
                            : "Sign in with your Microsoft account"
                        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.25
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Controls.Label {
                        Layout.fillWidth: true
                        text: root.loginMessage
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Controls.Label {
                        visible: root.userCode.length > 0
                        Layout.alignment: Qt.AlignHCenter
                        text: root.userCode
                        font.pixelSize: 28
                        font.weight: Font.Bold
                        font.family: "monospace"
                        Accessible.name: "Microsoft sign-in code"
                    }

                    Controls.Button {
                        visible: root.userCode.length > 0
                        Layout.alignment: Qt.AlignHCenter
                        text: "Open Microsoft sign-in"
                        icon.name: "internet-web-browser"
                        onClicked: backend.openVerificationUrl(root.verificationUri)
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: Kirigami.Units.smallSpacing

                        Controls.Button {
                            visible: !root.authenticated && !root.polling
                            enabled: backend.available && !root.loginStarting
                            text: root.loginStarting ? "Starting…" : "Sign in"
                            icon.name: "dialog-password"
                            onClicked: root.startLogin()
                        }

                        Controls.Button {
                            visible: root.polling
                            text: "Cancel sign-in"
                            icon.name: "dialog-cancel"
                            onClicked: root.cancelLogin()
                        }

                        Controls.Button {
                            visible: root.authenticated
                            enabled: backend.available && root.logoutRequestId === 0
                            text: root.logoutRequestId === 0 ? "Sign out" : "Signing out…"
                            icon.name: "system-log-out"
                            onClicked: {
                                root.logoutRequestId = backend.invoke("logout")
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                visible: root.authenticated
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.mediumSpacing

                Controls.Label {
                    Layout.fillWidth: true
                    text: "Signed in · session protected by the system keyring"
                    horizontalAlignment: Text.AlignHCenter
                    opacity: 0.8
                }

                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.currentSection === "player" ? 4
                        : root.currentSection === "consoles" ? 1
                        : root.currentSection === "cloud" ? 2
                        : root.currentSection === "settings" ? 3 : 0

                    Kirigami.Card {
                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.mediumSpacing
                            Controls.Label {
                                Layout.fillWidth: true
                                text: "Welcome to XJAUS"
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                text: "Browse Xbox Cloud Gaming or connect to a home console. The Kirigami shell handles sign-in and settings; the embedded player reuses the established WebRTC session lifecycle."
                                wrapMode: Text.Wrap
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Controls.Button {
                                    Layout.fillWidth: true
                                    text: "Consoles"
                                    icon.name: "input-gaming"
                                    onClicked: root.showSection("consoles")
                                }
                                Controls.Button {
                                    Layout.fillWidth: true
                                    text: "Cloud Gaming"
                                    icon.name: "applications-games"
                                    onClicked: root.showSection("cloud")
                                }
                                Controls.Button {
                                    Layout.fillWidth: true
                                    text: "Settings"
                                    icon.name: "settings-configure"
                                    onClicked: root.showSection("settings")
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing
                        RowLayout {
                            Layout.fillWidth: true
                            Controls.Label {
                                Layout.fillWidth: true
                                text: "Xbox Remote Play"
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                            }
                            Controls.Button {
                                text: "Refresh"
                                icon.name: "view-refresh"
                                enabled: backend.available
                                onClicked: root.loadConsoles()
                            }
                        }
                        Controls.Label {
                            Layout.fillWidth: true
                            text: root.consoleMessage + " " + root.serverMessage
                            wrapMode: Text.Wrap
                            opacity: 0.8
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: consoleModel
                            delegate: Controls.ItemDelegate {
                                width: ListView.view.width
                                text: name + " · " + powerState
                                enabled: root.streamingTargetFor(name).length > 0
                                onClicked: {
                                    const target = root.streamingTargetFor(name)
                                    if (!target) {
                                        root.serverMessage = "No matching Remote Play target was found. Refresh both lists and try again."
                                        return
                                    }
                                    root.launchNativeStream("home", target, name, null, {
                                        id: deviceId,
                                        name,
                                        powerState
                                    })
                                }
                            }
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(contentHeight, 140)
                            clip: true
                            model: serverModel
                            delegate: Controls.ItemDelegate {
                                width: ListView.view.width
                                text: name + (serverId.length ? " · " + serverId : "")
                                enabled: false
                            }
                        }
                        Kirigami.InlineMessage {
                            Layout.fillWidth: true
                            type: Kirigami.MessageType.Information
                            text: "Remote Play launches through the shared Xbox session and WebRTC path inside the native KDE player."
                        }
                    }

                    ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing
                        RowLayout {
                            Layout.fillWidth: true
                            Controls.Label {
                                Layout.fillWidth: true
                                text: "Cloud Gaming"
                                font.pixelSize: 20
                                font.weight: Font.DemiBold
                            }
                            Controls.Button {
                                text: "Refresh"
                                icon.name: "view-refresh"
                                enabled: backend.available
                                onClicked: root.loadCloud()
                            }
                        }
                        Controls.Label {
                            Layout.fillWidth: true
                            text: root.cloudMessage
                            wrapMode: Text.Wrap
                            opacity: 0.8
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: cloudModel
                            delegate: Controls.ItemDelegate {
                                width: ListView.view.width
                                text: name
                                enabled: titleId.length > 0 && backend.available
                                onClicked: root.launchNativeStream("cloud", titleId, name, {
                                    titleId,
                                    name
                                }, null)
                            }
                        }
                        Kirigami.InlineMessage {
                            Layout.fillWidth: true
                            type: Kirigami.MessageType.Information
                            text: "Cloud titles launch in the embedded player using the existing, shared WebRTC session implementation."
                        }
                    }

                    ColumnLayout {
                        spacing: Kirigami.Units.mediumSpacing
                        Controls.Label {
                            Layout.fillWidth: true
                            text: "Streaming settings"
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                        }
                        Kirigami.FormLayout {
                            Layout.fillWidth: true
                            Controls.ComboBox {
                                id: resolutionControl
                                Kirigami.FormData.label: "Resolution"
                                implicitWidth: 240
                                model: ["1280x720", "1920x1080", "2560x1440"]
                                currentIndex: 1
                            }
                            Controls.Slider {
                                id: bitrateControl
                                Kirigami.FormData.label: "Bitrate: " + Math.round(value) + " Mbps"
                                from: 15
                                to: 45
                                stepSize: 1
                                value: 30
                            }
                            Controls.ComboBox {
                                id: codecControl
                                Kirigami.FormData.label: "Codec preference"
                                implicitWidth: 240
                                model: ["auto", "h264", "hevc"]
                                currentIndex: 0
                            }
                            Controls.ComboBox {
                                id: audioControl
                                Kirigami.FormData.label: "Audio"
                                implicitWidth: 240
                                model: ["opus", "default"]
                                currentIndex: 0
                            }
                            Controls.Slider {
                                id: gainControl
                                Kirigami.FormData.label: "Audio gain: " + value.toFixed(1) + "×"
                                from: 1.0
                                to: 1.5
                                stepSize: 0.1
                                value: 1.0
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            Controls.Label {
                                Layout.fillWidth: true
                                text: root.settingsMessage
                                wrapMode: Text.Wrap
                            }
                            Controls.Button {
                                text: "Reload"
                                enabled: backend.available
                                onClicked: root.loadSettings()
                            }
                            Controls.Button {
                                text: root.settingsSaveRequestId ? "Saving…" : "Save"
                                enabled: backend.available && root.settingsSaveRequestId === 0
                                onClicked: {
                                    const next = {
                                        resolution: resolutionControl.currentText,
                                        bitrate: Math.round(bitrateControl.value) * 1000,
                                        codec: codecControl.currentText,
                                        audio: audioControl.currentText,
                                        audioGain: Number(gainControl.value.toFixed(1))
                                    }
                                    root.settingsSaveRequestId = backend.invoke(
                                        "save_settings", { "settings": next })
                                }
                            }
                        }
                    }

                    Kirigami.Card {
                        contentItem: ColumnLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Controls.Label {
                                Layout.fillWidth: true
                                text: root.nativeLaunchMessage
                                horizontalAlignment: Text.AlignHCenter
                                visible: root.nativeLaunchMessage.length > 0
                            }
                            WebEngineView {
                                id: webPlayer
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                webChannel: nativeChannel
                                settings.playbackRequiresUserGesture: false
                                settings.localContentCanAccessRemoteUrls: true
                                url: ""
                                onLoadingChanged: loadRequest => {
                                    if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                                        root.playerPageReady = true
                                        if (root.pendingNativeLaunch)
                                            playerLaunchTimer.restart()
                                    } else if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                                        root.playerPageReady = false
                                        root.nativeLaunchMessage = "The playback page could not be loaded. Check the installation and try again."
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Kirigami.InlineMessage {
                visible: !root.authenticated
                Layout.fillWidth: true
                type: Kirigami.MessageType.Information
                text: "The native KDE shell shares the Rust services and playback lifecycle with the existing client. Keep the Electron rollback until the Fedora RPM and real-session checks pass."
            }

            Controls.Label {
                Layout.fillWidth: true
                text: root.backendHealthMessage
                opacity: 0.8
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }

            Controls.Label {
                Layout.fillWidth: true
                text: "Backend: " + backend.statusMessage
                opacity: 0.65
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}

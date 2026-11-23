import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root
    width: 920
    height: 680
    minimumWidth: 620
    minimumHeight: 520
    visible: true
    title: "XJAUS"

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

    function startLogin() {
        if (!backend.available || loginStarting || polling)
            return
        attemptId = Qt.createUuid().replace("{", "").replace("}", "")
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

    function applyAuthStatus(result) {
        authenticated = result.authenticated === true
        if (authenticated) {
            pollTimer.stop()
            polling = false
            loginStarting = false
            attemptId = ""
            userCode = ""
            verificationUri = ""
            loginMessage = "Signed in for this app session."
        } else if (!polling && !loginStarting) {
            loginMessage = "Sign in to continue. Authentication is held in memory."
        }
    }

    Component.onCompleted: {
        if (backend.available)
            statusRequestId = backend.invoke("auth_status")
    }

    Connections {
        target: backend

        function onAvailableChanged() {
            if (backend.available) {
                loginMessage = "Backend ready. Checking sign-in status…"
                statusRequestId = backend.invoke("auth_status")
            } else {
                loginMessage = backend.statusMessage
            }
        }

        function onStatusMessageChanged() {
            if (!backend.available && !loginStarting && !polling)
                loginMessage = backend.statusMessage
        }

        function onRequestFinished(id, command, result, error) {
            if (command === "auth_status" && id === root.statusRequestId) {
                if (error.length > 0) {
                    root.loginMessage = "Could not read sign-in status."
                    return
                }
                root.applyAuthStatus(result)
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

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                type: Kirigami.MessageType.Information
                text: "This is the first Linux-native UI slice. Cloud catalog, console discovery, and streaming remain on the existing frontend until each screen is migrated and validated."
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

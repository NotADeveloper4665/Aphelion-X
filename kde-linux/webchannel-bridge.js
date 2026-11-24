(() => {
    window.__XJAUS_QT_BRIDGE__ = true;
    const install = () => {
        if (typeof QWebChannel !== "function" || !window.qt || !qt.webChannelTransport) {
            window.setTimeout(install, 10);
            return;
        }
        new QWebChannel(qt.webChannelTransport, channel => {
            const backend = channel.objects.backend;
            const pending = new Map();
            backend.requestFinished.connect((id, command, result, error) => {
                const item = pending.get(String(id));
                if (!item) return;
                pending.delete(String(id));
                if (error) item.reject(new Error(error));
                else item.resolve(result);
            });
            window.xjaus = Object.freeze({
                invoke(command, args = {}) {
                    return new Promise((resolve, reject) => {
                        const id = backend.invoke(command, args || {});
                        pending.set(String(id), { resolve, reject });
                    });
                },
                fullscreen(action) {
                    backend.fullscreen(action);
                    return Promise.resolve();
                },
                openExternal(url) {
                    backend.openExternalUrl(url);
                    return Promise.resolve();
                },
                openMicrosoftVerification(url) {
                    backend.openVerificationUrl(url);
                    return Promise.resolve();
                },
                copyText(text) {
                    backend.copyText(text);
                    return Promise.resolve();
                },
                reportStreamState(active) {
                    backend.reportStreamState(active);
                }
            });
            window.__XJAUS_QT_BRIDGE_READY__ = true;
            window.dispatchEvent(new Event("xjaus:bridge-ready"));
        });
    };
    install();
})();

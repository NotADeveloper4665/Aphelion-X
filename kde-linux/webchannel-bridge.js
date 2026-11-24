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
            const earlyResponses = new Map();
            backend.requestFinished.connect((id, command, result, error) => {
                const key = String(id);
                const item = pending.get(key);
                if (!item) {
                    // The QWebChannel method return and our completion signal
                    // are separate asynchronous messages. Keep a small bounded
                    // cache for the unlikely case the signal arrives first.
                    if (earlyResponses.size >= 64)
                        earlyResponses.delete(earlyResponses.keys().next().value);
                    earlyResponses.set(key, { result, error });
                    return;
                }
                pending.delete(key);
                if (error) item.reject(new Error(error));
                else item.resolve(result);
            });
            window.xjaus = Object.freeze({
                invoke(command, args = {}) {
                    return new Promise((resolve, reject) => {
                        // QWebChannel methods are asynchronous: C++ return
                        // values arrive through the last-argument callback.
                        backend.invoke(command, args || {}, id => {
                            const key = String(id);
                            const early = earlyResponses.get(key);
                            if (early) {
                                earlyResponses.delete(key);
                                if (early.error) reject(new Error(early.error));
                                else resolve(early.result);
                                return;
                            }
                            pending.set(key, { resolve, reject });
                        });
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

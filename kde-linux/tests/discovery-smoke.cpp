#include "sidecarclient.h"

#include <QDebug>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlExpression>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>

int main(int argc, char **argv)
{
    if (argc != 3)
        return 2;

    qputenv("XJAUS_BACKEND", argv[2]);
    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);
    SidecarClient backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.load(QUrl::fromLocalFile(QString::fromLocal8Bit(argv[1])));
    if (engine.rootObjects().isEmpty())
        return 1;

    QObject *window = engine.rootObjects().first();
    window->setProperty("currentSection", QStringLiteral("consoles"));
    bool clicked = false;
    QTimer poll;
    QObject::connect(&poll, &QTimer::timeout, &app, [&] {
        const auto evaluate = [&](const QString &script) {
            QQmlExpression expression(qmlContext(window), window, script);
            return expression.evaluate();
        };
        if (clicked) {
            if (window->property("currentSection").toString() == QStringLiteral("player")
                && evaluate(QStringLiteral("pendingNativeLaunch.target")).toString()
                    == QStringLiteral("streaming-fixture-id")
                && evaluate(QStringLiteral("pendingNativeLaunch.console.id")).toString()
                    == QStringLiteral("presence-fixture-id")
                && evaluate(QStringLiteral("webPlayer.height > 0")).toBool()) {
                app.exit(0);
            }
            return;
        }

        QObject *button = evaluate(QStringLiteral("remotePlayList.itemAtIndex(0)")).value<QObject *>();
        if (button && button->property("enabled").toBool() && button->property("visible").toBool()
            && button->property("height").toDouble() > 0
            && evaluate(QStringLiteral("remotePlayList.height > 0")).toBool()
            && button->property("text").toString() == QStringLiteral("Play Fixture Xbox")
            && window->property("consoleMessage").toString() == QStringLiteral("1 console record(s) returned.")) {
            clicked = QMetaObject::invokeMethod(button, "clicked");
        }
    });
    poll.start(50);
    QTimer::singleShot(15000, &app, [&] {
        qCritical() << window->property("consoleMessage") << window->property("serverMessage");
        app.exit(1);
    });
    backend.start();
    return app.exec();
}

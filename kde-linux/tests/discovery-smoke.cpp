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
    QTimer poll;
    QObject::connect(&poll, &QTimer::timeout, &app, [&] {
        QQmlExpression target(qmlContext(window), window,
                             QStringLiteral("streamingTargetFor('Fixture Xbox')"));
        if (target.evaluate().toString() == QStringLiteral("streaming-fixture-id")
            && window->property("consoleMessage").toString() == QStringLiteral("1 console record(s) returned.")) {
            app.exit(0);
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

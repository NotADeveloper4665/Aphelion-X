#include "sidecarclient.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>

int main(int argc, char *argv[])
{
    QtWebEngineQuick::initialize();
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("XJAUS"));
    QGuiApplication::setOrganizationName(QStringLiteral("XJAUS"));
    QGuiApplication::setApplicationVersion(QStringLiteral(XJAUS_KDE_VERSION));
    QGuiApplication::setDesktopFileName(QStringLiteral("io.github.xjaus.xjaus"));

    SidecarClient backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.loadFromModule(QStringLiteral("XjausKde"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty())
        return 1;

    backend.start();
    return app.exec();
}

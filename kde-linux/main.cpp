#include "sidecarclient.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("XJAUS"));
    QGuiApplication::setOrganizationName(QStringLiteral("XJAUS"));
    QGuiApplication::setApplicationVersion(QStringLiteral("1.2.4-kde-prototype"));

    SidecarClient backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.loadFromModule(QStringLiteral("XjausKde"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty())
        return 1;

    backend.start();
    return app.exec();
}

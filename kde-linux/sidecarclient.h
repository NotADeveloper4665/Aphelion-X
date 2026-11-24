#pragma once

#include <QHash>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QVariant>
#include <QVariantMap>

class SidecarClient final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)

public:
    explicit SidecarClient(QObject *parent = nullptr);
    ~SidecarClient() override;

    bool available() const;
    QString statusMessage() const;

    Q_INVOKABLE void start();
    Q_INVOKABLE qulonglong invoke(const QString &command, const QVariantMap &args = {});
    Q_INVOKABLE void openVerificationUrl(const QString &url);

signals:
    void availableChanged();
    void statusMessageChanged();
    void requestFinished(qulonglong id, const QString &command,
                         const QVariant &result, const QString &error);

private:
    struct Pending {
        QString command;
        QTimer *timer = nullptr;
    };

    QString resolveBackendPath() const;
    void setStatusMessage(const QString &message);
    void readResponses();
    void finish(qulonglong id, const QVariant &result, const QString &error);
    void failAll(const QString &message);

    QProcess process_;
    QByteArray stdoutBuffer_;
    QHash<qulonglong, Pending> pending_;
    qulonglong nextId_ = 0;
    QString statusMessage_ = QStringLiteral("Backend not started");
    bool started_ = false;
};

#include "sidecarclient.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QUrl>


namespace {
constexpr qsizetype kMaxLineBytes = 2 * 1024 * 1024;
constexpr qsizetype kMaxRequestBytes = 1024 * 1024;
constexpr qsizetype kMaxQueuedBytes = 2 * 1024 * 1024;
constexpr qsizetype kMaxPending = 64;

bool commandAllowed(const QString &command)
{
    return command == QStringLiteral("auth_status")
        || command == QStringLiteral("begin_login_window")
        || command == QStringLiteral("poll_login")
        || command == QStringLiteral("cancel_login")
        || command == QStringLiteral("logout");
}
}

SidecarClient::SidecarClient(QObject *parent)
    : QObject(parent)
{
    connect(&process_, &QProcess::readyReadStandardOutput,
            this, &SidecarClient::readResponses);
    connect(&process_, &QProcess::readyReadStandardError,
            this, [this] { process_.readAllStandardError(); });
    connect(&process_, &QProcess::started, this, [this] {
        started_ = true;
        setStatusMessage(QStringLiteral("Backend ready"));
        emit availableChanged();
    });
    connect(&process_, &QProcess::errorOccurred, this,
            [this](QProcess::ProcessError error) {
        if (error == QProcess::WriteError) {
            const bool wasAvailable = started_;
            started_ = false;
            failAll(QStringLiteral("Backend IPC write failed"));
            setStatusMessage(QStringLiteral("Backend IPC failed"));
            process_.kill();
            if (wasAvailable)
                emit availableChanged();
        } else if (error == QProcess::FailedToStart || error == QProcess::Crashed) {
            const bool wasAvailable = started_;
            started_ = false;
            failAll(QStringLiteral("Backend process stopped"));
            setStatusMessage(process_.errorString());
            if (wasAvailable)
                emit availableChanged();
        }
    });
    connect(&process_, qOverload<int, QProcess::ExitStatus>(&QProcess::finished),
            this, [this](int, QProcess::ExitStatus) {
        const bool wasAvailable = started_;
        started_ = false;
        failAll(QStringLiteral("Backend process stopped"));
        setStatusMessage(QStringLiteral("Backend process stopped"));
        if (wasAvailable)
            emit availableChanged();
    });
}

SidecarClient::~SidecarClient()
{
    if (process_.state() == QProcess::Running) {
        process_.closeWriteChannel();
        if (!process_.waitForFinished(1000)) {
            process_.terminate();
            if (!process_.waitForFinished(1000))
                process_.kill();
        }
    }
}

bool SidecarClient::available() const
{
    return started_ && process_.state() == QProcess::Running;
}

QString SidecarClient::statusMessage() const
{
    return statusMessage_;
}

void SidecarClient::setStatusMessage(const QString &message)
{
    if (statusMessage_ == message)
        return;
    statusMessage_ = message;
    emit statusMessageChanged();
}

QString SidecarClient::resolveBackendPath() const
{
    const QString configured = qEnvironmentVariable("XJAUS_BACKEND");
    if (!configured.isEmpty() && QFileInfo(configured).isExecutable())
        return QFileInfo(configured).absoluteFilePath();

    const QDir appDir(QCoreApplication::applicationDirPath());
    const QStringList candidates = {
        appDir.filePath(QStringLiteral("xjaus_backend")),
        appDir.filePath(QStringLiteral("../lib/xjaus/xjaus_backend")),
        appDir.filePath(QStringLiteral("../lib/xjaus_backend"))
    };
    for (const QString &candidate : candidates) {
        const QFileInfo info(candidate);
        if (info.isFile() && info.isExecutable())
            return info.absoluteFilePath();
    }
    return {};
}

void SidecarClient::start()
{
    if (process_.state() != QProcess::NotRunning)
        return;

    const QString executable = resolveBackendPath();
    if (executable.isEmpty()) {
        setStatusMessage(QStringLiteral(
            "Set XJAUS_BACKEND to the existing xjaus_backend executable"));
        return;
    }

    stdoutBuffer_.clear();
    process_.setProgram(executable);
    process_.setArguments({QStringLiteral("--shutdown-report")});
    process_.setProcessChannelMode(QProcess::SeparateChannels);
    process_.start();
    setStatusMessage(QStringLiteral("Starting backend…"));
}

qulonglong SidecarClient::invoke(const QString &command, const QVariantMap &args)
{
    const qulonglong id = ++nextId_;
    auto rejectLater = [this, id, command](const QString &message) {
        QTimer::singleShot(0, this, [this, id, command, message] {
            emit requestFinished(id, command, {}, message);
        });
    };

    if (!commandAllowed(command)) {
        rejectLater(QStringLiteral("Command is not enabled in this prototype"));
        return id;
    }
    if (!available()) {
        rejectLater(QStringLiteral("Backend is not available"));
        return id;
    }
    if (pending_.size() >= kMaxPending) {
        rejectLater(QStringLiteral("Backend request limit reached"));
        return id;
    }
    if (nextId_ >= 9007199254740000ULL) {
        rejectLater(QStringLiteral("Backend request ID limit reached"));
        return id;
    }

    QJsonObject request {
        {QStringLiteral("api_version"), 1},
        {QStringLiteral("id"), static_cast<double>(id)},
        {QStringLiteral("cmd"), command},
        {QStringLiteral("args"), QJsonObject::fromVariantMap(args)}
    };
    const QByteArray line = QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n';
    if (line.size() > kMaxRequestBytes
        || process_.bytesToWrite() + line.size() > kMaxQueuedBytes) {
        rejectLater(QStringLiteral("Backend request is too large or queued"));
        return id;
    }

    auto *timer = new QTimer(this);
    timer->setSingleShot(true);
    const int timeoutMs = command == QStringLiteral("poll_login") ? 75000
        : command == QStringLiteral("begin_login_window") ? 30000 : 10000;
    connect(timer, &QTimer::timeout, this, [this, id] {
        finish(id, {}, QStringLiteral("Backend request timed out; outcome may be unknown"));
    });
    pending_.insert(id, Pending{command, timer});
    timer->start(timeoutMs);

    if (process_.write(line) != line.size()) {
        process_.kill();
        finish(id, {}, QStringLiteral("Backend IPC write failed"));
    }
    return id;
}

void SidecarClient::openVerificationUrl(const QString &value)
{
    const QUrl url(value, QUrl::StrictMode);
    const bool valid = url.isValid()
        && url.scheme() == QStringLiteral("https")
        && (url.host() == QStringLiteral("microsoft.com")
            || url.host() == QStringLiteral("www.microsoft.com"))
        && url.port(-1) == -1
        && (url.path() == QStringLiteral("/devicelogin")
            || url.path() == QStringLiteral("/link"))
        && url.userInfo().isEmpty()
        && url.query().isEmpty()
        && url.fragment().isEmpty();
    if (!valid) {
        setStatusMessage(QStringLiteral("Microsoft verification address was rejected"));
        return;
    }
    QDesktopServices::openUrl(url);
}

void SidecarClient::readResponses()
{
    stdoutBuffer_ += process_.readAllStandardOutput();
    if (stdoutBuffer_.size() > kMaxLineBytes) {
        process_.kill();
        failAll(QStringLiteral("Backend response limit exceeded"));
        setStatusMessage(QStringLiteral("Backend response limit exceeded"));
        return;
    }

    while (true) {
        const qsizetype newline = stdoutBuffer_.indexOf('\n');
        if (newline < 0)
            return;
        const QByteArray line = stdoutBuffer_.left(newline);
        stdoutBuffer_.remove(0, newline + 1);
        if (line.size() > kMaxLineBytes)
            continue;

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(line, &parseError);
        if (parseError.error != QJsonParseError::NoError || !document.isObject())
            continue;

        const QJsonObject response = document.object();
        const QJsonValue version = response.value(QStringLiteral("api_version"));
        if (!version.isUndefined()
            && (!version.isDouble() || version.toInt(-1) != 1)) {
            const QJsonValue unsupportedId = response.value(QStringLiteral("id"));
            if (unsupportedId.isDouble() && unsupportedId.toDouble() >= 1)
                finish(static_cast<qulonglong>(unsupportedId.toDouble()), {},
                       QStringLiteral("Unsupported backend API version"));
            continue;
        }
        const QJsonValue idValue = response.value(QStringLiteral("id"));
        if (!idValue.isDouble() || idValue.toDouble() < 1)
            continue;
        const qulonglong id = static_cast<qulonglong>(idValue.toDouble());
        if (response.value(QStringLiteral("result")).isObject()) {
            finish(id, response.value(QStringLiteral("result")).toObject().toVariantMap(), {});
        } else if (response.value(QStringLiteral("error")).isString()) {
            finish(id, {}, response.value(QStringLiteral("error")).toString());
        } else if (response.value(QStringLiteral("result")).isNull()) {
            finish(id, {}, {});
        }
    }
}

void SidecarClient::finish(qulonglong id, const QVariantMap &result, const QString &error)
{
    auto it = pending_.find(id);
    if (it == pending_.end())
        return;
    const QString command = it->command;
    if (it->timer) {
        it->timer->stop();
        it->timer->deleteLater();
    }
    pending_.erase(it);
    emit requestFinished(id, command, result, error);
}

void SidecarClient::failAll(const QString &message)
{
    const auto ids = pending_.keys();
    for (const qulonglong id : ids)
        finish(id, {}, message);
}

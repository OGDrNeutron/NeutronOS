#pragma once

#include <QJsonObject>
#include <QString>
#include <QtGlobal>

class SecureIpcClient final
{
public:
    struct Identity {
        QString sessionId;
        QString user;
        QString applicationId;
        QString applicationInstance;
    };

    struct Result {
        bool transportOk = false;
        bool serviceOk = false;
        QString errorCode;
        QString errorMessage;
        QJsonObject response;
    };

    static Result request(const QString &socketPath,
                          const QString &service,
                          const QString &operation,
                          const QJsonObject &arguments,
                          const Identity &identity,
                          int timeoutMs = 5000);

private:
    static constexpr quint32 MaximumRequestBytes = 64U * 1024U;
    static constexpr quint32 MaximumResponseBytes = 1024U * 1024U;
};

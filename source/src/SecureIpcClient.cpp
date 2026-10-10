#include "SecureIpcClient.h"

#include <QDateTime>
#include <QDeadlineTimer>
#include <QJsonDocument>
#include <QJsonValue>
#include <QLocalSocket>
#include <QRandomGenerator>
#include <QUuid>
#include <QtEndian>

#include <cstring>

namespace {

QByteArray randomNonce()
{
    QByteArray bytes(32, Qt::Uninitialized);
    QRandomGenerator *generator = QRandomGenerator::system();
    for (qsizetype offset = 0; offset < bytes.size(); offset += 4) {
        const quint32 value = generator->generate();
        const qsizetype remaining = qMin<qsizetype>(4, bytes.size() - offset);
        memcpy(bytes.data() + offset, &value, static_cast<size_t>(remaining));
    }
    return bytes.toHex();
}

bool waitForBytes(QLocalSocket &socket, qint64 count, int timeoutMs)
{
    QDeadlineTimer deadline(timeoutMs);
    while (socket.bytesAvailable() < count) {
        const qint64 remaining = deadline.remainingTime();
        if (remaining <= 0 || !socket.waitForReadyRead(static_cast<int>(remaining)))
            return false;
    }
    return true;
}

} // namespace

SecureIpcClient::Result SecureIpcClient::request(const QString &socketPath,
                                                 const QString &service,
                                                 const QString &operation,
                                                 const QJsonObject &arguments,
                                                 const Identity &identity,
                                                 int timeoutMs)
{
    Result result;
    if (socketPath.isEmpty() || service.isEmpty() || operation.isEmpty() ||
        identity.sessionId.isEmpty() || identity.user.isEmpty() ||
        identity.applicationId.isEmpty() || identity.applicationInstance.isEmpty()) {
        result.errorCode = QStringLiteral("invalid_identity");
        result.errorMessage = QStringLiteral("Secure IPC identity fields are incomplete");
        return result;
    }

    const QString requestId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    QJsonObject requestObject{
        {QStringLiteral("protocol"), QStringLiteral("neutronos.ipc")},
        {QStringLiteral("version"), 1},
        {QStringLiteral("requestId"), requestId},
        {QStringLiteral("service"), service},
        {QStringLiteral("operation"), operation},
        {QStringLiteral("arguments"), arguments},
        {QStringLiteral("nonce"), QString::fromLatin1(randomNonce())},
        {QStringLiteral("timestamp"), QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
        {QStringLiteral("session"), QJsonObject{
            {QStringLiteral("id"), identity.sessionId},
            {QStringLiteral("user"), identity.user},
        }},
        {QStringLiteral("application"), QJsonObject{
            {QStringLiteral("id"), identity.applicationId},
            {QStringLiteral("instance"), identity.applicationInstance},
        }},
    };
    const QByteArray payload = QJsonDocument(requestObject).toJson(QJsonDocument::Compact);
    if (payload.isEmpty() || payload.size() > MaximumRequestBytes) {
        result.errorCode = QStringLiteral("message_too_large");
        result.errorMessage = QStringLiteral("Secure IPC request exceeds the size limit");
        return result;
    }

    QLocalSocket socket;
    socket.connectToServer(socketPath, QIODevice::ReadWrite);
    if (!socket.waitForConnected(timeoutMs)) {
        result.errorCode = QStringLiteral("connect_failed");
        result.errorMessage = socket.errorString();
        return result;
    }
    const quint32 networkSize = qToBigEndian(static_cast<quint32>(payload.size()));
    QByteArray frame(reinterpret_cast<const char *>(&networkSize), sizeof(networkSize));
    frame.append(payload);
    if (socket.write(frame) != frame.size() || !socket.waitForBytesWritten(timeoutMs)) {
        result.errorCode = QStringLiteral("write_failed");
        result.errorMessage = socket.errorString();
        return result;
    }
    if (!waitForBytes(socket, 4, timeoutMs)) {
        result.errorCode = QStringLiteral("timeout");
        result.errorMessage = QStringLiteral("Timed out waiting for the Security service response");
        return result;
    }
    const QByteArray header = socket.read(4);
    quint32 responseSize = 0;
    memcpy(&responseSize, header.constData(), sizeof(responseSize));
    responseSize = qFromBigEndian(responseSize);
    if (responseSize == 0 || responseSize > MaximumResponseBytes) {
        result.errorCode = QStringLiteral("invalid_response_size");
        result.errorMessage = QStringLiteral("Security service returned an invalid response size");
        return result;
    }
    if (!waitForBytes(socket, responseSize, timeoutMs)) {
        result.errorCode = QStringLiteral("timeout");
        result.errorMessage = QStringLiteral("Timed out while reading the Security service response");
        return result;
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(socket.read(responseSize), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        result.errorCode = QStringLiteral("invalid_response");
        result.errorMessage = QStringLiteral("Security service returned malformed JSON");
        return result;
    }
    result.response = document.object();
    if (result.response.value(QStringLiteral("requestId")).toString() != requestId) {
        result.errorCode = QStringLiteral("response_mismatch");
        result.errorMessage = QStringLiteral("Security service response did not match the request");
        return result;
    }
    result.transportOk = true;
    result.serviceOk = result.response.value(QStringLiteral("ok")).toBool(false);
    if (!result.serviceOk) {
        const QJsonObject error = result.response.value(QStringLiteral("error")).toObject();
        result.errorCode = error.value(QStringLiteral("code")).toString(QStringLiteral("service_error"));
        result.errorMessage = error.value(QStringLiteral("message")).toString(QStringLiteral("Security service rejected the request"));
    }
    return result;
}

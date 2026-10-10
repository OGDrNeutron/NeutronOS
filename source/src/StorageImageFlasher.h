#pragma once

#include <QObject>
#include <QProcess>
#include <QJsonObject>
#include <QJsonValue>
#include <QVariantList>
#include <QVariantMap>

class QNetworkAccessManager;
class QNetworkReply;
class QJsonDocument;

class StorageImageFlasher final : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QVariantList raspberryModels READ raspberryModels CONSTANT)
    Q_PROPERTY(QVariantList raspberryImages READ raspberryImages NOTIFY catalogChanged)
    Q_PROPERTY(bool catalogBusy READ catalogBusy NOTIFY catalogChanged)
    Q_PROPERTY(QString catalogMessage READ catalogMessage NOTIFY catalogChanged)

    Q_PROPERTY(bool busy READ busy NOTIFY operationChanged)
    Q_PROPERTY(QString stage READ stage NOTIFY operationChanged)
    Q_PROPERTY(QString status READ status NOTIFY operationChanged)
    Q_PROPERTY(int progress READ progress NOTIFY operationChanged)
    Q_PROPERTY(qulonglong bytesDone READ bytesDone NOTIFY operationChanged)
    Q_PROPERTY(qulonglong bytesTotal READ bytesTotal NOTIFY operationChanged)
    Q_PROPERTY(double bytesPerSecond READ bytesPerSecond NOTIFY operationChanged)
    Q_PROPERTY(qint64 etaSeconds READ etaSeconds NOTIFY operationChanged)
    Q_PROPERTY(QString logPath READ logPath NOTIFY operationChanged)
    Q_PROPERTY(bool canCancel READ canCancel NOTIFY operationChanged)
    Q_PROPERTY(bool succeeded READ succeeded NOTIFY operationChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY operationChanged)

public:
    explicit StorageImageFlasher(const QString &neutronRoot, QObject *parent = nullptr);
    ~StorageImageFlasher() override;

    QVariantList raspberryModels() const;
    QVariantList raspberryImages() const;
    bool catalogBusy() const;
    QString catalogMessage() const;

    bool busy() const;
    QString stage() const;
    QString status() const;
    int progress() const;
    qulonglong bytesDone() const;
    qulonglong bytesTotal() const;
    double bytesPerSecond() const;
    qint64 etaSeconds() const;
    QString logPath() const;
    bool canCancel() const;
    bool succeeded() const;
    QString lastError() const;

    Q_INVOKABLE QString canonicalUserHome() const;
    Q_INVOKABLE QString parentDirectory(const QString &path) const;
    Q_INVOKABLE QVariantList imagePickerEntries(const QString &path,
                                                const QStringList &extensions) const;
    Q_INVOKABLE QVariantMap inspectImage(const QString &path) const;
    Q_INVOKABLE QVariantMap inspectTarget(const QString &devicePath) const;
    Q_INVOKABLE QVariantList eligibleTargets() const;
    Q_INVOKABLE void fetchRaspberryCatalog(const QString &modelId);
    Q_INVOKABLE bool startFlash(const QVariantMap &request);
    Q_INVOKABLE bool cancel();
    Q_INVOKABLE bool ejectTarget(const QString &devicePath);
    Q_INVOKABLE QString humanBytes(qulonglong bytes) const;
    Q_INVOKABLE QString formatDuration(qint64 seconds) const;

signals:
    void catalogChanged();
    void operationChanged();
    void operationFinished(bool success, const QString &message);

private slots:
    void onCatalogFinished();
    void onProcessReadyRead();
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    QString m_neutronRoot;
    QNetworkAccessManager *m_network = nullptr;
    QNetworkReply *m_catalogReply = nullptr;
    QProcess *m_process = nullptr;
    QByteArray m_processBuffer;

    QVariantList m_raspberryImages;
    QVariantMap m_neutronImage;
    QString m_catalogModelId;
    QString m_catalogPhase;
    bool m_catalogBusy = false;
    QString m_catalogMessage;

    bool m_busy = false;
    QString m_stage;
    QString m_status;
    int m_progress = -1;
    qulonglong m_bytesDone = 0;
    qulonglong m_bytesTotal = 0;
    double m_bytesPerSecond = 0.0;
    qint64 m_etaSeconds = -1;
    QString m_logPath;
    bool m_canCancel = false;
    bool m_succeeded = false;
    QString m_lastError;
    QString m_targetDevice;
    QString m_configPath;
    bool m_writeStarted = false;

    static QString executable(const QString &name);
    static QString cleanDevicePath(const QString &path);
    static QString cleanFilePath(const QString &path);
    static QStringList stringList(const QJsonValue &value);
    static QString humanSize(qulonglong bytes);
    static QVariantMap result(bool ok, const QString &message);
    static void collectCatalogEntries(const QJsonValue &value,
                                      const QString &modelId,
                                      QVariantList *output,
                                      const QString &group = QString());
    static bool catalogEntryMatchesModel(const QJsonObject &object,
                                         const QString &modelId);
    static QString entryString(const QJsonObject &object,
                               const QStringList &keys);
    static qulonglong entrySize(const QJsonObject &object,
                                const QStringList &keys);
    static bool isFlashableNeutronAsset(const QString &name);
    static int imageSortPriority(const QVariantMap &image);

    void requestOfficialCatalog();
    QVariantMap parseNeutronRelease(const QJsonDocument &document) const;
    QVariantMap unavailableNeutronImage(const QString &reason) const;
    QString stateDirectory() const;
    QString cacheDirectory() const;
    QString helperPath() const;
    QString newLogPath() const;
    QString newConfigPath() const;
    QVariantMap blockDeviceInfo(const QString &devicePath) const;
    QString systemDiskPath() const;
    bool saveRequestConfig(const QVariantMap &request, QString *error);
    void resetOperation();
    void applyProgressObject(const QJsonObject &object);
    void finish(bool success, const QString &message);
};

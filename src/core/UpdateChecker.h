#ifndef UPDATECHECKER_H
#define UPDATECHECKER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QFile>
#include <QJsonObject>

class UpdateChecker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString latestVersion READ latestVersion NOTIFY infoChanged)
    Q_PROPERTY(QString changelog READ changelog NOTIFY infoChanged)
    Q_PROPERTY(QString changelogHtml READ changelogHtml NOTIFY infoChanged)
    Q_PROPERTY(QString releaseDate READ releaseDate NOTIFY infoChanged)
    Q_PROPERTY(QString downloadUrl READ downloadUrl NOTIFY infoChanged)
    Q_PROPERTY(QString githubDownloadUrl READ githubDownloadUrl NOTIFY infoChanged)
    Q_PROPERTY(bool isNewer READ isNewer NOTIFY infoChanged)
    Q_PROPERTY(bool checking READ checking NOTIFY checkingChanged)
    Q_PROPERTY(bool downloading READ downloading NOTIFY downloadingChanged)
    Q_PROPERTY(qint64 downloadProgress READ downloadProgress NOTIFY downloadProgressChanged)
    Q_PROPERTY(qint64 downloadTotal READ downloadTotal NOTIFY downloadProgressChanged)

public:
    explicit UpdateChecker(const QString &currentVersion, QObject *parent = nullptr);
    ~UpdateChecker() override;

    QString latestVersion() const { return m_latestVersion; }
    QString changelog() const { return m_changelog; }
    QString changelogHtml() const { return m_changelogHtml; }
    QString releaseDate() const { return m_releaseDate; }
    QString downloadUrl() const { return m_downloadUrl; }
    QString githubDownloadUrl() const;
    bool isNewer() const { return m_isNewer; }
    bool checking() const { return m_checking; }
    bool downloading() const { return m_downloading; }
    qint64 downloadProgress() const { return m_downloadProgress; }
    qint64 downloadTotal() const { return m_downloadTotal; }

    Q_INVOKABLE void checkForUpdates();
    Q_INVOKABLE void downloadInstaller(const QString &folderPath, const QString &customUrl = QString());
    Q_INVOKABLE void cancelDownload();
    Q_INVOKABLE void openDownloadFolder();

private:
    void loadCachedInfo();
    void saveCachedInfo();
    void clearInfo();
    QString cacheFilePath() const;

signals:
    void infoChanged();
    void checkingChanged();
    void downloadingChanged();
    void downloadProgressChanged();
    void downloadFinished(bool success, QString filePath, QString folderPath);
    void notifyMessage(QString title, QString message);

private:
    static bool compareVersions(const QString &current, const QString &latest);
    QString extractExeUrl(const QJsonArray &assets) const;

    QString m_currentVersion;
    QString m_latestVersion;
    QString m_changelog;
    QString m_changelogHtml;
    QString m_releaseDate;
    QString m_downloadUrl;        // Gitcode 国内下载（默认）
    QString m_githubDownloadUrl;  // GitHub 国际下载
    bool m_isNewer = false;
    bool m_checking = false;
    bool m_downloading = false;
    qint64 m_downloadProgress = 0;
    qint64 m_downloadTotal = 0;
    QNetworkAccessManager *m_networkManager = nullptr;
    QNetworkReply *m_checkReply = nullptr;
    QNetworkReply *m_downloadReply = nullptr;
    QString m_saveFolderPath;
    QString m_saveFilePath;
    QFile *m_outputFile = nullptr;
};

#endif // UPDATECHECKER_H
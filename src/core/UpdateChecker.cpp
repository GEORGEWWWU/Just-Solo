#include "UpdateChecker.h"
#include "CurlRequest.h"
#include "MarkdownHelper.h"

#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QUrl>
#include <QDir>
#include <QFileInfo>
#include <QDesktopServices>
#include <QUrl>
#include <QStandardPaths>
#include <QRegularExpression>
#include <QDebug>
#include <QNetworkProxy>
#include <QSslConfiguration>
#include <QSslSocket>

// 版本号 URL——返回最新 release 的 JSON 信息
static const char *kApiUrl = "https://getjustsolosetup.zzjjack.us.kg/";

UpdateChecker::UpdateChecker(const QString &currentVersion, QObject *parent)
    : QObject(parent)
    , m_currentVersion(currentVersion)
{
    m_networkManager = new QNetworkAccessManager(this);
    qDebug() << "[UpdateChecker] currentVersion=" << currentVersion
             << "supportsSsl=" << QSslSocket::supportsSsl()
             << "sslLibraryVersion=" << QSslSocket::sslLibraryVersionString()
             << "tlsBackend=" << QSslSocket::activeBackend();
    loadCachedInfo();
}

UpdateChecker::~UpdateChecker()
{
    qDebug() << "[UpdateChecker] Destructor called, any pending requests will be aborted";
}

QString UpdateChecker::cacheFilePath() const
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    return QDir(dir).filePath("update_cache.json");
}

void UpdateChecker::loadCachedInfo()
{
    QFile file(cacheFilePath());
    if (!file.open(QIODevice::ReadOnly)) return;

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject()) return;

    QJsonObject root = doc.object();
    m_latestVersion = root.value("latestVersion").toString();
    m_changelog = root.value("changelog").toString();
    m_changelogHtml = MarkdownHelper::toHtml(m_changelog);
    m_releaseDate = root.value("releaseDate").toString();
    m_downloadUrl = root.value("downloadUrl").toString();
    m_githubDownloadUrl = root.value("githubDownloadUrl").toString();
    m_isNewer = compareVersions(m_currentVersion, m_latestVersion);

    if (!m_latestVersion.isEmpty())
        emit infoChanged();
}

void UpdateChecker::saveCachedInfo()
{
    QJsonObject root;
    root["latestVersion"] = m_latestVersion;
    root["changelog"] = m_changelog;
    root["releaseDate"] = m_releaseDate;
    root["downloadUrl"] = m_downloadUrl;
    root["githubDownloadUrl"] = m_githubDownloadUrl;

    QFile file(cacheFilePath());
    if (file.open(QIODevice::WriteOnly))
        file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

void UpdateChecker::clearInfo()
{
    m_latestVersion.clear();
    m_changelog.clear();
    m_changelogHtml.clear();
    m_releaseDate.clear();
    m_downloadUrl.clear();
    m_githubDownloadUrl.clear();
    m_isNewer = false;
    emit infoChanged();

    QFile::remove(cacheFilePath());
}

void UpdateChecker::checkForUpdates()
{
    if (m_checking) return;
    m_checking = true;
    emit checkingChanged();

    qDebug() << "[UpdateChecker] Starting update check via libcurl to" << kApiUrl;

    auto *req = new CurlRequest(this);
    connect(req, &CurlRequest::finished, this, [this, req](bool success,
            const QByteArray &data, const QString &errorString, int httpStatus) {
        m_checking = false;
        emit checkingChanged();

        qDebug() << "[UpdateChecker] curl finished. success=" << success
                 << "httpStatus=" << httpStatus
                 << "error=" << errorString
                 << "responseSize=" << data.size();

        if (!success) {
            emit notifyMessage("检查更新失败",
                               QStringLiteral("无法获取更新信息：%1 (HTTP=%2)")
                                   .arg(errorString)
                                   .arg(httpStatus));
            req->deleteLater();
            return;
        }

        QJsonParseError parseError;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            emit notifyMessage("检查更新失败",
                               QStringLiteral("数据解析错误：%1").arg(parseError.errorString()));
            req->deleteLater();
            return;
        }

        QJsonObject root = doc.object();
        m_latestVersion = root.value("version").toString();
        m_changelog = root.value("changelog").toString().trimmed();
        m_changelogHtml = MarkdownHelper::toHtml(m_changelog);
        m_releaseDate = root.value("updated_at").toString();

        // 提取下载地址（新版 API 直接返回完整 URL）
        m_downloadUrl = root.value("gitcode_exe").toString();       // Gitcode 国内（默认）
        m_githubDownloadUrl = root.value("github_exe").toString(); // GitHub 国际

        // 版本比较
        m_isNewer = compareVersions(m_currentVersion, m_latestVersion);

        saveCachedInfo();
        emit infoChanged();
        req->deleteLater();
    });

    req->get(QString::fromLatin1(kApiUrl),
             QStringLiteral("JustSolo-UpdateChecker/1.0"));
}

void UpdateChecker::downloadInstaller(const QString &folderPath, const QString &customUrl)
{
    QString urlStr = customUrl.isEmpty() ? m_downloadUrl : customUrl;
    if (m_downloading || urlStr.isEmpty()) return;

    // 从下载 URL 提取文件名
    QString fileName = QUrl(urlStr).fileName();
    if (fileName.isEmpty()) {
        fileName = QStringLiteral("Just_Solo_%1.exe").arg(m_latestVersion);
    }
    // URL 解码处理中文/空格等
    fileName = QUrl::fromPercentEncoding(fileName.toUtf8());

    m_saveFolderPath = folderPath;
    m_saveFilePath = QDir(folderPath).filePath(fileName);

    // 如果文件已存在则加后缀
    if (QFileInfo::exists(m_saveFilePath)) {
        int dot = fileName.lastIndexOf('.');
        QString base = (dot > 0) ? fileName.left(dot) : fileName;
        QString ext  = (dot > 0) ? fileName.mid(dot) : QString();
        for (int i = 1; i < 100; ++i) {
            QString alt = QStringLiteral("%1 (%2)%3").arg(base).arg(i).arg(ext);
            QString altPath = QDir(folderPath).filePath(alt);
            if (!QFileInfo::exists(altPath)) {
                m_saveFilePath = altPath;
                break;
            }
        }
    }

    m_outputFile = new QFile(m_saveFilePath, this);
    if (!m_outputFile->open(QIODevice::WriteOnly)) {
        emit notifyMessage("下载失败",
                           QStringLiteral("无法写入文件：%1").arg(m_saveFilePath));
        delete m_outputFile;
        m_outputFile = nullptr;
        return;
    }

    m_downloading = true;
    m_downloadProgress = 0;
    m_downloadTotal = 0;
    emit downloadingChanged();
    emit downloadProgressChanged();

    QUrl dlUrl(urlStr);
    QNetworkRequest request(dlUrl);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("JustSolo-Updater/1.0"));
    request.setTransferTimeout(0); // 大文件不限时

    m_downloadReply = m_networkManager->get(request);

    connect(m_downloadReply, &QNetworkReply::readyRead, this, [this]() {
        if (m_outputFile) {
            m_outputFile->write(m_downloadReply->readAll());
        }
    });

    connect(m_downloadReply, &QNetworkReply::downloadProgress, this, [this](qint64 received, qint64 total) {
        m_downloadProgress = received;
        m_downloadTotal = total;
        emit downloadProgressChanged();
    });

    connect(m_downloadReply, &QNetworkReply::finished, this, [this]() {
        bool success = false;
        QString filePath = m_saveFilePath;
        QString folderPath = m_saveFolderPath;

        if (m_outputFile) {
            // 写入剩余数据
            if (m_downloadReply) {
                m_outputFile->write(m_downloadReply->readAll());
            }
            m_outputFile->close();
            delete m_outputFile;
            m_outputFile = nullptr;
        }

        if (m_downloadReply && m_downloadReply->error() == QNetworkReply::NoError) {
            success = true;
        } else if (m_downloadReply) {
            // 下载出错，删除残文件
            QFile::remove(m_saveFilePath);
            emit notifyMessage("下载失败",
                               QStringLiteral("下载安装程序时出错：%1")
                                   .arg(m_downloadReply->errorString()));
        }

        m_downloadReply->deleteLater();
        m_downloadReply = nullptr;
        m_downloading = false;
        m_downloadProgress = 0;
        m_downloadTotal = 0;
        emit downloadingChanged();
        emit downloadProgressChanged();
        emit downloadFinished(success, filePath, folderPath);
    });
}

QString UpdateChecker::githubDownloadUrl() const
{
    return m_githubDownloadUrl;
}

void UpdateChecker::cancelDownload()
{
    if (!m_downloading) return;

    if (m_downloadReply) {
        m_downloadReply->disconnect(this);  // 先断开信号，防止 abort() 同步触发 lambda 重复清理
        m_downloadReply->abort();
        m_downloadReply->deleteLater();
        m_downloadReply = nullptr;
    }
    if (m_outputFile) {
        m_outputFile->close();
        QFile::remove(m_saveFilePath);
        delete m_outputFile;
        m_outputFile = nullptr;
    }
    m_downloading = false;
    m_downloadProgress = 0;
    m_downloadTotal = 0;
    emit downloadingChanged();
    emit downloadProgressChanged();
}

void UpdateChecker::openDownloadFolder()
{
    if (!m_saveFolderPath.isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_saveFolderPath));
    }
}

bool UpdateChecker::compareVersions(const QString &current, const QString &latest)
{
    // 去掉前导 'v' 或 'V'
    QString cur = current;
    QString lat = latest;
    if (cur.startsWith('v', Qt::CaseInsensitive)) cur = cur.mid(1);
    if (lat.startsWith('v', Qt::CaseInsensitive)) lat = lat.mid(1);

    QStringList curParts = cur.split('.');
    QStringList latParts = lat.split('.');

    int maxLen = qMax(curParts.size(), latParts.size());
    for (int i = 0; i < maxLen; ++i) {
        int curNum = (i < curParts.size()) ? curParts[i].toInt() : 0;
        int latNum = (i < latParts.size()) ? latParts[i].toInt() : 0;
        if (latNum > curNum) return true;
        if (latNum < curNum) return false;
    }
    return false; // 版本相同
}

QString UpdateChecker::extractExeUrl(const QJsonArray &assets) const
{
    // 优先找 type 为 "attach" 且以 .exe 结尾的资源
    QString fallback;
    for (const QJsonValue &val : assets) {
        QJsonObject obj = val.toObject();
        QString name = obj.value("name").toString();
        QString type = obj.value("type").toString();
        QString url  = obj.value("browser_download_url").toString();

        if (type == "attach" && name.endsWith(".exe", Qt::CaseInsensitive)) {
            return url;
        }
        // 备用：任何 .exe 文件
        if (name.endsWith(".exe", Qt::CaseInsensitive) && !url.isEmpty()) {
            fallback = url;
        }
    }
    return fallback;
}
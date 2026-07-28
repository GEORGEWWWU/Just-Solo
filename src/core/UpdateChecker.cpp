#include "UpdateChecker.h"

#include <QJsonDocument>

#include <QJsonObject>
#include <QUrl>
#include <QDir>
#include <QFileInfo>
#include <QDesktopServices>
#include <QUrl>
#include <QStandardPaths>
#include <QRegularExpression>

// 版本号 URL——返回最新 release 的 JSON 信息
static const char *kApiUrl = "https://getjustsolosetup.zzjjack.us.kg/";

UpdateChecker::UpdateChecker(const QString &currentVersion, QObject *parent)
    : QObject(parent)
    , m_currentVersion(currentVersion)
{
    m_networkManager = new QNetworkAccessManager(this);
    loadCachedInfo();
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
    m_releaseDate = root.value("releaseDate").toString();
    m_downloadUrl = root.value("downloadUrl").toString();
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

    QFile file(cacheFilePath());
    if (file.open(QIODevice::WriteOnly))
        file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
}

void UpdateChecker::clearInfo()
{
    m_latestVersion.clear();
    m_changelog.clear();
    m_releaseDate.clear();
    m_downloadUrl.clear();
    m_isNewer = false;
    emit infoChanged();

    QFile::remove(cacheFilePath());
}

void UpdateChecker::checkForUpdates()
{
    if (m_checking) return;
    m_checking = true;
    emit checkingChanged();

    QUrl apiUrl(kApiUrl);
    QNetworkRequest request(apiUrl);
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("JustSolo-UpdateChecker/1.0"));
    request.setTransferTimeout(10000);

    m_checkReply = m_networkManager->get(request);
    connect(m_checkReply, &QNetworkReply::finished, this, [this]() {
        QNetworkReply *reply = m_checkReply;
        m_checkReply = nullptr;
        m_checking = false;
        emit checkingChanged();

        if (reply->error() != QNetworkReply::NoError) {
            emit notifyMessage("检查更新失败",
                               QStringLiteral("无法获取更新信息：%1").arg(reply->errorString()));
            reply->deleteLater();
            return;
        }

        QByteArray data = reply->readAll();
        reply->deleteLater();
        QJsonParseError parseError;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
        if (parseError.error != QJsonParseError::NoError) {
            emit notifyMessage("检查更新失败",
                               QStringLiteral("数据解析错误：%1").arg(parseError.errorString()));
            return;
        }

        QJsonObject root = doc.object();
        m_latestVersion = root.value("version").toString();
        m_changelog = root.value("changelog").toString().trimmed();
        m_releaseDate = root.value("updated_at").toString();
        m_downloadUrl = root.value("github_exe").toString();

        // 版本比较
        m_isNewer = compareVersions(m_currentVersion, m_latestVersion);

        saveCachedInfo();
        emit infoChanged();
    });
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
    if (m_latestVersion.isEmpty())
        return QString();

    // 用正则从 tag_name（如 "v0.7.6"）提取纯版本号
    QRegularExpression re(QStringLiteral(R"(^v?(\d+\.\d+\.\d+))"));
    QRegularExpressionMatch match = re.match(m_latestVersion);
    if (!match.hasMatch())
        return QString();

    QString version = match.captured(1);
    QString filename = QStringLiteral("Just.Solo.V%1.exe").arg(version);
    return QStringLiteral("https://github.com/ZZJ-jack/Just-Solo/releases/download/%1/%2")
        .arg(m_latestVersion, filename);
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


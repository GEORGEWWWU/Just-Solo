#ifndef AUDIOENGINE_H
#define AUDIOENGINE_H

#include <QObject>
#include <QString>
#include <QTimer>

struct ma_engine;
struct ma_sound;

class AudioEngine : public QObject
{
    Q_OBJECT
public:
    explicit AudioEngine(QObject *parent = nullptr);
    ~AudioEngine() override;

    bool load(const QString &filePath);
    void play();
    void pause();
    void stop();
    void seek(qint64 ms);

    qint64 position() const;
    qint64 duration() const;
    void setVolume(float vol);
    float volume() const;
    bool isPlaying() const;

signals:
    void positionChanged(qint64 ms);
    void playbackStateChanged();
    void endOfMedia();
    void durationChanged();

private:
    void pollAudio();
    void retryLoad();

    ma_engine *m_engine = nullptr;
    ma_sound *m_sound = nullptr;
    bool m_soundInitialized = false;

    QString m_currentFilePath;
    qint64 m_cachedDuration = 0;   // milliseconds
    bool m_wasPlaying = false;
    float m_volume = 0.9f;

    // Hotplug retry: 设备拔出时冻结状态并定时重试
    bool m_hotplugMode = false;
    QString m_hotplugFilePath;
    qint64 m_hotplugPosition = 0;
    bool m_hotplugWasPlaying = false;
    qint64 m_hotplugDuration = 0;
    QTimer *m_retryTimer = nullptr;
};

#endif

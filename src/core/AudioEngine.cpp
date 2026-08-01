#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "AudioEngine.h"
#include <QDebug>
#include <QFileInfo>
#include <QTimer>
#include <cstring>
#include <string>

AudioEngine::AudioEngine(QObject *parent)
    : QObject(parent)
{
    initAudioDevice();

    m_sound = new ma_sound;
    std::memset(m_sound, 0, sizeof(*m_sound));
    m_soundInitialized = false;

    // 轮询定时器：50ms 间隔，用于 positionChanged 和 endOfMedia 检测
    QTimer *pollTimer = new QTimer(this);
    pollTimer->setInterval(50);
    connect(pollTimer, &QTimer::timeout, this, &AudioEngine::pollAudio);
    pollTimer->start(50);

    // 热插拔重试定时器：每秒检查设备是否恢复
    m_retryTimer = new QTimer(this);
    m_retryTimer->setInterval(1000);
    connect(m_retryTimer, &QTimer::timeout, this, &AudioEngine::retryLoad);
}

AudioEngine::~AudioEngine()
{
    m_retryTimer->stop();
    shutdownAudioDevice();
    delete m_sound;
}

// ---- 设备驱动回调：等价于 miniaudio 内部 ma_engine_data_callback ----
void AudioEngine::deviceDataCallback(ma_device *pDevice, void *pFramesOut,
                                     const void *pFramesIn, unsigned int frameCount)
{
    ma_engine *pEngine = static_cast<ma_engine *>(pDevice->pUserData);
    (void)pFramesIn;
    ma_engine_read_pcm_frames(pEngine, pFramesOut, frameCount, nullptr);
}

bool AudioEngine::initAudioDevice()
{
    if (m_engine) return true;

    m_engine = new ma_engine;
    m_context = new ma_context;
    m_device = new ma_device;

    ma_context_config contextConfig = ma_context_config_init();
    if (ma_context_init(nullptr, 0, &contextConfig, m_context) != MA_SUCCESS) {
        qWarning("AudioEngine: Failed to initialize miniaudio context");
        goto on_fail;
    }

    // 设备：与引擎内部创建方式一致（f32、原生声道/采样率），仅额外指定 WASAPI 共享/独占模式
    {
        ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
        deviceConfig.playback.format = ma_format_f32;
        deviceConfig.playback.channels = 0;                    // 使用设备原生声道
        deviceConfig.sampleRate = 0;                           // 使用设备原生采样率
        deviceConfig.playback.shareMode = m_exclusive ? ma_share_mode_exclusive
                                                      : ma_share_mode_shared;
        deviceConfig.dataCallback = AudioEngine::deviceDataCallback;
        deviceConfig.pUserData = m_engine;
        deviceConfig.noPreSilencedOutputBuffer = MA_TRUE;      // 引擎总是写满输出帧
        deviceConfig.noClip = MA_TRUE;                         // 削波由引擎自己处理

        if (ma_device_init(m_context, &deviceConfig, m_device) != MA_SUCCESS) {
            qWarning("AudioEngine: Failed to initialize device (exclusive=%d)", m_exclusive);
            ma_context_uninit(m_context);
            goto on_fail;
        }
    }

    {
        ma_engine_config config = ma_engine_config_init();
        config.pContext = m_context;
        config.pDevice = m_device;
        if (ma_engine_init(&config, m_engine) != MA_SUCCESS) {
            qWarning("AudioEngine: Failed to initialize miniaudio engine");
            ma_device_uninit(m_device);
            ma_context_uninit(m_context);
            goto on_fail;
        }
    }

    if (m_exclusive)
        qDebug("AudioEngine: WASAPI exclusive mode enabled");
    return true;

on_fail:
    delete m_device;
    delete m_context;
    delete m_engine;
    m_device = nullptr;
    m_context = nullptr;
    m_engine = nullptr;
    return false;
}

void AudioEngine::shutdownAudioDevice()
{
    if (m_soundInitialized && m_sound) {
        ma_sound_stop(m_sound);
        ma_sound_uninit(m_sound);
        std::memset(m_sound, 0, sizeof(*m_sound));
        m_soundInitialized = false;
    }
    m_wasPlaying = false;

    if (m_engine) {
        ma_engine_uninit(m_engine);
        delete m_engine;
        m_engine = nullptr;
    }
    if (m_device) {
        ma_device_uninit(m_device);
        delete m_device;
        m_device = nullptr;
    }
    if (m_context) {
        ma_context_uninit(m_context);
        delete m_context;
        m_context = nullptr;
    }
}

bool AudioEngine::setExclusiveMode(bool exclusive)
{
    if (exclusive == m_exclusive) return true;

    // 保存当前播放现场（含热插拔状态）
    const bool wasPlaying = isPlaying();
    const qint64 pos = position();
    const QString path = !m_currentFilePath.isEmpty() ? m_currentFilePath : m_hotplugFilePath;
    const qint64 dur = m_cachedDuration;

    m_retryTimer->stop();
    m_hotplugMode = false;

    // 重建音频引擎（切换共享/独占）
    shutdownAudioDevice();
    m_exclusive = exclusive;
    if (!initAudioDevice()) {
        // 独占不可用（如设备被其他程序独占），回退共享模式
        qWarning("AudioEngine: exclusive mode unavailable, falling back to shared mode");
        m_exclusive = false;
        initAudioDevice();
    }
    if (!m_engine) return false;

    setVolume(m_volume);
    emit playbackStateChanged();

    // 恢复播放现场
    if (path.isEmpty()) return true;
    if (!load(path)) {
        // 文件暂不可用（如设备切换期间被拔出）：保留现场进入热插拔重试
        m_hotplugMode = true;
        m_hotplugFilePath = path;
        m_hotplugPosition = pos;
        m_hotplugWasPlaying = wasPlaying;
        m_hotplugDuration = dur;
        m_retryTimer->start();
        return true;
    }
    if (pos > 0) seek(pos);
    if (wasPlaying) play();
    return true;
}

bool AudioEngine::load(const QString &filePath)
{
    if (!m_engine || !m_sound) return false;

    // 保存旧状态（用于加载失败后的热插拔恢复）
    bool wasPlaying = m_soundInitialized && m_wasPlaying;
    qint64 oldPos = m_soundInitialized ? position() : 0;
    qint64 oldDuration = m_cachedDuration;

    // 停止重试
    m_retryTimer->stop();
    m_hotplugMode = false;

    // 停止并卸载旧声音
    if (m_soundInitialized) {
        ma_sound_stop(m_sound);
        ma_sound_uninit(m_sound);
        std::memset(m_sound, 0, sizeof(*m_sound));
        m_soundInitialized = false;
    }
    m_wasPlaying = false;

#ifdef Q_OS_WIN
    std::wstring path = filePath.toStdWString();
    ma_result result = ma_sound_init_from_file_w(
        m_engine, path.c_str(),
        MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_PITCH | MA_SOUND_FLAG_NO_SPATIALIZATION,
        nullptr, nullptr, m_sound
    );
#else
    QByteArray path = filePath.toUtf8();
    ma_result result = ma_sound_init_from_file(
        m_engine, path.constData(),
        MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_PITCH | MA_SOUND_FLAG_NO_SPATIALIZATION,
        nullptr, nullptr, m_sound
    );
#endif

    if (result != MA_SUCCESS) {
        qWarning() << "AudioEngine: Failed to load file:" << filePath << "error:" << result;

        // 进入热插拔重试模式：冻结旧状态，定时尝试重新加载
        if (!m_currentFilePath.isEmpty()) {
            m_hotplugMode = true;
            m_hotplugFilePath = filePath;
            m_hotplugPosition = oldPos;
            m_hotplugWasPlaying = wasPlaying;
            m_hotplugDuration = oldDuration;
            m_retryTimer->start();
            qDebug("AudioEngine: Entered hotplug retry mode for: %s", qPrintable(filePath));
        }
        return false;
    }

    m_soundInitialized = true;
    m_currentFilePath = filePath;

    // 缓存时长（毫秒）
    ma_uint64 frames;
    if (ma_sound_get_length_in_pcm_frames(m_sound, &frames) == MA_SUCCESS) {
        ma_format format;
        ma_uint32 channels, sampleRate;
        if (ma_sound_get_data_format(m_sound, &format, &channels, &sampleRate, nullptr, 0) == MA_SUCCESS && sampleRate > 0) {
            m_cachedDuration = static_cast<qint64>(frames) * 1000 / sampleRate;
        } else {
            // 兜底：用引擎采样率估算
            ma_uint32 engineSampleRate = ma_engine_get_sample_rate(m_engine);
            m_cachedDuration = (engineSampleRate > 0) ? static_cast<qint64>(frames) * 1000 / engineSampleRate : 0;
        }
    } else {
        m_cachedDuration = 0;
    }

    emit durationChanged();
    return true;
}

void AudioEngine::play()
{
    if (m_hotplugMode) {
        m_hotplugWasPlaying = true;
        emit playbackStateChanged();
        return;
    }
    if (!m_soundInitialized) return;
    ma_sound_start(m_sound);
    m_wasPlaying = true;
    emit playbackStateChanged();
}

void AudioEngine::pause()
{
    if (m_hotplugMode) {
        m_hotplugWasPlaying = false;
        emit playbackStateChanged();
        return;
    }
    if (!m_soundInitialized) return;
    ma_sound_stop(m_sound);
    m_wasPlaying = false;
    emit playbackStateChanged();
}

void AudioEngine::stop()
{
    if (m_hotplugMode) {
        m_hotplugMode = false;
        m_retryTimer->stop();
        m_wasPlaying = false;
        emit playbackStateChanged();
        emit positionChanged(0);
        return;
    }
    if (!m_soundInitialized) return;
    ma_sound_stop(m_sound);
    ma_sound_seek_to_pcm_frame(m_sound, 0);
    m_wasPlaying = false;
    emit playbackStateChanged();
    emit positionChanged(0);
}

void AudioEngine::seek(qint64 ms)
{
    if (m_hotplugMode) {
        m_hotplugPosition = qBound(0LL, ms, m_hotplugDuration > 0 ? m_hotplugDuration : ms);
        emit positionChanged(m_hotplugPosition);
        return;
    }
    if (!m_soundInitialized || m_cachedDuration <= 0) return;

    ma_uint64 frames;
    if (ma_sound_get_length_in_pcm_frames(m_sound, &frames) != MA_SUCCESS || frames == 0)
        return;

    ma_uint64 targetFrame = static_cast<ma_uint64>(
        static_cast<double>(qBound(0LL, ms, m_cachedDuration)) / m_cachedDuration * frames
    );
    ma_sound_seek_to_pcm_frame(m_sound, targetFrame);
    // seek 在混音线程延迟生效，但游标接口能立即感知 seekTarget，
    // 这里主动上报一次新位置，让进度条/歌词即刻跳转，无需等 50ms 轮询
    emit positionChanged(position());
}

qint64 AudioEngine::position() const
{
    if (m_hotplugMode) return m_hotplugPosition;
    if (!m_soundInitialized) return 0;

    // 用数据源游标而非节点时间轴：ma_sound_get_time_in_milliseconds() 基于节点
    // localTime（按引擎采样率累计），而 seek 时 localTime 被写入的是“文件采样率”的
    // 帧号（ma_node_set_time(pSound, seekTarget)），却仍除以引擎采样率——文件与
    // 引擎采样率不一致时（如 44.1k 文件 + 48k 设备），seek 后位置整体偏移，歌词错位。
    // 游标则始终以数据源（文件）帧号表示，且能感知未完成的 seek（直接返回 seekTarget）。
    ma_uint64 cursor = 0;
    if (ma_sound_get_cursor_in_pcm_frames(m_sound, &cursor) == MA_SUCCESS) {
        ma_uint32 sampleRate = 0;
        if (ma_sound_get_data_format(m_sound, nullptr, nullptr, &sampleRate, nullptr, 0) == MA_SUCCESS
            && sampleRate > 0) {
            return static_cast<qint64>(cursor) * 1000 / sampleRate;
        }
    }
    // 兜底：无数据源等异常情况下退回旧实现
    return static_cast<qint64>(ma_sound_get_time_in_milliseconds(m_sound));
}

qint64 AudioEngine::duration() const
{
    if (m_hotplugMode) return m_hotplugDuration;
    return m_cachedDuration;
}

void AudioEngine::setVolume(float vol)
{
    m_volume = vol;
    if (m_soundInitialized) {
        ma_sound_set_volume(m_sound, vol);
    }
}

float AudioEngine::volume() const
{
    return m_volume;
}

bool AudioEngine::isPlaying() const
{
    if (m_hotplugMode) return m_hotplugWasPlaying;
    return m_soundInitialized && (ma_sound_is_playing(m_sound) != MA_FALSE);
}

void AudioEngine::pollAudio()
{
    // 热插拔模式：持续发送冻结的位置，保持 UI 不跳变
    if (m_hotplugMode) {
        emit positionChanged(m_hotplugPosition);
        return;
    }

    if (!m_soundInitialized) return;

    qint64 pos = position();
    emit positionChanged(pos);

    bool currentlyPlaying = (ma_sound_is_playing(m_sound) != MA_FALSE);
    if (m_wasPlaying && !currentlyPlaying) {
        // 检测是否因设备拔出而停止播放（文件已不可访问）
        if (!QFileInfo::exists(m_currentFilePath)) {
            qDebug("AudioEngine: Device disconnected, entering hotplug retry mode");
            m_hotplugMode = true;
            m_hotplugFilePath = m_currentFilePath;
            m_hotplugPosition = pos;
            m_hotplugWasPlaying = true;
            m_hotplugDuration = m_cachedDuration;
            m_wasPlaying = false;
            emit playbackStateChanged();
            m_retryTimer->start();
            return;  // 不触发 endOfMedia
        }
        // 正常播完
        m_wasPlaying = false;
        emit playbackStateChanged();
        emit endOfMedia();
    }
    m_wasPlaying = currentlyPlaying;
}

void AudioEngine::retryLoad()
{
    if (!m_hotplugMode) {
        m_retryTimer->stop();
        return;
    }

    // 先检查文件是否存在（快速路径，避免每次调用 miniaudio）
    if (!QFileInfo::exists(m_hotplugFilePath)) {
        return;  // 设备仍未恢复
    }

    // 卸载旧声音（进入热插拔模式时可能未清理）
    if (m_soundInitialized) {
        ma_sound_stop(m_sound);
        ma_sound_uninit(m_sound);
        std::memset(m_sound, 0, sizeof(*m_sound));
        m_soundInitialized = false;
    }

    // 尝试重新加载
#ifdef Q_OS_WIN
    std::wstring path = m_hotplugFilePath.toStdWString();
    ma_result result = ma_sound_init_from_file_w(
        m_engine, path.c_str(),
        MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_PITCH | MA_SOUND_FLAG_NO_SPATIALIZATION,
        nullptr, nullptr, m_sound
    );
#else
    QByteArray path = m_hotplugFilePath.toUtf8();
    ma_result result = ma_sound_init_from_file(
        m_engine, path.constData(),
        MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_PITCH | MA_SOUND_FLAG_NO_SPATIALIZATION,
        nullptr, nullptr, m_sound
    );
#endif

    if (result != MA_SUCCESS) {
        return;  // 设备恢复但文件还不能读，继续重试
    }

    // 恢复成功
    m_soundInitialized = true;
    m_currentFilePath = m_hotplugFilePath;
    m_cachedDuration = m_hotplugDuration;
    ma_sound_set_volume(m_sound, m_volume);

    // 跳转到保存的位置
    if (m_hotplugPosition > 0) {
        seek(m_hotplugPosition);
    }

    bool wasPlaying = m_hotplugWasPlaying;
    // 退出热插拔模式
    m_hotplugMode = false;
    m_retryTimer->stop();

    qDebug("AudioEngine: Device reconnected, resuming playback at %lld ms", m_hotplugPosition);
    emit durationChanged();
    emit positionChanged(m_hotplugPosition);

    if (wasPlaying) {
        ma_sound_start(m_sound);
        m_wasPlaying = true;
        emit playbackStateChanged();
    }
}

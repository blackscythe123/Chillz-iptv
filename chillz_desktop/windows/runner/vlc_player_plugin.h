// VLC Player Plugin - Direct libVLC integration for Flutter
// This plugin provides VLC playback via platform channels
// NO media_kit, NO FFmpeg wrapper - pure libVLC

#ifndef VLC_PLAYER_PLUGIN_H_
#define VLC_PLAYER_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/event_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter_windows.h>

#include <windows.h>
#include <memory>
#include <mutex>
#include <atomic>
#include <vector>
#include <string>
#include <functional>
#include <thread>
#include <queue>
#include <condition_variable>

// Forward declarations for libVLC types
typedef struct libvlc_instance_t libvlc_instance_t;
typedef struct libvlc_media_player_t libvlc_media_player_t;
typedef struct libvlc_media_t libvlc_media_t;
typedef struct libvlc_event_manager_t libvlc_event_manager_t;
typedef struct libvlc_track_description_t libvlc_track_description_t;

// libVLC function pointer typedefs
typedef libvlc_instance_t* (*pfn_libvlc_new)(int, const char* const*);
typedef void (*pfn_libvlc_release)(libvlc_instance_t*);
typedef const char* (*pfn_libvlc_errmsg)(void);
typedef libvlc_media_player_t* (*pfn_libvlc_media_player_new)(libvlc_instance_t*);
typedef void (*pfn_libvlc_media_player_release)(libvlc_media_player_t*);
typedef void (*pfn_libvlc_media_player_set_media)(libvlc_media_player_t*, libvlc_media_t*);
typedef int (*pfn_libvlc_media_player_play)(libvlc_media_player_t*);
typedef void (*pfn_libvlc_media_player_stop)(libvlc_media_player_t*);
typedef void (*pfn_libvlc_media_player_pause)(libvlc_media_player_t*);
typedef int (*pfn_libvlc_media_player_is_playing)(libvlc_media_player_t*);
typedef int (*pfn_libvlc_audio_set_volume)(libvlc_media_player_t*, int);
typedef int (*pfn_libvlc_audio_get_volume)(libvlc_media_player_t*);
typedef int (*pfn_libvlc_audio_set_mute)(libvlc_media_player_t*, int);
typedef int (*pfn_libvlc_audio_get_mute)(libvlc_media_player_t*);
typedef libvlc_track_description_t* (*pfn_libvlc_audio_get_track_description)(libvlc_media_player_t*);
typedef int (*pfn_libvlc_audio_set_track)(libvlc_media_player_t*, int);
typedef int (*pfn_libvlc_audio_get_track)(libvlc_media_player_t*);
typedef int (*pfn_libvlc_audio_get_track_count)(libvlc_media_player_t*);
typedef void (*pfn_libvlc_track_description_list_release)(libvlc_track_description_t*);
typedef libvlc_media_t* (*pfn_libvlc_media_new_location)(libvlc_instance_t*, const char*);
typedef void (*pfn_libvlc_media_release)(libvlc_media_t*);
typedef void (*pfn_libvlc_media_add_option)(libvlc_media_t*, const char*);
typedef libvlc_event_manager_t* (*pfn_libvlc_media_player_event_manager)(libvlc_media_player_t*);
typedef int (*pfn_libvlc_event_attach)(libvlc_event_manager_t*, int, void(*)(const void*, void*), void*);
typedef void (*pfn_libvlc_event_detach)(libvlc_event_manager_t*, int, void(*)(const void*, void*), void*);
typedef void (*pfn_libvlc_video_set_callbacks)(libvlc_media_player_t*, void*, void*, void*, void*);
typedef void (*pfn_libvlc_video_set_format)(libvlc_media_player_t*, const char*, unsigned, unsigned, unsigned);
typedef void (*pfn_libvlc_video_set_format_callbacks)(libvlc_media_player_t*, void*, void*);
typedef int (*pfn_libvlc_video_get_size)(libvlc_media_player_t*, unsigned, unsigned*, unsigned*);
typedef void (*pfn_libvlc_media_player_set_hwnd)(libvlc_media_player_t*, void*);

// VLC event types we care about
enum libvlc_event_e {
    libvlc_MediaPlayerOpening = 0x100,
    libvlc_MediaPlayerBuffering,
    libvlc_MediaPlayerPlaying,
    libvlc_MediaPlayerPaused,
    libvlc_MediaPlayerStopped,
    libvlc_MediaPlayerEndReached,
    libvlc_MediaPlayerEncounteredError,
    libvlc_MediaPlayerTimeChanged,
    libvlc_MediaPlayerPositionChanged,
    libvlc_MediaPlayerAudioVolume = 0x200 + 13,
    libvlc_MediaPlayerMuted,
    libvlc_MediaPlayerUnmuted,
};

// Track description structure (matches libVLC)
struct libvlc_track_description_t {
    int i_id;
    char* psz_name;
    libvlc_track_description_t* p_next;
};

namespace vlc_player {

// Event stream handler for VLC events
class VlcEventStreamHandler : public flutter::StreamHandler<flutter::EncodableValue> {
public:
    VlcEventStreamHandler(std::function<void(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&)> on_listen,
                          std::function<void()> on_cancel)
        : on_listen_(on_listen), on_cancel_(on_cancel) {}

    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnListenInternal(
        const flutter::EncodableValue* arguments,
        std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) override {
        on_listen_(std::move(events));
        return nullptr;
    }

    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> OnCancelInternal(
        const flutter::EncodableValue* arguments) override {
        on_cancel_();
        return nullptr;
    }

private:
    std::function<void(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&)> on_listen_;
    std::function<void()> on_cancel_;
};

class VlcPlayerPlugin : public flutter::Plugin {
public:
    // Register with native Flutter C API registrar
    static void RegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar);

    // Register with C++ registrar (preferred)
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

    // Constructors
    VlcPlayerPlugin(FlutterDesktopMessengerRef messenger);
    VlcPlayerPlugin(flutter::PluginRegistrarWindows* registrar);
    ~VlcPlayerPlugin();

    // Disable copy
    VlcPlayerPlugin(const VlcPlayerPlugin&) = delete;
    VlcPlayerPlugin& operator=(const VlcPlayerPlugin&) = delete;

private:
    // Method channel handler
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue>& method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    // Core VLC operations
    bool LoadVlcLibrary(const std::string& vlc_path);
    bool Initialize(const std::string& plugins_path);
    bool Play(const std::string& url);
    void Stop();
    void Pause();
    void SetVolume(int volume);
    int GetVolume();
    void SetMute(bool mute);
    bool GetMute();
    std::vector<std::pair<int, std::string>> GetAudioTracks();
    void SetAudioTrack(int track_id);
    int GetAudioTrack();
    void Dispose();
    bool IsPlaying();

    // Video rendering callbacks (vmem)
    static void* LockCallback(void* opaque, void** planes);
    static void UnlockCallback(void* opaque, void* picture, void* const* planes);
    static void DisplayCallback(void* opaque, void* picture);
    static unsigned FormatCallback(void** opaque, char* chroma, unsigned* width, unsigned* height, unsigned* pitches, unsigned* lines);
    static void CleanupCallback(void* opaque);

    // Event handling
    static void VlcEventCallback(const void* event, void* user_data);
    void SendEvent(const std::string& event_name, const flutter::EncodableMap& data);
    void SetEventSink(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& sink);
    void ClearEventSink();

public:
    // Thread-safe event dispatching: enqueue events from any thread, dispatch on
    // the platform thread using the window message loop.
    // Public so FlutterWindow can call it when receiving the custom message.
    static void DispatchPendingEvents();

    // Video view management
    // Attach a child HWND for video rendering. If width/height are 0, attach to
    // the full client area of the Flutter view.
    // Returns true on success.
    bool AttachVideo(int x, int y, int width, int height);
    // Detach and destroy the child HWND (stop playback prior to destroying
    // to avoid orphaned HWNDs being used by libVLC)
    void DetachVideo();
    // Update bounds of the child HWND (called from Dart)
    void SetVideoBounds(int x, int y, int width, int height);

private:
    // Pointer to C++ registrar (used to get the platform window)
    flutter::PluginRegistrarWindows* registrar_ = nullptr;

    // Pending events queued from non-platform threads
    static std::mutex pending_events_mutex_;
    static std::vector<std::pair<std::string, flutter::EncodableMap>> pending_events_;

    // Child HWND used for VLC video rendering (created as a child of the
    // Flutter view). Never reuse an HWND after it has been destroyed.
    HWND video_hwnd_ = nullptr;
    // Delegate id returned by PluginRegistrarWindows::RegisterTopLevelWindowProcDelegate
    int resize_delegate_id_ = 0;
    // Current desired video bounds (if not full-parent)
    int video_x_ = 0, video_y_ = 0, video_w_ = 0, video_h_ = 0;
    bool video_full_parent_ = true;

    // Flutter messenger
    FlutterDesktopMessengerRef messenger_;
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_;
    std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;

    // Event sink for streaming events to Dart
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
    std::mutex event_sink_mutex_;

    // libVLC handles
    HMODULE vlc_lib_ = nullptr;
    HMODULE vlccore_lib_ = nullptr;
    libvlc_instance_t* vlc_instance_ = nullptr;
    libvlc_media_player_t* media_player_ = nullptr;
    libvlc_media_t* current_media_ = nullptr;

    // Function pointers
    pfn_libvlc_new fn_libvlc_new_ = nullptr;
    pfn_libvlc_release fn_libvlc_release_ = nullptr;
    pfn_libvlc_errmsg fn_libvlc_errmsg_ = nullptr;
    pfn_libvlc_media_player_new fn_libvlc_media_player_new_ = nullptr;
    pfn_libvlc_media_player_release fn_libvlc_media_player_release_ = nullptr;
    pfn_libvlc_media_player_set_media fn_libvlc_media_player_set_media_ = nullptr;
    pfn_libvlc_media_player_play fn_libvlc_media_player_play_ = nullptr;
    pfn_libvlc_media_player_stop fn_libvlc_media_player_stop_ = nullptr;
    pfn_libvlc_media_player_pause fn_libvlc_media_player_pause_ = nullptr;
    pfn_libvlc_media_player_is_playing fn_libvlc_media_player_is_playing_ = nullptr;
    pfn_libvlc_audio_set_volume fn_libvlc_audio_set_volume_ = nullptr;
    pfn_libvlc_audio_get_volume fn_libvlc_audio_get_volume_ = nullptr;
    pfn_libvlc_audio_set_mute fn_libvlc_audio_set_mute_ = nullptr;
    pfn_libvlc_audio_get_mute fn_libvlc_audio_get_mute_ = nullptr;
    pfn_libvlc_audio_get_track_description fn_libvlc_audio_get_track_description_ = nullptr;
    pfn_libvlc_audio_set_track fn_libvlc_audio_set_track_ = nullptr;
    pfn_libvlc_audio_get_track fn_libvlc_audio_get_track_ = nullptr;
    pfn_libvlc_audio_get_track_count fn_libvlc_audio_get_track_count_ = nullptr;
    pfn_libvlc_track_description_list_release fn_libvlc_track_description_list_release_ = nullptr;
    pfn_libvlc_media_new_location fn_libvlc_media_new_location_ = nullptr;
    pfn_libvlc_media_release fn_libvlc_media_release_ = nullptr;
    pfn_libvlc_media_add_option fn_libvlc_media_add_option_ = nullptr;
    pfn_libvlc_media_player_event_manager fn_libvlc_media_player_event_manager_ = nullptr;
    pfn_libvlc_event_attach fn_libvlc_event_attach_ = nullptr;
    pfn_libvlc_event_detach fn_libvlc_event_detach_ = nullptr;
    pfn_libvlc_video_set_callbacks fn_libvlc_video_set_callbacks_ = nullptr;
    pfn_libvlc_video_set_format fn_libvlc_video_set_format_ = nullptr;
    pfn_libvlc_video_set_format_callbacks fn_libvlc_video_set_format_callbacks_ = nullptr;
    pfn_libvlc_video_get_size fn_libvlc_video_get_size_ = nullptr;
    pfn_libvlc_media_player_set_hwnd fn_libvlc_media_player_set_hwnd_ = nullptr;

    // Video frame buffer for Flutter texture
    std::mutex frame_mutex_;
    std::vector<uint8_t> frame_buffer_;
    unsigned video_width_ = 0;
    unsigned video_height_ = 0;
    unsigned video_pitch_ = 0;
    int64_t texture_id_ = -1;
    std::atomic<bool> frame_ready_{false};

    // State
    std::atomic<bool> initialized_{false};
    std::atomic<bool> playing_{false};
    std::string current_url_;

    // VLC Command Thread - ALL blocking VLC operations run here, NEVER on UI thread
    std::thread vlc_command_thread_;
    std::queue<std::function<void()>> vlc_tasks_;
    std::mutex vlc_tasks_mutex_;
    std::condition_variable vlc_tasks_cv_;
    std::atomic<bool> vlc_thread_running_{false};

    // Worker thread methods
    void StartVlcThread();
    void StopVlcThread();
    void EnqueueVlcTask(std::function<void()> task);
    void VlcThreadLoop();

    // Internal async implementations (run on VLC thread)
    void PlayAsync(const std::string& url);
    void StopAsync();
};

}  // namespace vlc_player

#endif  // VLC_PLAYER_PLUGIN_H_

// VLC Player Plugin - Direct libVLC integration for Flutter on Linux
// This plugin provides VLC playback via platform channels
// NO media_kit, NO FFmpeg wrapper - pure libVLC

#ifndef VLC_PLAYER_PLUGIN_H_
#define VLC_PLAYER_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

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
typedef void (*pfn_libvlc_media_player_set_xwindow)(libvlc_media_player_t*, uint32_t);

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

G_BEGIN_DECLS

// Plugin registration function
void vlc_player_plugin_register_with_registrar(FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // VLC_PLAYER_PLUGIN_H_

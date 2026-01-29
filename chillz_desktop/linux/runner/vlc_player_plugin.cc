// VLC Player Plugin Implementation for Linux
// Direct libVLC integration - NO media_kit, NO FFmpeg wrapper

#include "vlc_player_plugin.h"
#include <dlfcn.h>
#include <iostream>
#include <sstream>
#include <cstring>
#include <unistd.h>
#include <limits.h>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

// Forward declare the plugin type
typedef struct _VlcPlayerPlugin VlcPlayerPlugin;

// Plugin structure
struct _VlcPlayerPlugin {
    // libVLC handles
    void* vlc_lib;
    libvlc_instance_t* vlc_instance;
    libvlc_media_player_t* media_player;
    
    // State
    gboolean initialized;
    int64_t texture_id;
    
    // Video window
    GtkWidget* video_widget;
    GtkWidget* parent_window;
    uint32_t xwindow_id;
    
    // Channels
    FlMethodChannel* method_channel;
    
    // Function pointers
    pfn_libvlc_new fn_libvlc_new;
    pfn_libvlc_release fn_libvlc_release;
    pfn_libvlc_errmsg fn_libvlc_errmsg;
    pfn_libvlc_media_player_new fn_libvlc_media_player_new;
    pfn_libvlc_media_player_release fn_libvlc_media_player_release;
    pfn_libvlc_media_player_set_media fn_libvlc_media_player_set_media;
    pfn_libvlc_media_player_play fn_libvlc_media_player_play;
    pfn_libvlc_media_player_stop fn_libvlc_media_player_stop;
    pfn_libvlc_media_player_pause fn_libvlc_media_player_pause;
    pfn_libvlc_media_player_is_playing fn_libvlc_media_player_is_playing;
    pfn_libvlc_audio_set_volume fn_libvlc_audio_set_volume;
    pfn_libvlc_audio_get_volume fn_libvlc_audio_get_volume;
    pfn_libvlc_audio_set_mute fn_libvlc_audio_set_mute;
    pfn_libvlc_audio_get_mute fn_libvlc_audio_get_mute;
    pfn_libvlc_audio_get_track_description fn_libvlc_audio_get_track_description;
    pfn_libvlc_audio_set_track fn_libvlc_audio_set_track;
    pfn_libvlc_audio_get_track fn_libvlc_audio_get_track;
    pfn_libvlc_audio_get_track_count fn_libvlc_audio_get_track_count;
    pfn_libvlc_track_description_list_release fn_libvlc_track_description_list_release;
    pfn_libvlc_media_new_location fn_libvlc_media_new_location;
    pfn_libvlc_media_release fn_libvlc_media_release;
    pfn_libvlc_media_add_option fn_libvlc_media_add_option;
    pfn_libvlc_media_player_event_manager fn_libvlc_media_player_event_manager;
    pfn_libvlc_event_attach fn_libvlc_event_attach;
    pfn_libvlc_event_detach fn_libvlc_event_detach;
    pfn_libvlc_media_player_set_xwindow fn_libvlc_media_player_set_xwindow;
};

// Global plugin instance
static VlcPlayerPlugin* g_plugin = NULL;

// Forward declarations
static gboolean load_vlc_library(VlcPlayerPlugin* self, const gchar* vlc_path);
static gboolean initialize_vlc(VlcPlayerPlugin* self, const gchar* plugins_path);
static gboolean play_media(VlcPlayerPlugin* self, const gchar* url);
static void stop_media(VlcPlayerPlugin* self);
static void pause_media(VlcPlayerPlugin* self);
static void set_volume(VlcPlayerPlugin* self, int volume);
static int get_volume(VlcPlayerPlugin* self);
static void set_mute(VlcPlayerPlugin* self, gboolean mute);
static gboolean get_mute(VlcPlayerPlugin* self);
static gboolean is_playing(VlcPlayerPlugin* self);
static void dispose_vlc(VlcPlayerPlugin* self);
static void vlc_event_callback(const void* event, void* user_data);
static gboolean attach_video(VlcPlayerPlugin* self, int x, int y, int width, int height);
static void set_video_bounds(VlcPlayerPlugin* self, int x, int y, int width, int height);
static void detach_video(VlcPlayerPlugin* self);

static gboolean load_vlc_library(VlcPlayerPlugin* self, const gchar* vlc_path) {
    g_print("[VlcPlayerPlugin] Loading VLC from: %s\n", vlc_path);
    
    // Build path to libvlc.so
    g_autofree gchar* vlc_lib_path = g_build_filename(vlc_path, "libvlc.so.5", NULL);
    
    // Try bundled first, then system
    self->vlc_lib = dlopen(vlc_lib_path, RTLD_NOW | RTLD_GLOBAL);
    if (!self->vlc_lib) {
        g_print("[VlcPlayerPlugin] Bundled libvlc not found at %s, trying system...\n", vlc_lib_path);
        // Try system libvlc
        self->vlc_lib = dlopen("libvlc.so.5", RTLD_NOW | RTLD_GLOBAL);
        if (!self->vlc_lib) {
            self->vlc_lib = dlopen("libvlc.so", RTLD_NOW | RTLD_GLOBAL);
        }
    }
    
    if (!self->vlc_lib) {
        g_printerr("[VlcPlayerPlugin] Failed to load libvlc: %s\n", dlerror());
        return FALSE;
    }
    
    // Get function pointers
    #define LOAD_VLC_FUNC(name) \
        self->fn_##name = (pfn_##name)dlsym(self->vlc_lib, #name); \
        if (!self->fn_##name) { \
            g_printerr("[VlcPlayerPlugin] Failed to get " #name ": %s\n", dlerror()); \
            return FALSE; \
        }

    LOAD_VLC_FUNC(libvlc_new);
    LOAD_VLC_FUNC(libvlc_release);
    LOAD_VLC_FUNC(libvlc_media_player_new);
    LOAD_VLC_FUNC(libvlc_media_player_release);
    LOAD_VLC_FUNC(libvlc_media_player_set_media);
    LOAD_VLC_FUNC(libvlc_media_player_play);
    LOAD_VLC_FUNC(libvlc_media_player_stop);
    LOAD_VLC_FUNC(libvlc_media_player_pause);
    LOAD_VLC_FUNC(libvlc_media_player_is_playing);
    LOAD_VLC_FUNC(libvlc_audio_set_volume);
    LOAD_VLC_FUNC(libvlc_audio_get_volume);
    LOAD_VLC_FUNC(libvlc_audio_set_mute);
    LOAD_VLC_FUNC(libvlc_audio_get_mute);
    LOAD_VLC_FUNC(libvlc_audio_get_track_description);
    LOAD_VLC_FUNC(libvlc_audio_set_track);
    LOAD_VLC_FUNC(libvlc_audio_get_track);
    LOAD_VLC_FUNC(libvlc_audio_get_track_count);
    LOAD_VLC_FUNC(libvlc_track_description_list_release);
    LOAD_VLC_FUNC(libvlc_media_new_location);
    LOAD_VLC_FUNC(libvlc_media_release);
    LOAD_VLC_FUNC(libvlc_media_add_option);
    LOAD_VLC_FUNC(libvlc_media_player_event_manager);
    LOAD_VLC_FUNC(libvlc_event_attach);
    LOAD_VLC_FUNC(libvlc_event_detach);
    LOAD_VLC_FUNC(libvlc_media_player_set_xwindow);
    
    // Optional - may not exist in all VLC versions
    self->fn_libvlc_errmsg = (pfn_libvlc_errmsg)dlsym(self->vlc_lib, "libvlc_errmsg");

    #undef LOAD_VLC_FUNC

    g_print("[VlcPlayerPlugin] VLC library loaded successfully\n");
    return TRUE;
}

static gboolean initialize_vlc(VlcPlayerPlugin* self, const gchar* plugins_path) {
    if (self->initialized) {
        return TRUE;
    }

    // Get directory containing plugins
    g_autofree gchar* vlc_path = g_strdup(plugins_path);
    
    // Remove trailing "/plugins" if present
    if (g_str_has_suffix(vlc_path, "/plugins")) {
        vlc_path[strlen(vlc_path) - 8] = '\0';
    }

    if (!load_vlc_library(self, vlc_path)) {
        return FALSE;
    }

    // VLC initialization arguments
    g_autofree gchar* plugin_arg = g_strdup_printf("--plugin-path=%s", plugins_path);
    const char* vlc_args[] = {
        "--no-video-title-show",
        "--no-stats",
        "--no-osd",
        "--network-caching=3000",
        "--live-caching=3000",
        "--sout-mux-caching=3000",
        "--verbose=2",
        "--ignore-config",
        plugin_arg,
    };

    self->vlc_instance = self->fn_libvlc_new(sizeof(vlc_args) / sizeof(vlc_args[0]), vlc_args);
    if (!self->vlc_instance) {
        g_printerr("[VlcPlayerPlugin] Failed to create VLC instance\n");
        return FALSE;
    }

    self->media_player = self->fn_libvlc_media_player_new(self->vlc_instance);
    if (!self->media_player) {
        g_printerr("[VlcPlayerPlugin] Failed to create media player\n");
        self->fn_libvlc_release(self->vlc_instance);
        self->vlc_instance = NULL;
        return FALSE;
    }

    // Attach event handlers
    libvlc_event_manager_t* event_manager = self->fn_libvlc_media_player_event_manager(self->media_player);
    if (event_manager) {
        self->fn_libvlc_event_attach(event_manager, libvlc_MediaPlayerOpening, vlc_event_callback, self);
        self->fn_libvlc_event_attach(event_manager, libvlc_MediaPlayerBuffering, vlc_event_callback, self);
        self->fn_libvlc_event_attach(event_manager, libvlc_MediaPlayerPlaying, vlc_event_callback, self);
        self->fn_libvlc_event_attach(event_manager, libvlc_MediaPlayerPaused, vlc_event_callback, self);
        self->fn_libvlc_event_attach(event_manager, libvlc_MediaPlayerStopped, vlc_event_callback, self);
        self->fn_libvlc_event_attach(event_manager, libvlc_MediaPlayerEndReached, vlc_event_callback, self);
        self->fn_libvlc_event_attach(event_manager, libvlc_MediaPlayerEncounteredError, vlc_event_callback, self);
    }

    self->initialized = TRUE;
    g_print("[VlcPlayerPlugin] VLC initialized successfully\n");
    return TRUE;
}

static gboolean play_media(VlcPlayerPlugin* self, const gchar* url) {
    if (!self->media_player) {
        g_printerr("[VlcPlayerPlugin] Media player not initialized\n");
        return FALSE;
    }

    g_print("[VlcPlayerPlugin] Playing: %s\n", url);

    self->fn_libvlc_media_player_stop(self->media_player);

    libvlc_media_t* media = self->fn_libvlc_media_new_location(self->vlc_instance, url);
    if (!media) {
        g_printerr("[VlcPlayerPlugin] Failed to create media from URL\n");
        return FALSE;
    }

    self->fn_libvlc_media_add_option(media, ":network-caching=3000");
    self->fn_libvlc_media_add_option(media, ":live-caching=3000");

    self->fn_libvlc_media_player_set_media(self->media_player, media);
    self->fn_libvlc_media_release(media);

    if (self->fn_libvlc_media_player_play(self->media_player) != 0) {
        g_printerr("[VlcPlayerPlugin] Failed to start playback\n");
        return FALSE;
    }

    return TRUE;
}

static void stop_media(VlcPlayerPlugin* self) {
    if (self->media_player) {
        self->fn_libvlc_media_player_stop(self->media_player);
        g_print("[VlcPlayerPlugin] Playback stopped\n");
    }
}

static void pause_media(VlcPlayerPlugin* self) {
    if (self->media_player) {
        self->fn_libvlc_media_player_pause(self->media_player);
    }
}

static void set_volume(VlcPlayerPlugin* self, int volume) {
    if (self->media_player) {
        self->fn_libvlc_audio_set_volume(self->media_player, volume);
    }
}

static int get_volume(VlcPlayerPlugin* self) {
    if (self->media_player) {
        return self->fn_libvlc_audio_get_volume(self->media_player);
    }
    return 0;
}

static void set_mute(VlcPlayerPlugin* self, gboolean mute) {
    if (self->media_player) {
        self->fn_libvlc_audio_set_mute(self->media_player, mute ? 1 : 0);
    }
}

static gboolean get_mute(VlcPlayerPlugin* self) {
    if (self->media_player) {
        return self->fn_libvlc_audio_get_mute(self->media_player) != 0;
    }
    return FALSE;
}

static gboolean is_playing(VlcPlayerPlugin* self) {
    if (self->media_player) {
        return self->fn_libvlc_media_player_is_playing(self->media_player) != 0;
    }
    return FALSE;
}

static FlValue* get_audio_tracks(VlcPlayerPlugin* self) {
    FlValue* track_list = fl_value_new_list();
    
    if (!self->media_player) {
        return track_list;
    }
    
    libvlc_track_description_t* tracks = self->fn_libvlc_audio_get_track_description(self->media_player);
    libvlc_track_description_t* track = tracks;
    
    while (track) {
        FlValue* track_map = fl_value_new_map();
        fl_value_set_string_take(track_map, "id", fl_value_new_int(track->i_id));
        fl_value_set_string_take(track_map, "name", fl_value_new_string(track->psz_name ? track->psz_name : "Unknown"));
        fl_value_append_take(track_list, track_map);
        track = track->p_next;
    }
    
    if (tracks) {
        self->fn_libvlc_track_description_list_release(tracks);
    }
    
    return track_list;
}

static void set_audio_track(VlcPlayerPlugin* self, int track_id) {
    if (self->media_player) {
        self->fn_libvlc_audio_set_track(self->media_player, track_id);
    }
}

static int get_audio_track(VlcPlayerPlugin* self) {
    if (self->media_player) {
        return self->fn_libvlc_audio_get_track(self->media_player);
    }
    return -1;
}

static void dispose_vlc(VlcPlayerPlugin* self) {
    if (self->media_player) {
        self->fn_libvlc_media_player_stop(self->media_player);
        self->fn_libvlc_media_player_release(self->media_player);
        self->media_player = NULL;
    }
    
    if (self->vlc_instance) {
        self->fn_libvlc_release(self->vlc_instance);
        self->vlc_instance = NULL;
    }
    
    if (self->vlc_lib) {
        dlclose(self->vlc_lib);
        self->vlc_lib = NULL;
    }
    
    if (self->video_widget) {
        gtk_widget_destroy(self->video_widget);
        self->video_widget = NULL;
    }
    
    self->initialized = FALSE;
    g_print("[VlcPlayerPlugin] VLC disposed\n");
}

// Struct for passing event data to main thread
typedef struct {
    VlcPlayerPlugin* plugin;
    gchar* state_name;
    float cache_value;
    gboolean has_cache;
} VlcEventData;

static gboolean dispatch_vlc_event(gpointer user_data) {
    VlcEventData* data = (VlcEventData*)user_data;
    
    // For Linux, we just log state changes - events are simpler
    // The Dart side polls state when needed
    g_print("[VlcPlayerPlugin] State changed: %s\n", data->state_name);
    
    g_free(data->state_name);
    g_free(data);
    return G_SOURCE_REMOVE;
}

// VLC event callback - called from VLC thread
static void vlc_event_callback(const void* p_event, void* user_data) {
    VlcPlayerPlugin* self = (VlcPlayerPlugin*)user_data;
    
    // VLC event structure (simplified)
    struct vlc_event {
        int type;
        void* obj;
        union {
            struct { float new_cache; } media_player_buffering;
        } u;
    };
    
    const struct vlc_event* event = (const struct vlc_event*)p_event;
    
    const gchar* state_name = NULL;
    float cache_value = 0.0f;
    gboolean has_cache = FALSE;
    
    switch (event->type) {
        case libvlc_MediaPlayerOpening:
            state_name = "opening";
            break;
        case libvlc_MediaPlayerBuffering:
            state_name = "buffering";
            cache_value = event->u.media_player_buffering.new_cache;
            has_cache = TRUE;
            break;
        case libvlc_MediaPlayerPlaying:
            state_name = "playing";
            break;
        case libvlc_MediaPlayerPaused:
            state_name = "paused";
            break;
        case libvlc_MediaPlayerStopped:
            state_name = "stopped";
            break;
        case libvlc_MediaPlayerEndReached:
            state_name = "ended";
            break;
        case libvlc_MediaPlayerEncounteredError:
            state_name = "error";
            break;
        default:
            return;
    }
    
    if (state_name) {
        VlcEventData* data = g_new0(VlcEventData, 1);
        data->plugin = self;
        data->state_name = g_strdup(state_name);
        data->cache_value = cache_value;
        data->has_cache = has_cache;
        
        g_idle_add(dispatch_vlc_event, data);
    }
}

static gboolean attach_video(VlcPlayerPlugin* self, int x, int y, int width, int height) {
    if (!self->media_player) {
        g_printerr("[VlcPlayerPlugin] Cannot attach video - player not initialized\n");
        return FALSE;
    }

#ifdef GDK_WINDOWING_X11
    g_print("[VlcPlayerPlugin] Video attach requested: %d,%d %dx%d\n", x, y, width, height);
    
    if (self->xwindow_id != 0) {
        self->fn_libvlc_media_player_set_xwindow(self->media_player, self->xwindow_id);
        g_print("[VlcPlayerPlugin] Video attached to XWindow: %u\n", self->xwindow_id);
        return TRUE;
    }
#endif

    g_print("[VlcPlayerPlugin] Video output set to default\n");
    return TRUE;
}

static void set_video_bounds(VlcPlayerPlugin* self, int x, int y, int width, int height) {
    g_print("[VlcPlayerPlugin] Video bounds: %d,%d %dx%d\n", x, y, width, height);
    
    if (self->video_widget) {
        gtk_widget_set_size_request(self->video_widget, width, height);
    }
}

static void detach_video(VlcPlayerPlugin* self) {
    if (self->media_player) {
        self->fn_libvlc_media_player_set_xwindow(self->media_player, 0);
        g_print("[VlcPlayerPlugin] Video detached\n");
    }
}

static void handle_method_call(FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
    VlcPlayerPlugin* self = (VlcPlayerPlugin*)user_data;
    const gchar* method = fl_method_call_get_name(method_call);
    FlValue* args = fl_method_call_get_args(method_call);
    
    g_autoptr(FlMethodResponse) response = NULL;
    
    if (g_strcmp0(method, "initialize") == 0) {
        FlValue* plugins_path_val = fl_value_lookup_string(args, "pluginsPath");
        if (plugins_path_val) {
            const gchar* plugins_path = fl_value_get_string(plugins_path_val);
            if (initialize_vlc(self, plugins_path)) {
                response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
            } else {
                response = FL_METHOD_RESPONSE(fl_method_error_response_new("INIT_FAILED", "Failed to initialize VLC", NULL));
            }
        } else {
            response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "pluginsPath required", NULL));
        }
    }
    else if (g_strcmp0(method, "play") == 0) {
        FlValue* url_val = fl_value_lookup_string(args, "url");
        if (url_val) {
            const gchar* url = fl_value_get_string(url_val);
            if (play_media(self, url)) {
                response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
            } else {
                response = FL_METHOD_RESPONSE(fl_method_error_response_new("PLAY_FAILED", "Failed to play media", NULL));
            }
        } else {
            response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "url required", NULL));
        }
    }
    else if (g_strcmp0(method, "stop") == 0) {
        stop_media(self);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    }
    else if (g_strcmp0(method, "pause") == 0) {
        pause_media(self);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    }
    else if (g_strcmp0(method, "setVolume") == 0) {
        FlValue* volume_val = fl_value_lookup_string(args, "volume");
        if (volume_val) {
            int volume = fl_value_get_int(volume_val);
            set_volume(self, volume);
            response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
        } else {
            response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "volume required", NULL));
        }
    }
    else if (g_strcmp0(method, "getVolume") == 0) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_int(get_volume(self))));
    }
    else if (g_strcmp0(method, "setMute") == 0) {
        FlValue* mute_val = fl_value_lookup_string(args, "mute");
        if (mute_val) {
            gboolean mute = fl_value_get_bool(mute_val);
            set_mute(self, mute);
            response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
        } else {
            response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "mute required", NULL));
        }
    }
    else if (g_strcmp0(method, "getMute") == 0) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(get_mute(self))));
    }
    else if (g_strcmp0(method, "getAudioTracks") == 0) {
        FlValue* tracks = get_audio_tracks(self);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(tracks));
    }
    else if (g_strcmp0(method, "setAudioTrack") == 0) {
        FlValue* track_id_val = fl_value_lookup_string(args, "trackId");
        if (track_id_val) {
            int track_id = fl_value_get_int(track_id_val);
            set_audio_track(self, track_id);
            response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
        } else {
            response = FL_METHOD_RESPONSE(fl_method_error_response_new("INVALID_ARGS", "trackId required", NULL));
        }
    }
    else if (g_strcmp0(method, "getAudioTrack") == 0) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_int(get_audio_track(self))));
    }
    else if (g_strcmp0(method, "isPlaying") == 0) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(is_playing(self))));
    }
    else if (g_strcmp0(method, "getTextureId") == 0) {
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_int(self->texture_id)));
    }
    else if (g_strcmp0(method, "dispose") == 0) {
        dispose_vlc(self);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    }
    else if (g_strcmp0(method, "attachVideo") == 0) {
        int x = 0, y = 0, w = 0, h = 0;
        FlValue* xv = fl_value_lookup_string(args, "x");
        FlValue* yv = fl_value_lookup_string(args, "y");
        FlValue* wv = fl_value_lookup_string(args, "width");
        FlValue* hv = fl_value_lookup_string(args, "height");
        if (xv) x = fl_value_get_int(xv);
        if (yv) y = fl_value_get_int(yv);
        if (wv) w = fl_value_get_int(wv);
        if (hv) h = fl_value_get_int(hv);
        
        if (attach_video(self, x, y, w, h)) {
            response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
        } else {
            response = FL_METHOD_RESPONSE(fl_method_error_response_new("ATTACH_FAILED", "Failed to attach video", NULL));
        }
    }
    else if (g_strcmp0(method, "setVideoBounds") == 0) {
        int x = 0, y = 0, w = 0, h = 0;
        FlValue* xv = fl_value_lookup_string(args, "x");
        FlValue* yv = fl_value_lookup_string(args, "y");
        FlValue* wv = fl_value_lookup_string(args, "width");
        FlValue* hv = fl_value_lookup_string(args, "height");
        if (xv) x = fl_value_get_int(xv);
        if (yv) y = fl_value_get_int(yv);
        if (wv) w = fl_value_get_int(wv);
        if (hv) h = fl_value_get_int(hv);
        
        set_video_bounds(self, x, y, w, h);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    }
    else if (g_strcmp0(method, "detachVideo") == 0) {
        detach_video(self);
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    }
    else if (g_strcmp0(method, "hideVideo") == 0) {
        if (self->video_widget) {
            gtk_widget_hide(self->video_widget);
        }
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    }
    else if (g_strcmp0(method, "showVideo") == 0) {
        if (self->video_widget) {
            gtk_widget_show(self->video_widget);
        }
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(TRUE)));
    }
    else {
        response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }
    
    fl_method_call_respond(method_call, response, NULL);
}

void vlc_player_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
    // Create plugin instance
    g_plugin = g_new0(VlcPlayerPlugin, 1);
    g_plugin->initialized = FALSE;
    g_plugin->texture_id = -1;
    g_plugin->xwindow_id = 0;
    
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    
    // Create method channel
    g_plugin->method_channel = fl_method_channel_new(
        fl_plugin_registrar_get_messenger(registrar),
        "com.chillz/vlc_player",
        FL_METHOD_CODEC(codec));
    
    fl_method_channel_set_method_call_handler(
        g_plugin->method_channel,
        handle_method_call,
        g_plugin,
        NULL);
    
    g_print("[VlcPlayerPlugin] Plugin registered\n");
}

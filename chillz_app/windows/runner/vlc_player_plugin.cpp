// VLC Player Plugin Implementation
// Direct libVLC integration - NO media_kit, NO FFmpeg wrapper

#include "vlc_player_plugin.h"
#include <flutter/standard_method_codec.h>
#include <shlwapi.h>
#include <iostream>
#include <sstream>

#pragma comment(lib, "shlwapi.lib")

namespace vlc_player {

// Static plugin instance with thread-safe access
static std::unique_ptr<VlcPlayerPlugin> g_plugin;
static std::mutex g_plugin_mutex;
static std::once_flag g_plugin_init_flag;

// Pending events queue (static storage definitions)
std::mutex VlcPlayerPlugin::pending_events_mutex_;
std::vector<std::pair<std::string, flutter::EncodableMap>> VlcPlayerPlugin::pending_events_;

// Static registration (C API)
void VlcPlayerPlugin::RegisterWithRegistrar(FlutterDesktopPluginRegistrarRef registrar) {
    std::call_once(g_plugin_init_flag, [registrar]() {
        FlutterDesktopMessengerRef messenger = FlutterDesktopPluginRegistrarGetMessenger(registrar);
        std::lock_guard<std::mutex> lock(g_plugin_mutex);
        g_plugin = std::make_unique<VlcPlayerPlugin>(messenger);
        OutputDebugStringA("[VlcPlayerPlugin] Plugin registered (C API)\n");
    });
}

// Static registration (C++ registrar) - preferred
void VlcPlayerPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
    auto plugin = std::make_unique<VlcPlayerPlugin>(registrar);
    registrar->AddPlugin(std::move(plugin));
    OutputDebugStringA("[VlcPlayerPlugin] Plugin registered (C++ registrar)\n");
}

VlcPlayerPlugin::VlcPlayerPlugin(FlutterDesktopMessengerRef messenger)
    : messenger_(messenger) {
    // Constructed from the C API messenger; do not create C++ channels here.
    // Use the C++ registrar constructor for reliable channel setup.
    OutputDebugStringA("[VlcPlayerPlugin] Constructed from C API messenger (channels not created)\n");
}

VlcPlayerPlugin::VlcPlayerPlugin(flutter::PluginRegistrarWindows* registrar)
    : messenger_(nullptr), registrar_(registrar) {
    // Use the C++ BinaryMessenger provided by the registrar (safe)
    auto binary_messenger = registrar->messenger();

    method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        binary_messenger,
        "com.chillz/vlc_player",
        &flutter::StandardMethodCodec::GetInstance());

    method_channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
            HandleMethodCall(call, std::move(result));
        });

    // Create event channel with proper stream handler
    event_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        binary_messenger,
        "com.chillz/vlc_player_events",
        &flutter::StandardMethodCodec::GetInstance());

    auto handler = std::make_unique<VlcEventStreamHandler>(
        [this](std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& sink) {
            SetEventSink(std::move(sink));
        },
        [this]() {
            ClearEventSink();
        }
    );
    event_channel_->SetStreamHandler(std::move(handler));

    OutputDebugStringA("[VlcPlayerPlugin] Constructed with C++ registrar and channels\n");
}

VlcPlayerPlugin::~VlcPlayerPlugin() {
    Dispose();
}

void VlcPlayerPlugin::SetEventSink(std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& sink) {
    std::lock_guard<std::mutex> lock(event_sink_mutex_);
    event_sink_ = std::move(sink);
    OutputDebugStringA("[VlcPlayerPlugin] Event sink connected\n");
}

void VlcPlayerPlugin::ClearEventSink() {
    std::lock_guard<std::mutex> lock(event_sink_mutex_);
    event_sink_ = nullptr;
    OutputDebugStringA("[VlcPlayerPlugin] Event sink cleared\n");
}

void VlcPlayerPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    
    const std::string& method = method_call.method_name();

    if (method == "initialize") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) {
            auto it = args->find(flutter::EncodableValue("pluginsPath"));
            if (it != args->end()) {
                std::string plugins_path = std::get<std::string>(it->second);
                if (Initialize(plugins_path)) {
                    result->Success(flutter::EncodableValue(true));
                } else {
                    result->Error("INIT_FAILED", "Failed to initialize VLC");
                }
                return;
            }
        }
        result->Error("INVALID_ARGS", "pluginsPath required");
    }
    else if (method == "play") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) {
            auto it = args->find(flutter::EncodableValue("url"));
            if (it != args->end()) {
                std::string url = std::get<std::string>(it->second);
                if (Play(url)) {
                    result->Success(flutter::EncodableValue(true));
                } else {
                    result->Error("PLAY_FAILED", "Failed to play media");
                }
                return;
            }
        }
        result->Error("INVALID_ARGS", "url required");
    }
    else if (method == "stop") {
        Stop();
        result->Success(flutter::EncodableValue(true));
    }
    else if (method == "pause") {
        Pause();
        result->Success(flutter::EncodableValue(true));
    }
    else if (method == "setVolume") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) {
            auto it = args->find(flutter::EncodableValue("volume"));
            if (it != args->end()) {
                int volume = std::get<int>(it->second);
                SetVolume(volume);
                result->Success(flutter::EncodableValue(true));
                return;
            }
        }
        result->Error("INVALID_ARGS", "volume required");
    }
    else if (method == "getVolume") {
        result->Success(flutter::EncodableValue(GetVolume()));
    }
    else if (method == "setMute") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) {
            auto it = args->find(flutter::EncodableValue("mute"));
            if (it != args->end()) {
                bool mute = std::get<bool>(it->second);
                SetMute(mute);
                result->Success(flutter::EncodableValue(true));
                return;
            }
        }
        result->Error("INVALID_ARGS", "mute required");
    }
    else if (method == "getMute") {
        result->Success(flutter::EncodableValue(GetMute()));
    }
    else if (method == "getAudioTracks") {
        auto tracks = GetAudioTracks();
        flutter::EncodableList track_list;
        for (const auto& track : tracks) {
            flutter::EncodableMap track_map;
            track_map[flutter::EncodableValue("id")] = flutter::EncodableValue(track.first);
            track_map[flutter::EncodableValue("name")] = flutter::EncodableValue(track.second);
            track_list.push_back(flutter::EncodableValue(track_map));
        }
        result->Success(flutter::EncodableValue(track_list));
    }
    else if (method == "setAudioTrack") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) {
            auto it = args->find(flutter::EncodableValue("trackId"));
            if (it != args->end()) {
                int track_id = std::get<int>(it->second);
                SetAudioTrack(track_id);
                result->Success(flutter::EncodableValue(true));
                return;
            }
        }
        result->Error("INVALID_ARGS", "trackId required");
    }
    else if (method == "getAudioTrack") {
        result->Success(flutter::EncodableValue(GetAudioTrack()));
    }
    else if (method == "isPlaying") {
        result->Success(flutter::EncodableValue(IsPlaying()));
    }
    else if (method == "getTextureId") {
        result->Success(flutter::EncodableValue(texture_id_));
    }
    else if (method == "dispose") {
        Dispose();
        result->Success(flutter::EncodableValue(true));
    }
    else if (method == "attachVideo") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        int x = 0, y = 0, w = 0, h = 0;
        if (args) {
            auto itx = args->find(flutter::EncodableValue("x"));
            auto ity = args->find(flutter::EncodableValue("y"));
            auto itw = args->find(flutter::EncodableValue("width"));
            auto ith = args->find(flutter::EncodableValue("height"));
            if (itx != args->end()) x = std::get<int>(itx->second);
            if (ity != args->end()) y = std::get<int>(ity->second);
            if (itw != args->end()) w = std::get<int>(itw->second);
            if (ith != args->end()) h = std::get<int>(ith->second);
        }
        if (AttachVideo(x,y,w,h)) {
            result->Success(flutter::EncodableValue(true));
        } else {
            result->Error("ATTACH_FAILED", "Failed to attach video HWND");
        }
    }
    else if (method == "setVideoBounds") {
        const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
        if (args) {
            int x = 0, y = 0, w = 0, h = 0;
            auto itx = args->find(flutter::EncodableValue("x"));
            auto ity = args->find(flutter::EncodableValue("y"));
            auto itw = args->find(flutter::EncodableValue("width"));
            auto ith = args->find(flutter::EncodableValue("height"));
            if (itx != args->end()) x = std::get<int>(itx->second);
            if (ity != args->end()) y = std::get<int>(ity->second);
            if (itw != args->end()) w = std::get<int>(itw->second);
            if (ith != args->end()) h = std::get<int>(ith->second);
            SetVideoBounds(x,y,w,h);
            result->Success(flutter::EncodableValue(true));
        } else {
            result->Error("INVALID_ARGS", "x,y,width,height required");
        }
    }
    else if (method == "detachVideo") {
        DetachVideo();
        result->Success(flutter::EncodableValue(true));
    }
    else if (method == "hideVideo") {
        // Hide video HWND when dialogs are shown
        if (video_hwnd_) {
            ShowWindow(video_hwnd_, SW_HIDE);
            OutputDebugStringA("[VLC] hideVideo: HWND hidden for dialog\n");
        }
        result->Success(flutter::EncodableValue(true));
    }
    else if (method == "showVideo") {
        // Show video HWND after dialogs close
        if (video_hwnd_) {
            ShowWindow(video_hwnd_, SW_SHOW);
            // Re-apply z-order at bottom
            SetWindowPos(video_hwnd_, HWND_BOTTOM, 0, 0, 0, 0, 
                SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            OutputDebugStringA("[VLC] showVideo: HWND shown after dialog\n");
        }
        result->Success(flutter::EncodableValue(true));
    }
    else {
        result->NotImplemented();
    }
}

bool VlcPlayerPlugin::LoadVlcLibrary(const std::string& vlc_path) {
    // Build path to libvlc.dll
    std::string vlc_dll_path = vlc_path + "\\libvlc.dll";
    std::string vlccore_dll_path = vlc_path + "\\libvlccore.dll";

    // Add VLC directory to DLL search path
    SetDllDirectoryA(vlc_path.c_str());

    // Load libvlccore first (dependency)
    vlccore_lib_ = LoadLibraryA(vlccore_dll_path.c_str());
    if (!vlccore_lib_) {
        OutputDebugStringA(("Failed to load libvlccore.dll from: " + vlccore_dll_path + "\n").c_str());
        return false;
    }

    // Load libvlc
    vlc_lib_ = LoadLibraryA(vlc_dll_path.c_str());
    if (!vlc_lib_) {
        OutputDebugStringA(("Failed to load libvlc.dll from: " + vlc_dll_path + "\n").c_str());
        FreeLibrary(vlccore_lib_);
        vlccore_lib_ = nullptr;
        return false;
    }

    // Get function pointers
    #define LOAD_VLC_FUNC(name) \
        fn_##name##_ = (pfn_##name)GetProcAddress(vlc_lib_, #name); \
        if (!fn_##name##_) { \
            OutputDebugStringA("[VlcPlayerPlugin] Failed to get " #name "\n"); \
            return false; \
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
    LOAD_VLC_FUNC(libvlc_video_set_callbacks);
    LOAD_VLC_FUNC(libvlc_video_set_format);
    LOAD_VLC_FUNC(libvlc_video_set_format_callbacks);
    LOAD_VLC_FUNC(libvlc_video_get_size);
    LOAD_VLC_FUNC(libvlc_media_player_set_hwnd);
    
    // Optional - may not exist in all VLC versions
    fn_libvlc_errmsg_ = (pfn_libvlc_errmsg)GetProcAddress(vlc_lib_, "libvlc_errmsg");

    #undef LOAD_VLC_FUNC

    OutputDebugStringA("[VlcPlayerPlugin] VLC library loaded successfully\n");
    return true;
}

bool VlcPlayerPlugin::Initialize(const std::string& plugins_path) {
    if (initialized_) {
        return true;
    }

    // Get directory containing plugins
    std::string vlc_path = plugins_path;
    // Remove trailing "plugins" if present
    size_t pos = vlc_path.rfind("\\plugins");
    if (pos != std::string::npos) {
        vlc_path = vlc_path.substr(0, pos);
    }

    if (!LoadVlcLibrary(vlc_path)) {
        return false;
    }

    // VLC initialization arguments
    std::string plugin_arg = "--plugin-path=" + plugins_path;
    const char* vlc_args[] = {
        "--no-video-title-show",     // Don't show title on video
        "--no-stats",                // Disable statistics
        "--no-osd",                  // No on-screen display
        "--network-caching=3000",    // 3 second network cache for IPTV
        "--live-caching=3000",       // Live stream cache
        "--sout-mux-caching=3000",   // Mux cache
        // "--quiet",                   // REMOVED: Enable logging for better error capture
        "--verbose=2",               // Enable verbose logging
        "--ignore-config",           // Ignore any VLC config
        plugin_arg.c_str(),
    };

    vlc_instance_ = fn_libvlc_new_(sizeof(vlc_args) / sizeof(vlc_args[0]), vlc_args);
    if (!vlc_instance_) {
        OutputDebugStringA("Failed to create VLC instance\n");
        return false;
    }

    // Create media player
    media_player_ = fn_libvlc_media_player_new_(vlc_instance_);
    if (!media_player_) {
        OutputDebugStringA("Failed to create media player\n");
        fn_libvlc_release_(vlc_instance_);
        vlc_instance_ = nullptr;
        return false;
    }

    // Attach event handlers
    libvlc_event_manager_t* event_manager = fn_libvlc_media_player_event_manager_(media_player_);
    if (event_manager) {
        fn_libvlc_event_attach_(event_manager, libvlc_MediaPlayerOpening, VlcEventCallback, this);
        fn_libvlc_event_attach_(event_manager, libvlc_MediaPlayerBuffering, VlcEventCallback, this);
        fn_libvlc_event_attach_(event_manager, libvlc_MediaPlayerPlaying, VlcEventCallback, this);
        fn_libvlc_event_attach_(event_manager, libvlc_MediaPlayerPaused, VlcEventCallback, this);
        fn_libvlc_event_attach_(event_manager, libvlc_MediaPlayerStopped, VlcEventCallback, this);
        fn_libvlc_event_attach_(event_manager, libvlc_MediaPlayerEndReached, VlcEventCallback, this);
        fn_libvlc_event_attach_(event_manager, libvlc_MediaPlayerEncounteredError, VlcEventCallback, this);
    }

    // CRITICAL: Create the child HWND immediately so it's ready before any Play().
    // This prevents VLC from creating its own top-level window.
    if (registrar_) {
        auto parent_view = registrar_->GetView();
        if (parent_view) {
            HWND parent = parent_view->GetNativeWindow();
            if (parent) {
                // Destroy any existing HWND first (should not exist at init)
                if (video_hwnd_) {
                    if (resize_delegate_id_ != 0) {
                        registrar_->UnregisterTopLevelWindowProcDelegate(resize_delegate_id_);
                        resize_delegate_id_ = 0;
                    }
                    DestroyWindow(video_hwnd_);
                    video_hwnd_ = nullptr;
                }

                // Get full client area for initial size
                RECT client_rect;
                GetClientRect(parent, &client_rect);
                video_full_parent_ = true;
                video_x_ = 0;
                video_y_ = 0;
                video_w_ = client_rect.right - client_rect.left;
                video_h_ = client_rect.bottom - client_rect.top;

                // Create child window for VLC rendering
                // CRITICAL: Use WS_EX_TRANSPARENT to allow Flutter overlays to render on top
                video_hwnd_ = CreateWindowExW(
                    WS_EX_TRANSPARENT,
                    L"STATIC",
                    nullptr,
                    WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
                    video_x_, video_y_, video_w_, video_h_,
                    parent, nullptr, GetModuleHandle(nullptr), nullptr);

                // CRITICAL: Position HWND at the bottom of z-order so Flutter renders on top
                if (video_hwnd_) {
                    SetWindowPos(video_hwnd_, HWND_BOTTOM, 0, 0, 0, 0, 
                        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                }

                if (video_hwnd_) {
                    // Prevent the child hwnd from stealing keyboard focus
                    LONG_PTR style = GetWindowLongPtr(video_hwnd_, GWL_STYLE);
                    style &= ~WS_TABSTOP; // Remove tab stop if present
                    SetWindowLongPtr(video_hwnd_, GWL_STYLE, style);

                    LONG_PTR exstyle = GetWindowLongPtr(video_hwnd_, GWL_EXSTYLE);
                    exstyle |= WS_EX_NOACTIVATE; // Prevent activation when clicked
                    SetWindowLongPtr(video_hwnd_, GWL_EXSTYLE, exstyle);

                    // Register resize delegate: use NOACTIVATE to avoid stealing focus
                    auto delegate = [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) -> std::optional<LRESULT> {
                        if (message == WM_SIZE) {
                            if (video_hwnd_ && video_full_parent_) {
                                RECT r;
                                GetClientRect(hwnd, &r);
                                SetWindowPos(video_hwnd_, nullptr, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOZORDER | SWP_NOACTIVATE);
                            }
                        }
                        return std::nullopt;
                    };
                    resize_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(delegate);

                    // CRITICAL: Set the HWND on the media player NOW before any Play() call
                    fn_libvlc_media_player_set_hwnd_(media_player_, reinterpret_cast<void*>(video_hwnd_));

                    // Ensure the Flutter parent retains keyboard focus
                    SetFocus(parent);

                    std::ostringstream oss;
                    oss << "[VLC] Initialize: child HWND created = 0x" << std::hex << reinterpret_cast<uintptr_t>(video_hwnd_)
                        << " (parent = 0x" << reinterpret_cast<uintptr_t>(parent) << ")";
                    OutputDebugStringA(oss.str().c_str());
                    OutputDebugStringA("\n");
                } else {
                    OutputDebugStringA("[VLC] WARNING: Failed to create child HWND in Initialize!\n");
                }
            } else {
                OutputDebugStringA("[VLC] WARNING: parent HWND is null in Initialize\n");
            }
        } else {
            OutputDebugStringA("[VLC] WARNING: no view from registrar in Initialize\n");
        }
    } else {
        OutputDebugStringA("[VLC] WARNING: registrar_ is null in Initialize\n");
    }

    initialized_ = true;
    OutputDebugStringA("[VLC] Initialized successfully\n");

    // Send initialized event
    flutter::EncodableMap data;
    data[flutter::EncodableValue("initialized")] = flutter::EncodableValue(true);
    SendEvent("initialized", data);

    return true;
}

bool VlcPlayerPlugin::Play(const std::string& url) {
    if (!initialized_ || !media_player_) {
        OutputDebugStringA("[VLC] Play failed: not initialized\n");
        return false;
    }

    // CRITICAL ASSERTION: video_hwnd_ MUST exist before Play
    // If it doesn't, VLC will create its own top-level window
    if (!video_hwnd_) {
        OutputDebugStringA("[VLC] ERROR: Play() called but video_hwnd_ is NULL! VLC will create external window!\n");
        // Attempt to create HWND now as fallback
        if (registrar_) {
            auto parent_view = registrar_->GetView();
            if (parent_view) {
                HWND parent = parent_view->GetNativeWindow();
                if (parent) {
                    RECT client_rect;
                    GetClientRect(parent, &client_rect);
                    video_full_parent_ = true;
                    video_x_ = 0;
                    video_y_ = 0;
                    video_w_ = client_rect.right - client_rect.left;
                    video_h_ = client_rect.bottom - client_rect.top;

                    // CRITICAL: Use WS_EX_TRANSPARENT for z-order
                    video_hwnd_ = CreateWindowExW(
                        WS_EX_TRANSPARENT,
                        L"STATIC",
                        nullptr,
                        WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
                        video_x_, video_y_, video_w_, video_h_,
                        parent, nullptr, GetModuleHandle(nullptr), nullptr);
                    
                    // Position at bottom of z-order
                    if (video_hwnd_) {
                        SetWindowPos(video_hwnd_, HWND_BOTTOM, 0, 0, 0, 0, 
                            SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                    }

                    if (video_hwnd_) {
                        // Prevent focus stealing
                        LONG_PTR style = GetWindowLongPtr(video_hwnd_, GWL_STYLE);
                        style &= ~WS_TABSTOP;
                        SetWindowLongPtr(video_hwnd_, GWL_STYLE, style);

                        LONG_PTR exstyle = GetWindowLongPtr(video_hwnd_, GWL_EXSTYLE);
                        exstyle |= WS_EX_NOACTIVATE;
                        SetWindowLongPtr(video_hwnd_, GWL_EXSTYLE, exstyle);

                        auto delegate = [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) -> std::optional<LRESULT> {
                            if (message == WM_SIZE) {
                                if (video_hwnd_ && video_full_parent_) {
                                    RECT r;
                                    GetClientRect(hwnd, &r);
                                    SetWindowPos(video_hwnd_, nullptr, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOZORDER | SWP_NOACTIVATE);
                                }
                            }
                            return std::nullopt;
                        };
                        resize_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(delegate);

                        // Ensure the Flutter parent retains keyboard focus
                        HWND parent_for_fallback = registrar_->GetView()->GetNativeWindow();
                        if (parent_for_fallback) {
                            SetFocus(parent_for_fallback);
                        }

                        std::ostringstream oss;
                        oss << "[VLC] Play: fallback HWND created = 0x" << std::hex << reinterpret_cast<uintptr_t>(video_hwnd_);
                        OutputDebugStringA(oss.str().c_str());
                        OutputDebugStringA("\n");
                    }
                }
            }
        }

        if (!video_hwnd_) {
            OutputDebugStringA("[VLC] FATAL: Could not create video_hwnd_, aborting Play to prevent external window!\n");
            return false;
        }
    }

    {
        std::ostringstream oss;
        oss << "[VLC] Play: video_hwnd_ = 0x" << std::hex << reinterpret_cast<uintptr_t>(video_hwnd_);
        OutputDebugStringA(oss.str().c_str());
        OutputDebugStringA("\n");
    }

    // CRITICAL: Stop current playback FIRST to prevent ghost audio
    Stop();

    // Create new media
    current_media_ = fn_libvlc_media_new_location_(vlc_instance_, url.c_str());
    if (!current_media_) {
        OutputDebugStringA(("Failed to create media for: " + url + "\n").c_str());
        return false;
    }

    // Add IPTV-friendly options
    fn_libvlc_media_add_option_(current_media_, ":network-caching=3000");
    fn_libvlc_media_add_option_(current_media_, ":live-caching=3000");
    fn_libvlc_media_add_option_(current_media_, ":clock-jitter=0");
    fn_libvlc_media_add_option_(current_media_, ":clock-synchro=0");

    // Set media on player
    fn_libvlc_media_player_set_media_(media_player_, current_media_);

    // Release media (player has its own reference)
    fn_libvlc_media_release_(current_media_);
    current_media_ = nullptr;

    // CRITICAL: ALWAYS set HWND before play - this is mandatory to prevent VLC
    // from creating its own window. Never pass nullptr here.
    {
        std::ostringstream oss;
        oss << "[VLC] Setting HWND on media_player before play: 0x" << std::hex << reinterpret_cast<uintptr_t>(video_hwnd_);
        OutputDebugStringA(oss.str().c_str());
        OutputDebugStringA("\n");
    }
    fn_libvlc_media_player_set_hwnd_(media_player_, reinterpret_cast<void*>(video_hwnd_));

    // Start playback
    OutputDebugStringA("[VLC] Calling libvlc_media_player_play\n");
    int result = fn_libvlc_media_player_play_(media_player_);
    if (result != 0) {
        OutputDebugStringA("Failed to start playback\n");
        return false;
    }

    current_url_ = url;
    playing_ = true;

    OutputDebugStringA(("Playing: " + url + "\n").c_str());
    return true;
}

void VlcPlayerPlugin::Stop() {
    if (!media_player_) {
        return;
    }

    OutputDebugStringA("[VLC] Stopping playback (preventing ghost audio)\n");

    // CRITICAL: Stop immediately to kill all audio/video
    fn_libvlc_media_player_stop_(media_player_);

    // Re-set HWND after stop to ensure it's ready for next Play()
    // This is critical because VLC may internally reset video output state
    if (video_hwnd_) {
        fn_libvlc_media_player_set_hwnd_(media_player_, reinterpret_cast<void*>(video_hwnd_));
        std::ostringstream oss;
        oss << "[VLC] Stop: re-attached HWND = 0x" << std::hex << reinterpret_cast<uintptr_t>(video_hwnd_);
        OutputDebugStringA(oss.str().c_str());
        OutputDebugStringA("\n");

        // Ensure Flutter keeps focus
        HWND parent = GetParent(video_hwnd_);
        if (parent) {
            SetFocus(parent);
            OutputDebugStringA("[VLC] Stop: focus returned to parent\n");
        }
    }
    
    playing_ = false;
    current_url_.clear();

    // Send stopped event
    flutter::EncodableMap data;
    data[flutter::EncodableValue("state")] = flutter::EncodableValue("stopped");
    SendEvent("playbackState", data);
}

void VlcPlayerPlugin::Pause() {
    if (!media_player_) {
        return;
    }
    fn_libvlc_media_player_pause_(media_player_);
}

void VlcPlayerPlugin::SetVolume(int volume) {
    if (!media_player_) {
        OutputDebugStringA("[VLC] SetVolume: media_player_ is null!\n");
        return;
    }
    // VLC-style 2x volume (0-200%), libVLC natively supports 0-200
    volume = std::max(0, std::min(200, volume));
    
    {
        std::ostringstream oss;
        oss << "[VLC] SetVolume: requesting " << volume << "%";
        OutputDebugStringA(oss.str().c_str());
        OutputDebugStringA("\n");
    }
    
    // Set the volume
    fn_libvlc_audio_set_volume_(media_player_, volume);
    
    // CRITICAL: Verify the volume was actually applied
    int applied = fn_libvlc_audio_get_volume_(media_player_);
    {
        std::ostringstream oss;
        oss << "[VLC] SetVolume: applied = " << applied << "% (requested " << volume << "%)";
        OutputDebugStringA(oss.str().c_str());
        OutputDebugStringA("\n");
    }
}

int VlcPlayerPlugin::GetVolume() {
    if (!media_player_) {
        return 0;
    }
    return fn_libvlc_audio_get_volume_(media_player_);
}

void VlcPlayerPlugin::SetMute(bool mute) {
    if (!media_player_) {
        return;
    }
    fn_libvlc_audio_set_mute_(media_player_, mute ? 1 : 0);
}

bool VlcPlayerPlugin::GetMute() {
    if (!media_player_) {
        return false;
    }
    return fn_libvlc_audio_get_mute_(media_player_) != 0;
}

std::vector<std::pair<int, std::string>> VlcPlayerPlugin::GetAudioTracks() {
    std::vector<std::pair<int, std::string>> tracks;
    
    if (!media_player_) {
        OutputDebugStringA("[VLC] GetAudioTracks: media_player_ is null\n");
        return tracks;
    }

    // Check if we're playing first
    int is_playing = fn_libvlc_media_player_is_playing_(media_player_);
    OutputDebugStringA(("[VLC] GetAudioTracks: is_playing = " + std::to_string(is_playing) + "\n").c_str());

    // Get audio track count first
    int track_count = fn_libvlc_audio_get_track_count_(media_player_);
    OutputDebugStringA(("[VLC] GetAudioTracks: track_count = " + std::to_string(track_count) + "\n").c_str());

    libvlc_track_description_t* track_desc = fn_libvlc_audio_get_track_description_(media_player_);
    libvlc_track_description_t* current = track_desc;

    while (current) {
        std::string name = current->psz_name ? current->psz_name : "Unknown";
        OutputDebugStringA(("[VLC] GetAudioTracks: found track id=" + std::to_string(current->i_id) + " name=" + name + "\n").c_str());
        tracks.push_back({current->i_id, name});
        current = current->p_next;
    }

    if (track_desc) {
        fn_libvlc_track_description_list_release_(track_desc);
    }

    OutputDebugStringA(("[VLC] GetAudioTracks: returning " + std::to_string(tracks.size()) + " tracks\n").c_str());
    return tracks;
}

void VlcPlayerPlugin::SetAudioTrack(int track_id) {
    if (!media_player_) {
        return;
    }
    fn_libvlc_audio_set_track_(media_player_, track_id);
}

int VlcPlayerPlugin::GetAudioTrack() {
    if (!media_player_) {
        return -1;
    }
    return fn_libvlc_audio_get_track_(media_player_);
}

bool VlcPlayerPlugin::IsPlaying() {
    if (!media_player_) {
        return false;
    }
    return fn_libvlc_media_player_is_playing_(media_player_) != 0;
}

void VlcPlayerPlugin::Dispose() {
    OutputDebugStringA("Disposing VLC player\n");

    // Stop playback first
    if (media_player_) {
        fn_libvlc_media_player_stop_(media_player_);
        
        // Detach events
        libvlc_event_manager_t* event_manager = fn_libvlc_media_player_event_manager_(media_player_);
        if (event_manager) {
            fn_libvlc_event_detach_(event_manager, libvlc_MediaPlayerOpening, VlcEventCallback, this);
            fn_libvlc_event_detach_(event_manager, libvlc_MediaPlayerBuffering, VlcEventCallback, this);
            fn_libvlc_event_detach_(event_manager, libvlc_MediaPlayerPlaying, VlcEventCallback, this);
            fn_libvlc_event_detach_(event_manager, libvlc_MediaPlayerPaused, VlcEventCallback, this);
            fn_libvlc_event_detach_(event_manager, libvlc_MediaPlayerStopped, VlcEventCallback, this);
            fn_libvlc_event_detach_(event_manager, libvlc_MediaPlayerEndReached, VlcEventCallback, this);
            fn_libvlc_event_detach_(event_manager, libvlc_MediaPlayerEncounteredError, VlcEventCallback, this);
        }

        fn_libvlc_media_player_release_(media_player_);
        media_player_ = nullptr;
    }

    if (current_media_) {
        fn_libvlc_media_release_(current_media_);
        current_media_ = nullptr;
    }

    if (vlc_instance_) {
        fn_libvlc_release_(vlc_instance_);
        vlc_instance_ = nullptr;
    }

    // Destroy child HWND if present (stop and release must be done first)
    if (video_hwnd_) {
        // Unregister resize delegate if registered
        if (registrar_ && resize_delegate_id_ != 0) {
            registrar_->UnregisterTopLevelWindowProcDelegate(resize_delegate_id_);
            resize_delegate_id_ = 0;
        }

        DestroyWindow(video_hwnd_);
        video_hwnd_ = nullptr;
    }

    // Unload libraries
    if (vlc_lib_) {
        FreeLibrary(vlc_lib_);
        vlc_lib_ = nullptr;
    }
    if (vlccore_lib_) {
        FreeLibrary(vlccore_lib_);
        vlccore_lib_ = nullptr;
    }

    initialized_ = false;
    playing_ = false;

    OutputDebugStringA("VLC player disposed\n");
}

// Create a child HWND for VLC video rendering. If width/height are zero,
// attach to the full client area of the Flutter view.
bool VlcPlayerPlugin::AttachVideo(int x, int y, int width, int height) {
    if (!registrar_) {
        OutputDebugStringA("AttachVideo failed: registrar_ is null\n");
        return false;
    }

    // If an existing HWND exists, destroy it first (do not reuse)
    if (video_hwnd_) {
        if (resize_delegate_id_ != 0) {
            registrar_->UnregisterTopLevelWindowProcDelegate(resize_delegate_id_);
            resize_delegate_id_ = 0;
        }
        DestroyWindow(video_hwnd_);
        video_hwnd_ = nullptr;
    }

    auto parent_view = registrar_->GetView();
    if (!parent_view) {
        OutputDebugStringA("AttachVideo failed: no view from registrar_\n");
        return false;
    }

    HWND parent = parent_view->GetNativeWindow();
    if (!parent) {
        OutputDebugStringA("AttachVideo failed: parent HWND null\n");
        return false;
    }

    // Compute bounds - if width/height are zero, use full client area
    RECT client_rect;
    GetClientRect(parent, &client_rect);
    if (width == 0 || height == 0) {
        video_full_parent_ = true;
        video_x_ = 0;
        video_y_ = 0;
        video_w_ = client_rect.right - client_rect.left;
        video_h_ = client_rect.bottom - client_rect.top;
    } else {
        video_full_parent_ = false;
        video_x_ = x;
        video_y_ = y;
        video_w_ = width;
        video_h_ = height;
    }

    // Create child window
    // CRITICAL: Use WS_EX_TRANSPARENT so Flutter can render overlays on top
    video_hwnd_ = CreateWindowExW(
        WS_EX_TRANSPARENT,
        L"STATIC",
        nullptr,
        WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
        video_x_, video_y_, video_w_, video_h_,
        parent, nullptr, GetModuleHandle(nullptr), nullptr);

    if (!video_hwnd_) {
        OutputDebugStringA("AttachVideo failed: CreateWindowExW returned null\n");
        return false;
    }
    
    // CRITICAL: Position at bottom of z-order so Flutter overlays appear on top
    SetWindowPos(video_hwnd_, HWND_BOTTOM, 0, 0, 0, 0, 
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

    // Prevent child hwnd from stealing keyboard focus
    LONG_PTR style = GetWindowLongPtr(video_hwnd_, GWL_STYLE);
    style &= ~WS_TABSTOP; // remove tab stop if present
    SetWindowLongPtr(video_hwnd_, GWL_STYLE, style);

    LONG_PTR exstyle = GetWindowLongPtr(video_hwnd_, GWL_EXSTYLE);
    exstyle |= WS_EX_NOACTIVATE; // avoid activation
    SetWindowLongPtr(video_hwnd_, GWL_EXSTYLE, exstyle);

    // Register a resize delegate to keep the child HWND in sync with parent
    if (registrar_) {
        auto delegate = [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) -> std::optional<LRESULT> {
            if (message == WM_SIZE) {
                if (video_hwnd_ && video_full_parent_) {
                    RECT r;
                    GetClientRect(hwnd, &r);
                    SetWindowPos(video_hwnd_, nullptr, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOZORDER | SWP_NOACTIVATE);
                }
            }
            return std::nullopt;
        };
        resize_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(delegate);
    }

    // Ensure Flutter retains keyboard focus
    SetFocus(parent);

    OutputDebugStringA("AttachVideo: child HWND created and attached\n");
    return true;
}

void VlcPlayerPlugin::SetVideoBounds(int x, int y, int width, int height) {
    if (!video_hwnd_) {
        OutputDebugStringA("[VLC] SetVideoBounds: video_hwnd_ is null!\n");
        return;
    }

    // CRITICAL: Disable auto-resize when explicit bounds are set
    video_full_parent_ = false;
    video_x_ = x;
    video_y_ = y;
    video_w_ = width;
    video_h_ = height;

    {
        std::ostringstream oss;
        oss << "[VLC] SetVideoBounds: x=" << x << " y=" << y << " w=" << width << " h=" << height;
        OutputDebugStringA(oss.str().c_str());
        OutputDebugStringA("\n");
    }

    // CRITICAL: Use HWND_BOTTOM and avoid z-order changes during resize
    // This ensures Flutter overlays (dialogs, popups) ALWAYS render on top of video
    SetWindowPos(video_hwnd_, HWND_BOTTOM, x, y, width, height, SWP_NOACTIVATE);
    
    // Force the window to stay at bottom of z-order
    SetWindowPos(video_hwnd_, HWND_BOTTOM, 0, 0, 0, 0, 
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);

    // Ensure Flutter parent keeps focus
    HWND parent = GetParent(video_hwnd_);
    if (parent) {
        SetFocus(parent);
    }
}

void VlcPlayerPlugin::DetachVideo() {
    // Stop playback and release media before destroying HWND
    if (media_player_) {
        fn_libvlc_media_player_stop_(media_player_);
    }

    if (current_media_) {
        fn_libvlc_media_release_(current_media_);
        current_media_ = nullptr;
    }

    if (resize_delegate_id_ != 0 && registrar_) {
        registrar_->UnregisterTopLevelWindowProcDelegate(resize_delegate_id_);
        resize_delegate_id_ = 0;
    }

    if (video_hwnd_) {
        DestroyWindow(video_hwnd_);
        video_hwnd_ = nullptr;
    }

    OutputDebugStringA("DetachVideo: child HWND destroyed\n");
}

// Video memory callbacks (placeholder for texture rendering)
void* VlcPlayerPlugin::LockCallback(void* opaque, void** planes) {
    VlcPlayerPlugin* self = static_cast<VlcPlayerPlugin*>(opaque);
    self->frame_mutex_.lock();
    *planes = self->frame_buffer_.data();
    return nullptr;
}

void VlcPlayerPlugin::UnlockCallback(void* opaque, void* picture, void* const* planes) {
    VlcPlayerPlugin* self = static_cast<VlcPlayerPlugin*>(opaque);
    self->frame_ready_ = true;
    self->frame_mutex_.unlock();
}

void VlcPlayerPlugin::DisplayCallback(void* opaque, void* picture) {
    // Placeholder - would notify Flutter texture
}

unsigned VlcPlayerPlugin::FormatCallback(void** opaque, char* chroma, unsigned* width, unsigned* height, unsigned* pitches, unsigned* lines) {
    VlcPlayerPlugin* self = static_cast<VlcPlayerPlugin*>(*opaque);
    
    // Request BGRA format (compatible with Flutter texture)
    memcpy(chroma, "BGRA", 4);
    
    self->video_width_ = *width;
    self->video_height_ = *height;
    self->video_pitch_ = *width * 4;  // 4 bytes per pixel (BGRA)
    
    pitches[0] = self->video_pitch_;
    lines[0] = *height;
    
    // Allocate frame buffer
    std::lock_guard<std::mutex> lock(self->frame_mutex_);
    self->frame_buffer_.resize(self->video_pitch_ * self->video_height_);
    
    return 1;  // 1 buffer
}

void VlcPlayerPlugin::CleanupCallback(void* opaque) {
    VlcPlayerPlugin* self = static_cast<VlcPlayerPlugin*>(opaque);
    std::lock_guard<std::mutex> lock(self->frame_mutex_);
    self->frame_buffer_.clear();
    self->video_width_ = 0;
    self->video_height_ = 0;
}

// VLC event callback
void VlcPlayerPlugin::VlcEventCallback(const void* event_ptr, void* user_data) {
    VlcPlayerPlugin* self = static_cast<VlcPlayerPlugin*>(user_data);
    
    // Simple event struct for type extraction
    struct SimpleEvent { int type; };
    const SimpleEvent* event = static_cast<const SimpleEvent*>(event_ptr);
    
    flutter::EncodableMap data;
    std::string event_name = "playbackState";
    
    switch (event->type) {
        case libvlc_MediaPlayerOpening:
            data[flutter::EncodableValue("state")] = flutter::EncodableValue("opening");
            break;
        case libvlc_MediaPlayerBuffering:
            data[flutter::EncodableValue("state")] = flutter::EncodableValue("buffering");
            break;
        case libvlc_MediaPlayerPlaying:
            data[flutter::EncodableValue("state")] = flutter::EncodableValue("playing");
            self->playing_ = true;
            break;
        case libvlc_MediaPlayerPaused:
            data[flutter::EncodableValue("state")] = flutter::EncodableValue("paused");
            break;
        case libvlc_MediaPlayerStopped:
            data[flutter::EncodableValue("state")] = flutter::EncodableValue("stopped");
            self->playing_ = false;
            break;
        case libvlc_MediaPlayerEndReached:
            data[flutter::EncodableValue("state")] = flutter::EncodableValue("ended");
            self->playing_ = false;
            break;
        case libvlc_MediaPlayerEncounteredError: {
            // VLC handles errors internally - we just notify UI
            // DO NOT surface decoder errors - let VLC handle them silently
            event_name = "error";
            
            // Try to get specific error message from libVLC
            const char* msg = nullptr;
            if (self->fn_libvlc_errmsg_) {
                msg = self->fn_libvlc_errmsg_();
            }
            
            if (msg) {
                data[flutter::EncodableValue("error")] = flutter::EncodableValue(std::string(msg));
            } else {
                data[flutter::EncodableValue("error")] = flutter::EncodableValue("playback_error");
            }
            data[flutter::EncodableValue("recoverable")] = flutter::EncodableValue(true);
            break;
        }
        default:
            return;  // Ignore other events
    }
    
    self->SendEvent(event_name, data);
}

void VlcPlayerPlugin::SendEvent(const std::string& event_name, const flutter::EncodableMap& data) {
    // If called from a non-platform thread, enqueue and post a message to the
    // platform window so events are dispatched on the platform thread.
    {
        std::lock_guard<std::mutex> lock(pending_events_mutex_);
        pending_events_.push_back({event_name, data});
    }

    if (registrar_) {
        auto view = registrar_->GetView();
        if (view) {
            HWND hwnd = view->GetNativeWindow();
            if (hwnd) {
                // Use a custom WM_APP message to notify platform thread
                PostMessage(hwnd, WM_APP + 0x100, 0, 0);
                return;
            }
        }
    }

    // Fallback: dispatch directly if we couldn't post to platform window
    std::lock_guard<std::mutex> lock(event_sink_mutex_);
    if (event_sink_) {
        flutter::EncodableMap event_data = data;
        event_data[flutter::EncodableValue("event")] = flutter::EncodableValue(event_name);
        event_sink_->Success(flutter::EncodableValue(event_data));
    }
}

void VlcPlayerPlugin::DispatchPendingEvents() {
    // Use the global plugin instance to access instance members from the
    // platform thread with thread-safe access.
    std::lock_guard<std::mutex> plugin_lock(g_plugin_mutex);
    if (!g_plugin) return;

    std::vector<std::pair<std::string, flutter::EncodableMap>> events;
    {
        std::lock_guard<std::mutex> lock(pending_events_mutex_);
        events.swap(pending_events_);
    }

    std::lock_guard<std::mutex> lock(g_plugin->event_sink_mutex_);
    if (!g_plugin->event_sink_) return;

    for (const auto& p : events) {
        flutter::EncodableMap event_data = p.second;
        event_data[flutter::EncodableValue("event")] = flutter::EncodableValue(p.first);
        g_plugin->event_sink_->Success(flutter::EncodableValue(event_data));
    }
}

}  // namespace vlc_player

# Chillz: Cross-Platform IPTV Solution 📺

**Chillz** is a modern, high-performance IPTV streaming project designed to provide a premium TV experience across **Windows Desktop**, **Web Browsers**, and **Mobile Devices**.

It solves the common problem of unreliable free streams by using different robust playback technologies tailored for each platform, with a focus on stability, performance, and user experience.

---

## 📂 Project Structure

This repository contains three distinct applications:

### 1. [Chillz Desktop](./chillz_desktop/) (Windows & Linux)
-   **Technology**: Flutter + C++ (Direct libVLC Integration with VLC Command Thread).
-   **Platforms**: Windows 10/11, Linux (Ubuntu/Debian/Fedora).
-   **What it is**: A native desktop application that embeds the VLC media engine directly into the window with a dedicated worker thread for non-blocking playback.
-   **Why use it**: Best for stability and compatibility. Typical web browsers block many IPTV streams (CORS, mixed content, codecs), but the Desktop app plays **everything** that VLC plays without UI freezing.
-   **Key Tech**: Custom native plugins for Windows (HWND) and Linux (GTK), VLC command thread architecture, low-level event loop bridging.
-   **Recent Improvements**: Implemented dedicated VLC command thread to eliminate UI freezes during stream switching and slow network conditions. Full Linux support added with self-contained packaging (.deb, .tar.gz, AppImage support).
-   **Downloads**: See [releases](./chillz_desktop/README.md#-downloads) for pre-built packages.

### 2. [Chillz Browser](./chillz_browser/) (Web Client)
-   **Technology**: React 19 + TypeScript + Vite 7.
-   **What it is**: A lightweight, instant-access web player using HLS.js.
-   **Why use it**: Accessibility. No install required, runs on any device (Mobile, Tablet, Laptop) instantly.
-   **Key Tech**: Virtualized channel lists (8,000+ items), client-side stream diagnosis, PWA support.

### 3. [Chillz App](./chillz_app/) (Flutter Mobile/TV)
-   **Technology**: Flutter (Cross-platform).
-   **What it is**: Mobile and Android TV application with platform-specific optimizations.
-   **Why use it**: Native mobile experience with TV remote support and touch-optimized UI.
-   **Key Tech**: Platform channels, adaptive UI for different screen sizes.

---

## 🎯 Shared Goals

All projects share the same design philosophy:

-   **Premium UI**: Glassmorphism, smooth animations, and zero clutter.
-   **Massive Content**: Integration with publicly available IPTV-ORG playlists (8,000+ channels).
-   **User Control**: Advanced filtering (Country, Language, Category) and instant search.
-   **Diagnostics**: Tools to help users understand *why* a stream might fail (Geo-blocking, 404s, etc.).
-   **Performance**: Non-blocking architecture ensures UI remains responsive even with slow/broken streams.

---

## 🚀 Getting Started

### Quick Downloads

#### Chillz Desktop v1.0.0
| Platform | Package | Size | Installation |
|----------|---------|------|--------------|
| **Linux (Debian/Ubuntu)** | `.deb` | 6.7 MB | `sudo apt install ./chillz-desktop_1.0.0_amd64.deb` |
| **Linux (Portable)** | `.tar.gz` | 18 MB | Extract and run `./run.sh` |
| **Windows** | `.msi` | ~40 MB | Run installer |

### Development Setup

To run the specific applications, navigate to their respective directories and follow the README instructions therein:

-   **Desktop**: `cd chillz_desktop` - Full VLC integration for Windows & Linux
-   **Web**: `cd chillz_browser` - Instant browser-based player
-   **Mobile/TV**: `cd chillz_app` - Flutter mobile and TV app

---

## 🏗️ Architecture Highlights

### Desktop (Windows & Linux)
- **VLC Command Thread**: All blocking VLC operations run on a dedicated worker thread
- **Non-blocking UI**: Platform channel calls return immediately, preventing UI freezes
- **Native Rendering**: 
  - Windows: Direct video rendering via child HWND
  - Linux: GTK integration with native window embedding
- **Event-driven**: Thread-safe event dispatch (PostMessage on Windows, g_idle_add on Linux)
- **Self-contained**: All packages include bundled VLC libraries for maximum compatibility
- **Distribution Formats**: 
  - Linux: .deb, .tar.gz, AppImage, .rpm
  - Windows: MSI installer, portable ZIP

### Browser (Web)
- **HLS.js Integration**: Polyfills native HLS support for non-Safari browsers
- **Virtual Scrolling**: Handles 8,000+ channels with 60fps performance
- **Client-side Only**: No backend required, fully static deployment

### Mobile/TV (Flutter)
- **Platform Channels**: Native integration for optimal performance
- **Adaptive UI**: Responsive layouts for phones, tablets, and TV screens
- **Remote Control**: Full D-pad and remote button support for Android TV

---

## 🤝 Contributing

We welcome contributions! Please read our [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) before contributing.

### How to Contribute
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is open source. Please check individual subprojects for specific licensing information.

---

## 🙏 Acknowledgments

- **VLC Media Player** - For the robust libVLC library
- **IPTV-ORG** - For maintaining the comprehensive channel database
- **HLS.js** - For enabling HLS playback in browsers
- **Flutter Team** - For the excellent cross-platform framework

---

## 📧 Contact

For questions, issues, or suggestions, please open an issue on GitHub.

---

**Built with ❤️ for the IPTV community**

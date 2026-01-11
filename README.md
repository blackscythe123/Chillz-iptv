# Chillz: Cross-Platform IPTV Solution 📺

**Chillz** is a modern, high-performance IPTV streaming project designed to provide a premium TV experience across both **Windows Desktop** and **Web Browsers**.

It solves the common problem of unreliable free streams by using different robust playback technologies tailored for each platform.

---

## 📂 Project Structure

This repository contains two distinct applications:

### 1. [Chillz Desktop](./chillz_desktop/) (Native Windows)
-   **Technology**: Flutter + C++ (Direct libVLC Integration).
-   **What it is**: A native Windows application that embeds the VLC media engine directly into the window.
-   **Why use it**: Best for stability and compatibility. typical web browsers block many IPTV streams (CORS, mixed content, codecs), but the Desktop app plays **everything** that VLC plays.
-   **Key Tech**: Custom C++ plugin for HWND management, low-level event loop bridging.

### 2. [Chillz Browser](./chillz_browser/) (Web Client)
-   **Technology**: React 19 + TypeScript + Vite 7.
-   **What it is**: A lightweight, instant-access web player using HLS.js.
-   **Why use it**: Accessibility. No install required, runs on any device (Mobile, Tablet, Laptop) instantly.
-   **Key Tech**: Virtualized channel lists (8,000+ items), client-side stream diagnosis.

---

## 🎯 Shared Goals

Both projects share the same design philosophy:

-   **Premium UI**: Glassmorphism, smooth animations, and zero clutter.
-   **Massive Content**: Integration with publicly available IPTV-ORG playlists (8,000+ channels).
-   **User Control**: Advanced filtering (Country, Language, Category) and instant search.
-   **Diagnostics**: Tools to help users understand *why* a stream might fail (Geo-blocking, 404s, etc.).

---

## 🚀 Getting Started

To run the specific applications, navigate to their respective directories and follow the README instructions therein:

-   **Desktop**: `cd chillz_desktop`
-   **Web**: `cd chillz_browser`

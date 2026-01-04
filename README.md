# Chillz — TV, but Chill 📺

A **100% client-side** IPTV web application built with React, TypeScript, and Vite. Chillz loads IPTV channel data directly in the browser and plays browser-compatible streams without any server, backend, or proxy requests.

## ✨ Features

### Core Playback
- **HLS.js Integration** — Plays HLS streams natively in the browser
- **Quality Selection** — Manual quality level switching (Auto, 1080p, 720p, etc.)
- **Audio Track Selection** — Switch between available audio tracks
- **Picture-in-Picture** — Floating player support
- **Fullscreen Mode** — Native fullscreen with keyboard shortcuts
- **Auto-hide Controls** — Controls fade after 3 seconds of inactivity

### Channel Management
- **Virtualized List** — Smooth scrolling for thousands of channels using @tanstack/react-virtual
- **Favorites** — Star channels, persisted in localStorage
- **Watch History** — Tracks recently played channels (last 50)
- **Hide Channels** — Remove unwanted channels from view
- **Search** — Real-time fuzzy search across channel names
- **Filters** — Category and country dropdowns

### Stream Diagnostics
- **Real-time Stats** — Bitrate, buffer length, dropped frames, latency
- **Error Recovery** — Automatic retry with exponential backoff
- **Broken Stream Reporting** — Report non-working streams (stored locally)
- **VLC Fallback** — Copy `vlc://` link for external playback

### UI/UX
- **Responsive Design** — Desktop sidebar + mobile bottom-sheet filters
- **Dark Theme** — Easy on the eyes for extended viewing
- **Loading Skeletons** — Visual feedback during channel loading
- **Keyboard Shortcuts** — Space (play/pause), F (fullscreen), M (mute), Arrows (seek/volume)

## 🏗️ Architecture

```
100% CLIENT-SIDE — No server requests for data or streams

┌─────────────────────────────────────────────────────────┐
│                      BROWSER                            │
├─────────────────────────────────────────────────────────┤
│  React App                                              │
│  ├── Loads /data/channels-global.json (bundled)        │
│  ├── Plays HLS streams via HLS.js                      │
│  ├── Stores preferences in localStorage                 │
│  └── No external API calls                              │
└─────────────────────────────────────────────────────────┘
```

### Tech Stack
- **React 18** — UI framework with hooks
- **TypeScript** — Type safety
- **Vite** — Lightning-fast dev server and build
- **HLS.js** — HLS stream playback
- **@tanstack/react-virtual** — Virtualized list rendering
- **Lucide React** — Beautiful icons
- **localStorage** — Persistent favorites, history, hidden channels

## 📁 Project Structure

```
chillz/
├── public/
│   └── data/
│       └── channels-global.json    # Static channel metadata
├── src/
│   ├── components/
│   │   ├── VideoPlayer.tsx         # Full-featured video player
│   │   ├── ChannelList.tsx         # Virtualized channel list
│   │   ├── Filters.tsx             # Search + category/country filters
│   │   └── Disclaimer.tsx          # First-run legal disclaimer
│   ├── hooks/
│   │   ├── usePlayer.ts            # HLS.js integration hook
│   │   └── useChannels.ts          # Channel loading + utilities
│   ├── utils/
│   │   └── storage.ts              # localStorage helpers
│   ├── types/
│   │   └── channel.ts              # TypeScript interfaces
│   ├── App.tsx                     # Main application layout
│   ├── App.css                     # Application styles
│   └── main.tsx                    # Entry point
└── package.json
```

## 🚀 Getting Started

### Prerequisites
- Node.js 18+
- npm or yarn

### Installation

```bash
# Clone the repository
git clone <repo-url>
cd chillz

# Install dependencies
npm install

# Start development server
npm run dev
```

The app will be available at `http://localhost:5173`

### Production Build

```bash
# Build for production
npm run build

# Preview production build
npm run preview
```

## 📺 Channel Data Format

Channels are loaded from `/public/data/channels-global.json`:

```json
{
  "channels": [
    {
      "id": "unique-id",
      "name": "Channel Name",
      "logo": "https://example.com/logo.png",
      "url": "https://example.com/stream.m3u8",
      "category": "News",
      "country": "United States",
      "language": "English"
    }
  ]
}
```

### Adding Your Own Channels

1. Edit `public/data/channels-global.json`
2. Add channel objects with required fields: `id`, `name`, `url`
3. Optional fields: `logo`, `category`, `country`, `language`
4. The app will automatically load the new channels

## ⌨️ Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Space` | Play / Pause |
| `F` | Toggle Fullscreen |
| `M` | Mute / Unmute |
| `←` / `→` | Seek -10s / +10s |
| `↑` / `↓` | Volume Up / Down |
| `Esc` | Exit Fullscreen |

## ⚠️ Legal Disclaimer

Chillz is a **client-side player only**. It does not:
- Host or provide any streams
- Proxy or restream any content
- Bypass DRM or geo-restrictions
- Store any copyrighted material

Users are solely responsible for the content they access. Ensure you have the right to view any streams you add to the application.

## 🛠️ Development

### Available Scripts

```bash
npm run dev       # Start dev server
npm run build     # Production build
npm run preview   # Preview production build
npm run lint      # Run ESLint
```

### Adding New Features

1. **Components** go in `src/components/`
2. **Hooks** go in `src/hooks/`
3. **Types** go in `src/types/`
4. **Utilities** go in `src/utils/`

## 📄 License

MIT License — See LICENSE file for details

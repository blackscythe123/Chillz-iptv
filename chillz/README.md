# Chillz — TV, but Chill 📺

A 100% client-side IPTV streaming web app using **8,585+ channels** from [iptv-org](https://iptv-org.github.io/) with HLS.js support.

## Features

✨ **Core Streaming**
- Live TV from 200+ countries
- 8,585+ channels with logos and metadata
- HLS/M3U8 stream support via HLS.js
- Audio track selection and quality switching

🎯 **Smart Filtering**
- Search channels in real-time
- Filter by category, country, and language
- Searchable dropdowns (type-to-filter)
- Favorites & watch history

🎮 **Player Controls**
- Play/Pause, Volume, Mute
- Quality & audio track selection
- Fullscreen & Picture-in-Picture (PiP)
- Stream diagnostics (resolution, bitrate, codec)
- VLC fallback for unsupported streams

🧠 **Stream Health Detection**
- Auto-detects VLC-only streams (codec issues)
- Identifies offline/dead streams
- Helpful error messages
- 30-second timeout handling

📱 **Responsive Design**
- Desktop & mobile optimized
- Virtual scrolling for smooth 8K+ channel lists
- Bottom-sheet filters on mobile

## Tech Stack

- **React 19** + **TypeScript** + **Vite 7**
- **HLS.js** for stream playback
- **@tanstack/react-virtual** for efficient list rendering
- **Lucide React** for icons
- **iptv-org API** for channel data (channels, streams, logos, languages, countries, categories)

## Getting Started

```bash
# Install dependencies
npm install

# Development server (http://localhost:5173)
npm run dev

# Production build
npm run build

# Preview build
npm run preview
```

## Deployment on Vercel

### Option 1: Git Push (Recommended)

1. Push this repo to GitHub
2. Connect repo at [vercel.com/new](https://vercel.com/new)
3. Vercel auto-detects Vite and deploys automatically
4. Your app is live in ~1 minute!

### Option 2: Vercel CLI

```bash
npm install -g vercel
vercel
```

## Browser Support

- Chrome/Edge 90+
- Firefox 88+
- Safari 14+
- Mobile browsers (iOS Safari 14+, Android Chrome)

## API Data Sources

All data comes from **iptv-org**:
- `channels.json` - Channel metadata
- `streams.json` - Stream URLs & quality
- `logos.json` - Channel logos
- `categories.json` - Channel categories
- `countries.json` - Country info & languages
- `languages.json` - Language codes

Data is cached in localStorage with 1-hour TTL.

## Known Limitations

- **HTTPS streams only** - Browser blocks HTTP streams on HTTPS pages (VLC can still play them)
- **CORS requirements** - Stream servers must allow CORS or be proxied
- **HLS codec support** - Some streams with unusual codecs only play in VLC
- **No playback on muted autoplay** - Browser policy restricts non-interactive audio

## Troubleshooting

**"Status: idle" in diagnostics?**
- Browser is blocking mixed-content (HTTPS app + HTTP stream)
- Try VLC player instead, or check CORS headers on stream server

**"VLC-Only" status?**
- Stream has video codec browser can't decode
- Works fine in VLC player
- Try different quality/audio track if available

**Stream keeps buffering?**
- Network too slow for current quality
- Auto quality or select lower resolution
- Check browser network tab for timeouts

## License

This project is not affiliated with iptv-org. Uses their public API data.

---

**Enjoy reliable TV streaming! 📺✨**

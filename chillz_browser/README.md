# Chillz Browser (React 19 + Vite 7) 📺

**Chillz Browser** is a blazing fast, client-side IPTV player designed for maximum accessibility. It brings the Chillz experience to any device with a web browser.

It is built to handle the massive 8,000+ channel lists of IPTV-ORG efficiently using modern virtualization techniques and provides instant access without installation.

---

## 🏛️ Architecture Deep Dive

This application operates entirely client-side (no backend required):

### 1. Core Stack
-   **Vite 7**: Next-generation bundler for instant dev start and optimized production builds.
-   **React 19**: Utilizing the latest React features for concurrent rendering and improved performance.
-   **TypeScript**: Full type safety for the complex IPTV data models.
-   **Modern Build**: Tree-shaking, code-splitting, and optimized chunks for fast loading.

### 2. Stream Playback (HLS.js)
The browser cannot natively play `.m3u8` (HLS) streams (except Safari). We use **HLS.js** to polyfill this capability.

-   **Integration**: Wrapped in a custom `<Player />` component with error boundaries.
-   **Quality Control**: Manually exposes ABR (Adaptive Bitrate) controls to the UI.
-   **Error Handling**: Catches network/decoding errors and advises the user (often suggesting VLC for unsupported codecs).
-   **Buffer Management**: Real-time monitoring of buffer health and bandwidth.

### 3. Data & State
-   **Data Source**: Fetches JSON directly from `iptv-org` GitHub raw endpoints.
-   **Virtualization**: Uses `@tanstack/react-virtual` to render the 8,000+ channel list. Only the ~20 visible items are in the DOM at any moment, ensuring 60fps scrolling even on mobile.
-   **Persistence**: Uses `localStorage` to cache the massive JSON payloads (TTL 1 hour) to save bandwidth and startup time.
-   **Search Optimization**: Debounced search with indexed filtering for instant results.

---

## ⚠️ Technical Limitations (vs Desktop)

The Web is a sandboxed environment, which introduces limits that the Desktop app does not have:

1.  **Mixed Content Blocking**:
    -   *Problem*: If the app is hosted on HTTPS (e.g., Vercel), the browser BLOCKS any stream URL that is HTTP.
    -   *Solution*: We filter for HTTPS streams or warn users. The Desktop app has no such limit.

2.  **CORS (Cross-Origin Resource Sharing)**:
    -   *Problem*: The browser blocks requests to video servers that don't send `Access-Control-Allow-Origin` headers.
    -   *Solution*: We can only play "modern" streams. Legacy streams often fail here.

3.  **Codec Support**:
    -   *Problem*: Browsers natively support limited video codecs (H.264, VP9). Many IPTV streams use old MPEG-TS or raw UDP.
    -   *Solution*: We detect these failures and show a "Open in VLC" prompt.

4.  **Network Restrictions**:
    -   *Problem*: Browser security policies prevent low-level network access.
    -   *Solution*: Cannot handle UDP streams or custom protocols.

---

## ✨ Key Features

-   **Instant Search**: Filter 8000+ channels in milliseconds using optimized local indexing.
-   **Stream Diagnostics**: Real-time view of Buffer Health, Bandwidth, and Resolution.
-   **PWA Ready**: Can be installed to the home screen on iOS/Android for app-like experience.
-   **Responsive Design**: Works seamlessly on desktop, tablet, and mobile devices.
-   **Dark Mode**: Beautiful dark theme with glassmorphism effects.
-   **Keyboard Shortcuts**: Space (play/pause), F (fullscreen), M (mute).

---

## 🛠️ Development Setup

### Prerequisites
-   Node.js 20+ (LTS recommended)
-   npm or yarn package manager

### Usage

```bash
# Install dependencies
npm install

# Start Dev Server (http://localhost:5173)
npm run dev

# Build for Production
npm run build

# Preview Production Build
npm run preview

# Type Check
npm run type-check

# Lint
npm run lint
```

### Deployment
This is a static site. It can be deployed anywhere:

-   **Vercel**: `vercel deploy` (recommended)
-   **Netlify**: Drag & drop `dist/` folder
-   **GitHub Pages**: Push `dist/` to `gh-pages` branch
-   **AWS S3**: Upload `dist/` to S3 bucket with static hosting

**Note**: Ensure your host supports `rewrite` rules if you use client-side routing (though this is mostly a single-page app).

---

## 📁 Project Structure

```
chillz_browser/
├── src/
│   ├── components/       # React components
│   ├── hooks/            # Custom React hooks
│   ├── utils/            # Utility functions
│   ├── types/            # TypeScript type definitions
│   ├── App.tsx           # Main app component
│   └── main.tsx          # Entry point
├── public/               # Static assets
├── index.html            # HTML template
├── vite.config.ts        # Vite configuration
├── tsconfig.json         # TypeScript configuration
└── package.json
```

---

## 🎨 UI/UX Highlights

-   **Glassmorphism**: Modern frosted glass effects for cards and overlays
-   **Smooth Animations**: 60fps transitions and micro-interactions
-   **Accessibility**: Keyboard navigation, ARIA labels, semantic HTML
-   **Performance**: Virtual scrolling, lazy loading, code splitting

---

## 🚀 Performance Optimizations

1.  **Virtual Scrolling**: Only renders visible items (20 out of 8000+)
2.  **Code Splitting**: Routes and heavy components loaded on demand
3.  **Asset Optimization**: Images compressed, fonts subset
4.  **Caching Strategy**: localStorage for data, service worker for assets (PWA)
5.  **Bundle Analysis**: Tree-shaking removes unused code

---

## 🤝 Contributing

Contributions are welcome! Please ensure:
1. TypeScript types are properly defined
2. Components are properly memoized where needed
3. Accessibility standards are maintained
4. Performance is not degraded

---

## 📄 License

See root project LICENSE file.

---

**Built with ❤️ using React and modern web technologies**

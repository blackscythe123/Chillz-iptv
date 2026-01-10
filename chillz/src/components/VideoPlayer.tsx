import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import {
  Play,
  Pause,
  Volume2,
  VolumeX,
  Maximize,
  Minimize,
  PictureInPicture2,
  Settings,
  AlertCircle,
  RefreshCw,
  ExternalLink,
  Copy,
  Check,
  Loader2,
  Activity,
  Headphones
} from 'lucide-react';
import { usePlayer } from '../hooks/usePlayer';
import type { Channel, PlayerState, StreamDiagnostics } from '../types/channel';
import './VideoPlayer.css';

interface VideoPlayerProps {
  channel: Channel | null;
  onReportBroken?: (channelId: string, reason: string) => void;
}

export function VideoPlayer({ channel, onReportBroken }: VideoPlayerProps) {
  // Memoize options to prevent unnecessary re-renders
  const playerOptions = useMemo(() => ({
    referrer: channel?.referrer,
    userAgent: channel?.userAgent
  }), [channel?.referrer, channel?.userAgent]);

  const {
    videoRef,
    state,
    error,
    diagnostics,
    volume,
    muted,
    isFullscreen,
    isPiP,
    qualityLevels,
    currentQuality,
    audioTracks,
    currentAudioTrack,
    togglePlay,
    setVolume,
    toggleMute,
    toggleFullscreen,
    togglePiP,
    setQuality,
    setAudioTrack,
    retry
  } = usePlayer(channel?.url || null, playerOptions);

  const [showControls, setShowControls] = useState(true);
  const [showSettings, setShowSettings] = useState(false);
  const [showDiagnostics, setShowDiagnostics] = useState(false);
  const [copied, setCopied] = useState(false);
  const controlsTimeoutRef = useRef<number | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  // Auto-hide controls
  const resetControlsTimeout = useCallback(() => {
    if (controlsTimeoutRef.current) {
      clearTimeout(controlsTimeoutRef.current);
    }
    setShowControls(true);
    if (state === 'playing') {
      controlsTimeoutRef.current = window.setTimeout(() => {
        setShowControls(false);
        setShowSettings(false);
      }, 3000);
    }
  }, [state]);

  useEffect(() => {
    resetControlsTimeout();
    return () => {
      if (controlsTimeoutRef.current) {
        clearTimeout(controlsTimeoutRef.current);
      }
    };
  }, [state, resetControlsTimeout]);

  const handleMouseMove = () => {
    resetControlsTimeout();
  };

  const handleCopyUrl = async () => {
    if (channel?.url) {
      await navigator.clipboard.writeText(channel.url);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    }
  };

  const handleOpenVLC = () => {
    if (channel?.url) {
      // Try multiple VLC URL protocols for better compatibility
      // vlc:// works on some systems, intent:// on Android, and direct link as fallback
      const vlcUrl = channel.url;
      
      // For desktop browsers, try the vlc:// protocol
      // This works if VLC is installed and registered as protocol handler
      const vlcProtocolUrl = `vlc://${vlcUrl}`;
      
      // Create a temporary link and try to open
      const link = document.createElement('a');
      link.href = vlcProtocolUrl;
      link.style.display = 'none';
      document.body.appendChild(link);
      
      // Try to detect if protocol handler exists
      const startTime = Date.now();
      
      // Set up fallback - if the protocol handler doesn't work,
      // show a helpful message with the URL
      const fallbackTimeout = setTimeout(() => {
        const elapsed = Date.now() - startTime;
        if (elapsed < 2500) {
          // Protocol handler likely didn't work
          // Show copy URL option
          const copyUrl = window.confirm(
            'VLC protocol may not be supported in your browser.\n\n' +
            'Would you like to copy the stream URL to paste into VLC?\n\n' +
            'In VLC: Media → Open Network Stream → Paste URL'
          );
          if (copyUrl) {
            navigator.clipboard.writeText(vlcUrl).then(() => {
              alert('Stream URL copied to clipboard!\n\nOpen VLC → Media → Open Network Stream → Paste');
            });
          }
        }
      }, 2000);
      
      // Try to open VLC
      window.location.href = vlcProtocolUrl;
      
      // Clean up
      setTimeout(() => {
        document.body.removeChild(link);
        clearTimeout(fallbackTimeout);
      }, 3000);
    }
  };

  const handleReport = () => {
    if (channel && onReportBroken) {
      onReportBroken(channel.id, error || 'Stream not working');
    }
  };

  if (!channel) {
    return (
      <div className="video-player video-player--empty">
        <div className="video-player__placeholder">
          <div className="video-player__logo">📺</div>
          <h2>Chillz</h2>
          <p>TV, but Chill</p>
          <p className="video-player__hint">Select a channel to start watching</p>
        </div>
      </div>
    );
  }

  return (
    <div 
      ref={containerRef}
      className={`video-player ${isFullscreen ? 'video-player--fullscreen' : ''}`}
      onMouseMove={handleMouseMove}
      onMouseLeave={() => state === 'playing' && setShowControls(false)}
    >
      <video
        ref={videoRef}
        className="video-player__video"
        playsInline
        onClick={togglePlay}
      />

      {/* Loading Overlay */}
      {state === 'loading' && (
        <div className="video-player__overlay video-player__overlay--loading">
          <Loader2 className="video-player__spinner" />
          <p>Loading stream...</p>
        </div>
      )}

      {/* Buffering Overlay */}
      {state === 'buffering' && (
        <div className="video-player__overlay video-player__overlay--buffering">
          <Loader2 className="video-player__spinner" />
          <p>Buffering...</p>
        </div>
      )}

      {/* Error Overlay */}
      {state === 'error' && (
        <div className="video-player__overlay video-player__overlay--error">
          <AlertCircle className="video-player__error-icon" />
          <h3>Playback Error</h3>
          <p>{error || 'Unable to play this stream'}</p>
          <div className="video-player__error-actions">
            <button onClick={retry} className="btn btn--primary">
              <RefreshCw size={16} /> Retry
            </button>
            <button onClick={handleOpenVLC} className="btn btn--secondary">
              <ExternalLink size={16} /> Open in VLC
            </button>
            <button onClick={handleReport} className="btn btn--ghost">
              Report Broken
            </button>
          </div>
        </div>
      )}

      {/* Channel Info */}
      <div className={`video-player__info ${showControls ? 'visible' : ''}`}>
        {channel.logo && (
          <img 
            src={channel.logo} 
            alt="" 
            className="video-player__channel-logo"
            onError={(e) => (e.currentTarget.style.display = 'none')}
          />
        )}
        <div className="video-player__channel-details">
          <h3>{channel.name}</h3>
          <span>{channel.categoryName} • {channel.countryFlag} {channel.countryName}{channel.quality ? ` • ${channel.quality}` : ''}</span>
        </div>
      </div>

      {/* Controls */}
      <div className={`video-player__controls ${showControls ? 'visible' : ''}`}>
        <div className="video-player__controls-left">
          <button 
            onClick={togglePlay} 
            className="video-player__btn"
            title={state === 'playing' ? 'Pause' : 'Play'}
          >
            {state === 'playing' ? <Pause size={24} /> : <Play size={24} />}
          </button>

          <div className="video-player__volume">
            <button 
              onClick={toggleMute} 
              className="video-player__btn"
              title={muted ? 'Unmute' : 'Mute'}
            >
              {muted || volume === 0 ? <VolumeX size={20} /> : <Volume2 size={20} />}
            </button>
            <input
              type="range"
              min="0"
              max="1"
              step="0.1"
              value={muted ? 0 : volume}
              onChange={(e) => setVolume(parseFloat(e.target.value))}
              className="video-player__volume-slider"
            />
          </div>
        </div>

        <div className="video-player__controls-right">
          <button 
            onClick={() => setShowDiagnostics(!showDiagnostics)}
            className={`video-player__btn ${showDiagnostics ? 'active' : ''}`}
            title="Diagnostics"
          >
            <Activity size={20} />
          </button>

          {audioTracks.length > 1 && (
            <div className="video-player__audio-selector">
              <button 
                className="video-player__btn"
                title="Audio Track"
              >
                <Headphones size={20} />
              </button>
              <select 
                value={currentAudioTrack}
                onChange={(e) => setAudioTrack(parseInt(e.target.value))}
                className="video-player__audio-select"
                title="Select audio track"
              >
                {audioTracks.map((track) => (
                  <option key={track.index} value={track.index}>
                    {track.name} {track.lang ? `(${track.lang})` : ''}
                  </option>
                ))}
              </select>
            </div>
          )}

          {qualityLevels.length > 1 && (
            <div className="video-player__quality-selector">
              <button 
                className="video-player__btn"
                title="Quality"
              >
                {currentQuality === -1 ? '⚙' : `${qualityLevels[currentQuality]?.height || 'Auto'}p`}
              </button>
              <select 
                value={currentQuality}
                onChange={(e) => setQuality(parseInt(e.target.value))}
                className="video-player__quality-select"
                title="Select quality"
              >
                <option value={-1}>Auto</option>
                {qualityLevels.map((level) => (
                  <option key={level.index} value={level.index}>
                    {level.height}p ({Math.round(level.bitrate / 1000)} kbps)
                  </option>
                ))}
              </select>
            </div>
          )}

          <button 
            onClick={handleCopyUrl}
            className="video-player__btn"
            title="Copy URL"
          >
            {copied ? <Check size={20} /> : <Copy size={20} />}
          </button>

          <button 
            onClick={() => setShowSettings(!showSettings)}
            className={`video-player__btn ${showSettings ? 'active' : ''}`}
            title="Settings"
          >
            <Settings size={20} />
          </button>

          {document.pictureInPictureEnabled && (
            <button 
              onClick={togglePiP}
              className={`video-player__btn ${isPiP ? 'active' : ''}`}
              title="Picture in Picture"
            >
              <PictureInPicture2 size={20} />
            </button>
          )}

          <button 
            onClick={toggleFullscreen}
            className="video-player__btn"
            title={isFullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
          >
            {isFullscreen ? <Minimize size={20} /> : <Maximize size={20} />}
          </button>
        </div>
      </div>

      {/* Settings Panel */}
      {showSettings && (
        <div className="video-player__settings">
          <div className="video-player__settings-header">
            <h4>Settings</h4>
            <button 
              onClick={() => setShowSettings(false)}
              className="video-player__settings-close"
            >
              ✕
            </button>
          </div>

          <div className="video-player__settings-content">
            {qualityLevels.length > 1 && (
              <div className="video-player__settings-section">
                <label className="video-player__settings-label">Quality</label>
                <select 
                  value={currentQuality}
                  onChange={(e) => setQuality(parseInt(e.target.value))}
                  className="video-player__settings-select"
                >
                  <option value={-1}>Auto (Recommended)</option>
                  {qualityLevels.map((level) => (
                    <option key={level.index} value={level.index}>
                      {level.height}p ({Math.round(level.bitrate / 1000)} kbps)
                    </option>
                  ))}
                </select>
              </div>
            )}

            {audioTracks.length > 1 && (
              <div className="video-player__settings-section">
                <label className="video-player__settings-label">Audio Track</label>
                <select 
                  value={currentAudioTrack}
                  onChange={(e) => setAudioTrack(parseInt(e.target.value))}
                  className="video-player__settings-select"
                >
                  {audioTracks.map((track) => (
                    <option key={track.index} value={track.index}>
                      {track.name} {track.lang ? `(${track.lang})` : ''}
                    </option>
                  ))}
                </select>
              </div>
            )}

            <div className="video-player__settings-section">
              <button onClick={handleOpenVLC} className="btn btn--full btn--secondary">
                <ExternalLink size={16} /> Open in VLC
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Diagnostics Panel */}
      {showDiagnostics && (
        <DiagnosticsPanel diagnostics={diagnostics} state={state} />
      )}
    </div>
  );
}

function DiagnosticsPanel({ diagnostics, state }: { diagnostics: StreamDiagnostics; state: PlayerState }) {
  const statusLabel = diagnostics.streamStatus && diagnostics.streamStatus !== 'normal'
    ? `${state} • ${diagnostics.streamStatus}`
    : state;

  return (
    <div className="video-player__diagnostics">
      <h4>Stream Diagnostics</h4>
      <div className="diagnostics-grid">
        <div className="diagnostics-item">
          <span className="diagnostics-label">Status</span>
          <span className={`diagnostics-value status-${state}`}>{statusLabel}</span>
        </div>
        <div className="diagnostics-item">
          <span className="diagnostics-label">Resolution</span>
          <span className="diagnostics-value">{diagnostics.resolution || 'N/A'}</span>
        </div>
        <div className="diagnostics-item">
          <span className="diagnostics-label">Bitrate</span>
          <span className="diagnostics-value">{diagnostics.bitrate || 'N/A'}</span>
        </div>
        <div className="diagnostics-item">
          <span className="diagnostics-label">Codec</span>
          <span className="diagnostics-value">{diagnostics.codec || 'N/A'}</span>
        </div>
        <div className="diagnostics-item">
          <span className="diagnostics-label">Buffer</span>
          <span className="diagnostics-value">{diagnostics.bufferLength}s</span>
        </div>
        <div className="diagnostics-item">
          <span className="diagnostics-label">Dropped Frames</span>
          <span className="diagnostics-value">{diagnostics.droppedFrames}</span>
        </div>
      </div>
    </div>
  );
}

export default VideoPlayer;

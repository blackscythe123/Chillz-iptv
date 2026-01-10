import { useRef, useEffect, useCallback, useState } from 'react';
import Hls from 'hls.js';
import type { PlayerState, StreamDiagnostics } from '../types/channel';

interface StreamOptions {
  referrer?: string | null;
  userAgent?: string | null;
}

interface UsePlayerResult {
  videoRef: React.RefObject<HTMLVideoElement | null>;
  state: PlayerState;
  error: string | null;
  diagnostics: StreamDiagnostics;
  currentTime: number;
  duration: number;
  volume: number;
  muted: boolean;
  isFullscreen: boolean;
  isPiP: boolean;
  qualityLevels: { index: number; height: number; bitrate: number }[];
  currentQuality: number;
  audioTracks: { index: number; name: string; lang: string }[];
  currentAudioTrack: number;
  play: () => void;
  pause: () => void;
  togglePlay: () => void;
  setVolume: (vol: number) => void;
  toggleMute: () => void;
  seek: (time: number) => void;
  toggleFullscreen: () => void;
  togglePiP: () => void;
  setQuality: (index: number) => void;
  setAudioTrack: (index: number) => void;
  retry: () => void;
}

export function usePlayer(url: string | null, options?: StreamOptions): UsePlayerResult {
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const hlsRef = useRef<Hls | null>(null);
  const retryCountRef = useRef(0);
  const manifestLoadedRef = useRef(false);
  const segmentRequestsRef = useRef(0);
  const fragLoadErrorsRef = useRef(0);
  const loadingTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const playbackStartedRef = useRef(false);
  const maxRetries = 3;
  const loadingTimeoutMs = 30000; // 30 second timeout for loading
  
  const [state, setState] = useState<PlayerState>('idle');
  const [error, setError] = useState<string | null>(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolumeState] = useState(1);
  const [muted, setMuted] = useState(false);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [isPiP, setIsPiP] = useState(false);
  const [qualityLevels, setQualityLevels] = useState<{ index: number; height: number; bitrate: number }[]>([]);
  const [currentQuality, setCurrentQuality] = useState(-1);
  const [audioTracks, setAudioTracks] = useState<{ index: number; name: string; lang: string }[]>([]);
  const [currentAudioTrack, setCurrentAudioTrack] = useState(0);
  const [diagnostics, setDiagnostics] = useState<StreamDiagnostics>({
    codec: '',
    resolution: '',
    bitrate: '',
    bufferLength: 0,
    droppedFrames: 0,
    latency: 0,
    errors: [],
    streamStatus: 'normal'
  });

  const setStreamStatus = useCallback((status: StreamDiagnostics['streamStatus'], reason?: string) => {
    setDiagnostics(prev => ({
      ...prev,
      streamStatus: status,
      errors: reason ? [...prev.errors.slice(-4), reason].slice(-5) : prev.errors
    }));
  }, []);

  const destroyHls = useCallback(() => {
    if (loadingTimeoutRef.current) {
      clearTimeout(loadingTimeoutRef.current);
      loadingTimeoutRef.current = null;
    }
    if (hlsRef.current) {
      hlsRef.current.destroy();
      hlsRef.current = null;
    }
  }, []);

  const tryAutoPlay = useCallback(async (video: HTMLVideoElement) => {
    try {
      // Try playing with sound first
      await video.play();
      setState('playing');
    } catch {
      try {
        // If blocked, try muted autoplay
        video.muted = true;
        setMuted(true);
        await video.play();
        setState('playing');
      } catch {
        // Autoplay completely blocked, wait for user interaction
        setState('idle');
      }
    }
  }, []);

  const initPlayer = useCallback(() => {
    const video = videoRef.current;
    if (!video || !url) return;

    destroyHls();
    setState('loading');
    setError(null);
    retryCountRef.current = 0;
    playbackStartedRef.current = false;
    manifestLoadedRef.current = false;
    segmentRequestsRef.current = 0;
    fragLoadErrorsRef.current = 0;
    setDiagnostics(prev => ({
      ...prev,
      streamStatus: 'normal'
    }));

    // Set loading timeout - if stream doesn't start within timeout, show error
    loadingTimeoutRef.current = setTimeout(() => {
      // Check if playback has started using the ref (closure-safe)
      if (!playbackStartedRef.current) {
        setError('Stream timeout - server not responding or stream offline. Try another channel.');
        setState('error');
        setStreamStatus('offline', 'manifestLoadTimeout');
        destroyHls();
      }
    }, loadingTimeoutMs);

    // Check if it's an HLS stream
    const isHls = url.includes('.m3u8') || url.includes('m3u8');
    
    if (isHls && Hls.isSupported()) {
      // Configure HLS.js with proper settings
      const hlsConfig: Partial<Hls['config']> = {
        enableWorker: true,
        lowLatencyMode: false,
        backBufferLength: 90,
        maxBufferLength: 30,
        maxMaxBufferLength: 600,
        maxBufferSize: 60 * 1000 * 1000, // 60 MB
        maxBufferHole: 0.5,
        startLevel: -1, // Auto quality
        capLevelToPlayerSize: true,
        debug: false, // Set to true for troubleshooting
        // Progressive loading for better compatibility
        progressive: true,
        // Fragment loading settings
        fragLoadingTimeOut: 20000,
        fragLoadingMaxRetry: 6,
        fragLoadingRetryDelay: 1000,
        // Manifest loading settings  
        manifestLoadingTimeOut: 10000,
        manifestLoadingMaxRetry: 4,
        manifestLoadingRetryDelay: 1000,
        // Level loading settings
        levelLoadingTimeOut: 10000,
        levelLoadingMaxRetry: 4,
        levelLoadingRetryDelay: 1000,
      };

      // Add custom headers via xhrSetup if needed
      if (options?.referrer || options?.userAgent) {
        hlsConfig.xhrSetup = (xhr: XMLHttpRequest) => {
          // Note: Some headers can't be set due to browser security
          // but we try anyway for compatibility
          if (options.userAgent) {
            try {
              xhr.setRequestHeader('User-Agent', options.userAgent);
            } catch {
              // Ignore - browser may block this
            }
          }
        };
      }
      
      const hls = new Hls(hlsConfig);
      hlsRef.current = hls;
      
      hls.on(Hls.Events.MEDIA_ATTACHED, () => {
        console.log('[HLS] Media attached, loading source:', url);
        hls.loadSource(url);
      });

      hls.on(Hls.Events.MANIFEST_PARSED, (_, data) => {
        console.log('[HLS] Manifest parsed, levels:', data.levels.length);
        manifestLoadedRef.current = true;
        setStreamStatus('normal');
        const levels = data.levels.map((level, index) => ({
          index,
          height: level.height || 0,
          bitrate: level.bitrate || 0
        }));
        setQualityLevels(levels);
        
        // Set initial quality info
        if (levels.length > 0) {
          const firstLevel = data.levels[0];
          setDiagnostics(prev => ({
            ...prev,
            resolution: firstLevel.width && firstLevel.height 
              ? `${firstLevel.width}x${firstLevel.height}` 
              : 'Auto',
            codec: firstLevel.codecSet || firstLevel.videoCodec || ''
          }));
        }
        
        // Try to play
        tryAutoPlay(video);
      });

      hls.on(Hls.Events.FRAG_LOADED, () => {
        // Fragment loaded successfully - stream is working
        segmentRequestsRef.current += 1;
        // Check if video is playing and update state
        setTimeout(() => {
          if (videoRef.current && !videoRef.current.paused && videoRef.current.readyState >= 3) {
            setStreamStatus('normal');
            setState('playing');
          }
        }, 100);
      });

      hls.on(Hls.Events.LEVEL_SWITCHED, (_, data) => {
        setCurrentQuality(data.level);
        const level = hls.levels[data.level];
        if (level) {
          setDiagnostics(prev => ({
            ...prev,
            resolution: level.width && level.height 
              ? `${level.width}x${level.height}` 
              : prev.resolution,
            bitrate: level.bitrate 
              ? `${Math.round(level.bitrate / 1000)} kbps` 
              : prev.bitrate,
            codec: level.codecSet || level.videoCodec || prev.codec
          }));
        }
      });

      hls.on(Hls.Events.AUDIO_TRACKS_UPDATED, (_, data) => {
        const tracks = data.audioTracks.map((track, index) => ({
          index,
          name: track.name || `Track ${index + 1}`,
          lang: track.lang || 'unknown'
        }));
        setAudioTracks(tracks);
      });

      hls.on(Hls.Events.AUDIO_TRACK_SWITCHED, (_, data) => {
        setCurrentAudioTrack(data.id);
      });

      hls.on(Hls.Events.ERROR, (_, data) => {
        console.error('[HLS] Error:', data.type, data.details, data.fatal);
        const details = data.details;

        // Detect VLC-only vs offline states
        if (details === Hls.ErrorDetails.MANIFEST_LOAD_TIMEOUT || details === Hls.ErrorDetails.MANIFEST_LOAD_ERROR) {
          setStreamStatus('offline', details);
        }

        if (details === Hls.ErrorDetails.FRAG_LOAD_ERROR) {
          fragLoadErrorsRef.current += 1;
          if (!manifestLoadedRef.current || segmentRequestsRef.current === 0 || fragLoadErrorsRef.current >= 2) {
            setStreamStatus('offline', 'fragLoadError');
          }
        }

        if (
          manifestLoadedRef.current &&
          segmentRequestsRef.current > 0 &&
          (details === Hls.ErrorDetails.FRAG_PARSING_ERROR || data.type === Hls.ErrorTypes.MEDIA_ERROR || details === Hls.ErrorDetails.MANIFEST_INCOMPATIBLE_CODECS_ERROR)
        ) {
          setStreamStatus('vlc-only', details);
        }
        
        if (data.fatal) {
          switch (data.type) {
            case Hls.ErrorTypes.NETWORK_ERROR:
              console.log('[HLS] Network error, attempting recovery...');
              if (retryCountRef.current < maxRetries) {
                retryCountRef.current++;
                hls.startLoad();
              } else {
                setError(`Network error - stream unavailable (${data.details})`);
                setState('error');
                setStreamStatus('offline', data.details);
              }
              break;
            case Hls.ErrorTypes.MEDIA_ERROR:
              console.log('[HLS] Media error, attempting recovery...');
              hls.recoverMediaError();
              break;
            default:
              setError(`Stream error: ${data.details}`);
              setState('error');
              setStreamStatus('offline', data.details);
              destroyHls();
          }
        } else {
          // Non-fatal error, just log it
          setDiagnostics(prev => ({
            ...prev,
            errors: [...prev.errors.slice(-4), data.details].slice(-5)
          }));
        }
      });

      hls.attachMedia(video);
      
    } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
      // Native HLS support (Safari, iOS)
      console.log('[Player] Using native HLS support');
      video.src = url;
      video.load();
      tryAutoPlay(video);
      
    } else if (!isHls) {
      // Direct video file (mp4, webm, etc.)
      console.log('[Player] Direct video source');
      video.src = url;
      video.load();
      tryAutoPlay(video);
      
    } else {
      setError('HLS playback is not supported in this browser');
      setState('error');
    }
  }, [url, options?.referrer, options?.userAgent, destroyHls, tryAutoPlay, setStreamStatus]);

  // Initialize player when URL changes
  useEffect(() => {
    if (url) {
      initPlayer();
    } else {
      destroyHls();
      setState('idle');
    }

    return () => {
      destroyHls();
    };
  }, [url, initPlayer, destroyHls]);

  // Video event listeners
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    const onPlay = () => {
      // Mark playback as started and clear loading timeout
      playbackStartedRef.current = true;
      if (loadingTimeoutRef.current) {
        clearTimeout(loadingTimeoutRef.current);
        loadingTimeoutRef.current = null;
      }
      setState('playing');
    };
    const onPause = () => setState(prev => prev === 'error' ? 'error' : 'idle');
    const onWaiting = () => setState('buffering');
    const onPlaying = () => {
      // Mark playback as started and clear loading timeout
      playbackStartedRef.current = true;
      if (loadingTimeoutRef.current) {
        clearTimeout(loadingTimeoutRef.current);
        loadingTimeoutRef.current = null;
      }
      setState('playing');
    };
    const onTimeUpdate = () => setCurrentTime(video.currentTime);
    const onDurationChange = () => setDuration(video.duration);
    const onVolumeChange = () => {
      setVolumeState(video.volume);
      setMuted(video.muted);
    };
    const onError = () => {
      setError('Playback error');
      setState('error');
    };
    const onEnterPiP = () => setIsPiP(true);
    const onLeavePiP = () => setIsPiP(false);

    video.addEventListener('play', onPlay);
    video.addEventListener('pause', onPause);
    video.addEventListener('waiting', onWaiting);
    video.addEventListener('playing', onPlaying);
    video.addEventListener('timeupdate', onTimeUpdate);
    video.addEventListener('durationchange', onDurationChange);
    video.addEventListener('volumechange', onVolumeChange);
    video.addEventListener('error', onError);
    video.addEventListener('enterpictureinpicture', onEnterPiP);
    video.addEventListener('leavepictureinpicture', onLeavePiP);

    return () => {
      video.removeEventListener('play', onPlay);
      video.removeEventListener('pause', onPause);
      video.removeEventListener('waiting', onWaiting);
      video.removeEventListener('playing', onPlaying);
      video.removeEventListener('timeupdate', onTimeUpdate);
      video.removeEventListener('durationchange', onDurationChange);
      video.removeEventListener('volumechange', onVolumeChange);
      video.removeEventListener('error', onError);
      video.removeEventListener('enterpictureinpicture', onEnterPiP);
      video.removeEventListener('leavepictureinpicture', onLeavePiP);
    };
  }, []);

  // Fullscreen change listener
  useEffect(() => {
    const onFullscreenChange = () => {
      setIsFullscreen(!!document.fullscreenElement);
    };

    document.addEventListener('fullscreenchange', onFullscreenChange);
    return () => document.removeEventListener('fullscreenchange', onFullscreenChange);
  }, []);

  // Update diagnostics periodically
  useEffect(() => {
    if (state !== 'playing') return;

    const interval = setInterval(() => {
      const video = videoRef.current;
      if (!video) return;

      const buffered = video.buffered;
      const bufferLength = buffered.length > 0 
        ? buffered.end(buffered.length - 1) - video.currentTime 
        : 0;

      setDiagnostics(prev => ({
        ...prev,
        bufferLength: Math.round(bufferLength * 10) / 10,
        droppedFrames: (video as HTMLVideoElement & { webkitDroppedFrameCount?: number }).webkitDroppedFrameCount || 0
      }));
    }, 1000);

    return () => clearInterval(interval);
  }, [state]);

  const play = useCallback(() => {
    videoRef.current?.play().catch(() => {});
  }, []);

  const pause = useCallback(() => {
    videoRef.current?.pause();
  }, []);

  const togglePlay = useCallback(() => {
    const video = videoRef.current;
    if (!video) return;
    if (video.paused) {
      video.play().catch(() => {});
    } else {
      video.pause();
    }
  }, []);

  const setVolume = useCallback((vol: number) => {
    if (videoRef.current) {
      videoRef.current.volume = Math.max(0, Math.min(1, vol));
    }
  }, []);

  const toggleMute = useCallback(() => {
    if (videoRef.current) {
      videoRef.current.muted = !videoRef.current.muted;
    }
  }, []);

  const seek = useCallback((time: number) => {
    if (videoRef.current) {
      videoRef.current.currentTime = time;
    }
  }, []);

  const toggleFullscreen = useCallback(async () => {
    const container = videoRef.current?.parentElement;
    if (!container) return;

    if (document.fullscreenElement) {
      await document.exitFullscreen();
    } else {
      await container.requestFullscreen();
    }
  }, []);

  const togglePiP = useCallback(async () => {
    const video = videoRef.current;
    if (!video) return;

    if (document.pictureInPictureElement) {
      await document.exitPictureInPicture();
    } else if (document.pictureInPictureEnabled) {
      await video.requestPictureInPicture();
    }
  }, []);

  const setQuality = useCallback((index: number) => {
    if (hlsRef.current) {
      hlsRef.current.currentLevel = index;
    }
  }, []);

  const setAudioTrack = useCallback((index: number) => {
    if (hlsRef.current) {
      hlsRef.current.audioTrack = index;
    }
  }, []);

  const retry = useCallback(() => {
    initPlayer();
  }, [initPlayer]);

  return {
    videoRef,
    state,
    error,
    diagnostics,
    currentTime,
    duration,
    volume,
    muted,
    isFullscreen,
    isPiP,
    qualityLevels,
    currentQuality,
    audioTracks,
    currentAudioTrack,
    play,
    pause,
    togglePlay,
    setVolume,
    toggleMute,
    seek,
    toggleFullscreen,
    togglePiP,
    setQuality,
    setAudioTrack,
    retry
  };
}

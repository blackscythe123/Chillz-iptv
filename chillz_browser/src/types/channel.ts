// iptv-org API types
export interface IPTVChannel {
  id: string;
  name: string;
  alt_names: string[];
  network: string | null;
  owners: string[];
  country: string;
  categories: string[];
  is_nsfw: boolean;
  launched: string | null;
  closed: string | null;
  replaced_by: string | null;
  website: string | null;
}

export interface IPTVStream {
  channel: string | null;
  feed: string | null;
  title: string;
  url: string;
  referrer: string | null;
  user_agent: string | null;
  quality: string | null;
}

export interface IPTVLogo {
  channel: string;
  feed: string | null;
  tags: string[];
  width: number;
  height: number;
  format: string | null;
  url: string;
}

export interface IPTVCategory {
  id: string;
  name: string;
  description: string;
}

export interface IPTVCountry {
  name: string;
  code: string;
  languages: string[];
  flag: string;
}

export interface IPTVLanguage {
  name: string;
  code: string;
}

export interface LanguageOption {
  code: string;
  name: string;
}

// Merged channel for display
export interface Channel {
  id: string;
  name: string;
  country: string;
  countryName: string;
  countryFlag: string;
  category: string;
  categoryName: string;
  categories: string[];
  logo: string;
  url: string;
  quality: string | null;
  languages: string[];
  languageNames: string[];
  isNsfw: boolean;
  network: string | null;
  website: string | null;
  referrer: string | null;
  userAgent: string | null;
}

export interface ChannelChunk {
  name: string;
  path: string;
  loaded: boolean;
}

export type PlayerState = 'idle' | 'loading' | 'playing' | 'buffering' | 'error' | 'audio-only';

export interface StreamDiagnostics {
  codec: string;
  resolution: string;
  bitrate: string;
  bufferLength: number;
  droppedFrames: number;
  latency: number;
  errors: string[];
  streamStatus: 'normal' | 'vlc-only' | 'offline';
}

export interface BrokenReport {
  channelId: string;
  timestamp: number;
  reason: string;
}


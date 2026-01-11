import { useState, useEffect, useCallback } from 'react';
import type { 
  Channel, 
  IPTVChannel, 
  IPTVStream, 
  IPTVLogo, 
  IPTVCategory, 
  IPTVCountry,
  IPTVLanguage 
} from '../types/channel';

interface UseChannelsResult {
  channels: Channel[];
  loading: boolean;
  error: string | null;
  progress: string;
}

// iptv-org API endpoints
const API_BASE = 'https://iptv-org.github.io/api';
const ENDPOINTS = {
  channels: `${API_BASE}/channels.json`,
  streams: `${API_BASE}/streams.json`,
  logos: `${API_BASE}/logos.json`,
  categories: `${API_BASE}/categories.json`,
  countries: `${API_BASE}/countries.json`,
  languages: `${API_BASE}/languages.json`,
};

// Cache keys for localStorage
const CACHE_KEY = 'chillz_api_cache';
const CACHE_TIMESTAMP_KEY = 'chillz_api_cache_timestamp';
const CACHE_DURATION = 1000 * 60 * 60; // 1 hour

interface CachedData {
  channels: IPTVChannel[];
  streams: IPTVStream[];
  logos: IPTVLogo[];
  categories: IPTVCategory[];
  countries: IPTVCountry[];
  languages: IPTVLanguage[];
}

function getCachedData(): CachedData | null {
  try {
    const timestamp = localStorage.getItem(CACHE_TIMESTAMP_KEY);
    if (!timestamp) return null;
    
    const cacheTime = parseInt(timestamp, 10);
    if (Date.now() - cacheTime > CACHE_DURATION) {
      localStorage.removeItem(CACHE_KEY);
      localStorage.removeItem(CACHE_TIMESTAMP_KEY);
      return null;
    }
    
    const data = localStorage.getItem(CACHE_KEY);
    return data ? JSON.parse(data) : null;
  } catch {
    return null;
  }
}

function setCachedData(data: CachedData): void {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify(data));
    localStorage.setItem(CACHE_TIMESTAMP_KEY, Date.now().toString());
  } catch {
    // Ignore storage errors (quota exceeded, etc.)
  }
}

export function useChannels(): UseChannelsResult {
  const [channels, setChannels] = useState<Channel[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [progress, setProgress] = useState('Initializing...');

  useEffect(() => {
    let cancelled = false;

    async function loadChannels() {
      try {
        setLoading(true);
        
        // Check cache first
        const cached = getCachedData();
        if (cached) {
          setProgress('Loading from cache...');
          const merged = mergeData(cached);
          if (!cancelled) {
            setChannels(merged);
            setLoading(false);
          }
          return;
        }

        // Fetch all data from API
        setProgress('Fetching channels...');
        const channelsRes = await fetch(ENDPOINTS.channels);
        if (!channelsRes.ok) throw new Error('Failed to fetch channels');
        const channelsData: IPTVChannel[] = await channelsRes.json();
        if (cancelled) return;

        setProgress('Fetching streams...');
        const streamsRes = await fetch(ENDPOINTS.streams);
        if (!streamsRes.ok) throw new Error('Failed to fetch streams');
        const streamsData: IPTVStream[] = await streamsRes.json();
        if (cancelled) return;

        setProgress('Fetching logos...');
        const logosRes = await fetch(ENDPOINTS.logos);
        if (!logosRes.ok) throw new Error('Failed to fetch logos');
        const logosData: IPTVLogo[] = await logosRes.json();
        if (cancelled) return;

        setProgress('Fetching categories...');
        const categoriesRes = await fetch(ENDPOINTS.categories);
        if (!categoriesRes.ok) throw new Error('Failed to fetch categories');
        const categoriesData: IPTVCategory[] = await categoriesRes.json();
        if (cancelled) return;

        setProgress('Fetching countries...');
        const countriesRes = await fetch(ENDPOINTS.countries);
        if (!countriesRes.ok) throw new Error('Failed to fetch countries');
        const countriesData: IPTVCountry[] = await countriesRes.json();
        if (cancelled) return;

        setProgress('Fetching languages...');
        const languagesRes = await fetch(ENDPOINTS.languages);
        if (!languagesRes.ok) throw new Error('Failed to fetch languages');
        const languagesData: IPTVLanguage[] = await languagesRes.json();
        if (cancelled) return;

        // Cache the raw data
        const rawData: CachedData = {
          channels: channelsData,
          streams: streamsData,
          logos: logosData,
          categories: categoriesData,
          countries: countriesData,
          languages: languagesData,
        };
        setCachedData(rawData);

        setProgress('Processing data...');
        const merged = mergeData(rawData);
        
        if (!cancelled) {
          setChannels(merged);
          setError(null);
        }
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : 'Failed to load channels');
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    loadChannels();

    return () => {
      cancelled = true;
    };
  }, []);

  return { channels, loading, error, progress };
}

function mergeData(data: CachedData): Channel[] {
  const { channels, streams, logos, categories, countries, languages } = data;
  
  // Create lookup maps
  const logoMap = new Map<string, string>();
  for (const logo of logos) {
    // Prefer main logos (no feed) or first logo found
    if (!logoMap.has(logo.channel) || !logo.feed) {
      logoMap.set(logo.channel, logo.url);
    }
  }

  const categoryMap = new Map<string, string>();
  for (const cat of categories) {
    categoryMap.set(cat.id, cat.name);
  }

  const countryMap = new Map<string, { name: string; flag: string; languages: string[] }>();
  for (const country of countries) {
    countryMap.set(country.code, { name: country.name, flag: country.flag, languages: country.languages });
  }

  const languageMap = new Map<string, string>();
  for (const lang of languages) {
    languageMap.set(lang.code, lang.name);
  }

  // Create stream lookup by channel ID
  const streamMap = new Map<string, IPTVStream>();
  for (const stream of streams) {
    if (stream.channel && stream.url) {
      // Keep first stream found for each channel (or best quality)
      if (!streamMap.has(stream.channel)) {
        streamMap.set(stream.channel, stream);
      }
    }
  }

  // Merge channels with streams
  const mergedChannels: Channel[] = [];
  
  for (const channel of channels) {
    // Skip NSFW and closed channels
    if (channel.is_nsfw || channel.closed) continue;
    
    const stream = streamMap.get(channel.id);
    if (!stream) continue; // Skip channels without streams
    
    const countryInfo = countryMap.get(channel.country) || { name: channel.country, flag: '🌐', languages: [] };
    const primaryCategory = channel.categories[0] || 'general';
    
    // Get language names from country's languages
    const channelLanguages = countryInfo.languages.map(code => languageMap.get(code) || code);
    
    mergedChannels.push({
      id: channel.id,
      name: channel.name,
      country: channel.country,
      countryName: countryInfo.name,
      countryFlag: countryInfo.flag,
      category: primaryCategory,
      categoryName: categoryMap.get(primaryCategory) || primaryCategory,
      categories: channel.categories,
      logo: logoMap.get(channel.id) || '',
      url: stream.url,
      quality: stream.quality,
      languages: countryInfo.languages,
      languageNames: channelLanguages,
      isNsfw: channel.is_nsfw,
      network: channel.network,
      website: channel.website,
      referrer: stream.referrer,
      userAgent: stream.user_agent,
    });
  }

  // Sort by name
  mergedChannels.sort((a, b) => a.name.localeCompare(b.name));
  
  return mergedChannels;
}

export function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => {
      setDebouncedValue(value);
    }, delay);

    return () => {
      clearTimeout(timer);
    };
  }, [value, delay]);

  return debouncedValue;
}

export function useLocalStorage<T>(key: string, initialValue: T): [T, (value: T | ((prev: T) => T)) => void] {
  const [storedValue, setStoredValue] = useState<T>(() => {
    try {
      const item = localStorage.getItem(key);
      return item ? JSON.parse(item) : initialValue;
    } catch {
      return initialValue;
    }
  });

  const setValue = useCallback((value: T | ((prev: T) => T)) => {
    setStoredValue(prev => {
      const newValue = value instanceof Function ? value(prev) : value;
      localStorage.setItem(key, JSON.stringify(newValue));
      return newValue;
    });
  }, [key]);

  return [storedValue, setValue];
}

export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() => {
    if (typeof window !== 'undefined') {
      return window.matchMedia(query).matches;
    }
    return false;
  });

  useEffect(() => {
    const mediaQuery = window.matchMedia(query);
    const handler = (event: MediaQueryListEvent) => setMatches(event.matches);
    
    mediaQuery.addEventListener('change', handler);
    return () => mediaQuery.removeEventListener('change', handler);
  }, [query]);

  return matches;
}

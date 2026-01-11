import type { Channel, BrokenReport } from '../types/channel';

const FAVORITES_KEY = 'chillz_favorites';
const HISTORY_KEY = 'chillz_history';
const BROKEN_KEY = 'chillz_broken';
const HIDDEN_KEY = 'chillz_hidden';
const DISCLAIMER_KEY = 'chillz_disclaimer_accepted';

const MAX_HISTORY = 50;

export function getFavorites(): string[] {
  try {
    const data = localStorage.getItem(FAVORITES_KEY);
    return data ? JSON.parse(data) : [];
  } catch {
    return [];
  }
}

export function setFavorites(ids: string[]): void {
  localStorage.setItem(FAVORITES_KEY, JSON.stringify(ids));
}

export function toggleFavorite(channelId: string): boolean {
  const favorites = getFavorites();
  const index = favorites.indexOf(channelId);
  if (index === -1) {
    favorites.unshift(channelId);
    setFavorites(favorites);
    return true;
  } else {
    favorites.splice(index, 1);
    setFavorites(favorites);
    return false;
  }
}

export function isFavorite(channelId: string): boolean {
  return getFavorites().includes(channelId);
}

export function getHistory(): string[] {
  try {
    const data = localStorage.getItem(HISTORY_KEY);
    return data ? JSON.parse(data) : [];
  } catch {
    return [];
  }
}

export function addToHistory(channelId: string): void {
  const history = getHistory().filter(id => id !== channelId);
  history.unshift(channelId);
  if (history.length > MAX_HISTORY) {
    history.pop();
  }
  localStorage.setItem(HISTORY_KEY, JSON.stringify(history));
}

export function clearHistory(): void {
  localStorage.removeItem(HISTORY_KEY);
}

export function getBrokenReports(): BrokenReport[] {
  try {
    const data = localStorage.getItem(BROKEN_KEY);
    return data ? JSON.parse(data) : [];
  } catch {
    return [];
  }
}

export function reportBroken(channelId: string, reason: string): void {
  const reports = getBrokenReports();
  reports.push({
    channelId,
    timestamp: Date.now(),
    reason
  });
  localStorage.setItem(BROKEN_KEY, JSON.stringify(reports));
}

export function getHiddenChannels(): string[] {
  try {
    const data = localStorage.getItem(HIDDEN_KEY);
    return data ? JSON.parse(data) : [];
  } catch {
    return [];
  }
}

export function hideChannel(channelId: string): void {
  const hidden = getHiddenChannels();
  if (!hidden.includes(channelId)) {
    hidden.push(channelId);
    localStorage.setItem(HIDDEN_KEY, JSON.stringify(hidden));
  }
}

export function unhideChannel(channelId: string): void {
  const hidden = getHiddenChannels().filter(id => id !== channelId);
  localStorage.setItem(HIDDEN_KEY, JSON.stringify(hidden));
}

export function isDisclaimerAccepted(): boolean {
  return localStorage.getItem(DISCLAIMER_KEY) === 'true';
}

export function acceptDisclaimer(): void {
  localStorage.setItem(DISCLAIMER_KEY, 'true');
}

export function filterChannels(
  channels: Channel[],
  search: string,
  category: string,
  country: string,
  favorites: string[],
  history: string[],
  hiddenChannels: string[],
  showFavoritesOnly: boolean,
  showHistoryOnly: boolean,
  showHidden: boolean
): Channel[] {
  let filtered = channels;
  
  // Filter hidden channels
  if (!showHidden) {
    filtered = filtered.filter(ch => !hiddenChannels.includes(ch.id));
  }
  
  // Filter by favorites
  if (showFavoritesOnly) {
    filtered = filtered.filter(ch => favorites.includes(ch.id));
  }
  
  // Filter by history
  if (showHistoryOnly) {
    filtered = filtered.filter(ch => history.includes(ch.id));
    // Sort by history order
    filtered.sort((a, b) => history.indexOf(a.id) - history.indexOf(b.id));
  }
  
  // Filter by search
  if (search.trim()) {
    const searchLower = search.toLowerCase();
    filtered = filtered.filter(ch =>
      ch.name.toLowerCase().includes(searchLower) ||
      ch.countryName.toLowerCase().includes(searchLower) ||
      ch.categoryName.toLowerCase().includes(searchLower) ||
      (ch.network && ch.network.toLowerCase().includes(searchLower)) ||
      ch.languageNames.some(lang => lang.toLowerCase().includes(searchLower))
    );
  }
  
  // Filter by category
  if (category && category !== 'all') {
    filtered = filtered.filter(ch => 
      ch.category.toLowerCase() === category.toLowerCase() ||
      ch.categories.some(c => c.toLowerCase() === category.toLowerCase())
    );
  }
  
  // Filter by country
  if (country && country !== 'all') {
    filtered = filtered.filter(ch => ch.country.toLowerCase() === country.toLowerCase());
  }
  
  return filtered;
}

// Filter by language
export function filterByLanguage(channels: Channel[], language: string): Channel[] {
  if (!language || language === 'all') return channels;
  return channels.filter(ch => 
    ch.languages.some(lang => lang.toLowerCase() === language.toLowerCase())
  );
}

export function getUniqueCategories(channels: Channel[]): { id: string; name: string }[] {
  const categoryMap = new Map<string, string>();
  for (const ch of channels) {
    if (!categoryMap.has(ch.category)) {
      categoryMap.set(ch.category, ch.categoryName);
    }
  }
  return Array.from(categoryMap.entries())
    .map(([id, name]) => ({ id, name }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

export function getUniqueCountries(channels: Channel[]): { code: string; name: string; flag: string }[] {
  const countryMap = new Map<string, { name: string; flag: string }>();
  for (const ch of channels) {
    if (!countryMap.has(ch.country)) {
      countryMap.set(ch.country, { name: ch.countryName, flag: ch.countryFlag });
    }
  }
  return Array.from(countryMap.entries())
    .map(([code, info]) => ({ code, ...info }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

export function getUniqueLanguages(channels: Channel[]): { code: string; name: string }[] {
  const languageMap = new Map<string, string>();
  for (const ch of channels) {
    for (let i = 0; i < ch.languages.length; i++) {
      const code = ch.languages[i];
      const name = ch.languageNames[i] || code;
      if (!languageMap.has(code)) {
        languageMap.set(code, name);
      }
    }
  }
  return Array.from(languageMap.entries())
    .map(([code, name]) => ({ code, name }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

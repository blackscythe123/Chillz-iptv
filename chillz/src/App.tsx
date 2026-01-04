import { useState, useCallback, useMemo, useEffect, useRef } from 'react';
import { Menu, X, Filter } from 'lucide-react';
import { useChannels, useDebounce, useMediaQuery } from './hooks/useChannels';
import type { Channel } from './types/channel';
import {
  getFavorites,
  toggleFavorite,
  getHistory,
  addToHistory,
  hideChannel,
  getHiddenChannels,
  filterChannels,
  filterByLanguage,
  getUniqueCategories,
  getUniqueCountries,
  getUniqueLanguages,
  isDisclaimerAccepted,
  acceptDisclaimer,
  reportBroken
} from './utils/storage';
import { VideoPlayer } from './components/VideoPlayer';
import { ChannelList } from './components/ChannelList';
import { Filters, MobileFilters } from './components/Filters';
import { Disclaimer } from './components/Disclaimer';
import './App.css';

function App() {
  const { channels, loading, error, progress } = useChannels();
  const isMobile = useMediaQuery('(max-width: 768px)');
  
  // State
  const [disclaimerAccepted, setDisclaimerAccepted] = useState(isDisclaimerAccepted);
  const [selectedChannel, setSelectedChannel] = useState<Channel | null>(null);
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('all');
  const [country, setCountry] = useState('all');
  const [language, setLanguage] = useState('all');
  const [favorites, setFavorites] = useState<string[]>(getFavorites);
  const [history, setHistory] = useState<string[]>(getHistory);
  const [hiddenChannels, setHiddenChannels] = useState<string[]>(getHiddenChannels);
  const [showFavorites, setShowFavorites] = useState(false);
  const [showHistory, setShowHistory] = useState(false);
  const [sidebarOpen, setSidebarOpen] = useState(!isMobile);
  const [mobileFiltersOpen, setMobileFiltersOpen] = useState(false);
  
  const debouncedSearch = useDebounce(search, 300);
  const listContainerRef = useRef<HTMLDivElement>(null);
  const [listHeight, setListHeight] = useState(400);

  // Update list height on resize
  useEffect(() => {
    const updateHeight = () => {
      if (listContainerRef.current) {
        const rect = listContainerRef.current.getBoundingClientRect();
        setListHeight(rect.height);
      }
    };

    updateHeight();
    window.addEventListener('resize', updateHeight);
    return () => window.removeEventListener('resize', updateHeight);
  }, [sidebarOpen]);

  // Computed values
  const categories = useMemo(() => getUniqueCategories(channels), [channels]);
  const countries = useMemo(() => getUniqueCountries(channels), [channels]);
  const languages = useMemo(() => getUniqueLanguages(channels), [channels]);
  
  const filteredChannels = useMemo(() => {
    let filtered = filterChannels(
      channels,
      debouncedSearch,
      category,
      country,
      favorites,
      history,
      hiddenChannels,
      showFavorites,
      showHistory,
      false
    );
    // Apply language filter
    filtered = filterByLanguage(filtered, language);
    return filtered;
  }, [channels, debouncedSearch, category, country, language, favorites, history, hiddenChannels, showFavorites, showHistory]);

  // Handlers
  const handleAcceptDisclaimer = useCallback(() => {
    acceptDisclaimer();
    setDisclaimerAccepted(true);
  }, []);

  const handleSelectChannel = useCallback((channel: Channel) => {
    setSelectedChannel(channel);
    addToHistory(channel.id);
    setHistory(getHistory());
    if (isMobile) {
      setSidebarOpen(false);
    }
  }, [isMobile]);

  const handleToggleFavorite = useCallback((channelId: string) => {
    toggleFavorite(channelId);
    setFavorites(getFavorites());
  }, []);

  const handleHideChannel = useCallback((channelId: string) => {
    hideChannel(channelId);
    setHiddenChannels(getHiddenChannels());
    if (selectedChannel?.id === channelId) {
      setSelectedChannel(null);
    }
  }, [selectedChannel]);

  const handleReportBroken = useCallback((channelId: string, reason: string) => {
    reportBroken(channelId, reason);
    // Optionally hide the channel
  }, []);

  const filterProps = {
    search,
    onSearchChange: setSearch,
    category,
    onCategoryChange: setCategory,
    country,
    onCountryChange: setCountry,
    language,
    onLanguageChange: setLanguage,
    categories,
    countries,
    languages,
    showFavorites,
    onToggleFavorites: () => {
      setShowFavorites(!showFavorites);
      setShowHistory(false);
    },
    showHistory,
    onToggleHistory: () => {
      setShowHistory(!showHistory);
      setShowFavorites(false);
    },
    channelCount: filteredChannels.length
  };

  // Show disclaimer on first run
  if (!disclaimerAccepted) {
    return <Disclaimer onAccept={handleAcceptDisclaimer} />;
  }

  return (
    <div className="app">
      {/* Header */}
      <header className="app__header">
        <div className="app__header-left">
          <button 
            className="app__menu-btn"
            onClick={() => setSidebarOpen(!sidebarOpen)}
          >
            {sidebarOpen ? <X size={24} /> : <Menu size={24} />}
          </button>
          <div className="app__brand">
            <span className="app__logo">📺</span>
            <div className="app__brand-text">
              <h1>Chillz</h1>
              <span>TV, but Chill</span>
            </div>
          </div>
        </div>

        {isMobile && selectedChannel && (
          <button 
            className="app__filter-btn"
            onClick={() => setMobileFiltersOpen(true)}
          >
            <Filter size={20} />
          </button>
        )}
      </header>

      <div className="app__main">
        {/* Sidebar */}
        <aside className={`app__sidebar ${sidebarOpen ? 'open' : ''}`}>
          {!isMobile && <Filters {...filterProps} />}
          
          <div className="app__channel-list" ref={listContainerRef}>
            {loading ? (
              <div className="app__loading">
                <div className="app__loading-spinner"></div>
                <p>{progress}</p>
              </div>
            ) : error ? (
              <div className="app__error">
                <p>Failed to load channels</p>
                <p>{error}</p>
              </div>
            ) : (
              <ChannelList
                channels={filteredChannels}
                selectedChannel={selectedChannel}
                favorites={favorites}
                onSelect={handleSelectChannel}
                onToggleFavorite={handleToggleFavorite}
                onHide={handleHideChannel}
                height={listHeight}
              />
            )}
          </div>
        </aside>

        {/* Player Area */}
        <main className="app__player">
          <VideoPlayer 
            channel={selectedChannel}
            onReportBroken={handleReportBroken}
          />

          {selectedChannel && (
            <div className="app__channel-info">
              <div className="app__channel-details">
                <h2>{selectedChannel.name}</h2>
                <p>
                  {selectedChannel.categoryName} • {selectedChannel.countryFlag} {selectedChannel.countryName}
                  {selectedChannel.quality && <> • {selectedChannel.quality}</>}
                  {selectedChannel.network && <> • {selectedChannel.network}</>}
                </p>
              </div>
            </div>
          )}
        </main>
      </div>

      {/* Mobile Filters Bottom Sheet */}
      {isMobile && (
        <MobileFilters 
          isOpen={mobileFiltersOpen}
          onClose={() => setMobileFiltersOpen(false)}
          {...filterProps}
        />
      )}
    </div>
  );
}

export default App;

import { useRef, memo } from 'react';
import { useVirtualizer } from '@tanstack/react-virtual';
import { Heart, Star, EyeOff, AlertTriangle } from 'lucide-react';
import type { Channel } from '../types/channel';
import './ChannelList.css';

interface ChannelListProps {
  channels: Channel[];
  selectedChannel: Channel | null;
  favorites: string[];
  onSelect: (channel: Channel) => void;
  onToggleFavorite: (channelId: string) => void;
  onHide: (channelId: string) => void;
  height: number;
}

interface ChannelItemProps {
  channel: Channel;
  isSelected: boolean;
  isFavorite: boolean;
  onSelect: (channel: Channel) => void;
  onToggleFavorite: (channelId: string) => void;
  onHide: (channelId: string) => void;
}

const ITEM_HEIGHT = 72;

const ChannelItem = memo(({ 
  channel,
  isSelected,
  isFavorite,
  onSelect, 
  onToggleFavorite, 
  onHide 
}: ChannelItemProps) => {
  return (
    <div
      className={`channel-item ${isSelected ? 'channel-item--selected' : ''}`}
      onClick={() => onSelect(channel)}
    >
      <div className="channel-item__logo-wrapper">
        {channel.logo ? (
          <img
            src={channel.logo}
            alt=""
            className="channel-item__logo"
            loading="lazy"
            onError={(e) => {
              e.currentTarget.style.display = 'none';
              e.currentTarget.nextElementSibling?.classList.add('visible');
            }}
          />
        ) : null}
        <div className={`channel-item__logo-fallback ${!channel.logo ? 'visible' : ''}`}>
          {channel.name.charAt(0).toUpperCase()}
        </div>
      </div>

      <div className="channel-item__content">
        <div className="channel-item__name">
          {channel.name}
          {isFavorite && <Star className="channel-item__star" size={14} />}
        </div>
        <div className="channel-item__meta">
          <span className="channel-item__category">{channel.categoryName}</span>
          <span className="channel-item__separator">•</span>
          <span className="channel-item__country">{channel.countryFlag} {channel.countryName}</span>
          {channel.quality && (
            <>
              <span className="channel-item__separator">•</span>
              <span className="channel-item__quality">{channel.quality}</span>
            </>
          )}
        </div>
      </div>

      <div className="channel-item__actions">
        <button
          className={`channel-item__action ${isFavorite ? 'active' : ''}`}
          onClick={(e) => {
            e.stopPropagation();
            onToggleFavorite(channel.id);
          }}
          title={isFavorite ? 'Remove from favorites' : 'Add to favorites'}
        >
          <Heart size={16} fill={isFavorite ? 'currentColor' : 'none'} />
        </button>
        <button
          className="channel-item__action channel-item__action--hide"
          onClick={(e) => {
            e.stopPropagation();
            onHide(channel.id);
          }}
          title="Hide channel"
        >
          <EyeOff size={16} />
        </button>
      </div>
    </div>
  );
});

ChannelItem.displayName = 'ChannelItem';

export function ChannelList({
  channels,
  selectedChannel,
  favorites,
  onSelect,
  onToggleFavorite,
  onHide,
  height
}: ChannelListProps) {
  const parentRef = useRef<HTMLDivElement>(null);

  const virtualizer = useVirtualizer({
    count: channels.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => ITEM_HEIGHT,
    overscan: 5,
  });

  if (channels.length === 0) {
    return (
      <div className="channel-list__empty">
        <AlertTriangle size={48} />
        <h3>No channels found</h3>
        <p>Try adjusting your filters or search term</p>
      </div>
    );
  }

  return (
    <div 
      ref={parentRef} 
      className="channel-list"
      style={{ height, overflow: 'auto' }}
    >
      <div
        style={{
          height: `${virtualizer.getTotalSize()}px`,
          width: '100%',
          position: 'relative',
        }}
      >
        {virtualizer.getVirtualItems().map((virtualItem) => {
          const channel = channels[virtualItem.index];
          const isSelected = selectedChannel?.id === channel.id;
          const isFavorite = favorites.includes(channel.id);

          return (
            <div
              key={virtualItem.key}
              style={{
                position: 'absolute',
                top: 0,
                left: 0,
                width: '100%',
                height: `${virtualItem.size}px`,
                transform: `translateY(${virtualItem.start}px)`,
              }}
            >
              <ChannelItem
                channel={channel}
                isSelected={isSelected}
                isFavorite={isFavorite}
                onSelect={onSelect}
                onToggleFavorite={onToggleFavorite}
                onHide={onHide}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
}

// Loading skeletons
export function ChannelListSkeleton({ count = 10 }: { count?: number }) {
  return (
    <div className="channel-list">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="channel-item channel-item--skeleton">
          <div className="channel-item__logo-wrapper skeleton"></div>
          <div className="channel-item__content">
            <div className="skeleton skeleton--text skeleton--name"></div>
            <div className="skeleton skeleton--text skeleton--meta"></div>
          </div>
        </div>
      ))}
    </div>
  );
}

export default ChannelList;

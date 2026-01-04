import { useState, useRef, useEffect, useMemo } from 'react';
import { Search, Heart, Clock, X, ChevronDown, Globe } from 'lucide-react';
import './Filters.css';

interface CategoryOption {
  id: string;
  name: string;
}

interface CountryOption {
  code: string;
  name: string;
  flag: string;
}

interface LanguageOption {
  code: string;
  name: string;
}

interface FiltersProps {
  search: string;
  onSearchChange: (value: string) => void;
  category: string;
  onCategoryChange: (value: string) => void;
  country: string;
  onCountryChange: (value: string) => void;
  language: string;
  onLanguageChange: (value: string) => void;
  categories: CategoryOption[];
  countries: CountryOption[];
  languages: LanguageOption[];
  showFavorites: boolean;
  onToggleFavorites: () => void;
  showHistory: boolean;
  onToggleHistory: () => void;
  channelCount: number;
}

// Searchable Combobox Component
interface SearchableSelectProps<T> {
  value: string;
  onChange: (value: string) => void;
  options: T[];
  getKey: (option: T) => string;
  getLabel: (option: T) => string;
  getValue: (option: T) => string;
  placeholder: string;
  allLabel: string;
}

function SearchableSelect<T>({
  value,
  onChange,
  options,
  getKey,
  getLabel,
  getValue,
  placeholder,
  allLabel
}: SearchableSelectProps<T>) {
  const [isOpen, setIsOpen] = useState(false);
  const [searchText, setSearchText] = useState('');
  const containerRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  // Find the selected option's label
  const selectedLabel = useMemo(() => {
    if (value === 'all') return allLabel;
    const option = options.find(o => getValue(o).toLowerCase() === value.toLowerCase());
    return option ? getLabel(option) : allLabel;
  }, [value, options, getValue, getLabel, allLabel]);

  // Filter options based on search
  const filteredOptions = useMemo(() => {
    if (!searchText) return options;
    const searchLower = searchText.toLowerCase();
    return options.filter(o => 
      getLabel(o).toLowerCase().includes(searchLower)
    );
  }, [options, searchText, getLabel]);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setIsOpen(false);
        setSearchText('');
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  // Focus input when opening
  useEffect(() => {
    if (isOpen && inputRef.current) {
      inputRef.current.focus();
    }
  }, [isOpen]);

  const handleSelect = (val: string) => {
    onChange(val);
    setIsOpen(false);
    setSearchText('');
  };

  return (
    <div className="searchable-select" ref={containerRef}>
      <button
        type="button"
        className="searchable-select__trigger"
        onClick={() => setIsOpen(!isOpen)}
      >
        <span className="searchable-select__value">{selectedLabel}</span>
        <ChevronDown className={`searchable-select__icon ${isOpen ? 'open' : ''}`} size={16} />
      </button>

      {isOpen && (
        <div className="searchable-select__dropdown">
          <div className="searchable-select__search">
            <Search size={14} />
            <input
              ref={inputRef}
              type="text"
              placeholder={placeholder}
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              className="searchable-select__input"
            />
            {searchText && (
              <button
                type="button"
                onClick={() => setSearchText('')}
                className="searchable-select__clear"
              >
                <X size={12} />
              </button>
            )}
          </div>
          <div className="searchable-select__options">
            <button
              type="button"
              className={`searchable-select__option ${value === 'all' ? 'selected' : ''}`}
              onClick={() => handleSelect('all')}
            >
              {allLabel}
            </button>
            {filteredOptions.map((option) => (
              <button
                key={getKey(option)}
                type="button"
                className={`searchable-select__option ${getValue(option).toLowerCase() === value ? 'selected' : ''}`}
                onClick={() => handleSelect(getValue(option).toLowerCase())}
              >
                {getLabel(option)}
              </button>
            ))}
            {filteredOptions.length === 0 && (
              <div className="searchable-select__empty">No results found</div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export function Filters({
  search,
  onSearchChange,
  category,
  onCategoryChange,
  country,
  onCountryChange,
  language,
  onLanguageChange,
  categories,
  countries,
  languages,
  showFavorites,
  onToggleFavorites,
  showHistory,
  onToggleHistory,
  channelCount
}: FiltersProps) {
  return (
    <div className="filters">
      <div className="filters__search">
        <Search className="filters__search-icon" size={18} />
        <input
          type="text"
          placeholder="Search channels..."
          value={search}
          onChange={(e) => onSearchChange(e.target.value)}
          className="filters__search-input"
        />
        {search && (
          <button
            className="filters__search-clear"
            onClick={() => onSearchChange('')}
          >
            <X size={16} />
          </button>
        )}
      </div>

      <div className="filters__dropdowns">
        <SearchableSelect
          value={category}
          onChange={onCategoryChange}
          options={categories}
          getKey={(c) => c.id}
          getLabel={(c) => c.name}
          getValue={(c) => c.id}
          placeholder="Type to filter..."
          allLabel="All Categories"
        />

        <SearchableSelect
          value={country}
          onChange={onCountryChange}
          options={countries}
          getKey={(c) => c.code}
          getLabel={(c) => `${c.flag} ${c.name}`}
          getValue={(c) => c.code}
          placeholder="Type to filter..."
          allLabel="All Countries"
        />

        <SearchableSelect
          value={language}
          onChange={onLanguageChange}
          options={languages}
          getKey={(l) => l.code}
          getLabel={(l) => l.name}
          getValue={(l) => l.code}
          placeholder="Type to filter..."
          allLabel="All Languages"
        />
      </div>

      <div className="filters__toggles">
        <button
          className={`filters__toggle ${showFavorites ? 'active' : ''}`}
          onClick={onToggleFavorites}
        >
          <Heart size={16} fill={showFavorites ? 'currentColor' : 'none'} />
          Favorites
        </button>
        <button
          className={`filters__toggle ${showHistory ? 'active' : ''}`}
          onClick={onToggleHistory}
        >
          <Clock size={16} />
          History
        </button>
      </div>

      <div className="filters__count">
        <Globe size={14} />
        {channelCount} channel{channelCount !== 1 ? 's' : ''}
      </div>
    </div>
  );
}

// Mobile Bottom Sheet Filters
interface MobileFiltersProps extends FiltersProps {
  isOpen: boolean;
  onClose: () => void;
}

export function MobileFilters({
  isOpen,
  onClose,
  ...props
}: MobileFiltersProps) {
  if (!isOpen) return null;

  return (
    <div className="mobile-filters-overlay" onClick={onClose}>
      <div 
        className="mobile-filters-sheet"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mobile-filters-sheet__handle" />
        <div className="mobile-filters-sheet__header">
          <h3>Filters</h3>
          <button onClick={onClose}>
            <X size={24} />
          </button>
        </div>
        <div className="mobile-filters-sheet__content">
          <Filters {...props} />
        </div>
      </div>
    </div>
  );
}

export default Filters;

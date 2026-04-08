interface Option {
  label: string;
  value: string;
}

interface Props {
  search: string;
  onSearchChange: (value: string) => void;
  filters?: Array<{
    key: string;
    value: string;
    label: string;
    options: Option[];
    onChange: (value: string) => void;
  }>;
}

export function SearchFilterBar({ search, onSearchChange, filters = [] }: Props) {
  return (
    <div className="search-filter-bar panel">
      <input
        className="input"
        value={search}
        onChange={(event) => onSearchChange(event.target.value)}
        placeholder="Search..."
      />
      {filters.map((filter) => (
        <label className="filter" key={filter.key}>
          <span>{filter.label}</span>
          <select value={filter.value} onChange={(event) => filter.onChange(event.target.value)}>
            {filter.options.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
      ))}
    </div>
  );
}

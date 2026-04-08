interface Props {
  title: string;
  items: string[];
}

export function ResponseGuidanceCard({ title, items }: Props) {
  return (
    <div className="panel">
      <h3>{title}</h3>
      <ul className="plain-list">
        {items.map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </div>
  );
}

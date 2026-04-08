interface Props {
  title: string;
  value: string | number;
  subtitle?: string;
}

export function SummaryCard({ title, value, subtitle }: Props) {
  return (
    <article className="panel summary-card">
      <p className="label">{title}</p>
      <p className="value">{value}</p>
      {subtitle ? <p className="subtle">{subtitle}</p> : null}
    </article>
  );
}

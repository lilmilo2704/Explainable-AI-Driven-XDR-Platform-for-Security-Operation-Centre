interface Props {
  title: string;
  message: string;
}

export function EmptyState({ title, message }: Props) {
  return (
    <div className="state empty-state panel">
      <p className="label">{title}</p>
      <p>{message}</p>
    </div>
  );
}

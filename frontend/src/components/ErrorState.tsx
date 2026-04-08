interface Props {
  title?: string;
  message: string;
  onRetry?: () => void;
}

export function ErrorState({ title = "Data Error", message, onRetry }: Props) {
  return (
    <div className="state error-state panel">
      <p className="label">{title}</p>
      <p>{message}</p>
      {onRetry ? (
        <button className="button secondary" onClick={onRetry}>
          Retry
        </button>
      ) : null}
    </div>
  );
}

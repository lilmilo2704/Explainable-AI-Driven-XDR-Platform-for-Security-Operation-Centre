interface Props {
  title?: string;
  message?: string;
}

export function LoadingState({ title = "Loading", message = "Retrieving telemetry data..." }: Props) {
  return (
    <div className="state loading-state panel">
      <p className="label">{title}</p>
      <p>{message}</p>
    </div>
  );
}

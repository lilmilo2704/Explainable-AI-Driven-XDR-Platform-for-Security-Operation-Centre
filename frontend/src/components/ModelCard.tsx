import type { ModelRecord } from "../types/domain";
import { formatTime } from "../utils/format";

interface Props {
  model: ModelRecord;
}

export function ModelCard({ model }: Props) {
  return (
    <article className="panel model-card">
      <h3>{model.name}</h3>
      <p className="subtle">Version {model.version}</p>
      <p>{model.purpose}</p>
      <p className="subtle">Classes: {model.attack_classes_supported.join(", ")}</p>
      <p className="subtle">Latest Inference: {formatTime(model.latest_inference_time)}</p>
      <span className={`badge ${model.explanation_available ? "ok" : "neutral"}`}>
        Explanation {model.explanation_available ? "Available" : "Unavailable"}
      </span>
    </article>
  );
}

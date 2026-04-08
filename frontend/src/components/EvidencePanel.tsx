import type { IncidentDetail } from "../types/domain";
import { formatTime } from "../utils/format";

interface Props {
  evidence: IncidentDetail["evidence"];
}

export function EvidencePanel({ evidence }: Props) {
  return (
    <div className="panel">
      <h3>Evidence</h3>
      <div className="evidence-grid">
        <div>
          <p className="label">Related Alerts</p>
          <p>{evidence.related_alert_ids.join(", ") || "None"}</p>
        </div>
        <div>
          <p className="label">Raw References</p>
          <p>{evidence.raw_references.join(", ") || "None"}</p>
        </div>
        <div>
          <p className="label">Linked Assets</p>
          <p>{evidence.linked_assets.join(", ") || "None"}</p>
        </div>
        <div>
          <p className="label">Linked IPs</p>
          <p>{evidence.linked_ips.join(", ") || "None"}</p>
        </div>
        <div>
          <p className="label">Linked Users</p>
          <p>{evidence.linked_users.join(", ") || "None"}</p>
        </div>
      </div>

      <div className="key-log-section">
        <p className="label">Key Logs & Analyst Explanation</p>
        {evidence.key_logs.length === 0 ? (
          <p className="subtle">No key logs captured for this incident.</p>
        ) : (
          <div className="key-log-list">
            {evidence.key_logs.map((log, index) => (
              <div key={`${log.timestamp}-${index}`} className="key-log-item">
                <div>
                  <p className="label">
                    {formatTime(log.timestamp)} | {log.source}
                  </p>
                  <pre>{log.raw_log}</pre>
                </div>
                <div>
                  <p className="label">Why It Matters</p>
                  <p>{log.explanation}</p>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

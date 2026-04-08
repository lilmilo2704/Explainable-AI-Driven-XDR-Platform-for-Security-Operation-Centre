import type { TimelineEvent } from "../types/domain";
import { formatTime } from "../utils/format";

interface Props {
  events: TimelineEvent[];
}

export function TimelineView({ events }: Props) {
  return (
    <div className="panel">
      <h3>Incident Timeline</h3>
      <div className="timeline">
        {events.map((event) => (
          <div key={event.id} className="timeline-item">
            <div>
              <p className="label">{event.event_type}</p>
              <p>{event.explanation}</p>
            </div>
            <div className="timeline-meta">
              <span>{formatTime(event.timestamp)}</span>
              <span>{event.asset}</span>
              {event.user ? <span>User: {event.user}</span> : null}
              {event.ip ? <span>IP: {event.ip}</span> : null}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

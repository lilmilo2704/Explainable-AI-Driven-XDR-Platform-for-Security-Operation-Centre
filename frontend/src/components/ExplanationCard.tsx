import { Bar, BarChart, Cell, ResponsiveContainer, XAxis, YAxis } from "recharts";
import type { IncidentDetail } from "../types/domain";

interface Props {
  explanation: IncidentDetail["explanation"];
}

export function ExplanationCard({ explanation }: Props) {
  return (
    <div className="panel">
      <h3>Explanation</h3>
      <p>{explanation.summary}</p>
      <div className="chart-wrap short">
        <ResponsiveContainer width="100%" height={220}>
          <BarChart data={explanation.features}>
            <XAxis dataKey="feature" interval={0} angle={-20} height={70} textAnchor="end" />
            <YAxis />
            <Bar dataKey="contribution">
              {explanation.features.map((feature) => (
                <Cell key={feature.feature} fill={feature.direction === "up" ? "#2bc48a" : "#f28b82"} />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

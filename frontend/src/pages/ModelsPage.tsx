import { Bar, BarChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { ErrorState } from "../components/ErrorState";
import { LoadingState } from "../components/LoadingState";
import { ModelCard } from "../components/ModelCard";
import { useModelsQuery } from "../hooks/queries";

export function ModelsPage() {
  const modelsQuery = useModelsQuery();

  if (modelsQuery.isLoading) return <LoadingState title="Loading Models" />;
  if (modelsQuery.error) return <ErrorState message="Unable to load model metadata." onRetry={() => void modelsQuery.refetch()} />;

  const data = modelsQuery.data;
  if (!data) return <ErrorState message="No model data returned." />;

  return (
    <section className="stack gap-sm">
      <article className="panel">
        <h3>Deployed Models</h3>
        <div className="grid two-col">
          {data.models.map((model) => (
            <ModelCard key={model.id} model={model} />
          ))}
        </div>
      </article>

      <section className="grid two-col">
        <article className="panel">
          <h3>Global Explanation Summary</h3>
          <div className="chart-wrap">
            <ResponsiveContainer width="100%" height={260}>
              <BarChart data={data.class_level_scores}>
                <XAxis dataKey="class_name" interval={0} angle={-20} height={80} textAnchor="end" />
                <YAxis />
                <Tooltip />
                <Bar dataKey="average_confidence" fill="#53b3cb" />
              </BarChart>
            </ResponsiveContainer>
          </div>
          <div className="stack gap-sm">
            {data.dominant_features_by_class.map((item) => (
              <div key={item.class_name} className="panel soft">
                <p className="label">{item.class_name}</p>
                <p>{item.features.join(" | ")}</p>
              </div>
            ))}
          </div>
        </article>

        <article className="panel">
          <h3>Model-to-Product Mapping</h3>
          <div className="stack gap-sm">
            {data.mappings.map((mapping) => (
              <div key={`${mapping.source_model}-${mapping.product_surface}`} className="list-row">
                <p className="label">{mapping.source_model}</p>
                <p>{mapping.product_surface}</p>
              </div>
            ))}
          </div>
          <p className="subtle">{data.note}</p>
        </article>
      </section>
    </section>
  );
}

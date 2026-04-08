import { useMemo, useState } from "react";
import ReactFlow, { Background, Controls, MarkerType, type Edge, type Node } from "reactflow";
import type { GraphEdge, GraphNode } from "../types/domain";

interface Props {
  nodes: GraphNode[];
  edges: GraphEdge[];
}

export function CausalGraphPanel({ nodes, edges }: Props) {
  const [selectedEdge, setSelectedEdge] = useState<GraphEdge | null>(null);

  const flowNodes = useMemo<Node[]>(
    () =>
      nodes.map((node) => ({
        ...node,
        type: "default",
        data: { label: `${node.data.label} (${Math.round((node.data.confidence ?? 0) * 100)}%)` },
      })),
    [nodes],
  );

  const flowEdges = useMemo<Edge[]>(
    () =>
      edges.map((edge) => ({
        id: edge.id,
        source: edge.source,
        target: edge.target,
        label: `${edge.label} (${Math.round(edge.data.confidence * 100)}%)`,
        markerEnd: { type: MarkerType.ArrowClosed },
      })),
    [edges],
  );

  return (
    <div className="panel">
      <div className="row between">
        <h3>Causal Graph</h3>
        <span className="subtle">Click edge chips below for explanation</span>
      </div>
      <div className="graph-panel">
        <ReactFlow nodes={flowNodes} edges={flowEdges} fitView>
          <Controls />
          <Background />
        </ReactFlow>
      </div>
      <div className="edge-chip-list">
        {edges.map((edge) => (
          <button
            key={edge.id}
            className={`chip ${selectedEdge?.id === edge.id ? "active" : ""}`}
            onClick={() => setSelectedEdge(edge)}
          >
            {edge.label}
          </button>
        ))}
      </div>
      {selectedEdge ? (
        <div className="edge-detail">
          <p className="label">{selectedEdge.label}</p>
          <p>{selectedEdge.data.explanation}</p>
          <p className="subtle">Evidence Strength: {Math.round(selectedEdge.data.confidence * 100)}%</p>
        </div>
      ) : null}
    </div>
  );
}

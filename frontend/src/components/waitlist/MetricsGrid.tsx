import React from "react";

type MetricItem = {
  label: string;
  value: string;
};

type MetricsGridProps = {
  metrics: MetricItem[];
};

const MetricsGrid: React.FC<MetricsGridProps> = ({ metrics }) => (
  <div className="waitlist-metrics-grid">
    {metrics.map((metric) => (
      <article key={metric.label} className="tweet-card waitlist-metric-card reveal">
        <p className="waitlist-metric-value">{metric.value}</p>
        <p className="waitlist-metric-label">{metric.label}</p>
      </article>
    ))}
  </div>
);

export default MetricsGrid;

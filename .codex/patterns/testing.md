# Testing Patterns

- Add tests proportional to blast radius. Cross-service and contract changes require broader checks.
- Prefer contract tests around backend -> ML payloads and frontend -> backend responses.
- Validate exact model base features before ML inference:
  - `request_completed_count`
  - `request_rate_per_second`
  - `peak_request_rate_per_second`
  - `unique_path_count`
  - `repeated_path_count`
  - `search_query_count`
  - `avg_response_time_ms`
  - `max_response_time_ms`
  - `p95_response_time_ms`
  - `health_check_count`
  - `avg_health_check_latency_ms`
  - `max_health_check_latency_ms`
- Multi-record persistence should be transactional and tested for rollback on failure.
- Demo validation must check service health, backend responses, frontend rendering, and failure visibility.
- Do not count ignored dependency tests as project tests.

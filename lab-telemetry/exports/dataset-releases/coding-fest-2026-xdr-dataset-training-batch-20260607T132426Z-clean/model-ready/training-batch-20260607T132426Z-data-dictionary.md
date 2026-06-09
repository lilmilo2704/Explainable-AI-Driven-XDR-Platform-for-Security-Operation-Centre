# Model-Ready Data Dictionary - training-batch-20260607T132426Z

Target column: main_label

This export removes known leakage/provenance columns and raw/path/IP string fields. It is intended for a first baseline classifier handoff, not for final public-quality modelling.

## Columns

- `main_label`
- `intensity`
- `planned_request_count`
- `actual_request_count`
- `safety_limit_applied`
- `is_clean_supervised_training_candidate`
- `request_completed_count`
- `webapp_request_completed_count`
- `nginx_request_count`
- `run_duration_seconds`
- `request_rate_per_second`
- `peak_request_rate_per_second`
- `unique_path_count`
- `repeated_path_count`
- `search_query_count`
- `burst_search_count`
- `human_repeated_search_count`
- `page_view_count`
- `login_page_view_count`
- `admin_access_count`
- `successful_web_login_count`
- `auth_event_count`
- `webapp_line_count`
- `nginx_line_count`
- `wazuh_archive_event_count`
- `wazuh_alert_event_count`
- `wazuh_archive_evidence_present`
- `status_2xx_count`
- `status_3xx_count`
- `status_4xx_count`
- `status_5xx_count`
- `error_status_count`
- `error_rate`
- `avg_response_time_ms`
- `max_response_time_ms`
- `min_response_time_ms`
- `p95_response_time_ms`
- `avg_request_duration_ms`
- `max_request_duration_ms`
- `health_check_count`
- `health_check_failed_count`
- `avg_health_check_latency_ms`
- `max_health_check_latency_ms`
- `nginx_error_count`
- `observed_source_count`
- `same_source_request_ratio`
- `top_source_ip_ratio`
- `distributed_evidence_confirmed`
- `distributed`
- `source_count`

## Removed Families

- Scenario and sublabel identifiers.
- Actor/scenario variant metadata.
- Run IDs and file paths.
- Raw evidence text.
- String IP addresses.
- Direct attack-mode metadata.

Wazuh counts are retained as numeric evidence-volume features. Wazuh alerts are not labels.

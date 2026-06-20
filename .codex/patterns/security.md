# Security Patterns

- Treat evidence files and imported telemetry as untrusted input.
- Defend against path traversal when reading evidence paths or run identifiers.
- Do not pass user-controlled strings into shell commands.
- Use parameterized database access; do not build SQL by string concatenation.
- Never load model artifacts from untrusted or user-supplied paths.
- CORS should be scoped for the local/dev environment and reviewed before demos.
- Avoid exposing secrets, absolute local paths, raw credentials, or sensitive raw evidence in frontend responses.
- Destructive lab commands require explicit approval and controlled targets.
- DoS-style lab generation must stay bounded, sequential, lab-only, and non-destructive.

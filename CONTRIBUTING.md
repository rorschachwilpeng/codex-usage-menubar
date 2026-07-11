# Contributing

Issues and pull requests are welcome.

Before submitting a change:

```bash
./scripts/test.sh
./scripts/build-app.sh
./scripts/verify-app.sh "build/Codex Usage.app"
```

Keep changes focused. Do not add analytics, credential access, or prompt/conversation collection. If a change affects Codex app-server compatibility, include the Codex and macOS versions used for validation.

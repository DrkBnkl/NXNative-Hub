# CLAUDE.md

Project conventions are defined in [CONTRIBUTING.md](CONTRIBUTING.md) and the code structure in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Follow both.

Key rules:
- English for code, comments, commit messages and all documentation; UI strings always via `tr("German", "English")`.
- Record user-facing changes in `CHANGELOG.md` under `[Unreleased]`; keep entries short.
- No macOS SDK may be available in the agent environment: if `./build.sh` cannot run, say so and ask the user to build and test.

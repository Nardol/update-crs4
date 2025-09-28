# Repository Guidelines

## Project Structure & Module Organization
- `update_crs_inplace.sh`: main Bash script for in-place CRS4 updates.
- `README.md`, `PROGRESS.md`: user-facing docs; extend them when behavior changes.
- `etc/modsecurity/crs4/`: sample tree mirroring the CRS minimal archive (leave untouched unless updating fixtures).
- `.github/workflows/`: GitHub Actions (`lint.yml`, `release.yml`, `crs-update.yml`) that must stay green on every PR.

## Build, Test, and Development Commands
- `shellcheck update_crs_inplace.sh`: static analysis; fix every warning before pushing.
- `shfmt -i 2 -ci -bn -sr -w update_crs_inplace.sh`: apply the canonical formatting required by CI.
- `./update_crs_inplace.sh --version 4.18.0 --base-dir "$PWD/etc/modsecurity/crs4" --skip-verify --no-test`: local smoke test using the bundled fixture (adjust version as needed).

## Coding Style & Naming Conventions
- Bash sources use 2-space indentation, `set -euo pipefail`, and long-form flags for readability.
- Keep functions lowercase with underscores (e.g., `sync_release`).
- Prefer explicit logging via the `log` helper; errors should call `errexit` with actionable messages.
- New CLI options follow the existing GNU-style pattern (`--flag`, optional short alias).

## Testing Guidelines
- No automated unit tests exist; rely on the smoke command above plus `nginx -t` if available.
- Regenerate backups/backups directories only during manual tests; remove artifacts before committing.
- When altering workflows, trigger them manually (Actions tab → *Run workflow*) to confirm behavior.

## Commit & Pull Request Guidelines
- Use imperative, concise commit subjects (e.g., `Add noop job for workflow push trigger`).
- Every PR must:
  - Target `main` and include a clear summary plus linked issue (if applicable).
  - Pass the `shellcheck` status check (enforced by branch protection).
  - Explain user-facing changes in `README.md` or `PROGRESS.md` when relevant.
  - Include workflow updates when new commands/linting rules are introduced.
- Squash merge via GitHub (`--admin` override is available but only if checks pass).

## Security & Configuration Tips
- Do not commit server secrets or overrides inside `etc/`; it is illustrative only.
- Always verify CRS signatures in production (`--skip-verify` is for local testing or sandbox runs).
- Keep the GPG key fingerprint (`38EE ACA1 AB8A 6E72`) visible whenever documentation is updated.

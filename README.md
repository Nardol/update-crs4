CRS4 In-Place Updater
=====================

Synchronise an existing OWASP Core Rule Set 4 (CRS4) deployment with the latest
release without restructuring your ModSecurity installation. The `update_crs_inplace.sh`
script keeps your vendor directory layout intact, backs up the current ruleset,
preserves local tweaks, and optionally reloads Nginx when the update succeeds.

> Built by OpenAI Codex in collaboration with Pierre Zajda.

Why this tool?
--------------
- **No vendor switch** – keep your historic `/etc/modsecurity/crs4` tree.
- **Safe updates** – automatic tarball backups and GPG verification (unless you skip it).
- **Selective preservation** – built-in handling for `crs-setup.conf`, 900/999 exclusion
  files, custom plugins, and user-defined glob patterns.
- **Minimal archive first** – prefers the official `coreruleset-<version>-minimal.tar.gz`
  asset but falls back to the full bundle when needed.
- **Practical automation** – optional cache, backup retention, and Nginx reload flag.

Quick start (server side)
-------------------------
```bash
sudo install -m 0755 update_crs_inplace.sh /usr/local/sbin/update_crs_inplace.sh
sudo /usr/local/sbin/update_crs_inplace.sh --latest --keep-backups 5 --reload-nginx
```

Requirements
------------
- Bash 4+
- `curl`, `tar`, `rsync`, `python3`, `date`
- `gpg` (recommended for signature verification)
- `nginx` available in `$PATH` if you want automatic testing/reloads
- Optional: `systemctl` for service reloads, otherwise the script falls back to
  `nginx -s reload`

Installation
------------
1. Copy `update_crs_inplace.sh` to your server (example: `/usr/local/sbin`).
2. Ensure it is executable: `chmod +x /usr/local/sbin/update_crs_inplace.sh`.
3. (Optional) Import the CRS release signing key:
   ```bash
   gpg --keyserver hkps://keys.openpgp.org --recv 0x38EEACA1AB8A6E72
   ```

Usage
-----
Update to the latest stable release exposed by the GitHub API:
```bash
sudo update_crs_inplace.sh --latest
```
Update to a specific version:
```bash
sudo update_crs_inplace.sh --version 4.16.0 --keep-backups 10
```

Key features in detail
----------------------
- **Backups:** each run produces a dated tarball `../crs4-backups/crs4-YYYYmmdd-HHMMSS.tar.gz`.
- **Preservation:** the script copies local files aside, syncs CRS, then restores
  your versions while keeping upstream revisions as `*.upstream` for comparison.
- **Cache:** downloaded tarballs/signatures are stored in `${TMPDIR:-/tmp}/coreruleset-cache`
  to speed up retries and dry runs.
- **Fallback logic:** signatures missing for one asset automatically trigger a
  fallback to the next candidate (minimal → full).
- **Plugin awareness:** any file (or symlink) in `plugins/` except the CRS-provided
  placeholders is preserved automatically.

Options
-------
| Option | Description |
| ------ | ----------- |
| `-v, --version <x.y.z>` | Update to the specified CRS version. |
| `-l, --latest` | Query GitHub for the most recent stable release. |
| `-b, --base-dir <path>` | Path to the CRS directory (`/etc/modsecurity/crs4` by default). |
| `-p, --preserve <relative>` | Add an extra relative path to preserve (repeatable). |
| `--preserve-glob '<glob>'` | Preserve every file matching the glob (repeatable). |
| `-B, --backup-root <dir>` | Custom root for backups. Defaults to sibling `crs4-backups`. |
| `--keep-backups <n>` | Retain the latest *n* backups, purge older archives. `0` disables pruning. |
| `--skip-verify` | Skip GPG signature verification (discouraged). |
| `-t, --no-test` | Skip `nginx -t`. |
| `-q, --quiet` | Reduce log noise. |
| `--asset-suffix <suffix>` | Override the archive suffix (default `-minimal`; pass empty string for full bundle only). |
| `--cache-dir <dir>` | Override the download cache directory. |
| `--reload-nginx` | Reload Nginx after a successful update (`systemctl reload` → `nginx -s reload`). |

Best practices
--------------
1. **Diff your preserved files** – compare `*.upstream` with your copies after each update.
2. **Monitor logs** – keep an eye on ModSecurity audit logs and Nginx error logs after upgrades.
3. **Test first** – run `--no-test` on staging if you don’t want the script to execute `nginx -t`.
4. **Cron?** – prefer manual execution or a supervised job to avoid unattended CRS changes.

Development notes
-----------------
- Run `shellcheck update_crs_inplace.sh` before committing changes.
- The repository includes a sample CRS directory (`etc/modsecurity/crs4/`) mirrored from
  the minimal archive for testing purposes.
- Ideas/todos live in `PROGRESS.md`.

Licence
-------
Released under the MIT License – see `LICENSE`.

French summary / Résumé
-----------------------
Ce dépôt contient un script Bash pour mettre à jour un répertoire CRS4 existant
sans changer son arborescence. Il sauvegarde le dossier avant chaque mise à jour,
préserve `crs-setup.conf`, les exclusions 900/999, tes plugins personnalisés, et
peut recharger Nginx automatiquement (`--reload-nginx`). Les archives téléchargées
sont vérifiées via GPG (sauf `--skip-verify`) et mises en cache pour accélérer les
exécutions suivantes. Toutes les options sont listées ci-dessus ; utilise `--keep-backups`
pour limiter le nombre de sauvegardes et `--preserve-glob` pour ajouter tes propres motifs.

#!/usr/bin/env bash
set -euo pipefail

VERSION=""
LATEST=0
BASE_DIR="/etc/modsecurity/crs4"
SKIP_VERIFY=0
NO_TEST=0
QUIET=0
FORCE=0
PRESERVE=()
BACKUP_ROOT=""
PRESERVE_GLOBS=()
KEEP_BACKUPS=0
ASSET_SUFFIX="-minimal"
CACHE_DIR="${TMPDIR:-/tmp}/coreruleset-cache"
USED_ASSET=""
TMP_DIR_CLEANUP=""
RELOAD_NGINX=0
INSTALLED_VERSION=""

contains_preserve() {
  local needle="$1" item
  for item in "${PRESERVE[@]}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

add_preserve_path() {
  local rel="$1"
  [[ -n "$rel" ]] || return
  if ! contains_preserve "$rel"; then
    PRESERVE+=("$rel")
  fi
}

log() {
  [[ $QUIET -eq 0 ]] && printf '%s\n' "$*"
}

errexit() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat << 'USAGE'
Usage: update_crs_inplace.sh [options]

Options:
  -v, --version <x.y.z>  Met à jour vers la version CRS v<x.y.z>
  -l, --latest           Utilise la dernière release stable via l'API GitHub
  -b, --base-dir <path>  Chemin vers le dossier crs4 (défaut: /etc/modsecurity/crs4)
  -p, --preserve <path>  Chemin (relatif au dossier crs4) à préserver; option répétable
      --preserve-glob <glob>
                         Motif (glob) relatif à crs4 dont les fichiers doivent être préservés
  -B, --backup-root <dir> Ranger les sauvegardes dans ce dossier (défaut: crs4-backups à côté du dossier)
      --keep-backups <n>  Conserver les <n> sauvegardes les plus récentes (0 = pas de purge)
  -s, --skip-verify      Ignore la vérification GPG (non recommandé)
  -t, --no-test          Ne pas exécuter nginx -t en fin de mise à jour
  -q, --quiet            Réduit les logs au minimum
      --asset-suffix <s> Suffixe d'archive (défaut: -minimal). Exemple : --asset-suffix ""
      --cache-dir <dir>  Répertoire cache des archives (défaut: ${TMPDIR:-/tmp}/coreruleset-cache)
      --reload-nginx     Exécute un reload nginx (systemctl ou nginx -s reload) après mise à jour
  -f, --force            Force la mise à jour même si la version détectée correspond déjà
  -h, --help             Affiche cette aide

Le script :
  1. Télécharge la release CRS désirée
  2. Sauvegarde le dossier crs4 actuel sous forme d'archive tar.gz
  3. Synchronise les fichiers de la release vers le dossier existant (suppression des fichiers obsolètes)
  4. Restaure les fichiers listés avec --preserve (copie + sauvegarde de la version upstream en *.upstream)
  5. Exécute nginx -t (optionnel) et affiche un résumé

Fichiers préservés par défaut :
  crs-setup.conf
  rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf
  rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf
USAGE
}

require_cmd() {
  command -v "$1" > /dev/null 2>&1 || errexit "Commande requise manquante: $1"
}

fetch_latest_version() {
  require_cmd curl
  require_cmd python3
  local api="https://api.github.com/repos/coreruleset/coreruleset/releases/latest"
  VERSION="$(curl -fsSL "$api" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')"
  [[ -n "$VERSION" ]] || errexit "Impossible de déterminer la dernière version via l'API GitHub"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v | --version)
        VERSION="${2:-}"
        [[ -n "$VERSION" ]] || errexit "--version nécessite une valeur"
        shift 2
        ;;
      -l | --latest)
        LATEST=1
        shift
        ;;
      -b | --base-dir)
        BASE_DIR="${2:-}"
        [[ -n "$BASE_DIR" ]] || errexit "--base-dir nécessite une valeur"
        shift 2
        ;;
      -p | --preserve)
        local rel="${2:-}"
        [[ -n "$rel" ]] || errexit "--preserve nécessite un chemin"
        PRESERVE+=("$rel")
        shift 2
        ;;
      --preserve-glob)
        local glob="${2:-}"
        [[ -n "$glob" ]] || errexit "--preserve-glob nécessite un motif"
        PRESERVE_GLOBS+=("$glob")
        shift 2
        ;;
      -B | --backup-root)
        BACKUP_ROOT="${2:-}"
        [[ -n "$BACKUP_ROOT" ]] || errexit "--backup-root nécessite un chemin"
        shift 2
        ;;
      --keep-backups)
        local keep="${2:-}"
        [[ -n "$keep" ]] || errexit "--keep-backups nécessite une valeur"
        [[ "$keep" =~ ^[0-9]+$ ]] || errexit "--keep-backups attend un entier"
        KEEP_BACKUPS="$keep"
        shift 2
        ;;
      -s | --skip-verify)
        SKIP_VERIFY=1
        shift
        ;;
      -t | --no-test)
        NO_TEST=1
        shift
        ;;
      -q | --quiet)
        QUIET=1
        shift
        ;;
      --asset-suffix)
        [[ $# -ge 2 ]] || errexit "--asset-suffix nécessite une valeur (utilisez \"\" pour vide)"
        ASSET_SUFFIX="$2"
        shift 2
        ;;
      --cache-dir)
        CACHE_DIR="${2:-}"
        [[ -n "$CACHE_DIR" ]] || errexit "--cache-dir nécessite un chemin"
        shift 2
        ;;
      --reload-nginx)
        RELOAD_NGINX=1
        shift
        ;;
      -f | --force)
        FORCE=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage
        errexit "Option inconnue: $1"
        ;;
    esac
  done
}

detect_installed_version() {
  local -a candidates=(
    "crs-setup.conf.example"
    "rules/REQUEST-901-INITIALIZATION.conf"
  )
  local rel path line version

  for rel in "${candidates[@]}"; do
    path="$BASE_DIR/$rel"
    [[ -f "$path" ]] || continue
    line="$(grep -m1 -E '# OWASP CRS ver\.[0-9.]+' "$path" 2> /dev/null || true)"
    if [[ -n "$line" ]]; then
      version="${line##*ver.}"
      version="${version%%[^0-9.]*}"
      if [[ -n "$version" ]]; then
        printf '%s\n' "$version"
        return 0
      fi
    fi
  done

  if [[ -d "$BASE_DIR/rules" ]]; then
    while IFS= read -r -d '' path; do
      rel="${path#"$BASE_DIR"/}"
      if contains_preserve "$rel"; then
        continue
      fi
      line="$(grep -m1 -E '# OWASP CRS ver\.[0-9.]+' "$path" 2> /dev/null || true)"
      if [[ -n "$line" ]]; then
        version="${line##*ver.}"
        version="${version%%[^0-9.]*}"
        if [[ -n "$version" ]]; then
          printf '%s\n' "$version"
          return 0
        fi
      fi
    done < <(find "$BASE_DIR/rules" -type f -name '*.conf' -print0 2> /dev/null)
  fi

  return 1
}

archive_backup() {
  local ts parent backup_dir backup_file
  ts="$(date +%Y%m%d-%H%M%S)"
  parent="$(dirname "$BASE_DIR")"
  backup_dir="${BACKUP_ROOT:-$parent/crs4-backups}"
  mkdir -p "$backup_dir"
  backup_file="$backup_dir/crs4-${ts}.tar.gz"
  log "Sauvegarde du dossier actuel dans $backup_file"
  (cd "$parent" && tar -czf "$backup_file" "$(basename "$BASE_DIR")")
  echo "$backup_file"
}

prune_backups() {
  [[ $KEEP_BACKUPS -gt 0 ]] || return
  local parent backup_dir
  parent="$(dirname "$BASE_DIR")"
  backup_dir="${BACKUP_ROOT:-$parent/crs4-backups}"
  [[ -d "$backup_dir" ]] || return

  local -a existing
  mapfile -t existing < <(find "$backup_dir" -maxdepth 1 -type f -name 'crs4-*.tar.gz' -printf '%T@\t%p\n' | sort -nr | cut -f2-)

  local idx=0 file
  for file in "${existing[@]}"; do
    idx=$((idx + 1))
    if [[ $idx -gt $KEEP_BACKUPS ]]; then
      rm -f "$file"
      log "Backup supprimée: $file"
    fi
  done
}

prepare_preserve_list() {
  local defaults=(
    "crs-setup.conf"
    "rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf"
    "rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf"
  )

  if [[ ${#PRESERVE[@]} -eq 0 ]]; then
    PRESERVE=()
  fi

  local rel
  for rel in "${defaults[@]}"; do
    add_preserve_path "$rel"
  done

  discover_plugin_preserve
  apply_preserve_globs
}

discover_plugin_preserve() {
  local plugin_dir="$BASE_DIR/plugins"
  [[ -d "$plugin_dir" ]] || return

  while IFS= read -r -d '' path; do
    local name
    name="$(basename "$path")"
    case "$name" in
      empty-*.conf | README.md)
        continue
        ;;
    esac
    local rel
    rel="${path#"$BASE_DIR"/}"
    add_preserve_path "$rel"
  done < <(find "$plugin_dir" -mindepth 1 \( -type f -o -type l \) -print0)
}

apply_preserve_globs() {
  if [[ ${#PRESERVE_GLOBS[@]} -eq 0 ]]; then
    return 0
  fi
  local pattern path rel
  shopt -s nullglob
  for pattern in "${PRESERVE_GLOBS[@]}"; do
    for path in "$BASE_DIR"/$pattern; do
      [[ -e "$path" ]] || continue
      rel="${path#"$BASE_DIR"/}"
      add_preserve_path "$rel"
    done
  done
  shopt -u nullglob
}

ensure_cache_dir() {
  mkdir -p "$CACHE_DIR"
}

try_fetch_asset() {
  local asset="$1" sig_asset="$2" tarball="$3" sig="$4" base_url="$5"
  local cache_tar="$CACHE_DIR/$asset"
  local cache_sig="$CACHE_DIR/$sig_asset"

  if [[ -f "$cache_tar" && -f "$cache_sig" ]]; then
    cp "$cache_tar" "$tarball"
    cp "$cache_sig" "$sig"
    log "Archive récupérée depuis le cache ($asset)"
    USED_ASSET="$asset"
    return 0
  fi

  local tmp_tar="$tarball.tmp"
  local tmp_sig="$sig.tmp"

  if ! curl -fsSL "${base_url}/${asset}" -o "$tmp_tar"; then
    rm -f "$tmp_tar" "$tmp_sig"
    return 1
  fi

  if ! curl -fsSL "${base_url}/${sig_asset}" -o "$tmp_sig"; then
    rm -f "$tmp_tar" "$tmp_sig"
    log "Signature absente pour ${asset}, tentative sur une autre archive"
    return 1
  fi

  ensure_cache_dir
  mv "$tmp_tar" "$cache_tar"
  mv "$tmp_sig" "$cache_sig"
  cp "$cache_tar" "$tarball"
  cp "$cache_sig" "$sig"
  log "Archive téléchargée (${asset})"
  USED_ASSET="$asset"
  return 0
}

fetch_tarball_with_fallback() {
  local tarball="$1" sig="$2" base_url="$3"
  local asset_base="coreruleset-${VERSION}"
  local -a candidates=()
  local candidate sig_candidate

  USED_ASSET=""

  if [[ -n "$ASSET_SUFFIX" ]]; then
    candidates+=("${asset_base}${ASSET_SUFFIX}.tar.gz")
  fi
  candidates+=("${asset_base}.tar.gz")

  for candidate in "${candidates[@]}"; do
    sig_candidate="${candidate}.asc"
    if try_fetch_asset "$candidate" "$sig_candidate" "$tarball" "$sig" "$base_url"; then
      return 0
    fi
  done

  errexit "Impossible de télécharger une archive CRS pour la version ${VERSION}"
}

save_preserve_files() {
  local tmp_preserve="$1"
  mkdir -p "$tmp_preserve"
  local rel
  for rel in "${PRESERVE[@]}"; do
    local src="$BASE_DIR/$rel"
    if [[ -e "$src" ]]; then
      local dest="$tmp_preserve/$rel"
      mkdir -p "$(dirname "$dest")"
      cp -a "$src" "$dest"
      log "Préservé: $rel"
    fi
  done
}

restore_preserve_files() {
  local tmp_preserve="$1"
  local rel
  for rel in "${PRESERVE[@]}"; do
    local saved="$tmp_preserve/$rel"
    local target="$BASE_DIR/$rel"
    [[ -e "$saved" ]] || continue
    if [[ -e "$target" ]]; then
      mv "$target" "$target.upstream"
      log "Version upstream sauvegardée: $rel.upstream"
    fi
    mkdir -p "$(dirname "$target")"
    cp -a "$saved" "$target"
    log "Version préservée restaurée: $rel"
  done
}

verify_signature() {
  local tarball="$1" sig="$2"
  if [[ $SKIP_VERIFY -eq 1 ]]; then
    log "Vérification GPG sautée (--skip-verify)"
    return
  fi
  require_cmd gpg
  log "Vérification GPG..."
  gpg --verify "$sig" "$tarball" || errexit "Signature GPG invalide"
}

sync_release() {
  local src="$1"
  require_cmd rsync
  log "Synchronisation vers $BASE_DIR (suppression des fichiers obsolètes)"
  rsync -a --delete "$src/" "$BASE_DIR/"
}

run_nginx_test() {
  if [[ $NO_TEST -eq 1 ]]; then
    log "nginx -t non exécuté (--no-test)"
    return
  fi
  if command -v nginx > /dev/null 2>&1; then
    log "Exécution de nginx -t"
    if ! nginx -t; then
      errexit "nginx -t a échoué"
    fi
  else
    log "Commande nginx introuvable, test ignoré"
  fi
}

reload_nginx() {
  if [[ $RELOAD_NGINX -eq 0 ]]; then
    return
  fi

  log "Reload nginx (--reload-nginx)"

  if command -v systemctl > /dev/null 2>&1; then
    if systemctl reload nginx; then
      log "systemctl reload nginx OK"
      return
    fi
    log "systemctl reload nginx a échoué, tentative nginx -s reload"
  fi

  if command -v nginx > /dev/null 2>&1; then
    if nginx -s reload; then
      log "nginx -s reload OK"
      return
    fi
  fi

  errexit "Impossible de recharger nginx automatiquement"
}

main() {
  parse_args "$@"

  [[ -d "$BASE_DIR" ]] || errexit "Dossier inexistant: $BASE_DIR"

  if [[ $LATEST -eq 1 ]]; then
    fetch_latest_version
  fi

  [[ -n "$VERSION" ]] || errexit "Spécifiez --version ou --latest"

  prepare_preserve_list

  if INSTALLED_VERSION="$(detect_installed_version)"; then
    log "Version CRS détectée: $INSTALLED_VERSION"
    if [[ $FORCE -eq 0 && "$INSTALLED_VERSION" == "$VERSION" ]]; then
      log "CRS ${VERSION} déjà installée. Utilisez --force pour forcer la mise à jour."
      exit 0
    fi
    if [[ $FORCE -eq 1 && "$INSTALLED_VERSION" == "$VERSION" ]]; then
      log "Version identique détectée (${VERSION}) mais mise à jour forcée (--force)."
    fi
  else
    INSTALLED_VERSION=""
    log "Impossible de détecter la version CRS installée (aucun motif « # OWASP CRS ver.X » trouvé)."
  fi

  require_cmd curl
  require_cmd tar

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  TMP_DIR_CLEANUP="$tmp_dir"
  trap 'if [[ -n ${TMP_DIR_CLEANUP-} ]]; then rm -rf "$TMP_DIR_CLEANUP"; fi' EXIT

  local tarball="${tmp_dir}/coreruleset-${VERSION}.tar.gz"
  local sig="${tarball}.asc"
  local base_url="https://github.com/coreruleset/coreruleset/releases/download/v${VERSION}"

  log "Téléchargement de CRS ${VERSION} (suffixe préféré: ${ASSET_SUFFIX:-<aucun>})"
  fetch_tarball_with_fallback "$tarball" "$sig" "$base_url"
  if [[ -n "$USED_ASSET" ]]; then
    log "Archive utilisée: $USED_ASSET"
  fi
  verify_signature "$tarball" "$sig"

  log "Extraction de l'archive"
  tar -xzf "$tarball" -C "$tmp_dir"
  local release_dir="$tmp_dir/coreruleset-${VERSION}"
  [[ -d "$release_dir" ]] || errexit "Archive inattendue (coreruleset-${VERSION} absent)"

  local backup_file
  backup_file="$(archive_backup)"

  local preserve_dir="$tmp_dir/preserve"
  save_preserve_files "$preserve_dir"

  sync_release "$release_dir"

  restore_preserve_files "$preserve_dir"

  prune_backups

  run_nginx_test
  reload_nginx

  log "Mise à jour terminée. Sauvegarde: $backup_file"
  log "Comparez vos fichiers préservés avec les nouvelles versions *.upstream si nécessaire."
}

main "$@"

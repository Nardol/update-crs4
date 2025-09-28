CRS4 – état au 2025-09-27
=========================

Contexte
--------
On reste sur la structure historique `/etc/modsecurity/crs4`. L’objectif est de
faciliter les mises à jour sans toucher à l’architecture existante.

Ce qui est fait
---------------
1. Répertoire d’exemple remis à neuf avec CRS 4.16.0 (archive « minimal »)
   dans `etc/modsecurity/crs4/`.
2. `update_crs_inplace.sh` privilégie désormais l’archive minimale, retombe sur
   l’archive complète si nécessaire, gère un cache local, limite les sauvegardes
   via `--keep-backups`, peut recharger nginx (`--reload-nginx`), et restaure
   automatiquement les fichiers sensibles (y compris les plugins personnalisés
   détectés dans `plugins/`).
3. README mis à jour pour documenter l’usage, le fonctionnement de l’archive
   minimale et la suppression des fichiers obsolètes.

À faire (lorsque tu reprendras)
-------------------------------
1. Lister les fichiers que tu modifies habituellement (ex : exclusions
   spécifiques) et les ajouter via `--preserve` si besoin.
2. Tester le script sur un environnement de test ou avec `--no-test` et vérifier
   que la sauvegarde et la restauration fonctionnent.
3. Mettre en place un rappel (cron/systemd) si tu souhaites automatiser la
   vérification de nouvelles releases.
4. Sur le serveur de prod : importer la clé GPG si absent, lancer
   `update_crs_inplace.sh --latest`, puis examiner les fichiers `*.upstream`
   générés pour mettre à jour tes réglages.

Notes
-----
- Les copies upstream sont nommées `*.upstream` (ex : `crs-setup.conf.upstream`).
- Les sauvegardes sont stockées dans `../crs4-backups/` par défaut.
- Le dossier d’exemple reflète la structure livrée par `coreruleset-<version>-minimal.tar.gz`.
- Les fichiers plugins spécifiques détectés sont ajoutés automatiquement à la
  liste de préservation, tout comme les motifs fournis via `--preserve-glob`.
- Le cache des archives se situe par défaut dans `${TMPDIR:-/tmp}/coreruleset-cache`.
- Workflows CI/CD disponibles : lint (ShellCheck + shfmt), release packaging sur
  tag `v*`, et vérification hebdomadaire des nouvelles versions CRS (ouvre une
  issue si besoin).
- `--reload-nginx` force un reload via `systemctl` ou `nginx -s reload` après
  la validation `nginx -t`.

# DegenView Flatpak repository

The signed Flatpak repository for [DegenView](https://github.com/degenview/degenview), served at
<https://flatpak.degenview.app>. This repo holds only the scripts and the workflow that build it.

## Install

The runtime comes from Flathub, so [set Flathub up](https://flathub.org/setup) first.

```bash
flatpak remote-add --if-not-exists degenview https://flatpak.degenview.app/degenview.flatpakrepo
flatpak install degenview es.nico.degenview//stable
```

Release candidates are on the `beta` branch (`es.nico.degenview//beta`). Update with
`flatpak update`; DegenView itself does not check for updates when it is installed this way.

## How it is built

`.github/workflows/publish.yml` runs every six hours and by hand. It pulls from the app's GitHub
releases; nothing in `degenview/degenview` holds a token for this repo.

| Job | Secrets | What it does |
| --- | --- | --- |
| `fetch` | none | `scripts/fetch.sh` picks the newest `stable` and `beta` release made by the app's release workflow after `SINCE_PUBLISHED_AT` (`config.env`), downloads both CPUs' bundles and verifies them (`gh release verify`, `verify-asset`, `gh attestation verify`). Stops when the live `state.json` already lists the same releases. |
| `sign` | `FLATPAK_GPG_KEY` (environment `publish`, `main` only) | `scripts/build-repo.sh` imports the bundles into an OSTree repo, signs it, and writes the `.flatpakrepo`, the `.flatpakref` files, the landing page and `state.json`. `scripts/smoke-test.sh` then installs the app from that repo over `file://`. |
| `deploy` | none | Publishes the result with GitHub Pages. |

The repo is rebuilt from scratch on every change. A bundle holds one commit and no history, so only
the newest release of each channel is served; older ones stay on the releases page.

Releases are assigned to a Flatpak branch by `degenview/degenview`'s `release.yml`: `stable` for a
final release, `beta` for a tag with a hyphen (a release candidate). Bundles from before that (branch
`master`) are skipped.

## One-time setup (maintainer)

1. `tools/generate-signing-key.sh private.asc`, then paste the file into a secret named
   `FLATPAK_GPG_KEY` in the `publish` environment (deployment branches: `main` only), keep a copy in
   a password manager, and delete the file. Treat the key as permanent: changing it means every user
   has to add the repository again.
2. Settings > Pages: source "GitHub Actions", custom domain `flatpak.degenview.app`, enforce HTTPS.
3. DNS: `CNAME flatpak -> degenview.github.io`.
4. Run **Publish** once by hand after the first release built with channels, and check the job logs.

## Limits

GitHub Pages is not a download network: sites are limited to 1 GB and about 100 GB of traffic a month,
and `summary` is cached for roughly ten minutes, so an update can appear that much late. The site is
plain static files, so only the `deploy` job would change if it moved elsewhere.

Nothing here has been run yet. The Flatpak commands in `build-repo.sh` and `smoke-test.sh` are written
from the manuals; the first run of the workflow is their test.

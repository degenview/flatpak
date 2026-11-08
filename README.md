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
| `fetch` | none | `scripts/fetch.sh` picks the releases for `stable` and `beta` (below) from those made by the app's release workflow after `SINCE_PUBLISHED_AT` (`config.env`), downloads both CPUs' bundles and verifies them (`gh release verify`, `verify-asset`, `gh attestation verify`). Stops when the live `state.json` already lists the same releases. |
| `sign` | `FLATPAK_GPG_KEY` (environment `publish`, `main` only) | `scripts/build-repo.sh` imports the bundles into an OSTree repo, signs it, and writes the `.flatpakrepo`, the `.flatpakref` files, the landing page and `state.json`. `scripts/smoke-test.sh` then installs the app from that repo over `file://`. |
| `deploy` | none | Publishes the result with GitHub Pages. |

The repo is rebuilt from scratch on every change. A bundle holds one commit and no history, so only
one release per branch is served; older ones stay on the releases page.

`degenview/degenview`'s `release.yml` builds a final release on `stable` and an `-rc.N` tag (a
release candidate) on `beta`. An `-alpha.N` or `-beta.N` tag is offered to no channel by the app's
updater, so it is built on `dev` and never published here. Bundles from before that (branch
`master`) are skipped. Releases are
compared by version, not upload time:

- `stable` is the newest final release.
- `beta` is the newest release the Release Candidate channel of the app offers: a final or an
  `-rc.N`, never an `-alpha.N` or `-beta.N`. A Flatpak follows its own branch and never switches, and
  the app's Release Candidate channel accepts finals, so when a final is the newest release it is
  copied onto `beta` as well (`flatpak build-commit-from`, signed). Someone on `beta` then moves from
  release candidates to the final and on to the next candidate.

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

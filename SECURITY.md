# Security policy

Report a problem with this repository, or with how the packages are signed, privately through
[GitHub's private vulnerability reporting](https://github.com/degenview/flatpak/security/advisories/new)
(Security tab, "Report a vulnerability"). Do not open a public issue for it. For the app itself, use
the [policy of degenview/degenview](https://github.com/degenview/degenview/security/policy).

## What protects what you install

- Every bundle comes from an immutable release made by the app's own release workflow, and is checked
  here before it is imported: `gh release verify`, `gh release verify-asset`, and
  `gh attestation verify --repo degenview/degenview --signer-workflow degenview/degenview/.github/workflows/release.yml`.
- The repository is signed with a GPG key that only the `publish` environment of this repository can
  read, and only the `sign` job uses it. The job that downloads and verifies files has no secrets.
- Flatpak checks that signature on every install and update. The key's fingerprint is on
  https://flatpak.degenview.app.

## What does not

- Anyone who can change the `publish` environment's secret, or push to `main` here, can publish a repo
  you will trust. Both are limited to the maintainer.
- A lost or leaked signing key cannot be replaced quietly: users would have to add the repository again
  with the new key.

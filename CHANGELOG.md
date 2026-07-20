# Changelog

## Unreleased

- Environments (MEP 8): `mip env create/list/delete` manage addressable
  package roots — named envs in `<root>/envs/<name>` (conda-style) or local
  path envs like `./.mip` (venv-style) — and `mip activate` /
  `mip deactivate` (aliases for `mip env activate/deactivate`) point the
  session at one. Activation swaps the session's load state (sticky
  packages included; mip excepted) and moves `MIP_ROOT`; deactivation
  restores the prior root and package set. Session commands act on the
  active env, printing a leading `environment:` line while one is active.
  The self flows (`mip uninstall mip`, `mip update mip`) now trigger only
  when the active root is the root mip runs from; elsewhere the identity
  is an ordinary, inert package.
- Local installs (copy and editable) now auto-install missing channel
  dependencies declared in `mip.yaml` instead of erroring with
  `mip:dependencyNotFound`; the same applies to `mip update` of local
  packages. (#161)

## 1.1.0 (2026-07-16)

- Installing from a URL now takes the URL as a positional argument:
  `mip install <url> --name <name>`. The `--name` flag is optional; without
  it, mip prompts for a name with a default derived from the URL (File
  Exchange slug, GitHub repo name, or zip filename), and `MIP_CONFIRM=y`
  accepts the default non-interactively. The old `--url` flag raises an
  error pointing at the new syntax. (#339)
- mip prints a self-update notice when the core channel index is loaded and
  it lists a newer mip version, suggesting `mip update mip`. If the index
  declares a `mip_compatibility_floor` above the installed version, the
  notice states that the update is required. The check is best-effort and
  never interrupts the running command. (#344)

## 1.0.0 (2026-07-07)

Initial stable release.

# Changelog

## 1.3.0 (2026-11-04)

- Packages published from their own GitHub repository (MEP 10).
  `mip install` accepts `<owner>/<repo>`, `gh/<owner>/<repo>`, and
  `[https://]github.com/<owner>/<repo>`, optionally with `@<version>`.
  mip reads the index from the repository's `mip-index` release and
  installs the package as `gh/<owner>/<repo>`. The 2-part form falls back
  to the personal channel `<owner>/<owner>` when the repository publishes
  no mip package. `update`, `info`, and `avail <owner>/<repo>` support
  repository packages, and `mip init -g` writes the publishing workflow
  (`repo-build.yml`). Personal-channel packages now display as
  `<owner>/<owner>/<pkg>`. (#360)
- Dependencies may be written `github.com/<owner>/<repo>`. A 2-part
  `<owner>/<name>` dependency resolves as it does for `mip install`: to
  the repository package if there is one, otherwise to the
  personal-channel package `<owner>/<owner>/<name>`. Bare-name
  dependencies of a repository package resolve to `mip-org/core`. (#360)
- Tab completion no longer intermittently fails with "Failed to parse
  JSON file ... functionSignatures.json". mip now replaces the file with
  an atomic rename when the JVM is available, and skips the rewrite when
  the signatures are unchanged. (#359)

## 1.2.0 (2026-10-14)

- Environments (MEP 8): `mip env create/list/delete` manage addressable
  package roots — named envs in `<root>/envs/<name>` (conda-style) or local
  path envs like `./.mip` (venv-style) — and `mip activate` /
  `mip deactivate` (aliases for `mip env activate/deactivate`) point the
  session at one. Activation swaps the session's load state (sticky
  packages included; the running mip excepted) and moves `MIP_ROOT`;
  deactivation restores the prior root and package set. Session commands
  act on the active env, printing a leading `environment:` line while one
  is active. Bulk unloads (`unload --all [--force]`, `reset`, the
  activation swap, pruning) never unload the package providing the
  running mip — so a loaded preview build of mip (e.g.
  `mip-org/labs/mip`) survives activation; explicitly unloading it still
  works.
  The self flows (`mip uninstall mip`, `mip update mip`) now trigger only
  when the active root is the root mip runs from; elsewhere the identity
  is an ordinary, inert package. (#346)
- Local installs (copy and editable) now auto-install missing channel
  dependencies declared in `mip.yaml` instead of erroring with
  `mip:dependencyNotFound`; the same applies to `mip update` of local
  packages. (#161)
- A bare dependency of a package that is itself on no channel — installed
  from a local directory, in editable mode, or from `fex`/`web`/`mhl` —
  now resolves to whatever is installed under that name, instead of
  always to `mip-org/core`. Previously a package developed alongside its
  dependency could not be installed at all: `mip install -e .` resolved
  its bare dependency to `mip-org/core/<name>` and an editable install of
  that dependency, being `local/<name>`, could never satisfy it.
  Packages installed from a channel are unaffected, and a missing
  dependency is still fetched from `mip-org/core`. (#356)
- `mip install <file-exchange-url>` works again. File Exchange now
  requires signing in for its `?download=true` links, so mip resolves the
  download through the MathWorks add-on registry instead and records the
  versioned `addons.mathworks.com` zip URL as the package's `repository`.
  Submissions that are not in the registry, such as MathWorks support
  packages, fail with `mip:install:fexResolveFailed`. (#358)
- Re-loading an already-loaded package now moves its own paths to the
  front of the MATLAB path, so the most recently loaded package also wins
  function shadowing, not only name resolution. Scripts that re-load
  packages defensively will now reorder the path. (#349)
- The self operations (`mip update mip`, `mip uninstall mip`,
  `mip install mip@<version>`) now check the session first and refuse in
  an active environment, when another mip is loaded, or in a standalone
  session. The loaded package providing the running mip cannot be updated
  or uninstalled, `mip update --all` skips it, and no mip package can be
  installed into or loaded from an environment. (#354)
- `mip uninstall mip` no longer prints spurious name-conflict warnings
  (for example on MATLAB Online) while it resets the path. (#357)

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

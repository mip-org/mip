# MIP Package Manager

A package manager for MATLAB/MEX. Handles installing, updating, loading, and unloading packages from channels (GitHub-hosted package repositories).

## Architecture

- `mip.m` — CLI entry point, dispatches to command handlers
- `+mip/` — MATLAB package namespace containing all functionality
  - Core commands: `install.m`, `update.m`, `uninstall.m`, `load.m`, `unload.m`, `list.m`, `info.m`, `avail.m`, `bundle.m`
  - `+build/` — Package preparation, compilation, script generation
  - `+channel/` — Network operations (downloading .mhl archives, fetching channel indexes)
  - `+config/` — Config file reading (mip.yaml, mip.json, build fields, local install setup)
  - `+dependency/` — Dependency graph resolution and topological sorting
  - `+parse/` — Input parsing (package args, channel specs, YAML, FQN construction)
  - `+paths/` — Directory and path management (package dirs, source dirs, cleanup)
  - `+resolve/` — Package discovery and resolution (name resolution, version selection, dependency traversal)
  - `+state/` — Persistent state management and queries (key-value store, load/install status, pruning)
- `tests/` — Unit tests using MATLAB's `matlab.unittest` framework

## Key Concepts

- **FQN (Fully Qualified Name)**: variable-length, source-type prefixed.
  - GitHub channel packages: `gh/<owner>/<channel>/<package>` (e.g., `gh/mip-org/core/chebfun`)
  - Packages published from their own GitHub repository (MEP 10): `gh/<owner>/<repo>` (e.g., `gh/fastalgorithms/chunkie`); the package name equals the repo name. `parse_package_arg` sets `is_repo` and `channel = ''`; `make_fqn(owner, '', name)` builds one.
  - Local directory / editable installs: `local/<package>`
  - File Exchange installs: `fex/<package>`
  - Generic remote .zip installs: `web/<package>`
- **Display form**: strips the `gh/` prefix (`mip-org/core/chebfun`, `fastalgorithms/chunkie`, `local/foo`, `fex/bar`, `web/baz`). Personal channels are not collapsed (`gh/magland/magland/chunkie` → `magland/magland/chunkie`). See `mip.parse.display_fqn`.
- **User input**: `gh/` is optional for channel packages. The parser accepts bare names, `<category>/<name>` (non-gh), `<owner>/<repo>` (repository package, with `fallback_fqn` = the personal-channel `gh/<owner>/<owner>/<repo>`: install falls back to it on a 404 index, installed-package commands use it when the repo package isn't installed), `gh/<owner>/<repo>` and `https://github.com/<owner>/<repo>` (repository, no fallback), `<owner>/<channel>/<name>` (implicit gh), and `gh/<owner>/<channel>/<name>` (explicit).
- **Bare name**: Just `package` — resolved via priority: `gh/mip-org/core` first, then alphabetical
- **Channels**: Package repositories hosted on GitHub Pages (e.g., `mip-org/mip-core`). Channel identifiers remain 2-part `<owner>/<channel>` — `gh/` is a source-type prefix in FQNs, not part of the channel.
- **Index sources**: a channel `<owner>/<channel>` or a package repository `github.com/<owner>/<repo>` (index at `https://github.com/<owner>/<repo>/releases/download/mip-index/index.json`). `fetch_index`, `index_url` take either; `mip.channel.index_source(fqn)` maps an FQN to its source.
- **Packages installed at**:
  - `<root>/packages/gh/<owner>/<channel>/<package>/` (gh channel)
  - `<root>/packages/gh/<owner>/<repo>/` (gh repository; a dir directly under `gh/<owner>/` containing `mip.json` is a repo package, otherwise a channel)
  - `<root>/packages/local/<package>/`, `<root>/packages/fex/<package>/`, or `<root>/packages/web/<package>/` (non-gh)
- **Editable installs**: Thin wrapper at `local/<pkg>/` pointing to source directory
- **Persistent state**: Uses `setappdata(0, key, value)` for loaded/sticky/directly-loaded package tracking; `directly_installed.txt` for install tracking

## Running Tests

```matlab
addpath('tests'); addpath('tests/helpers');
results = run_tests();
```

Or from any directory:
```matlab
cd /path/to/mip-package-manager
addpath('tests'); addpath('tests/helpers');
results = run_tests();
```

## Development Rules

- **Always add unit tests** for new functionality. Tests go in `tests/Test*.m` as `matlab.unittest.TestCase` subclasses. Use `createTestPackage` and `createTestSourcePackage` helpers to set up fake packages in temporary directories. Use `MIP_ROOT` env var to isolate tests from the real `<root>` directory.
- The special identity `gh/mip-org/core/mip` must always be checked by FQN, never by bare name `'mip'`. Other packages named `mip` on different channels must not get special treatment.

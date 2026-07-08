# Project environments (prototype)

Status: **prototype** on branch `project-environments-prototype`.
Tracking issue: [mip-org/mip#337](https://github.com/mip-org/mip/issues/337).

This adds project-level, lockfile-backed environments to mip — the MATLAB
analog of a `uv`/`pip` virtual environment. A project declares exactly which
mip packages it needs, pins them in a lockfile, and installs them into a
project-local directory instead of the global mip root.

The immediate motivation is [calkit](https://github.com/calkit/calkit)
integration (calkit#1016): calkit wants MATLAB users to define reproducible
environments **without building Docker images**. calkit's only current MATLAB
support is a Docker environment kind that needs a license server and a built
image; a native `mip` environment kind lets it treat MATLAB packages the way
it already treats `uv`/`conda`/`pixi`.

## Files

Everything lives in the project directory (the folder you point `--directory`
at, or the current folder):

| File          | Role                                   | Format | Edited by |
| ------------- | -------------------------------------- | ------ | --------- |
| `mipenv.yaml` | Spec: dependencies + channels          | YAML   | you       |
| `mipenv.lock` | Lock: resolved versions, URLs, SHA-256 | JSON   | mip       |
| `.mip/`       | Project-local install root (`packages/`, cache, install state) | — | mip |

### Why not `mip.toml`?

mip already uses two `mip.*` files that mean different things:

- `mip.yaml` — a **package manifest** (a package author declares its name,
  version, dependencies, paths, and builds).
- `mip.json` — the **installed-package metadata** snapshot written into each
  installed package and read back at load time.

A third `mip.toml` for a *project environment* would be a confusing third
meaning of the `mip.*` prefix. The environment files therefore use a distinct
basename — `mipenv.*` — that reads as "mip environment" and parallels
`venv`/`virtualenv`. The lock uses a `.lock` extension (like `uv.lock`) to
mark it generated; its content is JSON so it round-trips through MATLAB's
native `jsonencode`/`jsondecode` with no extra dependency.

### `mipenv.yaml`

```yaml
# mip project environment specification
name: my-analysis

dependencies:
  - findtria                       # bare name -> resolved against core + channels
  - chebfun@1.0.0                  # pin a version
  - mip-org/labs/treeweave         # fully qualified: pin the channel

channels:                          # extra channels (besides mip-org/core)
  - mip-org/labs                   # consulted, in order, for bare names
```

### `mipenv.lock`

```json
{
  "lock_version": 1,
  "generated_with_mip": "1.0.0",
  "arch": "linux_x86_64",
  "requested": ["findtria", "mip-org/labs/treeweave"],
  "channels": ["mip-org/core", "mip-org/labs"],
  "packages": [
    {
      "fqn": "gh/mip-org/core/aabb-tree",
      "name": "aabb-tree", "owner": "mip-org", "channel": "core",
      "direct": false,
      "version": "master", "architecture": "any",
      "mhl_url": "https://github.com/mip-org/mip-core/releases/download/aabb_tree-master/aabb_tree-master-any.mhl",
      "mhl_sha256": "c57834b5…",
      "source_hash": "9ed6ebea…", "commit_hash": "",
      "dependencies": []
    }
  ]
}
```

The lock records the **full transitive closure** in dependency-first order.
`direct: true` marks packages named directly by the spec (versus dependencies
pulled in transitively). Each entry carries the exact `.mhl` URL and SHA-256,
so `sync` reinstalls without re-resolving.

## Commands

All under a new `mip env` subcommand group. Every subcommand accepts
`--directory <dir>` so a project can hold several environments in different
subdirectories (per the issue's request to "mimic uv and allow a `--directory`
argument").

```
mip env init [--directory <dir>] [--name <name>]     Create mipenv.yaml + .mip
mip env add <pkg> [...] [--channel <c>] [--no-sync]  Add deps, re-lock, install
mip env remove <pkg> [...] [--no-sync]               Remove deps, re-lock, prune
mip env lock [--directory <dir>]                      Resolve spec -> mipenv.lock
mip env sync [--directory <dir>] [--relock]           Install exactly the lock
mip env status [--directory <dir>]                    Show declared/locked/installed
mip env activate [--directory <dir>] [--no-load]      Use env in this session
mip env deactivate                                    Return to the global root
```

Correspondence to uv: `add`≈`uv add`, `remove`≈`uv remove`, `lock`≈`uv lock`,
`sync`≈`uv sync`. `activate` has no uv analog because mip runs *inside* a
MATLAB session (see below).

### Typical flow

```matlab
mip env init --name my-analysis
mip env add findtria
mip env add treeweave --channel mip-org/labs
mip env activate          % installs (if needed) and loads onto the path
% ... your code now sees findtria + treeweave ...
```

Commit `mipenv.yaml` **and** `mipenv.lock`; add `.mip/` to `.gitignore`.
Elsewhere, `mip env sync` reproduces the exact package set from the lock.

## How it works (design)

The whole feature is a thin layer over the existing installer. The key
observation: `mip.paths.root()` already honors the `MIP_ROOT` environment
variable (any directory containing a `packages/` subdir). So a project
environment is just a project-local root at `<project>/.mip`, and every
`mip env` command runs the normal install/resolve/load code against it:

- `mip.env.with_root(root)` temporarily sets `MIP_ROOT` (restoring it on
  scope exit via `onCleanup`). Under that guard, `mip.install`, the resolver,
  the channel-index cache, and the per-project `directly_installed.txt` state
  all operate on the project environment, isolated from the global one.
- `mip.env.resolve_lock` reuses `mip.channel.fetch_index`,
  `mip.resolve.build_package_info_map`, `mip.dependency.build_graph`, and
  `topological_sort` — the same machinery `install` uses — to compute the
  pinned closure without installing.
- `mip.env.sync` installs each locked entry directly from its `mhl_url`
  (verifying `mhl_sha256`) via `mip.channel.download_mhl`/`extract_mhl`, so a
  `sync` from a committed lock does **no** network resolution.
- `mip.env.activate` sets `MIP_ROOT` for the rest of the session and loads the
  direct packages with `mip.load`.

Nothing in the global install path changed; `mip env` is additive.

### New files

```
+mip/mip.m                        (dispatch: added `case 'env'`)
+mip/+env/dispatch.m              mip env <subcommand> router
+mip/+env/init.m  add.m  remove.m  lock.m  sync.m  status.m
+mip/+env/activate.m  deactivate.m
+mip/+env/read_spec.m  write_spec.m         mipenv.yaml I/O
+mip/+env/read_lock.m  write_lock.m         mipenv.lock I/O (JSON)
+mip/+env/resolve_lock.m                    spec -> pinned closure
+mip/+env/project_dir.m  spec_path.m  lock_path.m  env_root.m  with_root.m
```

## calkit integration

calkit models every environment as `{kind, path, ...}` in `calkit.yaml`, with
the lockfile derived as a sibling of `path` (uv → `uv.lock`, pixi →
`pixi.lock`). A native mip kind fits directly:

```yaml
# calkit.yaml
environments:
  matlab:
    kind: mip
    path: mipenv.yaml     # -> lockfile sibling mipenv.lock
```

calkit's per-kind hooks map onto the `mip env` CLI. Because mip runs inside
MATLAB, calkit invokes it through `matlab -batch` (it already does this for the
Docker MATLAB kind and for `requiredFilesAndProducts` dependency detection):

- **check / build the env** (analog of `uv sync`):
  `matlab -batch "mip env sync --directory <envdir>"`
  — lockfile path for DVC = `<envdir>/mipenv.lock`.
- **run a command in the env** (`calkit xenv`, analog of `uv run …`):
  `matlab -batch "cd('<wdir>'); mip env activate --directory <envdir>; <command>"`
  — `activate` sets the project root and loads the locked packages, then the
  user's MATLAB command runs with those packages on the path. No Docker image,
  no license server beyond the user's normal MATLAB.

This is the smallest change on calkit's side: add a `kind == "mip"` branch to
`get_env_lock_fpath` (return the `mipenv.lock` sibling) and to the `xenv`
runner (wrap the command as above), mirroring the existing `uv` branch.

## Prototype limitations / open questions

- **Cross-platform locks.** The lock records the current architecture's
  `.mhl` URL + SHA. `sync` on a *different* arch re-resolves that package from
  its channel by the locked version (preserving the version pin) to get the
  right binary. A fuller solution would lock all architectures at once (as
  `uv.lock` does for wheels). The lock format has room to grow into that.
- **Floating versions.** Branch "versions" like `main`/`master` are not
  immutable; the lock also records `source_hash`/`commit_hash` for traceability
  but cannot yet pin an install to a specific commit (needs channel support).
- **Project discovery** does not walk up the directory tree; the project is
  either explicit (`--directory`) or the current folder.
- **Session load state** (`MIP_LOADED_PACKAGES`) is global to the MATLAB
  session, so activating a second environment in the same session mixes paths.
  Restart MATLAB (or `mip env deactivate`) between environments.

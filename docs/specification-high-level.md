# MIP Cheat Sheet

A quick overview of how the MIP package manager works. For exact rules and edge cases, see [behavior-reference.md](behavior-reference.md).

---

## What is MIP?

MIP is a package manager for MATLAB. It installs, loads, updates, and unloads packages from **channels** -- package repositories hosted on GitHub Pages.

Packages live at `~/.mip/packages/<owner>/<channel>/<name>/`.

---

## Naming

Every package has a **fully qualified name (FQN)**: `owner/channel/name`

```
mip-org/core/chebfun
│        │       └── package name
│        └── channel
└── GitHub owner
```

You can also use just the **bare name** (`chebfun`). MIP resolves it by checking `mip-org/core` first, then alphabetically among other channels.

Pin a version with `@`: `chebfun@1.2.0`, `mip-org/core/chebfun@main`

---

## Commands at a Glance

| Command | What it does |
|---|---|
| `mip install <pkg>` | Install from channel (+ dependencies) |
| `mip install ./path` | Install from local directory (copy) |
| `mip install -e ./path` | Install from local directory (editable -- source changes take effect immediately) |
| `mip uninstall <pkg>` | Remove package and prune orphaned deps |
| `mip update <pkg>` | Reinstall latest version, preserve load state |
| `mip update --deps <pkg>` | Update package and its dependencies |
| `mip update --all` | Update all installed packages |
| `mip update --no-compile <pkg>` | Update editable local install without re-running compile_script |
| `mip load <pkg>` | Add package (+ deps) to MATLAB path |
| `mip unload <pkg>` | Remove package from path, prune unused deps |
| `mip list` | List installed packages |
| `mip info <pkg>` | Show package details (installed + remote) |
| `mip avail` | List packages available in a channel |
| `mip compile <pkg>` | Run the package's compile script |
| `mip test <pkg>` | Run the package's test script |
| `mip bundle ./path` | Build a `.mhl` archive from a local package |
| `mip reset` | Unload everything and clear all state |
| `mip version` | Print mip version |
| `mip index` | Print channel index URL |
| `mip root` | Print mip root directory |

---

## Installing

**From a channel:**
```
mip install chebfun                          % from mip-org/core (default)
mip install chebfun --channel mylab/custom   % from a specific channel
mip install mip-org/core/chebfun             % using FQN (--channel ignored)
mip install chebfun@1.2.0                    % pin a version
```

**From a local directory:**
```
mip install ./mypackage                      % copy into ~/.mip
mip install -e ./mypackage                   % editable (symlink-like)
mip install -e ./mypackage --no-compile      % editable, skip compilation
```

A bare name like `chebfun` is always treated as a channel install, even if a `chebfun/` directory exists locally. Use `./chebfun` for local install.

Dependencies are installed automatically for channel packages. For local packages, dependencies must already be installed.

---

## Loading and Unloading

```
mip load chebfun              % add to path (loads deps too)
mip load chebfun --sticky     % sticky: survives `mip unload --all`
mip load chebfun --install    % install first if needed

mip unload chebfun            % remove from path, prune unused deps
mip unload --all              % unload everything except sticky packages
mip unload --all --force      % unload everything (sticky too)
```

Dependencies are loaded automatically but tracked separately -- they get pruned when no longer needed.

---

## Updating

```
mip update chebfun            % update if newer version available
mip update --force chebfun    % force reinstall even if up to date
mip update --deps chebfun     % update chebfun and its dependencies
mip update --all              % update all installed packages
mip update ./mypackage        % local packages always reinstall
mip update --no-compile <pkg> % editable local: skip compile_script
```

Only the named packages are updated -- existing dependencies are left as-is unless `--deps` is specified. Missing dependencies are installed automatically; orphaned dependencies are pruned. Load state is preserved across the update.

---

## Key Behaviors

**The `mip-org/core/mip` package is special.** It's the package manager itself. It cannot be unloaded, uninstalled, or pruned.

**Directly installed vs. dependencies.** MIP tracks which packages you explicitly installed vs. which were pulled in as dependencies. Orphaned dependencies are automatically pruned on uninstall or unload.

**Editable installs** create a thin wrapper that points to your source directory. Changes to source files take effect immediately. `mip update` re-runs compilation by default; pass `--no-compile` to skip it for a given update.

**Sticky packages** survive `mip unload --all`. Use `--force` to override.

---

## Package Files

**`mip.yaml`** -- lives in your source directory, defines a package:
```yaml
name: mypackage
version: "1.0.0"
dependencies: [dep1, owner/channel/dep2]
paths:
  - path: "src"
builds:
  - architectures: [any]
    compile_script: "compile.m"
    test_script: "run_tests.m"
```

**`mip.json`** -- generated at install time, lives in the installed package directory. Contains resolved metadata (name, version, architecture, dependencies, paths).

**`.mhl`** -- a ZIP archive containing `mip.json` and the package source.

---

## Filesystem Layout

```
~/.mip/
  packages/
    directly_installed.txt        # tracks user-installed packages
    mip-org/
      core/
        chebfun/
          mip.json
          chebfun/                # source files
    local/
      local/
        mypackage/                # local install wrapper
```

Override the root with the `MIP_ROOT` environment variable (must point to an existing directory with a `packages/` subdirectory).

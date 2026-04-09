# MIP Package Manager: Behavior Reference

This document is the authoritative reference for the behavior of the MIP package manager. It specifies the exact rules governing every operation, including edge cases. All behaviors described here should be reflected by unit tests.

---

## 1. Core Concepts

### 1.1 Fully Qualified Name (FQN)

Every installed package has a unique **FQN** of the form `org/channel/name` (e.g., `mip-org/core/chebfun`). The three components are:

- **org** -- the GitHub organization that hosts the channel repository
- **channel** -- the channel name within that organization
- **name** -- the package name

All three components must match the regex `^[-a-zA-Z0-9_.]+$` and must not be `.` or `..`.

### 1.2 Bare Names

A **bare name** is just the package name without org/channel (e.g., `chebfun`). Bare names are resolved to FQNs using context-dependent rules described in section 2.4.

### 1.3 Version Strings

Versions are either **numeric** (e.g., `1.2.3`) or **non-numeric** (e.g., `main`, `master`, `unspecified`). Numeric versions use dot-separated components that are each parseable as numbers.

### 1.4 The `@version` Suffix

Any package argument (bare or FQN) can include `@version` to pin a specific version:
- `chebfun@1.2.0`
- `mip-org/core/mip@main`

The `@` is parsed from the last occurrence in the string. The version suffix is stripped before resolving the package identity.

### 1.5 Channels

A channel is a package repository hosted on GitHub Pages at `https://<org>.github.io/mip-<channel>/index.json`. The default channel is `mip-org/core`.

Channel strings can be specified as:
- `org/channel` (e.g., `mip-org/core`, `mylab/custom`)

A bare channel name (e.g., just `core`) is **invalid** and raises `mip:invalidChannel`.

### 1.6 The `local/local` Channel

Packages installed from local directories (both editable and non-editable) are placed under the synthetic channel `local/local`. This is not a real GitHub-hosted channel; it exists only on the local filesystem.

### 1.7 The `mip-org/core/mip` Identity

The package `mip-org/core/mip` is the package manager itself. It has special protections:

- It is **always** marked as loaded and sticky when any `mip` command runs.
- It **cannot** be unloaded via `mip unload` (raises `mip:cannotUnloadMip`).
- It **cannot** be uninstalled via `mip uninstall` (prints instructions instead).
- It survives `mip unload --all --force`.
- It is never pruned during dependency pruning.

**Important**: These protections apply **only** to the exact FQN `mip-org/core/mip`. A package named `mip` on any other channel (e.g., `mylab/custom/mip`, `local/local/mip`) is treated as a normal package.

---

## 2. Parsing and Resolution

### 2.1 Parsing a Package Argument (`parse_package_arg`)

Input is split on `/` after stripping any `@version` suffix:

| Input format | Result |
|---|---|
| `name` | bare name: `is_fqn=false`, `org=''`, `channel=''` |
| `org/channel/name` | FQN: `is_fqn=true`, org/channel/name populated |
| `a/b` (2 parts) | **Error** `mip:invalidPackageSpec` |
| `a/b/c/d` (4+ parts) | **Error** `mip:invalidPackageSpec` |

Validation rules:
- Each non-empty component must match `^[-a-zA-Z0-9_.]+$`
- `.` and `..` are rejected as names (but `.github` is valid because it starts with `.` followed by more chars -- the regex allows it, and the explicit `.`/`..` check doesn't match)
- Spaces and special characters (`!`, `#`, etc.) are rejected

### 2.2 Parsing a Channel Spec (`parse_channel_spec`)

| Input | Result |
|---|---|
| `''` (empty) | defaults to `mip-org`, `core` |
| `org/channel` | parsed as-is |
| `name` (single part) | **Error** `mip:invalidChannel` |
| `a/b/c` (3+ parts) | **Error** `mip:invalidChannel` |

### 2.3 Parsing the `--channel` Flag (`parse_channel_flag`)

Scans an argument list for `--channel <value>` and extracts it:
- Returns the channel string and the remaining arguments with `--channel` and its value removed
- If `--channel` appears without a following value, raises `mip:missingChannelValue`
- If `--channel` is absent, returns empty string and the original arguments unchanged
- Works regardless of position in the argument list (beginning, middle, or end)

### 2.4 Resolving a Dependency Name

There are **three different resolution contexts** with different priority rules. This is a critical area of the system.

#### 2.4.1 Resolving a Bare Name Among Installed Packages (`resolve_bare_name`)

Used by: `mip load`, `mip update`, `mip compile` (when given a bare name)

Priority:
1. `mip-org/core/<name>` -- if installed
2. First alphabetically by FQN among all other installed matches

Returns empty string if no match found.

#### 2.4.2 Resolving a Bare Name for Unload (`resolveLoadedFqn` in `unload.m`)

Used by: `mip unload` (when given a bare name)

Searches **loaded** packages (not installed):
1. If exactly one loaded package matches the bare name, use it
2. If multiple loaded packages match, use the **most recently loaded** one (last in the `MIP_LOADED_PACKAGES` list)
3. If none match, returns the bare name as-is (caller handles "not loaded" message)

#### 2.4.3 Resolving a Bare Name for Uninstall (`find_all_installed_by_name`)

Used by: `mip uninstall` (when given a bare name)

1. If exactly one installed package matches, resolve to it
2. If multiple installed packages match, **refuse** and print all matching FQNs, asking the user to disambiguate
3. If none match, report "not installed"

#### 2.4.4 Resolving a Dependency During Load (`resolveDependency` in `load.m`)

Used by: the load process when resolving bare-name dependencies listed in `mip.json`

Priority:
1. If the dependency is a FQN, use as-is
2. Try **same channel** as the parent package (check if directory exists)
3. Try `mip-org/core/<name>` (check if directory exists)
4. Fall back to general `resolve_bare_name` (which has its own priority)
5. If nothing found, raise `mip:dependencyNotFound`

#### 2.4.5 Resolving a Dependency During Remote Install (`build_dependency_graph`)

Used by: the install process when building the dependency graph from channel indexes

- If the dependency is a FQN, use as-is
- If bare name, **always** resolve to `mip-org/core/<name>`

Note: this differs from load-time resolution (2.4.4) which tries the same channel first.

#### 2.4.6 Resolving a Dependency During Prune (`getAllDependencies` in `unload.m` and `uninstall.m`)

Used by: dependency pruning after unload or uninstall

Priority:
1. If the dependency is a FQN, use as-is
2. Try same channel as the parent package (check if directory exists)
3. Fall back to `resolve_bare_name`
4. If not found, skip (do not error)

### 2.5 Resolving a Package Name with Channel Context (`resolve_package_name`)

Used by: `mip install` for remote packages

- If the argument is a FQN, use the org/channel/name from it (ignoring `--channel`)
- If the argument is a bare name, apply the `--channel` flag (defaulting to `mip-org/core`)

---

## 3. Installation

### 3.0 Argument Categorization

`mip install` accepts a mix of argument types in a single call. Each positional argument is categorized **before** any installation work happens:

1. If the argument ends in `.mhl` or starts with `http://` / `https://`, it is an **mhl source** (see [§3.3](#33-installation-from-mhl-file)).
2. Else if the argument starts with `~`, `.`, `/`, or a Windows drive letter followed by `:\` or `:/` (e.g. `C:\path\mypkg`, `D:/path/mypkg`), it is a **local directory path** (see [§3.2](#32-local-installation)).
3. Else the argument must parse as a package spec — either a bare name (`pkg`) or a fully qualified name (`org/channel/pkg`). Anything with 2 or 4+ slash-separated parts (e.g. `foo/bar`, `a/b/c/d`) is rejected with `mip:install:invalidPackageSpec`. The error message hints at the `./` form for users who actually meant a local path.

This means a bare name like `chebfun` is **always** treated as a channel install, even if a directory called `chebfun` happens to exist in the current folder. To install a local directory, the user must write `./chebfun`. This was decided in [#107](https://github.com/mip-org/mip/issues/107) to avoid the surprise of a local directory shadowing a channel package.

If a channel install fails (e.g. `mip:packageNotFound`, `mip:indexFetchFailed`) and one of the requested names also exists as a relative directory in the current folder, the error message is augmented with a hint about prefixing with `./` so the user knows how to install it as a local package instead.

The `--editable` / `-e` flag is only valid when at least one local path is present in the argument list. Using `-e` with only bare-name or FQN arguments raises `mip:install:editableRequiresLocal`.

### 3.1 Remote Installation (`mip install <package>`)

#### 3.1.1 Channel Resolution

1. If `--channel` is provided, use it as the primary channel for any bare-name arguments. Otherwise default to `mip-org/core`.
2. FQN arguments use the org/channel encoded in the name; `--channel` does not apply to them.
3. If every package argument is a FQN, the `--channel` value is ignored entirely (no warning, no index fetch). See [§14.18](#1418--channel-flag-interaction-with-fqn).

#### 3.1.2 Index Fetching

1. Always fetch the `mip-org/core` index (bare-name dependencies always resolve there -- see [§3.1.5](#315-dependency-resolution)).
2. If at least one bare-name argument is present, fetch the primary channel index (`--channel` value, or `mip-org/core` by default). When all arguments are FQNs, the primary channel is not fetched.
3. Also fetch indexes for any channels referenced by FQN arguments.
4. During dependency resolution, if a cross-channel FQN dependency is missing, fetch its channel lazily (up to 10 retry attempts).

#### 3.1.3 Version Selection (`select_best_version`)

Given all available versions for a package:

1. If any numeric versions exist (all dot-separated components are numbers), select the **highest** numeric version.
2. Else if `main` exists, select it.
3. Else if `master` exists, select it.
4. Else if `unspecified` exists, select it.
5. Else select the alphabetically first version.

If a `@version` was specified, it overrides this selection. If the requested version doesn't exist, raises `mip:versionNotFound`.

#### 3.1.4 Architecture Selection (`select_best_variant`)

Given all variants for the chosen version:

1. **Exact match** for the current architecture is preferred.
2. For `numbl_*` architectures (except `numbl_wasm`), `numbl_wasm` is a valid fallback.
3. `any` architecture is a universal fallback.
4. If no compatible variant exists, the package is "unavailable" for this architecture.

Priority: exact match > `numbl_wasm` fallback > `any`.

#### 3.1.5 Dependency Resolution

1. Build a dependency graph recursively using `build_dependency_graph`.
2. Bare-name dependencies always resolve to `mip-org/core/<name>` during graph building.
3. FQN dependencies are used as-is.
4. Circular dependencies are detected and raise `mip:circularDependency`.
5. If a dependency's channel hasn't been fetched yet, it is fetched lazily.
6. The result is deduplicated and topologically sorted so dependencies install before dependents.

#### 3.1.6 Installation Process

1. For each package in topological order:
   - If already installed (directory exists), skip it.
   - Download the `.mhl` file from the URL in the index.
   - Extract to `~/.mip/packages/<org>/<channel>/<name>/`.
2. Mark the **user-requested** packages (not their dependencies) as "directly installed" in `directly_installed.txt`.
3. Print a summary with load hints.

If any package in step 1 fails (download error, extraction failure, etc.), the install loop aborts and `mip install` runs the same prune logic that `mip uninstall` uses (`mip.utils.prune_unused_packages`). Because the user-requested packages haven't been added to `directly_installed.txt` yet, any dependencies that did install successfully during this call get pruned as orphans, leaving the package set as it was before the call -- modulo any pre-existing orphans, which the prune sweep will also remove. The original install error is then re-raised. See [§14.11](#1411-no-rollback-on-failed-install).

#### 3.1.7 Already-Installed Behavior

If a package is already installed, `mip install` prints a message and skips it. It does **not** error. It does **not** reinstall or upgrade. Use `mip update` for that.

**Exception** -- explicit version upgrade: if the user passed an explicit `@version` for a directly-requested package and a *different* version is currently installed, `mip install` silently replaces it (uninstall + install of the requested version, including unload-before / reload-after for the affected package). The replacement only triggers when the version that would actually be installed matches the requested version; otherwise the old install is left in place. See [§14.13](#1413-multiple-versions-of-the-same-package).

#### 3.1.8 Multiple Packages

`mip install pkg1 pkg2 pkg3` installs all listed packages and their combined dependencies in a single operation.

### 3.2 Local Installation

An argument is treated as a local install only when it begins with `~`, `.`, `/`, or a Windows drive letter followed by `:\` or `:/` (see [§3.0](#30-argument-categorization)). Examples: `./mypkg`, `../mypkg`, `.`, `~/proj/mypkg`, `/abs/path/mypkg`, `C:\path\mypkg`, `D:/path/mypkg`. The path must point to an existing directory containing a `mip.yaml` file:

- If the path is not a directory, raises `mip:install:notADirectory`.
- If the directory does not contain `mip.yaml`, raises `mip:install:noMipYaml`.

Bare names without a path prefix are **never** dispatched to local install, even if a directory of the same name exists in the current folder ([§3.0](#30-argument-categorization), [#107](https://github.com/mip-org/mip/issues/107)).

#### 3.2.1 Non-Editable (Copy) Install

This is the default when installing from a local directory without `-e`/`--editable`.

1. Read `mip.yaml` from the source directory.
2. Match a build entry for the current architecture.
3. Copy source into a staging directory under `<name>/`.
4. Remove `.git` directory if present.
5. Strip pre-existing MEX binaries.
6. Compute addpaths from `mip.yaml`.
7. Generate `load_package.m` with **relative** paths (using `pkg_dir` computed at load time).
8. Generate `unload_package.m`.
9. Run compile script if specified.
10. Create `mip.json` with metadata.
11. Move staging directory to `~/.mip/packages/local/local/<name>/`.
12. Store `source_path` in `mip.json` (for `mip update`).
13. Mark as directly installed.

#### 3.2.2 Editable Install (`-e` / `--editable`)

1. Read `mip.yaml` from the source directory.
2. Match build and compute addpaths.
3. Create a thin wrapper directory at `~/.mip/packages/local/local/<name>/`.
4. Generate `load_package.m` with **absolute** paths pointing to the source directory.
5. Generate `unload_package.m` with absolute paths.
6. Create `mip.json` with `editable: true` and `source_path`.
7. Store `compile_script` in `mip.json` if present.
8. **Compile by default** (unless `--no-compile`).
9. Mark as directly installed.

Source file changes are reflected immediately without reinstalling.

#### 3.2.3 `--no-compile` Flag

- Only valid with `--editable`. Using `--no-compile` without `--editable` raises `mip:install:noCompileRequiresEditable`.
- Skips the compile step but still stores `compile_script` in `mip.json`.
- Prints a hint to run `mip compile <name>` later.

#### 3.2.4 Dependency Validation for Local Install

Before installing, all dependencies listed in `mip.yaml` are checked:
- FQN dependencies: check if the directory exists at the expected path.
- Bare-name dependencies: resolve to `mip-org/core/<name>` and check existence.
- If any dependency is missing, raises `mip:dependencyNotFound`.

Note: local install does **not** auto-install dependencies. They must be pre-installed.

#### 3.2.5 Already-Installed Behavior (Local)

If the package is already installed at `local/local/<name>`, prints a message and returns without error. Does not reinstall. Use `mip update` or `mip uninstall` first.

### 3.3 Installation from `.mhl` File

`mip install /path/to/file.mhl` or `mip install https://example.com/package.mhl`:

1. Download or copy the `.mhl` file to a temp directory.
2. Extract and read `mip.json` to get the package name.
3. If already installed, skip.
4. Install any dependencies from the remote repository first.
5. Move extracted files to `~/.mip/packages/<org>/<channel>/<name>/`.
6. The org/channel is determined by the `--channel` flag (default `mip-org/core`).
7. Mark as directly installed.

### 3.4 Load Hint After Install

After installation, a hint is printed showing how to load the package:
- If the package name is unique across all installed packages, the bare name is shown.
- If the package name exists in multiple channels, the FQN is shown.

---

## 4. Loading

### 4.1 Basic Load (`mip load <package>`)

1. Resolve the package argument to an FQN (see section 2.4.1 for bare name resolution).
2. If the FQN is `mip-org/core/mip`, print "always loaded" and return.
3. Check for circular dependencies in the loading stack.
4. Look up the package directory. If it doesn't exist, raise `mip:packageNotFound`.
5. If already loaded:
   - If this is a direct load and the package was previously loaded as a dependency, promote it to "directly loaded".
   - If `--sticky` is specified, add to sticky packages.
   - Return early.
6. Read `mip.json` and load dependencies first (recursively, as non-direct loads).
7. Execute `load_package.m` in the package directory (changes `pwd` temporarily).
8. Add to `MIP_LOADED_PACKAGES`.
9. If this is a direct load, add to `MIP_DIRECTLY_LOADED_PACKAGES`.
10. If `--sticky`, add to `MIP_STICKY_PACKAGES`.

### 4.2 The `--sticky` Flag

Sticky packages are not unloaded by `mip unload --all`. They can only be unloaded by:
- Explicit `mip unload <package>` (targeted unload)
- `mip unload --all --force`

The `--sticky` flag can be applied to already-loaded packages to retroactively make them sticky.

### 4.3 The `--install` Flag

If `--install` is specified and the package is not installed, it is automatically installed before loading:
- Uses `--channel` if provided.
- If installation succeeds, proceeds with normal loading.
- If the package is already installed, just loads it.

### 4.4 Dependency Loading

When loading a package with dependencies (listed in `mip.json`):

1. Each dependency is resolved using same-channel-first resolution (section 2.4.4).
2. Dependencies are loaded recursively before the package itself.
3. Dependencies are loaded as **non-direct** (they won't appear in `MIP_DIRECTLY_LOADED_PACKAGES`).
4. Dependencies are loaded as **non-sticky** (even if the parent was loaded with `--sticky`).
5. Already-loaded dependencies are skipped.

### 4.5 Circular Dependency Detection

A loading stack tracks the current dependency chain. If a package appears in its own dependency chain, `mip:circularDependency` is raised with a message showing the full cycle.

### 4.6 Multiple Packages

`mip load pkg1 pkg2 --sticky` loads all listed packages. Each is marked as directly loaded. The `--sticky` flag applies to all of them.

### 4.7 `load_package.m` Execution

The load script is executed by `cd`-ing to the package directory and calling `run(loadFile)`. For:
- **Non-editable installs**: paths are relative, computed from the package directory.
- **Editable installs**: paths are absolute, pointing to the source directory.

If `load_package.m` doesn't exist, raises `mip:loadNotFound`.

---

## 5. Unloading

### 5.1 Basic Unload (`mip unload <package>`)

1. Resolve the package argument to an FQN (see section 2.4.2 for bare name resolution among loaded packages).
2. If the FQN is `mip-org/core/mip`, raise `mip:cannotUnloadMip`.
3. If not loaded, print a message and continue (no error).
4. Execute `unload_package.m` if it exists.
5. Remove from `MIP_STICKY_PACKAGES`.
6. Remove from `MIP_DIRECTLY_LOADED_PACKAGES`.
7. Remove from `MIP_LOADED_PACKAGES`.
8. After all explicit unloads, **prune unused dependencies**.

### 5.2 Bare Name Disambiguation for Unload

When multiple loaded packages share the same bare name:
- The **most recently loaded** one (last in `MIP_LOADED_PACKAGES` list) is unloaded.
- This is based on **load order**, not alphabetical or `mip-org/core` priority.

### 5.3 Unload All (`mip unload --all`)

1. Find all loaded packages that are **not** in `MIP_STICKY_PACKAGES`.
2. Execute `unload_package.m` for each.
3. Update state: `MIP_LOADED_PACKAGES` is set to just the sticky packages.
4. `MIP_DIRECTLY_LOADED_PACKAGES` is filtered to only those that are also sticky.

### 5.4 Unload All Force (`mip unload --all --force`)

1. Find all loaded packages **except** `mip-org/core/mip`.
2. Execute `unload_package.m` for each.
3. Reset state:
   - `MIP_LOADED_PACKAGES` = `{'mip-org/core/mip'}`
   - `MIP_DIRECTLY_LOADED_PACKAGES` = `{}`
   - `MIP_STICKY_PACKAGES` = `{'mip-org/core/mip'}`

### 5.5 Dependency Pruning After Unload

After unloading one or more packages, the system prunes dependencies that are no longer needed:

1. Build the set of "needed" packages: all directly loaded packages plus their transitive dependencies.
2. For each loaded package not in the needed set (and not `mip-org/core/mip`):
   - Execute `unload_package.m`.
   - Remove from `MIP_LOADED_PACKAGES`.
3. After pruning, check for broken dependencies (warn if any loaded package's dependency is no longer loaded).

### 5.6 Shared Dependency Behavior

If two directly-loaded packages share a dependency:
- Unloading one does **not** prune the shared dependency (it's still needed by the other).
- Unloading both **does** prune the shared dependency.

### 5.7 Multiple Packages

`mip unload pkg1 pkg2` unloads all listed packages, then runs a single prune pass. If one of the listed packages is not loaded, it prints a message but continues with the others.

### 5.8 `unload_package.m` Execution

Executed by `cd`-ing to the package directory and calling `run(unloadFile)`. If the file doesn't exist, a warning is issued (`mip:unloadNotFound`) but the package is still removed from tracking.

### 5.9 Broken Dependency Warning

After unloading (and pruning), the system checks all still-loaded packages. If any loaded package has a dependency that is no longer loaded, a warning (`mip:brokenDependencies`) is printed.

---

## 6. Uninstallation

### 6.1 Basic Uninstall (`mip uninstall <package>`)

1. Resolve each argument to an FQN:
   - FQN arguments: used directly.
   - Bare names: uses `find_all_installed_by_name` (section 2.4.3). If ambiguous, refuses.
2. Filter out `mip-org/core/mip` (prints manual uninstall instructions).
3. **Require confirmation** via interactive `input()` prompt. User must type `y` or `yes`.
4. Unload any packages that are currently loaded.
5. Remove each package directory (`rmdir`).
6. Remove from `directly_installed.txt`.
7. Clean up empty parent directories (channel dir, then org dir).
8. **Prune** packages that are no longer needed.

### 6.2 Dependency Pruning After Uninstall

After uninstalling, the system checks for orphaned dependency packages:

1. Build the set of needed packages: all directly installed packages plus their transitive dependencies.
2. For each installed package not in the needed set (and not `mip-org/core/mip`):
   - Remove the package directory.
   - Clean up empty parent directories.
3. After pruning, check for broken dependencies among remaining installed packages.

### 6.3 Bare Name Ambiguity

If a bare name matches packages in multiple channels:
- The uninstall is **refused** with a message listing all matching FQNs.
- The user must specify the FQN to disambiguate.

Using an FQN bypasses this check entirely.

---

## 7. Updating

### 7.1 Remote Package Update (`mip update <package>`)

1. Resolve to FQN (bare name uses `resolve_bare_name`).
2. Check the package is installed. If not, raises `mip:update:notInstalled`.
3. Fetch the channel index.
4. Compare installed version + commit hash with latest in index:
   - Same version **and** same commit hash (or no hash available): "already up to date", return.
   - Same version but different commit hash: update (content changed within the same version).
   - Different version: update.
5. If updating:
   - Note whether the package is currently loaded.
   - Unload if loaded.
   - Delete the old package directory.
   - Remove from `directly_installed.txt`.
   - Clean up empty parent directories.
   - Reinstall via `mip install <fqn>`.
   - Reload if it was previously loaded.

### 7.2 Local Package Update

1. Read `source_path` from `mip.json`. If absent, raises `mip:update:noSourcePath`.
2. Check the source directory still exists. If not, raises `mip:update:sourceNotFound`.
3. Note whether loaded.
4. Remove old package directory.
5. Reinstall from source (preserving editable/non-editable mode).
6. Reload if it was previously loaded.

Local updates **always** reinstall (no up-to-date check). Timestamps change on every update. For editable installs the `compile_script` runs again on every update; the `--no-compile` flag from the original install is **not** preserved. See [§14.16](#1416-mip-update-on-local-package-always-reinstalls).

### 7.3 Force Update (`--force`)

Skips the up-to-date check. For remote packages, this causes a full re-download and reinstall even when version and commit hash match.

### 7.4 Self-Update (`mip update mip`)

Special flow for `mip-org/core/mip`:
1. Fetch the latest from the `mip-org/core` channel.
2. Download the new `.mhl`, extract to staging.
3. Replace the installed package in-place.
4. Re-run `load_package.m` to reload.

Does not go through the normal unload/reinstall flow since mip cannot be unloaded.

### 7.5 Load State Preservation

- If the package was loaded before update, it is unloaded, updated, then reloaded.
- If it was not loaded, it stays unloaded after update.

### 7.6 Directly Installed Tracking

The `directly_installed.txt` status is preserved across updates. The package is removed during cleanup and re-added during reinstall.

---

## 8. Compilation

### 8.1 `mip compile <package>`

1. Resolve the package to an FQN.
2. Check it is installed. If not, raises `mip:compile:notInstalled`.
3. Read `mip.json` and check for `compile_script`. If absent, raises `mip:compile:noCompileScript`.
4. Determine the compile directory:
   - **Editable installs**: compile in the `source_path` directory.
   - **Non-editable installs**: compile in the installed package subdirectory (`<pkgDir>/<name>/`).
5. `cd` to the compile directory and run the compile script.

### 8.2 Compilation During Editable Install

- By default, editable installs compile immediately after installation.
- With `--no-compile`, compilation is skipped but `compile_script` is still stored in `mip.json`.
- A hint is printed to run `mip compile <name>` either way.

### 8.3 Compilation During Non-Editable Install

- Non-editable installs compile as part of `prepare_package` during the build process.
- The compile script runs in the staging directory before the package is moved to its final location.

---

## 9. Package Discovery and Information

### 9.1 `mip list`

Lists all installed packages. Default sort is by reverse load order (most recently loaded first). `--sort-by-name` sorts alphabetically.

### 9.2 `mip info <package>`

Displays information about a package from two sources:

**Local Installation section:**
- Version, path, loaded status, dependencies, editable flag, source path.
- If the package is not installed locally, shows "Not installed".

**Remote Channel section:**
- Fetches channel index and shows available versions/architectures.

**Bare name with multiple installations:** Shows info for **all** installations with that name.

**FQN:** Shows info for only that specific installation.

**Unknown package:** If neither installed nor in any channel, raises `mip:unknownPackage`.

### 9.3 `mip avail`

Lists packages available in the channel index. Uses `--channel` to specify which channel (default: `mip-org/core`).

---

## 10. State Management

### 10.1 In-Memory State (Session-Scoped)

Stored via `setappdata(0, key, value)`. Survives `clear all` but not MATLAB restart.

| Key | Contents | Purpose |
|---|---|---|
| `MIP_LOADED_PACKAGES` | Cell array of FQNs | All currently loaded packages (direct + dependencies) |
| `MIP_DIRECTLY_LOADED_PACKAGES` | Cell array of FQNs | Only packages explicitly loaded by the user |
| `MIP_STICKY_PACKAGES` | Cell array of FQNs | Packages that survive `mip unload --all` |

### 10.2 File-Based State (Persistent)

| File | Contents | Purpose |
|---|---|---|
| `~/.mip/packages/directly_installed.txt` | One FQN per line | Tracks which packages were directly installed (vs. installed as dependencies). Used for pruning. |

### 10.3 Key-Value Storage Operations

- `key_value_get(key)`: Returns cell array of strings (empty `{}` if key doesn't exist).
- `key_value_set(key, values)`: Overwrites entirely.
- `key_value_append(key, value)`: Adds if not already present (no-op for duplicates).
- `key_value_remove(key, value)`: Removes one value. No-op if not present.

### 10.4 Directly Installed Tracking

- `add_directly_installed(fqn)`: Appends (deduplicates).
- `remove_directly_installed(fqn)`: Removes.
- `set_directly_installed(list)`: Overwrites entirely.
- `get_directly_installed()`: Returns current list.

This tracking is critical for dependency pruning: only directly installed packages are "roots" in the dependency graph. Packages installed only as dependencies can be pruned when no root needs them.

---

## 11. Filesystem Layout

```
<mip-root>/                                # See §11.5 for resolution rules
  packages/
    directly_installed.txt                 # Persistent tracking of directly installed packages
    mip-org/
      core/
        mip/                               # The package manager itself
          load_package.m
          unload_package.m
          mip.json
          mip/                             # Package source files
        chebfun/
          load_package.m
          unload_package.m
          mip.json
          chebfun/
      test-channel1/
        alpha/
          ...
    mylab/
      custom/
        mypkg/
          ...
    local/
      local/
        devpkg/                            # Editable install (thin wrapper)
          load_package.m                   # Contains absolute paths to source
          unload_package.m
          mip.json                         # editable: true, source_path: /path/to/source
        copypkg/                           # Non-editable local install
          load_package.m                   # Contains relative paths
          unload_package.m
          mip.json                         # source_path: /original/source (for updates)
          copypkg/                         # Copied source files
```

### 11.1 `mip.json` Schema

```json
{
  "name": "package_name",
  "version": "1.0.0",
  "description": "...",
  "architecture": "linux_x86_64",
  "dependencies": ["dep1", "org/chan/dep2"],
  "editable": false,
  "source_path": "/path/to/source",
  "compile_script": "do_compile.m",
  "commit_hash": "abc123...",
  "source_hash": "def456...",
  "timestamp": "2026-04-06T12:00:00"
}
```

Required: `name`. All other fields have defaults or are optional.

### 11.2 `mip.yaml` Schema

```yaml
name: package_name              # Required
version: "1.0.0"                # Optional (defaults to "unknown")
description: "..."              # Optional
license: MIT                    # Optional
homepage: "https://..."         # Optional
repository: "https://..."       # Optional
dependencies: [dep1, dep2]      # Optional (defaults to [])
addpaths:                       # Optional (defaults to [])
  - path: "src"
  - path: "lib"
builds:                         # Optional
  - architectures: [any]
    compile_script: "compile.m" # Optional
```

### 11.3 `.mhl` File Format

A ZIP archive containing:
```
load_package.m
unload_package.m
mip.json
<package_name>/
  [source files]
```

### 11.4 Empty Directory Cleanup

After removing a package, empty channel and org directories are cleaned up:
- If `<org>/<channel>/` is empty after removal, remove it.
- If `<org>/` is empty after that, remove it.

### 11.5 `MIP_ROOT` Environment Variable

The `MIP_ROOT` environment variable overrides the location of the mip root directory. When set, it is validated by [`mip.root()`](../+mip/root.m) according to these rules:

- **Unset**: `mip.root()` falls back to path-based detection (navigating up from the installed `+mip/root.m` location).
- **Set to empty string** (`""`): treated the same as unset. `getenv` returns `''` for both unset and empty values, and `mip.root()` makes no attempt to distinguish them.
- **Set to a path that does not exist or is not a directory**: raises `mip:rootInvalid`.
- **Set to an existing directory that does not contain a `packages/` subdirectory**: raises `mip:rootInvalid`. `mip.root()` does **not** auto-create `packages/`. The use case for `MIP_ROOT` is pointing at an existing mip installation, so a missing `packages/` indicates a misconfiguration rather than a fresh setup.

---

## 12. Architecture Detection

`mip.arch()` returns a tag based on the platform:

| Platform | Tag |
|---|---|
| Linux x86_64 | `linux_x86_64` |
| macOS ARM | `macos_arm64` |
| macOS x86_64 | `macos_x86_64` |
| Windows x86_64 | `windows_x86_64` |
| MATLAB Numerics (numbl) Linux | `numbl_linux_x86_64` |
| MATLAB Numerics macOS ARM | `numbl_macos_arm64` |
| MATLAB Numerics macOS x86_64 | `numbl_macos_x86_64` |
| MATLAB Numerics WASM/Browser | `numbl_wasm` |

The `numbl_wasm` tag serves as a fallback architecture for all `numbl_*` platforms.

---

## 13. Error Identifiers

| Error ID | Trigger |
|---|---|
| `mip:invalidPackageSpec` | Invalid package argument format or characters |
| `mip:rootInvalid` | `MIP_ROOT` is set but path doesn't exist, isn't a directory, or has no `packages/` subdir |
| `mip:invalidChannel` | Invalid channel spec (not `org/channel` format) |
| `mip:missingChannelValue` | `--channel` flag without a value |
| `mip:packageNotFound` | Package not found (not installed, or not in index) |
| `mip:packageUnavailable` | Package exists but not for this architecture |
| `mip:versionNotFound` | Requested `@version` doesn't exist in the index |
| `mip:circularDependency` | Circular dependency detected |
| `mip:dependencyNotFound` | A dependency is not installed |
| `mip:cannotUnloadMip` | Attempt to unload `mip-org/core/mip` |
| `mip:loadNotFound` | `load_package.m` missing |
| `mip:mipYamlNotFound` | `mip.yaml` missing in source directory |
| `mip:invalidMipYaml` | `mip.yaml` missing required `name` field |
| `mip:mipJsonNotFound` | `mip.json` missing in package directory |
| `mip:unknownPackage` | Package not installed and not found in any channel |
| `mip:install:noPackage` | No package specified for install |
| `mip:install:noMipYaml` | Directory doesn't contain `mip.yaml` |
| `mip:install:editableRequiresLocal` | `--editable` used without a local directory |
| `mip:install:noCompileRequiresEditable` | `--no-compile` used without `--editable` |
| `mip:update:notInstalled` | Package not installed |
| `mip:update:noSourcePath` | Local package missing `source_path` in `mip.json` |
| `mip:update:sourceNotFound` | Source directory no longer exists |
| `mip:compile:notInstalled` | Package not installed |
| `mip:compile:noCompileScript` | Package has no `compile_script` |
| `mip:uninstall:noPackage` | No package specified for uninstall |

---

## 14. Open Questions, Edge Cases, and Discussion

This section collects behaviors that are ambiguous, inconsistently implemented, untested, or potentially surprising. Each item is a candidate for clarification and potential changes.

### 14.1 Inconsistent Bare-Name Dependency Resolution

**Problem**: Bare-name dependencies are resolved differently in different contexts:

- **During `install` (graph building)**: bare name -> always `mip-org/core/<name>` (section 2.4.5)
- **During `load` (runtime)**: bare name -> same channel first, then `mip-org/core`, then general resolution (section 2.4.4)
- **During `prune` (after unload/uninstall)**: bare name -> same channel first, then general resolution (section 2.4.6)

This means a package could be installed with dependencies resolved one way, but loaded with those same dependencies resolved differently. For example:
- Package `mip-org/test-channel1/gamma` depends on `alpha` (bare name).
- During install, `alpha` is resolved to `mip-org/core/alpha`.
- During load, if `mip-org/test-channel1/alpha` is also installed, it would be preferred over `mip-org/core/alpha`.

**Suggestion**: Consider unifying this behavior. Two options:
1. Always resolve bare-name deps to `mip-org/core` everywhere (simpler, more predictable).
2. Always try same-channel first everywhere (more intuitive for channel authors who expect their dependencies to stay within the channel).

A potential middle ground: at install time, resolve bare-name deps using same-channel-first logic and **store the resolved FQN** in `mip.json`. Then at load time, always use the resolved FQN. This would make behavior consistent and explicit.

### 14.2 No Version Constraint System

**Current behavior**: Dependencies are by name only, with no version constraints. `mip install` always gets the latest version. There's no way to say "depends on chebfun >= 2.0".

**Questions**:
- Should there be a minimum version constraint system?
- What happens if a dependency is already installed at an older version? Currently it's just skipped (already installed).
- Should `mip install` warn if a dependency is installed but at a potentially incompatible version?

### 14.3 Local Install Dependency Check Is Incomplete

**Current behavior** (section 3.2.4): Local install checks that each dependency's directory exists, but bare-name dependencies are always resolved to `mip-org/core/<name>`. If the dependency is installed on a different channel (e.g., `mylab/custom/depA`), the check fails even though the dependency is present.

**Suggestion**: Use `resolve_bare_name` for the dependency check in local installs, consistent with other resolution contexts.

### 14.4 `mip uninstall` Doesn't Track Dependency-Only Packages Across Channels

**Current behavior**: `directly_installed.txt` tracks which packages the user explicitly installed. Pruning removes packages not in this set and not transitively needed. But the pruning uses same-channel-first resolution for bare-name dependencies, which could differ from the original install-time resolution.

**Edge case**: If you install `A` which depends on `B` (bare name), the install resolves `B` to `mip-org/core/B`. But if you later install `myorg/chan/B`, pruning might now resolve `A`'s dependency on `B` to `myorg/chan/B` (same-channel first), potentially leaving `mip-org/core/B` eligible for pruning even though `A` was actually using it.

### 14.5 No Lock File or Dependency Snapshot

**Current behavior**: There is no lock file recording exactly which versions/commits of all dependencies were installed. The installed state is the only record.

**Questions**:
- Should there be a lock file for reproducibility?
- Should `mip install` record exact commit hashes of all dependencies?

### 14.6 Ambiguous Unload Behavior (Load-Order Based)

**Current behavior** (section 5.2): When multiple loaded packages share a bare name, `mip unload <bare>` unloads the **most recently loaded** one.

**Questions**:
- Is load-order-based disambiguation intuitive enough?
- Should this instead error and require FQN disambiguation (consistent with how uninstall handles it)?
- Should there be a warning that multiple packages match?

### 14.7 `mip load --install` Doesn't Resolve Through Channels

**Current behavior**: `mip load --install chebfun` will try `mip install chebfun` if not installed. But if the package name is ambiguous across channels (e.g., exists in both core and a custom channel), the install will use the default channel (or `--channel` if provided).

**Question**: Should `--install` error if the bare name could resolve to multiple channels, similar to how uninstall handles ambiguity?

### 14.8 Promotion from Dependency to Direct Load

**Current behavior** (section 4.1, step 5): If a package is already loaded as a dependency and you do `mip load <package>`, it gets promoted to "directly loaded". This affects pruning: it won't be pruned when the original parent is unloaded.

**Question**: Should promotion also work in reverse? If you directly load a package and then another package loads it as a dependency, should unloading the direct reference demote it back to dependency status? Currently, yes -- unloading removes it from `MIP_DIRECTLY_LOADED_PACKAGES`, and if it's still needed as a dependency, the prune step won't remove it.

### 14.9 Concurrent MATLAB Sessions

**Current behavior**: In-memory state (`setappdata`) is per-session. File-based state (`directly_installed.txt`) is shared. Two MATLAB sessions can see different loaded packages but share the installed state.

**Questions**:
- Can concurrent sessions corrupt `directly_installed.txt` (no file locking)?
- Should `mip list` or `mip info` warn if file state and memory state are inconsistent?

### 14.10 Update Doesn't Update Dependencies

**Current behavior**: `mip update <pkg>` only updates the specified package. It does not check whether dependencies also have newer versions available.

**Question**: Should there be a `mip update --recursive` or `mip update --all` that updates a package and all its dependencies?

### 14.11 Rollback on Failed Install

**Current behavior**: If an install fails mid-way (e.g., download error), `downloadAndInstall` removes its own partial directory and `mip install` then runs `mip.utils.prune_unused_packages` to roll back any dependencies that were installed during the same call. The user-requested packages haven't been added to `directly_installed.txt` yet, so anything installed by this call that isn't already a directly-installed package or one of its needed dependencies is pruned as an orphan. The original install error is re-raised.

**Resolved in [#100](https://github.com/mip-org/mip/issues/100)** by extracting `mip.utils.prune_unused_packages` (formerly a private helper inside `mip uninstall`) and reusing it from the install failure path.

**Caveats**:
- The rollback prune sweep also removes any *pre-existing* orphans (packages that were already on disk but not in `directly_installed.txt`). In practice this is fine -- those should have been pruned already -- but it's a minor side effect to be aware of.
- If `mip.utils.prune_unused_packages` itself fails, a `mip:rollbackFailed` warning is printed and the original install error is still re-raised.

### 14.12 `MIP_ROOT` Environment Variable Validation

**Resolved in [#101](https://github.com/mip-org/mip/issues/101)**: See [§11.5](#115-mip_root-environment-variable) for the rules. In short: empty string is treated as unset; nonexistent paths and directories missing a `packages/` subdirectory raise `mip:rootInvalid`; `mip.root()` never auto-creates `packages/`.

### 14.13 Multiple Versions of the Same Package

**Current behavior**: Only one version of a package can be installed per FQN. The same package name can exist at different versions on different channels (e.g., `mip-org/core/pkg` at v1 and `mylab/custom/pkg` at v2) -- those are independent installs.

**Resolved in [#102](https://github.com/mip-org/mip/issues/102)**: `mip install pkg@2.0` when a different version of `pkg` is already installed silently replaces it (uninstall + install). See [§3.1.7](#317-already-installed-behavior). This only applies when the user passed an explicit `@version`; without `@version`, the existing "already installed" behavior is unchanged. `@version` is honored regardless of whether the request is bare-name or a FQN to any channel.

Lock files (#96) and dependency version constraints (#95) are out of scope for now.

### 14.14 `mip.json` Dependencies Store Bare Names

**Current behavior**: The `dependencies` field in `mip.json` stores whatever was in `mip.yaml` -- which may be bare names or FQNs. This means the resolution happens at load time and prune time, which can produce different results.

**Suggestion**: Normalize dependencies to FQNs at install time and store the resolved FQNs in `mip.json`. This would eliminate the resolution inconsistency described in 14.1.

### 14.15 Missing Test Coverage

The following behaviors are specified in this document but not fully covered by tests:

- Cross-channel bare-name dependency resolution inconsistency between install and load
- `mip install` with multiple packages and shared dependencies
- Pruning behavior after uninstall with complex dependency graphs
- `mip load --install` with `--channel`
- Concurrent session file state consistency
- `mip update` with loaded dependencies
- `mip info` with `--channel` for remote-only packages
- `mip install` from URL (https://...)
- Broken dependency warnings after prune

### 14.16 `mip update` on Local Package Always Reinstalls

**Current behavior**: `mip update local/local/pkg` always deletes and reinstalls from source, even if nothing changed (see [§7.2](#72-local-package-update)). For editable installs the `compile_script` runs again on every update.

This behavior is intentional and was confirmed in [#103](https://github.com/mip-org/mip/issues/103):
- Unconditional uninstall + reinstall is the expected semantics for `mip update` on a local package — `mip update` is the user's "rebuild from source" hammer.
- For editable installs, recompiling is wanted: the user almost certainly edited source that needs rebuilding.
- A future `mip update --all` should **not** include local packages.

### 14.17 `load_package.m` Error Handling

**Current behavior**: If `load_package.m` throws an error during execution, a warning is printed (`mip:loadError`) but the package is still marked as loaded. This could leave the system in an inconsistent state where a package is "loaded" but its paths aren't actually on the MATLAB path.

**Suggestion**: If `load_package.m` fails, the package should **not** be marked as loaded. Or at minimum, the error should be surfaced more prominently.

### 14.18 `--channel` Flag Interaction with FQN

**Current behavior**: When using `mip install org/chan/pkg --channel other/chan`, the FQN takes precedence and `--channel` is silently ignored for that package -- no warning, no error. If every package argument is a FQN, `--channel` is ignored entirely: its index is not fetched and the "Using channel" line is not printed. In a mixed call (`mip install <fqn> <bare> --channel <other>`), `--channel` applies only to the bare-name argument.

This behavior is intentional and was confirmed in [#105](https://github.com/mip-org/mip/issues/105). Bare-name dependencies in `mip.json` are always resolved to `mip-org/core` (see [§3.1.5](#315-dependency-resolution)) and are unaffected by `--channel`.

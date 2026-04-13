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

Any package argument passed to a `mip` command (bare or FQN) can include `@version` to pin a specific version:
- `chebfun@1.2.0`
- `mip-org/core/mip@main`

The `@` is parsed from the last occurrence in the string. The version suffix is stripped before resolving the package identity.

The `@version` suffix applies **only** to command-line package arguments. It is not supported inside the `dependencies` field of `mip.yaml` -- dependency entries are plain package names (bare or FQN) with no version or version-constraint grammar.

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

#### 2.4.4 Resolving a Bare-Name Dependency (`resolve_dependency`)

Used by: all contexts that resolve dependencies listed in `mip.json` — loading, pruning (unload/uninstall), and broken-dependency checks.

- If the dependency is a FQN, use as-is
- If bare name, **always** resolve to `mip-org/core/<name>`

To depend on a package from a different channel, use the fully qualified name in `mip.yaml`.

#### 2.4.5 Resolving a Dependency During Remote Install (`build_dependency_graph`)

Used by: the install process when building the dependency graph from channel indexes

- If the dependency is a FQN, use as-is
- If bare name, **always** resolve to `mip-org/core/<name>`

This is consistent with the general dependency resolution rule (2.4.4).

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
3. If every package argument is a FQN, the `--channel` value is ignored entirely (no warning, no index fetch).

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

If any package in step 1 fails (download error, extraction failure, etc.), the install loop aborts and `mip install` runs the same prune logic that `mip uninstall` uses (`mip.state.prune_unused_packages`). Because the user-requested packages haven't been added to `directly_installed.txt` yet, any dependencies that did install successfully during this call get pruned as orphans, leaving the package set as it was before the call -- modulo any pre-existing orphans, which the prune sweep will also remove. The original install error is then re-raised.

#### 3.1.7 Already-Installed Behavior

If a package is already installed, `mip install` prints a message and skips it. It does **not** error. It does **not** reinstall or upgrade. Use `mip update` for that.

**Exception** -- explicit version upgrade: if the user passed an explicit `@version` for a directly-requested package and a *different* version is currently installed, `mip install` silently replaces it (uninstall + install of the requested version, including unload-before / reload-after for the affected package). The replacement only triggers when the version that would actually be installed matches the requested version; otherwise the old install is left in place.

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
7. Execute `load_package.m` in the package directory (changes `pwd` temporarily). If it errors, raise `mip:loadError` and stop -- the package is **not** marked as loaded (see [§4.7](#47-load_packagem-execution)).
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

1. Each dependency is resolved using `resolve_dependency` ([§2.4.4](#244-resolving-a-bare-name-dependency-resolve_dependency)): bare names always resolve to `mip-org/core/<name>`.
2. Dependencies are loaded recursively before the package itself.
3. Dependencies are loaded as **non-direct** (they won't appear in `MIP_DIRECTLY_LOADED_PACKAGES`).
4. Dependencies are loaded as **non-sticky** (even if the parent was loaded with `--sticky`).
5. Already-loaded dependencies are skipped.

### 4.5 Circular Dependency Detection

A loading stack tracks the current dependency chain. If a package appears in its own dependency chain, `mip:circularDependency` is raised with a message showing the full cycle.

### 4.6 Multiple Packages

`mip load pkg1 pkg2 --sticky` loads all listed packages. Each is marked as directly loaded. The `--sticky` flag applies to all of them. Packages are loaded in argument order; if any package errors, loading stops and remaining packages on the command line are not attempted.

### 4.7 `load_package.m` Execution

The load script is executed by `cd`-ing to the package directory and calling `run(loadFile)`. For:
- **Non-editable installs**: paths are relative, computed from the package directory.
- **Editable installs**: paths are absolute, pointing to the source directory.

If `load_package.m` doesn't exist, raises `mip:loadNotFound`.

If `load_package.m` throws during execution, the working directory is restored and `mip:loadError` is raised (with the original error attached as a cause). The package is **not** added to `MIP_LOADED_PACKAGES` or `MIP_DIRECTLY_LOADED_PACKAGES`, so the user can fix the issue and retry without first having to run `mip unload`. The error propagates up through dependency recursion, so a parent package whose dependency failed to load is also not marked as loaded. mip does **not** attempt to undo whatever the partially-executed `load_package.m` did to the path -- recovering arbitrary path or workspace mutations is not generally possible. Users should treat a `mip:loadError` as a signal that the path may be in a partial state and restart MATLAB if anything looks wrong.

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

`mip update X Y Z` updates only the named packages. Existing dependencies are **not** updated. After replacing each package with the latest version from its channel, any new dependencies that the updated packages require are installed and any orphaned packages (old dependencies no longer needed by any directly installed package) are pruned. Packages that do **not** need updating are left entirely alone unless `--force` is specified.

### 7.1 Update Flow (`mip update X Y Z`)

1. Parse `--force` flag.
2. Resolve each argument to a `(fqn, org, channel, name, pkgDir, pkgInfo, isLocal, sourcePath, editable)` tuple. Validation errors are raised **before** any destructive action:
   - Not installed → `mip:update:notInstalled`.
   - Local package without `source_path` in `mip.json` → `mip:update:noSourcePath`.
   - Local package whose source directory is missing → `mip:update:sourceNotFound`.
3. If `mip-org/core/mip` is among the arguments, handle it via the self-update flow ([§7.4](#74-self-update-mip-update-mip)) and remove it from the batch.
4. For each remaining package, decide whether it needs updating:
   - `--force`: always yes.
   - Local package: always yes (no up-to-date check).
   - Remote package: fetch the channel index and compare installed version + commit hash with latest:
     - Same version **and** same commit hash (or no hash available): "already up to date", skip.
     - Same version but different commit hash: update (content changed within the same version).
     - Different version: update.
5. If no packages need updating, return. Otherwise:
   - Snapshot `MIP_LOADED_PACKAGES` and `MIP_DIRECTLY_LOADED_PACKAGES`.
   - **Local packages** are updated in-place: unload if loaded, `rmdir` the old directory, `remove_directly_installed`, then `mip.build.install_local(sourcePath, editable)`. They do **not** go through `mip.uninstall` because the prune step would remove their deps, which `install_local` cannot re-fetch from a channel.
   - **Remote packages** are updated in place: unload if loaded, `rmdir` the old directory, download and extract the new version from the channel. The `directly_installed.txt` entry is preserved (no removal/re-addition). Then install any new dependencies that the updated packages require but are not yet installed, and prune any orphaned packages.
   - Reload every package in the pre-update `MIP_LOADED_PACKAGES` snapshot that is not currently loaded and whose directory exists. Packages that were in the snapshot but are no longer installed are skipped with a warning.
   - Restore `MIP_DIRECTLY_LOADED_PACKAGES` to the pre-update snapshot (filtered to entries that are actually loaded now) so that packages which were only transitively loaded before the update remain only transitively loaded after.

### 7.2 Local Package Update

Local packages do **not** go through `mip.uninstall` + `mip.install`. Instead, the old package directory is removed directly and `mip.build.install_local` is called with the original `source_path` and `editable` flag from `mip.json`. This avoids pruning transitive dependencies that `install_local` cannot re-fetch.

- The up-to-date check is skipped -- local packages are always reinstalled.
- Timestamps change on every update. For editable installs the `compile_script` runs again on every update; the `--no-compile` flag from the original install is **not** preserved.

### 7.3 Force Update (`--force`)

Skips the up-to-date check. The named package is replaced with the latest version from the channel even when version and commit hash match. Dependencies are still not updated — only the named packages are replaced. To update a dependency, name it explicitly: `mip update dep`.

### 7.4 Self-Update (`mip update mip`)

Special flow for `mip-org/core/mip`:
1. Fetch the latest from the `mip-org/core` channel.
2. Download the new `.mhl`, extract to staging.
3. Replace the installed package in-place.
4. Re-run `load_package.m` to reload.

Does not go through the normal update flow since mip cannot be uninstalled. Self-update runs before the batch so it is safe to pass `mip` in the same call as other packages.

### 7.5 Load State Preservation

- Packages that were loaded before the update are reloaded afterward.
- Packages that were not loaded before the update remain unloaded afterward.
- The directly-vs-transitively loaded distinction is preserved: a package that was only transitively loaded before the update is not promoted to directly loaded, even if it needed an explicit `mip.load` call during the reload pass.
- If a previously-loaded package ends up uninstalled after the update (e.g. it was a transitive dep of the old version but not the new one, and was pruned), it is skipped with a warning; its entry is effectively dropped from the loaded set.
- **Partial failure**: if a package fails mid-batch, the reload pass still runs so that packages updated earlier in the batch are not left unloaded. The original error is re-raised after reloading.

### 7.6 Dependency Handling

`mip update foo` does **not** check whether `foo`'s dependencies have newer versions in the channel index. Only the named packages are updated. After the update:

- **New dependencies**: if the new version of `foo` depends on a package that is not installed, it is installed automatically.
- **Removed dependencies**: if the old version of `foo` depended on a package that is no longer needed by any directly installed package, it is pruned.
- **Existing dependencies**: dependencies that are already installed are left as-is, even if newer versions exist in the channel.

To update a dependency, name it explicitly: `mip update dep`.

### 7.7 Directly Installed Tracking

The `directly_installed.txt` entry for each updated package is preserved across the update (the entry is never removed). New dependencies installed during the update are **not** added to `directly_installed.txt` — they remain transitive dependencies.

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

### 9.4 `mip version`

Prints the mip version string, read from `mip.yaml` in the package root.

### 9.5 `mip index`

Prints the channel index URL. Takes an optional channel argument (default: `mip-org/core`). The URL follows the pattern `https://<org>.github.io/mip-<channel>/index.json`.

### 9.6 `mip root`

Prints the mip root directory path. See [§11.5](#115-mip_root-environment-variable) for resolution rules.

### 9.7 `mip reset`

Resets mip to a clean state:
1. Runs `mip unload --all --force` (unloads everything except `mip-org/core/mip`).
2. Removes all in-memory key-value stores (`MIP_LOADED_PACKAGES`, `MIP_DIRECTLY_LOADED_PACKAGES`, `MIP_STICKY_PACKAGES`).

### 9.8 `mip bundle <path>`

Builds a `.mhl` archive from a local package directory containing `mip.yaml`. Options:
- `--output <dir>` -- output directory (default: current directory)
- `--arch <arch>` -- override architecture (default: auto-detect)

Output filename: `<name>-<version>-<architecture>.mhl`. See [§11.3](#113-mhl-file-format) for the archive format.

### 9.9 `mip test <package>`

Loads the package (if not already loaded) and runs its `test_script` (defined in `mip.yaml`). If no test script is defined, prints a message and returns.

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
  "dependencies": ["dep1", "org/chan/dep2"],   // bare or FQN names only; no @version or constraints
  "editable": false,
  "source_path": "/path/to/source",
  "compile_script": "do_compile.m",
  "test_script": "run_tests.m",
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
dependencies: [dep1, dep2]      # Optional (defaults to []); bare or FQN names only, no @version or constraints
addpaths:                       # Optional (defaults to [])
  - path: "src"
  - path: "lib"
builds:                         # Optional
  - architectures: [any]
    compile_script: "compile.m" # Optional
    test_script: "run_tests.m"  # Optional
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
| `mip:loadError` | `load_package.m` threw an error during execution |
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

## 14. Open Questions and Gaps

This section collects unresolved design questions and untested behaviors. Items that were previously open but have since been resolved are documented in the relevant sections above (see issues [#94](https://github.com/mip-org/mip/issues/94), [#95](https://github.com/mip-org/mip/issues/95), [#99](https://github.com/mip-org/mip/issues/99)--[#105](https://github.com/mip-org/mip/issues/105)).

### 14.4 No Lock File

There is no lock file recording exact versions/commits of installed dependencies. The installed state on disk (`~/.mip/packages/` and `directly_installed.txt`) is the only record, so installs are not reproducible across machines or over time. Lock file support is **not planned for the first release**.

### 14.5 Ambiguous Unload Uses Load Order

When multiple loaded packages share a bare name, `mip unload <bare>` unloads the most recently loaded one ([§5.2](#52-bare-name-disambiguation-for-unload)). This differs from `mip uninstall`, which refuses and requires FQN disambiguation ([§6.3](#63-bare-name-ambiguity)). Should these be consistent?

### 14.6 `mip load --install` Channel Handling

`mip load --install chebfun` installs from the default channel (or `--channel`) if not installed. There is no disambiguation check when the package name exists on multiple channels. Should this error like `mip uninstall` does?

**Untested.**

### 14.7 Concurrent MATLAB Sessions

Running multiple MATLAB sessions that share the same `~/.mip` directory is **not supported**. In-memory state (`setappdata`) is per-session, while file state (`directly_installed.txt`, installed packages on disk) is shared with no file locking. Concurrent `mip install`/`mip uninstall` operations can race on `directly_installed.txt` (read-modify-write without locking) and one session's `mip uninstall` can remove packages another session has loaded. Users should avoid running `mip` commands that modify state from multiple sessions simultaneously.

### 14.8 Missing Test Coverage

Behaviors specified in this document but not covered by tests:

- `mip load --install` with `--channel` ([§14.6](#146-mip-load---install-channel-handling))
- `mip install` from URL (`https://...`)
- `mip avail` ([§9.3](#93-mip-avail)), `mip info` remote-only display with `--channel`

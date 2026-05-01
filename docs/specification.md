# MIP Package Manager: Behavior Reference

This document is the authoritative reference for the behavior of the MIP package manager. It specifies the exact rules governing every operation, including edge cases. All behaviors described here should be reflected by unit tests.

---

## 1. Core Concepts

### 1.1 Fully Qualified Name (FQN)

Every installed package has a unique **FQN** that begins with a **source-type prefix** indicating where the package came from. The canonical internal form is variable-length:

| Source type | Canonical FQN | Example |
|---|---|---|
| `gh` — GitHub channel package | `gh/<org>/<channel>/<name>` | `gh/mip-org/core/chebfun` |
| `local` — local directory / editable install | `local/<name>` | `local/mypkg` |
| `fex` — File Exchange / `--url` zip install | `fex/<name>` | `fex/some_fex_pkg` |

For GitHub channel packages:
- **org** -- the GitHub organization that hosts the channel repository
- **channel** -- the channel name within that organization
- **name** -- the package name

All components must match the regex `^[-a-zA-Z0-9_.]+$` and must not be `.` or `..`.

#### 1.1.1 Display Form

The **display form** of a canonical FQN strips the `gh/` prefix only; non-gh FQNs are displayed unchanged. `mip list`, `mip info`, and all install/load/update messages use the display form. `mip.parse.display_fqn` performs the conversion.

| Canonical FQN | Display form |
|---|---|
| `gh/mip-org/core/chebfun` | `mip-org/core/chebfun` |
| `local/mypkg` | `local/mypkg` |
| `fex/some_fex_pkg` | `fex/some_fex_pkg` |

#### 1.1.2 Accepted User Input

The parser accepts either the canonical form or a shorter form for GitHub packages. Users may omit the `gh/` prefix:

| User input | Interpreted as |
|---|---|
| `chebfun` | bare name (resolved via §2.4) |
| `local/mypkg`, `fex/some_pkg` | 2-part non-gh FQN |
| `mip-org/core/chebfun` | 3-part, implicit `gh/` prefix (`gh/mip-org/core/chebfun`) |
| `gh/mip-org/core/chebfun` | 4-part, explicit canonical form |

### 1.2 Bare Names

A **bare name** is just the package name without org/channel (e.g., `chebfun`). Bare names are resolved to FQNs using context-dependent rules described in section 2.4.

### 1.3 Version Strings

Versions are either **numeric** (e.g., `1.2.3`) or **non-numeric** (e.g., `main`, `master`). Numeric versions use dot-separated components that are each parseable as numbers.

A version can live in two places:

- **Channel release directory** (`packages/<name>/<version>/`) — the authoritative version for a channel-published package. May be numeric or non-numeric (e.g., a branch name like `main`).
- **`mip.yaml`'s `version` field** — optional; when present, must be blank or numeric. Non-numeric values like branch names belong in the release directory name, not in `mip.yaml`. See [§11.2.1](#1121-channel-version-rules) for how the two relate.

### 1.4 The `@version` Suffix

Any package argument passed to a `mip` command (bare or FQN) can include `@version` to pin a specific version:
- `chebfun@1.2.0`
- `mip-org/core/mip@main`

The `@` is parsed from the last occurrence in the string. The version suffix is stripped before resolving the package identity.

The `@version` suffix applies **only** to command-line package arguments that are not local paths. It is not supported inside the `dependencies` field of `mip.yaml` -- dependency entries are plain package names (bare or FQN) with no version or version-constraint grammar.

When an argument is identified as a local path (see [§3.0](#30-argument-categorization)), `@` is treated as a literal path character, not a version separator. This allows installing from directories whose names contain `@` (e.g., MATLAB class folders like `@MyClass`). For example, `./@MyClass` and `./pkg@dev` are both valid local paths where `@` is part of the directory name.

### 1.5 Channels

A channel is a package repository hosted on GitHub Pages at `https://<org>.github.io/mip-<channel>/index.json`. The default channel is `mip-org/core`.

Channel strings can be specified as:
- `org/channel` (e.g., `mip-org/core`, `mylab/custom`)

A bare channel name (e.g., just `core`) is **invalid** and raises `mip:invalidChannel`.

### 1.6 Non-channel Source Types

Packages installed from local directories and from File Exchange / `--url` zips are not hosted on a GitHub channel. They live under top-level source-type prefixes:

- `local/<name>` — directory and editable installs
- `fex/<name>` — File Exchange URLs and `--url` zip installs

These are addressed by the source-type prefix directly; no `org/channel` is involved.

### 1.7 The `gh/mip-org/core/mip` Identity

The package `gh/mip-org/core/mip` is the package manager itself. It has special protections:

- It is **always** marked as loaded and sticky when any `mip` command runs.
- It **cannot** be unloaded via `mip unload` (raises `mip:cannotUnloadMip`).
- It survives `mip unload --all --force`.
- It is never pruned during dependency pruning.
- `mip uninstall mip-org/core/mip` triggers a full self-uninstall (see [§6.4](#64-self-uninstall-mip-uninstall-mip)) rather than an ordinary package removal.

**Important**: These protections apply **only** to the exact canonical FQN `gh/mip-org/core/mip`. A package named `mip` on any other channel (e.g., `mylab/custom/mip`) or any `local/mip` or `fex/mip` is treated as a normal package. The match is by name equivalence (see [§1.8](#18-name-equivalence)), so any case variant of `mip` under `gh/mip-org/core/` refers to the same protected identity.

### 1.8 Name Equivalence

Two package names refer to the same package iff their **normalized** forms are equal, where normalization is:

```
normalize(name) = lowercase(name) with '-' replaced by '_'
```

So `My-Pkg`, `my_pkg`, `MY-PKG`, and `My_Pkg` all refer to the same package. `mypkg` (no separator) is a *different* name — normalization equates `-` with `_`, but does not remove them.

This rule applies **only to the name component** of an FQN. The `org` and `channel` components compare strictly (case-sensitive, no separator equivalence) because they map to GitHub paths. So `mip-org/core/My-Pkg` and `mip-org/core/my_pkg` refer to the same package, but `MIP-ORG/core/my_pkg` does not.

#### 1.8.1 Canonical Form

Internally, mip stores names in a single **canonical** form per install. The canonical form is:

- **For an installed package**: the actual on-disk directory name under `<root>/packages/gh/<org>/<channel>/`. Whatever case/separators the directory uses is the canonical form for that install.
- **For a not-yet-installed package being installed**: the name as published by its source — the `name` field in the channel index entry, the `name` field in `mip.yaml` (local install), or the `name` field in `mip.json` (mhl install). The on-disk directory is named to match.

This means the on-disk name is always the canonical name, and stored FQNs (`MIP_LOADED_PACKAGES`, `directly_installed.txt`, etc.) are always in canonical form. User input that differs from the canonical form is canonicalized at command entry by case-insensitive lookup against the on-disk directory or the channel index.

#### 1.8.2 Consequences

- `mip install MyPkg` followed by `mip load MY_PKG` works — bare-name resolution finds the on-disk directory case-insensitively.
- `mip install mip-org/core/MyPkg` when the package is already installed as `mip-org/core/my-pkg` is treated as already-installed (no-op), regardless of which form was used originally.
- The channel index lookup is case-insensitive: `mip install MyPkg` will match an entry named `mypkg` in the channel index, and the install uses the channel's published form (`mypkg`) as the on-disk dir name.
- If a channel publishes two entries with names that differ only in case/separator (e.g. `MyPkg` and `my_pkg`), they are treated as the same package and the first encountered is canonical.
- The mip identity check ([§1.7](#17-the-mip-orgcoremip-identity)) uses name equivalence, so any case variant of `mip` on the `mip-org/core` channel is protected.

---

## 2. Parsing and Resolution

### 2.1 Parsing a Package Argument (`parse_package_arg`)

Input is split on `/` after stripping any `@version` suffix:

| Input format | Result |
|---|---|
| `name` | bare name: `is_fqn=false`, `type=''`, `fqn=''` |
| `type/name` (2 parts, `type != 'gh'`) | non-gh FQN: `type='local'`/`'fex'`/..., `fqn='<type>/<name>'` |
| `org/channel/name` (3 parts) | gh FQN: `type='gh'`, org/channel/name populated, `fqn='gh/<org>/<channel>/<name>'` |
| `gh/org/channel/name` (4 parts) | gh FQN (explicit), same result as 3-part form |
| 2-part input starting with `gh/` | **Error** `mip:invalidPackageSpec` |
| 4-part input not starting with `gh/` | **Error** `mip:invalidPackageSpec` |
| 5+ parts | **Error** `mip:invalidPackageSpec` |

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
1. `gh/mip-org/core/<name>` -- if installed
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
- If bare name, **always** resolve to `gh/mip-org/core/<name>`

To depend on a package from a different channel, use the fully qualified name in `mip.yaml`.

#### 2.4.5 Resolving a Dependency During Remote Install (`build_dependency_graph`)

Used by: the install process when building the dependency graph from channel indexes

- If the dependency is a FQN, use as-is
- If bare name, **always** resolve to `gh/mip-org/core/<name>`

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

If a channel install fails (e.g. `mip:packageNotFound`, `mip:indexFetchFailed`) and one of the requested names also exists as a relative directory in the current folder, the error message is augmented with a hint about prefixing with `./` so the user knows how to install it as a local package instead. When the argument contains `@` (e.g. `foo@1.0`), the hint also checks the base name with the `@version` suffix stripped (i.e. checks for a directory named `foo`).

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

Channel index fetches go through an on-disk cache (see [§11.6](#116-channel-index-cache)). Repeat fetches of the same channel within the cache TTL are served from the cache without hitting the network.

#### 3.1.3 Version Selection (`select_best_version`)

Given all available versions for a package:

1. If any numeric versions exist (all dot-separated components are numbers), select the **highest** numeric version.
2. Else if `main` exists, select it.
3. Else if `master` exists, select it.
4. Else select the alphabetically first version.

If a `@version` was specified, it overrides this selection. If the requested version doesn't exist, raises `mip:versionNotFound`.

#### 3.1.4 Architecture Selection (`select_best_variant`)

Given all variants for the chosen version:

1. **Exact match** for the current architecture is preferred.
2. For `numbl_*` architectures (except `numbl_wasm`), `numbl_wasm` is a valid fallback.
3. `any` architecture is a universal fallback.
4. If no compatible variant exists, the package is "unavailable" for this architecture.

Priority: exact match > `numbl_wasm` fallback > `any`.

**Version selection is final.** Architecture selection only considers variants within the version chosen in §3.1.3. If the best version has no compatible architecture, the package is reported as unavailable — MIP does **not** fall back to an older version that might have a compatible build. To install a specific older version that supports the current architecture, use the `@version` suffix explicitly.

#### 3.1.5 Dependency Resolution

1. Build a dependency graph recursively using `build_dependency_graph`.
2. Bare-name dependencies always resolve to `gh/mip-org/core/<name>` during graph building.
3. FQN dependencies are used as-is.
4. Circular dependencies are detected and raise `mip:circularDependency`.
5. If a dependency's channel hasn't been fetched yet, it is fetched lazily.
6. The result is deduplicated and topologically sorted so dependencies install before dependents.

#### 3.1.6 Installation Process

1. For each package in topological order:
   - If already installed (directory exists), skip it.
   - Download the `.mhl` file from the URL in the index.
   - If the channel index entry includes `mhl_sha256`, verify the downloaded file against it. Mismatch raises `mip:digestMismatch` and deletes the corrupted file. Missing digest (legacy releases) or an unavailable JVM (e.g. `numbl_wasm`) silently skips verification. See [§3.6](#36-mhl-archive-integrity).
   - Validate the `.mhl` archive against path-traversal attacks before extraction (see [§3.6](#36-mhl-archive-integrity)).
   - Extract to `<root>/packages/gh/<org>/<channel>/<name>/`.
2. Mark the **user-requested** packages (not their dependencies) as "directly installed" in `directly_installed.txt`.
3. Print a summary with load hints.

If any package in step 1 fails (download error, extraction failure, etc.), the install loop aborts and `mip install` runs the same prune logic that `mip uninstall` uses (`mip.state.prune_unused_packages`). Because the user-requested packages haven't been added to `directly_installed.txt` yet, any dependencies that did install successfully during this call get pruned as orphans, leaving the package set as it was before the call -- modulo any pre-existing orphans, which the prune sweep will also remove. The original install error is then re-raised.

#### 3.1.7 Already-Installed Behavior

If a package is already installed, `mip install` prints a message and skips it. It does **not** error. It does **not** reinstall or upgrade. Use `mip update` for that.

**Exception** -- explicit version upgrade: if the user passed an explicit `@version` for a directly-requested package and a *different* version is currently installed, `mip install` replaces it (uninstall + install of the requested version, including unload-before / reload-after for the affected package) and prints `Replacing "<name>" <old> with requested version <new>...`. The replacement only triggers when the version that would actually be installed matches the requested version; otherwise the old install is left in place.

#### 3.1.8 Multiple Packages

`mip install pkg1 pkg2 pkg3` installs all listed packages and their combined dependencies in a single operation.

### 3.2 Local Installation

An argument is treated as a local install only when it begins with `~`, `.`, `/`, or a Windows drive letter followed by `:\` or `:/` (see [§3.0](#30-argument-categorization)). Examples: `./mypkg`, `../mypkg`, `.`, `~/proj/mypkg`, `/abs/path/mypkg`, `C:\path\mypkg`, `D:/path/mypkg`. The path must point to an existing directory:

- If the path is not a directory, raises `mip:install:notADirectory`.
- If the directory does not contain `mip.yaml`, mip prompts the user (`Auto-generate mip.yaml? (y/n):`) to auto-generate one via `mip init`. On `y`/`yes` (case-insensitive), init runs and the install continues. Otherwise, raises `mip:install:abortedNoMipYaml` and no install work is done. The `MIP_CONFIRM` environment variable overrides the prompt for non-interactive use: a value of `y` or `yes` (case-insensitive) auto-confirms; any other non-empty value declines. An unset or empty `MIP_CONFIRM` is ignored and the interactive prompt runs as usual. This applies to both editable and non-editable local installs.

Bare names without a path prefix are **never** dispatched to local install, even if a directory of the same name exists in the current folder ([§3.0](#30-argument-categorization), [#107](https://github.com/mip-org/mip/issues/107)).

#### 3.2.1 Non-Editable (Copy) Install

This is the default when installing from a local directory without `-e`/`--editable`.

1. Read `mip.yaml` from the source directory.
2. Match a build entry for the current architecture.
3. Copy source into a staging directory under `<name>/`.
4. Remove `.git` directory if present.
5. Strip pre-existing MEX binaries.
6. Compute paths from `mip.yaml` relative to the source subdir.
7. Run compile script if specified.
8. Create `mip.json` with metadata, including the `paths` field (list of addpath entries, relative to the package source subdir). `mip.load` resolves these against the installed package dir at load time.
9. Move staging directory to `<root>/packages/local/<name>/`.
10. Store `source_path` in `mip.json` (for `mip update`).
11. Mark as directly installed.

#### 3.2.2 Editable Install (`-e` / `--editable`)

1. Read `mip.yaml` from the source directory.
2. Match build and compute paths relative to the source directory.
3. Create a thin wrapper directory at `<root>/packages/local/<name>/`.
4. Create `mip.json` with `editable: true`, `source_path`, and the `paths` field (addpath entries relative to the source dir). `mip.load` resolves these against `source_path` at load time.
5. Store `compile_script` and `test_script` in `mip.json` if present.
6. If a `compile_script` is defined, **compile by default** (unless `--no-compile`). Packages with no `compile_script` skip this step silently.
7. Mark as directly installed.

Source file changes are reflected immediately without reinstalling.

#### 3.2.3 `--no-compile` Flag

- Only valid with `--editable`. Using `--no-compile` without `--editable` raises `mip:install:noCompileRequiresEditable`.
- Skips the compile step but still stores `compile_script` in `mip.json`.
- Prints a hint to run `mip compile <name>` later.

#### 3.2.4 Dependency Validation for Local Install

Before installing, all dependencies listed in `mip.yaml` are checked:
- FQN dependencies: check if the directory exists at the expected path.
- Bare-name dependencies: resolve to `gh/mip-org/core/<name>` and check existence.
- If any dependency is missing, raises `mip:dependencyNotFound`.

Note: local install does **not** auto-install dependencies. They must be pre-installed.

#### 3.2.5 Already-Installed Behavior (Local)

If the package is already installed at `local/<name>`, prints a message and returns without error. Does not reinstall. Use `mip update` or `mip uninstall` first.

### 3.3 Installation from `.mhl` File

`mip install /path/to/file.mhl` or `mip install https://example.com/package.mhl`:

1. Download or copy the `.mhl` file to a temp directory. Direct `.mhl` installs from a path or URL have no digest source, so SHA-256 verification is not performed (see [§3.6](#36-mhl-archive-integrity)).
2. Validate the archive for path-traversal safety (see [§3.6](#36-mhl-archive-integrity)), then extract and read `mip.json` to get the package name.
3. If already installed, skip.
4. Install any dependencies from the remote repository first. These dependencies are **not** marked as directly installed -- only the top-level `.mhl` package is. This lets them be pruned later when their parent is uninstalled.
5. Move extracted files to `<root>/packages/gh/<org>/<channel>/<name>/`.
6. The org/channel is determined by the `--channel` flag (default `mip-org/core`).
7. Mark the top-level `.mhl` package as directly installed.

### 3.4 Installation from a Remote `.zip` URL

`mip install <name> --url <zip-url>` installs a package from a remote `.zip` archive, using the positional `<name>` as the package name:

1. Download the archive to a temporary directory.
2. Extract it. If the archive expands to a single top-level subdirectory (as GitHub-produced source archives do, e.g. `repo-main/`), descend into that subdirectory and treat its contents as the source tree. Otherwise use the extraction root.
3. If the extracted source has no `mip.yaml`, run `mip init` on it with `--name <name>` and `--repository <zip-url>`. The URL is recorded in the generated mip.yaml's `repository` field. No prompt is issued -- the user opted in by specifying `--url`.
4. Run a non-editable local install (`mip.build.install_local`) on the extracted source.
5. Clear `source_path` in the installed `mip.json` to an empty string. `install_local` would otherwise record the temp extraction directory, which is about to be deleted; storing that stale path is worse than storing none. An empty `source_path` signals "no source available to reinstall from", which `mip update` handles by skipping ([§7.1](#71-update-flow-mip-update-x-y-z)).
6. Clean up the temp directory regardless of success or failure.

Constraints:

- The URL must point to a `.zip` archive: the URL's path component (before `?` or `#`) ends in `.zip`, case-insensitive. Otherwise raises `mip:install:urlMustBeZip`.
- Exactly one positional argument is required when `--url` is given, and it must be a bare name (not an FQN, URL, or path). Otherwise raises `mip:install:urlRequiresName` / `mip:install:urlTakesSingleName`.
- `--url` may appear at most once per call (raises `mip:install:multipleUrls`).
- `--editable` / `-e` is rejected (the source dir is temporary; raises `mip:install:editableRequiresLocal`).

**File Exchange URLs**: a URL starting with `https://www.mathworks.com/matlabcentral/fileexchange/` is treated as a landing page, not a direct download. mip resolves it to the underlying `.zip` URL by appending `?download=true`, issuing a HEAD request (with a curl-style User-Agent to bypass MathWorks' Akamai bot detection), following the 302 redirect to the UUID-based `mlc-downloads/...` URL, and stripping its query string. The resolved zip URL is what gets downloaded **and** what gets recorded in the auto-generated mip.yaml's `repository` field. If resolution fails (network error, non-2xx response, or final URL is not a `.zip`), raises `mip:install:fexResolveFailed`.

Limitation: because the source directory is deleted after install, `mip update` cannot reinstall from the original URL. `mip update <name>` (or `mip update --all`) prints a skip message for URL-installed packages and moves on. To pull in an updated archive, re-run `mip install <name> --url <zip-url>` (uninstall first if needed).

### 3.5 Load Hint After Install

After installation, a hint is printed showing how to load the package:
- If the package name is unique across all installed packages, the bare name is shown.
- If the package name exists in multiple channels, the FQN is shown.

### 3.6 `.mhl` Archive Integrity

Every `.mhl` downloaded from a channel is checked in two ways before extraction:

**SHA-256 digest verification.** Channel index entries may include an `mhl_sha256` hex digest. When present, the downloaded (or locally copied) file's SHA-256 is compared against the index value (case-insensitive). On mismatch, the file is deleted and `mip:digestMismatch` is raised. If the index entry has no digest (e.g. legacy releases) or the MATLAB JVM is unavailable (e.g. `numbl_wasm`), verification is silently skipped -- the absence of a digest is not itself an error. Digest verification is performed by both `mip install` and `mip update` when they download `.mhl` files from a channel. `mip install /path/to/file.mhl` and `mip install https://.../file.mhl` (bypassing the channel index) have no digest source, so no verification is performed in those cases.

**Path-traversal validation.** Before `unzip` is ever called, the `.mhl` archive is parsed in pure MATLAB (central directory + each local file header) and every entry name is validated. Any of the following rejects the archive with `mip:pathTraversal`:

- an entry name containing an absolute path, a Windows drive letter, a null byte, or a `..` component that resolves outside the extraction root (benign in-tree `..` such as `foo/../bar` is allowed);
- a disagreement between the central directory name and the local file header name for the same entry (spec violation, likely malicious);
- a symlink entry whose target, resolved relative to the link's own directory, escapes the extraction root; or a symlink with a compressed payload (rejected as a safe fallback).

Validation happens *before* extraction so that a malicious entry can never write to disk in the first place.

---

## 4. Loading

### 4.1 Basic Load (`mip load <package>`)

1. Resolve the package argument to an FQN (see section 2.4.1 for bare name resolution).
2. If the FQN is `mip-org/core/mip`, print "always loaded" and return.
3. Check for circular dependencies in the loading stack.
4. Look up the package directory. If it doesn't exist, raise `mip:packageNotFound`.
5. If already loaded:
   - If this is a direct load and the package was previously loaded as a dependency, promote it to "directly loaded".
   - If this is a direct load, also mark the package as directly installed (idempotent; promotes a previously transitive install).
   - If `--sticky` is specified, add to sticky packages.
   - Return early.
6. Read `mip.json` and load dependencies first (recursively, as non-direct loads).
7. Add each entry in the `mip.json` `paths` field to the MATLAB path (see [§4.8](#48-path-addition-from-mipjson)). If the field is missing, raise `mip:loadNotFound` and stop -- the package is **not** marked as loaded.
8. Add to `MIP_LOADED_PACKAGES`.
9. If this is a direct load, add to `MIP_DIRECTLY_LOADED_PACKAGES` and mark the package as directly installed.
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

1. Each dependency is resolved using `resolve_dependency` ([§2.4.4](#244-resolving-a-bare-name-dependency-resolve_dependency)): bare names always resolve to `gh/mip-org/core/<name>`.
2. Dependencies are loaded recursively before the package itself.
3. Dependencies are loaded as **non-direct** (they won't appear in `MIP_DIRECTLY_LOADED_PACKAGES`, and are not added to `directly_installed.txt`).
4. Dependencies are loaded as **non-sticky** (even if the parent was loaded with `--sticky`).
5. Already-loaded dependencies are skipped.

### 4.5 Circular Dependency Detection

A loading stack tracks the current dependency chain. If a package appears in its own dependency chain, `mip:circularDependency` is raised with a message showing the full cycle.

### 4.6 Multiple Packages

`mip load pkg1 pkg2 --sticky` loads all listed packages. Each is marked as directly loaded. The `--sticky` flag applies to all of them. Packages are loaded in argument order; if any package errors, loading stops and remaining packages on the command line are not attempted.

### 4.7 The `--addpath` and `--rmpath` Flags

`mip load <pkg> --addpath <relpath>` adds `fullfile(srcDir, relpath)` to the MATLAB path **after** the entries from `mip.json` `paths` have been added. `--rmpath <relpath>` removes the same. **Both flags may be repeated** to specify multiple paths in one call (e.g. `mip load foo --addpath src/a --addpath src/b --rmpath src/legacy`); each occurrence is accumulated and applied in argument order.

The `srcDir` resolution is the same one used elsewhere ([`mip.paths.get_source_dir`](../+mip/+paths/get_source_dir.m)):
- **Editable installs**: `srcDir = source_path` (the user's original source directory).
- **Non-editable installs**: `srcDir = pkgDir/<name>/` (the copied source subdir, *not* the load-script wrapper dir above it).

Constraints:
- Only valid with a single positional package argument. With multiple packages, raises `mip:load:addpathSinglePackage`.
- Applied **only** to the directly-named package, not to transitively-loaded dependencies.
- Applied even when the package is already loaded (lets the user adjust path entries on an existing load without unload+reload).
- `--addpath` still calls `addpath` if the target directory does not exist; MATLAB emits its native `MATLAB:addpath:DirNotFound` warning.
- `--rmpath` does not error if the target is not currently on the path (matches MATLAB's `rmpath` behavior, which emits `MATLAB:rmpath:DirNotFound`).
- `--addpath` / `--rmpath` are **transient**: they are applied at this load and not persisted. A subsequent `mip load` (or reload after `mip update`) without the flags will not re-apply them.
- The relative path is **not sandboxed**: `fullfile(srcDir, relpath)` is passed to `addpath` / `rmpath` as-is, so `..` segments escape `srcDir`. Entries outside `srcDir` will also not be caught by the unload sweep (§5.8), so the user is responsible for cleaning them up.

These adjustments are not separately tracked because the unload sweep (§5.8) removes everything under `srcDir` regardless.

### 4.8 Path Addition from `mip.json`

Each entry in the `mip.json` `paths` field is resolved relative to `srcDir` (see [`mip.paths.get_source_dir`](../+mip/+paths/get_source_dir.m)) and passed to `addpath`. The entry `.` means `srcDir` itself; other entries are resolved via `fullfile(srcDir, entry)`. For:
- **Non-editable installs**: `srcDir = pkgDir/<name>/`, so paths resolve under the installed copy.
- **Editable installs**: `srcDir = source_path`, so paths resolve under the user's original source directory.

If `mip.json` has no `paths` field, raises `mip:loadNotFound` and the package is **not** added to `MIP_LOADED_PACKAGES` or `MIP_DIRECTLY_LOADED_PACKAGES`.

---

## 5. Unloading

### 5.1 Basic Unload (`mip unload <package>`)

1. Resolve the package argument to an FQN (see section 2.4.2 for bare name resolution among loaded packages).
2. If the FQN is `mip-org/core/mip`, raise `mip:cannotUnloadMip`.
3. If not loaded, print a message and continue (no error).
4. Remove the `mip.json` `paths` entries from the MATLAB path (see [§5.8](#58-path-removal-from-mipjson)).
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
2. Remove the `mip.json` `paths` entries for each.
3. Update state: `MIP_LOADED_PACKAGES` is set to just the sticky packages.
4. `MIP_DIRECTLY_LOADED_PACKAGES` is filtered to only those that are also sticky.

### 5.4 Unload All Force (`mip unload --all --force`)

1. Find all loaded packages **except** `mip-org/core/mip`.
2. Remove the `mip.json` `paths` entries for each.
3. Reset state:
   - `MIP_LOADED_PACKAGES` = `{'mip-org/core/mip'}`
   - `MIP_DIRECTLY_LOADED_PACKAGES` = `{}`
   - `MIP_STICKY_PACKAGES` = `{'mip-org/core/mip'}`

### 5.5 Dependency Pruning After Unload

After unloading one or more packages, the system prunes dependencies that are no longer needed:

1. Build the set of "needed" packages: all directly loaded packages plus their transitive dependencies.
2. For each loaded package not in the needed set (and not `mip-org/core/mip`):
   - Remove the `mip.json` `paths` entries.
   - Remove from `MIP_LOADED_PACKAGES`.
3. After pruning, check for broken dependencies (warn if any loaded package's dependency is no longer loaded).

### 5.6 Shared Dependency Behavior

If two directly-loaded packages share a dependency:
- Unloading one does **not** prune the shared dependency (it's still needed by the other).
- Unloading both **does** prune the shared dependency.

### 5.7 Multiple Packages

`mip unload pkg1 pkg2` unloads all listed packages, then runs a single prune pass. If one of the listed packages is not loaded, it prints a message but continues with the others.

### 5.8 Path Removal from `mip.json`

Each entry in the `mip.json` `paths` field is resolved against `srcDir` (see [§4.8](#48-path-addition-from-mipjson)) and passed to `rmpath`. MATLAB's `MATLAB:rmpath:DirNotFound` warning is suppressed during this pass so stale or missing entries do not produce noise.

If `mip.json` has no `paths` field, the `mip:unloadNotFound` warning is issued. The package is still removed from tracking either way.

**Defensive path sweep**: after the step above, mip walks the current MATLAB path and `rmpath`s every entry that equals `srcDir` or starts with `srcDir<filesep>`. The `srcDir` is resolved via [`mip.paths.get_source_dir`](../+mip/+paths/get_source_dir.m) — the same base used for `mip load --addpath`/`--rmpath`. The sweep is what catches paths added via `mip load --addpath` that are not listed in the `paths` field.

Each swept entry is reported (`swept residual path entry for "<fqn>": <path>`). Because the sweep matches only entries beginning with `srcDir<filesep>` (or exactly equal to `srcDir`), a sibling directory whose name happens to share a prefix is never touched.

### 5.9 Broken Dependency Warning

After unloading (and pruning), the system checks all still-loaded packages. If any loaded package has a dependency that is no longer loaded, a warning (`mip:brokenDependencies`) is printed.

---

## 6. Uninstallation

### 6.1 Basic Uninstall (`mip uninstall <package>`)

1. Resolve each argument to an FQN:
   - FQN arguments: used directly.
   - Bare names: uses `find_all_installed_by_name` (section 2.4.3). If ambiguous, refuses.
2. If `mip-org/core/mip` is among the resolved packages, dispatch to the self-uninstall flow ([§6.4](#64-self-uninstall-mip-uninstall-mip)). If the user confirms, that flow tears down the entire mip root (removing all installed packages along with mip itself) and returns; no further per-package processing happens. If the user declines, `mip-org/core/mip` is dropped from the list and normal uninstallation continues for any other packages.
3. Unload any packages that are currently loaded.
4. Remove each package directory (`rmdir`).
5. Remove from `directly_installed.txt`.
6. Clear the pin entry for the package, if any (so a reinstall starts unpinned -- see [§7.11](#711-pinned-packages)).
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

### 6.4 Self-Uninstall (`mip uninstall mip`)

When `mip-org/core/mip` is among the resolved uninstall targets, the command delegates to a self-uninstall flow:

1. Print a warning describing what will happen (remove mip from the saved MATLAB path, unload and delete all installed packages, delete the mip root directory).
2. Prompt the user for confirmation (`y`/`yes` to proceed). The prompt is skipped if the environment variable `MIP_CONFIRM` is set.
3. If the user declines, the self-uninstall is aborted. `mip uninstall` then drops `mip-org/core/mip` from its argument list and proceeds normally with any remaining packages.
4. If the user confirms, mip runs `mip.reset()`, removes `<MIP_ROOT>/packages/mip-org/core/mip/mip` from the saved MATLAB path (via `path(pathdef)` + `rmpath` + `savepath`, with the live path restored and then re-pruned for the current session), and deletes the entire mip root directory (`rmdir(mip.paths.root(), 's')`).
5. A reinstall hint is printed.

If the packages directory is missing when self-uninstall is invoked, the flow raises `mip:uninstall:corrupted` and aborts without touching anything.

---

## 7. Updating

`mip update X Y Z` updates only the named packages. Existing dependencies are **not** updated (unless `--deps` is specified). After replacing each package with the latest version from its channel, any missing dependencies that the updated packages require are installed and any orphaned packages (old dependencies no longer needed by any directly installed package) are pruned. Packages that do **not** need updating are left entirely alone unless `--force` is specified.

Packages can be **pinned** to block all `mip update` paths from upgrading them; see [§7.11](#711-pinned-packages).

### 7.1 Update Flow (`mip update X Y Z`)

1. Parse `--force`, `--all`, `--deps`, and `--no-compile` flags.
2. If `--all` is specified, expand the argument list to all installed packages, then drop any pinned packages from the batch (a "Skipping pinned package" message is printed for each). `--force` does **not** override the pin filter (see [§7.11](#711-pinned-packages)). If every installed package is pinned, a message is printed and `mip update --all` returns without error. Otherwise (no `--all`), drop any explicitly named pinned packages from the batch with a "Skipping pinned package" message; the unpinned named packages still update. The user must `mip unpin <pkg>` first to update a pinned package. If every named package is pinned, the call returns without error. If `--deps` is specified, expand each remaining package's installed transitive dependencies into the argument list, dropping any pinned dependencies with a "Skipping pinned dependency" message.
3. Resolve each argument to a `(fqn, org, channel, name, pkgDir, pkgInfo, isLocal, sourcePath, editable, noSource)` tuple. Validation errors are raised **before** any destructive action:
   - Not installed → `mip:update:notInstalled`.
   - Local package whose `source_path` is non-empty but points to a missing directory → `mip:update:sourceNotFound`.
   - `--no-compile` specified but any package in the batch is not an editable local install → `mip:update:noCompileRequiresEditable` (checked after the `noSource` filter in step 4).
4. **Skip** local packages whose `source_path` is absent or empty in `mip.json` (`noSource = true`) -- these have no local source to reinstall from (URL installs being the primary case, see [§3.4](#34-installation-from-a-remote-zip-url)). A "Skipping" message is printed and they are dropped from the batch. If every requested package is skipped, `mip update` returns without error. `--force` does not override this skip.
5. If `mip-org/core/mip` is among the arguments, handle it via the self-update flow ([§7.7](#77-self-update-mip-update-mip)) and remove it from the batch.
6. For each remaining package, decide whether it needs updating:
   - `--force`: always yes.
   - Local package: always yes (no up-to-date check).
   - Remote package: fetch the channel index and pick the target version (see [§7.1.1](#711-target-version-selection-for-update)), then compare installed version + commit hash with the target:
     - Same version **and** same commit hash (or no hash available): "already up to date", skip.
     - Same version but different commit hash: update (content changed within the same version).
     - Different version: update.
7. If no packages need updating, return. Otherwise:
   - Snapshot `MIP_LOADED_PACKAGES` and `MIP_DIRECTLY_LOADED_PACKAGES`.
   - **Local packages** are updated via backup-and-restore: unload if loaded, move the old directory to a temporary backup, `remove_directly_installed`, then `mip.build.install_local(sourcePath, editable, noCompile)`. If `install_local` fails, the backup is moved back and `directly_installed` is restored. They do **not** go through `mip.uninstall` because the prune step would remove their deps, which `install_local` cannot re-fetch from a channel.
   - **Remote packages** are updated via staging: unload if loaded, download and extract the new version to a temporary staging directory, then move the old directory to a backup and move the staged version into place. If the swap fails, the backup is restored. The old package is never destroyed until the new version is fully in place. The `directly_installed.txt` entry is preserved (no removal/re-addition). Then install any missing dependencies that the updated packages require, and prune any orphaned packages.
   - Reload every package in the pre-update `MIP_LOADED_PACKAGES` snapshot that is not currently loaded and whose directory exists. Packages that were in the snapshot but are no longer installed are skipped with a warning.
   - Restore `MIP_DIRECTLY_LOADED_PACKAGES` to the pre-update snapshot (filtered to entries that are actually loaded now) so that packages which were only transitively loaded before the update remain only transitively loaded after.

#### 7.1.1 Target Version Selection for Update

`mip update` does **not** always pick the channel's best version as the update target. If the installed version is **non-numeric** (e.g., `main`, `master`), the update stays on that branch or version — the target is the same version in the channel, and only the commit hash is refreshed. This preserves the user's deliberate choice to follow a branch and prevents `mip update` from silently switching to a numeric release that appears alongside it.

Behavior by installed version:

- **Non-numeric installed version** (e.g., `main`): target = same non-numeric version in the channel. If that version no longer exists in the channel, `mip:update:versionNotInChannel` is raised (with guidance pointing at `mip install X@<version>`) and the installed package is left untouched.
- **Numeric installed version** (e.g., `1.0.0`): target = channel's best version per [§3.1.3](#313-version-selection-select_best_version) (typically the highest numeric version).

This rule only governs **implicit** `mip update X` calls. `mip install X@<version>` always honors the explicit request regardless of what is currently installed.

### 7.2 Local Package Update

Local packages do **not** go through `mip.uninstall` + `mip.install`. Instead, the old package directory is moved to a temporary backup and `mip.build.install_local` is called with the original `source_path` and `editable` flag from `mip.json`. If `install_local` fails, the backup is restored and the package remains in its pre-update state. This avoids pruning transitive dependencies that `install_local` cannot re-fetch.

- The up-to-date check is skipped -- local packages are always reinstalled.
- Timestamps change on every update. For editable installs the `compile_script` runs again on every update by default; the `--no-compile` flag from the original install is **not** preserved. Pass `--no-compile` to `mip update` to skip compilation for the current update ([§7.6](#76-skip-compilation-no-compile)).

### 7.3 Force Update (`--force`)

Skips the up-to-date check. The named package is replaced with the latest version from the channel even when version and commit hash match. Dependencies are still not updated (unless `--deps` is also specified) — only the named packages are replaced. To update a dependency, name it explicitly (`mip update dep`) or use `--deps`.

### 7.4 Update All (`--all`)

`mip update --all` updates every installed package. It is equivalent to listing all installed packages by name. Cannot be combined with explicit package names — `mip update --all foo` raises `mip:update:allWithPackages`. Can be combined with `--force` to force-update all packages.

### 7.5 Update With Dependencies (`--deps`)

`mip update --deps foo` updates `foo` **and** all of its installed transitive dependencies. Dependencies are resolved recursively from each package's `mip.json`. Only dependencies that are actually installed are included — missing dependencies are not installed by this flag (they are handled by the normal new-dependency installation step after the update). Can be combined with `--force`. Can be combined with multiple package names: `mip update --deps foo bar`.

### 7.6 Skip Compilation (`--no-compile`)

`mip update --no-compile foo` skips the `compile_script` step when updating `foo`. Only applies to editable local installs — if any package in the batch is not an editable local install (non-editable local, remote, or `mip` itself), the call raises `mip:update:noCompileRequiresEditable` **before** any destructive action. Can be combined with `--force`, `--all`, and `--deps`, but only when every resolved package is an editable local install.

### 7.7 Self-Update (`mip update mip`)

Special flow for `mip-org/core/mip`:
1. Fetch the latest from the `mip-org/core` channel.
2. Download the new `.mhl`, extract to staging.
3. Replace the installed package in-place.
4. Reload: `addpath` each entry from the new `mip.json` `paths` field (resolved against the new package dir).

Does not go through the normal uninstall-and-reinstall update flow, since mip is running and cannot remove itself mid-update. Self-update runs before the batch so it is safe to pass `mip` in the same call as other packages. (This is distinct from `mip uninstall mip`, which is a user-initiated tear-down — see [§6.4](#64-self-uninstall-mip-uninstall-mip).)

### 7.8 Load State Preservation

- Packages that were loaded before the update are reloaded afterward.
- Packages that were not loaded before the update remain unloaded afterward.
- The directly-vs-transitively loaded distinction is preserved: a package that was only transitively loaded before the update is not promoted to directly loaded, even if it needed an explicit `mip.load` call during the reload pass.
- If a previously-loaded package ends up uninstalled after the update (e.g. it was a transitive dep of the old version but not the new one, and was pruned), it is skipped with a warning; its entry is effectively dropped from the loaded set.
- **Partial failure**: if a package fails mid-batch, the reload pass still runs so that packages updated earlier in the batch are not left unloaded. The original error is re-raised after reloading.

### 7.9 Dependency Handling

`mip update foo` does **not** check whether `foo`'s dependencies have newer versions in the channel index. Only the named packages are updated. After the update:

- **Missing dependencies**: if the new version of `foo` depends on a package that is not installed, it is installed automatically.
- **Removed dependencies**: if the old version of `foo` depended on a package that is no longer needed by any directly installed package, it is pruned.
- **Existing dependencies**: dependencies that are already installed are left as-is, even if newer versions exist in the channel.

To update a dependency, name it explicitly (`mip update dep`) or use `--deps` to update a package and all its dependencies in one command.

### 7.10 Directly Installed Tracking

Each updated package remains directly installed after the update. The mechanism differs by install type:

- **Remote packages** preserve the `directly_installed.txt` entry in place — the entry is never removed.
- **Local packages** go through `remove_directly_installed` + `install_local` (see [§7.1](#71-update-flow-mip-update-x-y-z) step 7); `install_local` re-adds the entry, so the net effect is the same but there is a brief window during the update where the entry is absent.

Missing dependencies installed during the update are **not** added to `directly_installed.txt` — they remain transitive dependencies.

### 7.11 Pinned Packages

A package can be **pinned** to block all `mip update` paths from upgrading it. Pin state is stored persistently in `<root>/packages/pinned.txt` (one FQN per line) -- it survives MATLAB restarts and is separate from the loaded/sticky/directly-installed state.

#### 7.11.1 `mip pin <package> [...]`

Pins one or more installed packages. Each argument is resolved to an FQN against installed packages; not-installed arguments raise `mip:pin:notInstalled`. Already-pinned packages print a "already pinned" message and are otherwise a no-op. At least one argument is required (raises `mip:pin:noPackage`). Accepts both bare names and FQNs.

#### 7.11.2 `mip unpin <package> [...]`

Removes a pin. Each argument is resolved against installed packages; not-installed arguments raise `mip:unpin:notInstalled`. Arguments that are installed but not pinned print a "not pinned" message and are otherwise a no-op. At least one argument is required (raises `mip:unpin:noPackage`).

#### 7.11.3 Pin Behavior

A pin blocks every `mip update` invocation from upgrading the pinned package. The only way to update a pinned package is to `mip unpin <pkg>` first; `--force` does not override the pin.

- **`mip update <name>`** (explicit, with or without `--force`): if `<name>` is pinned, it is dropped from the batch with a "Skipping pinned package" message that points the user at `mip unpin <name>`. Other (unpinned) named packages in the same call still update. If every named package is pinned, the call returns without error.
- **`mip update --all`** (with or without `--force`): pinned packages are dropped from the batch with a "Skipping pinned package" message. If every installed package is pinned, the command prints a message and returns. See [§7.1](#71-update-flow-mip-update-x-y-z).
- **`mip update --deps <name>`**: if `<name>` itself is pinned, it is dropped from the batch with the same "Skipping pinned package" message as the explicit-name rule (its dependencies are not expanded). Pinned dependencies surfaced by the `--deps` expansion of unpinned named packages are dropped with a "Skipping pinned dependency" message and are not updated.
- **`mip uninstall <name>`**: the pin for `<name>` is cleared automatically so a reinstall starts unpinned.
- **`mip list`**: pinned packages display a `[pinned]` marker alongside any other markers (`[sticky]`, `[editable]`, etc.).

The `mip-org/core/mip` identity is not special-cased: it can be pinned and unpinned like any other package. `mip update mip` is treated as an explicit named update for pin purposes — if `mip` is pinned, it is skipped from the batch with the same "Skipping pinned package" message rather than running the self-update flow ([§7.7](#77-self-update-mip-update-mip)).

### 7.12 Build Matching (`match_build`)

When installing or compiling a package, MIP selects a build entry from the `builds` array in `mip.yaml` using a two-pass scan:

1. **Pass 1 — exact match**: scan all build entries in order; return the first whose `architectures` list contains the current architecture string.
2. **Pass 2 — `any` fallback**: scan all build entries again; return the first whose `architectures` list contains `any`.
3. If neither pass finds a match, raises `mip:noMatchingBuild`.

This guarantees an exact architecture match is always preferred over `any`, regardless of declaration order in `mip.yaml`.

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

Lists all installed packages. Default sort is by reverse load order (most recently loaded first). `--sort-by-name` sorts alphabetically. Status markers shown per package: `[sticky]` ([§4.2](#42-the---sticky-flag)), `[pinned]` ([§7.11](#711-pinned-packages)), and `[editable: <source>]` ([§3.2.2](#322-editable-install--e----editable)). An asterisk (`*`) marks directly loaded packages.

### 9.2 `mip info [<package>]`

With no arguments, prints mip's own version (from `mip.yaml`), the resolved mip root directory (see [§11.5](#115-mip_root-environment-variable)), and the current architecture tag (see [§12](#12-architecture-detection)).

With a package name, displays information about that package from two sources:

**Local Installation section:**
- Version, path, loaded status, dependencies, editable flag, source path.
- If the package is not installed locally, shows "Not installed".

**Remote Channel section:**
- Fetches channel index and shows available versions/architectures.

**Bare name with multiple installations:** Shows info for **all** installations with that name.

**FQN:** Shows info for only that specific installation.

**Unknown package:** If neither installed nor in any channel, raises `mip:unknownPackage`.

### 9.3 `mip avail`

Lists packages available in the channel index. Uses `--channel` to specify which channel (default: `mip-org/core`). Always re-downloads the channel index, bypassing the on-disk cache (see [§11.6](#116-channel-index-cache)) so the displayed list reflects the current state of the channel.

### 9.4 `mip version`

Prints the mip version string, read from `mip.yaml` in the package root. If `mip.yaml`'s `version` is blank or missing, an empty string is printed (see [§11.2](#112-mipyaml-schema)).

### 9.5 `mip reset`

Resets mip to a clean state:
1. Runs `mip unload --all --force` (unloads everything except `mip-org/core/mip`).
2. Removes all in-memory key-value stores (`MIP_LOADED_PACKAGES`, `MIP_DIRECTLY_LOADED_PACKAGES`, `MIP_STICKY_PACKAGES`).

### 9.6 `mip bundle <path>`

Builds a `.mhl` archive from a local package directory containing `mip.yaml`. Options:
- `--output <dir>` -- output directory (default: current directory)
- `--arch <arch>` -- override architecture (default: auto-detect)

Output filename: `<name>-<version>-<architecture>.mhl`. Because `-` is the field separator in this scheme, any `-` in the canonical package name is encoded as `_` in the filename only (e.g. `foo-bar` version `1.0` on `linux_x86_64` becomes `foo_bar-1.0-linux_x86_64.mhl`). The canonical name is preserved verbatim inside the bundled `mip.json`, and name normalization ([§1.8](#18-name-equivalence)) treats `-` and `_` as equivalent, so this encoding is transparent at install time. The **version** string, by contrast, is written verbatim; versions containing `-` (e.g. `1.0-beta`) are not encoded and will produce an ambiguous-looking filename. Nothing in mip currently parses the filename back out (installs read `mip.json` for the canonical metadata), so the ambiguity is cosmetic, but package authors should prefer dot-separated versions. See [§11.3](#113-mhl-file-format) for the archive format.

### 9.7 `mip test <package>`

Loads the package (if not already loaded) and runs its `test_script` (defined in `mip.yaml`). If no test script is defined, prints a message and returns.

### 9.8 `mip init`

Scaffolds a new mip package by generating a `mip.yaml` in a target directory.

```
mip init [<path>] [--name <packagename>] [--repository <url>]
```

- **`<path>`** (optional positional) -- directory to initialize. Defaults to the current directory (`.`) when omitted. Must already exist; otherwise raises `mip:init:notADirectory`.
- **`--name <packagename>`** (optional) -- overrides the default package name. When omitted, the name defaults to the target directory's basename. Names must match the regex `^[a-zA-Z0-9]([-a-zA-Z0-9_]*[a-zA-Z0-9])?$` (letters/digits/hyphens/underscores, starting and ending with a letter or digit); otherwise raises `mip:init:invalidName` with a hint to use `--name` to override.
- **`--repository <url>`** (optional) -- fills in the generated `mip.yaml`'s `repository` field. Omit to leave it blank.

Behavior:

1. If the target directory already contains a `mip.yaml`, `mip init` prints a message and exits without modifying anything.
2. `paths` is auto-populated by walking the directory and identifying folders that contain runtime MATLAB code. The walk happens **before** the placeholder test script is created, so the root is not auto-included just because of that new file.
3. A blank `test_<name>.m` is created at the target root (unless one already exists), and the generated `mip.yaml`'s `test_script` field points at it.
4. Other optional string fields (`description`, `version`, `license`, `homepage`) are emitted blank for the user to fill in. A single `builds: [{ architectures: [any] }]` entry is emitted.

`mip init` also runs automatically on behalf of local installs that are missing a `mip.yaml` (after the user confirms the prompt -- see [§3.2](#32-local-installation)) and on URL-based installs that land on a source tree with no `mip.yaml` (see [§3.4](#34-installation-from-a-remote-zip-url)).

Error identifiers: `mip:init:notADirectory`, `mip:init:invalidName`, `mip:init:missingNameValue`, `mip:init:missingRepositoryValue`, `mip:init:unexpectedArg`, `mip:init:writeFailed`.

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
| `<root>/packages/directly_installed.txt` | One FQN per line | Tracks which packages were directly installed (vs. installed as dependencies). Used for pruning. |
| `<root>/packages/pinned.txt` | One FQN per line | Tracks which packages are pinned against `mip update`. See [§7.11](#711-pinned-packages). |

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

Entries are added by:
- `mip install <pkg>` — marks the user-requested packages, even if they were already on disk as transitive dependencies (so re-installing a transitive dep promotes it to a root).
- `mip load <pkg>` — marks any package the user loads directly (`isDirect`). This means a `mip load` of a package previously pulled in only as a transitive dependency promotes it to a root, so a later uninstall of its parent will not prune it. Loads marked `--transitive` (used internally for dependency loads) do not mark.

Writes to `directly_installed.txt` are performed atomically: the new contents are written to `directly_installed.txt.tmp` and then moved into place via `movefile`. If the temp write fails, the existing `directly_installed.txt` is left untouched and the temp file is deleted. A stale `.tmp` from a previous crashed write is overwritten on the next write, not appended to.

### 10.5 Pinned Packages Tracking

Pinned packages are stored in `<root>/packages/pinned.txt`, one FQN per line. The file is sorted on every write and created on first pin. See [§7.11](#711-pinned-packages) for the behavioral effect of pinning.

- `add_pinned(fqn)`, `remove_pinned(fqn)`, `is_pinned(fqn)`, `get_pinned()`, `set_pinned(list)`.

---

## 11. Filesystem Layout

```
<mip-root>/                                # See §11.5 for resolution rules
  packages/
    directly_installed.txt                 # Persistent tracking of directly installed packages
    mip-org/
      core/
        mip/                               # The package manager itself
          mip.json
          mip/                             # Package source files
        chebfun/
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
          mip.json                         # editable: true, source_path: /path/to/source
        copypkg/                           # Non-editable local install
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
  "paths": ["src", "lib"],                     // addpath entries, relative to srcDir (see §4.8)
  "editable": false,
  "source_path": "/path/to/source",
  "compile_script": "do_compile.m",
  "test_script": "run_tests.m",
  "commit_hash": "abc123...",
  "source_hash": "def456...",
  "install_type": "local",
  "timestamp": "2026-04-06T12:00:00"
}
```

Required: `name`. All other fields have defaults or are optional.

The `paths` field is the authoritative list of directories that `mip load` adds to the MATLAB path. Each entry is interpreted relative to `srcDir` (see [`mip.paths.get_source_dir`](../+mip/+paths/get_source_dir.m)): the installed package's source subdir for copy installs, or `source_path` for editable installs. Entries are `rmpath`'d in matching fashion by `mip unload` (see [§5.8](#58-path-removal-from-mipjson)).

### 11.2 `mip.yaml` Schema

```yaml
name: package_name              # Required
version: "1.0.0"                # Optional; blank or numeric
description: "..."              # Optional
license: MIT                    # Optional
homepage: "https://..."         # Optional
repository: "https://..."       # Optional
dependencies: [dep1, dep2]      # Optional (defaults to []); bare or FQN names only, no @version or constraints
paths:                          # Optional (defaults to [])
  - path: "src"
  - path: "lib"
extra_paths:                    # Optional
  examples:
    - path: "examples"
  tests:
    - path: "tests"
builds:                         # Optional
  - architectures: [any]
    compile_script: "compile.m" # Optional
    test_script: "run_tests.m"  # Optional
```

#### 11.2.1 Channel Version Rules

A channel's package layout is `packages/<name>/<version>/` where the directory name is the authoritative version. `recipe.yaml` does not carry a `version` field. `mip.yaml`'s `version` is optional; when present it must be either blank or numeric (e.g. `1.2.3`). Non-numeric values like branch names belong in the release directory name, not in `mip.yaml`.

The channel build (`prepare_packages.py`) validates that the release-directory name is one of:

1. the numeric `version` in `mip.yaml`,
2. the `source.branch` in `recipe.yaml`, or
3. any string, when `mip.yaml`'s `version` is blank/missing.

The channel build passes the release-directory name to `mip bundle` so the bundled `mip.json` carries it as the authoritative version. The source `mip.yaml` in the bundle is unchanged; its `version` may remain blank or numeric while `mip.json` records the release-directory name.

### 11.3 `.mhl` File Format

A ZIP archive containing:
```
mip.json
<package_name>/
  [source files]
```

### 11.4 Empty Directory Cleanup

After removing a package, empty channel and org directories are cleaned up:
- If `<org>/<channel>/` is empty after removal, remove it.
- If `<org>/` is empty after that, remove it.

### 11.5 `MIP_ROOT` Environment Variable

The `MIP_ROOT` environment variable overrides the location of the mip root directory. When set, it is validated by [`mip.paths.root()`](../+mip/+paths/root.m) according to these rules:

- **Unset**: `mip.paths.root()` first tries path-based detection (navigating up from the installed `+mip/+paths/root.m` location, assuming `<root>/packages/mip-org/core/mip/mip/+mip/+paths/root.m`). If the inferred root has no `packages/` subdir (typical for an editable source checkout, where `root.m` resolves to the working tree rather than an installed location), it falls back to `<userpath>/mip`. If **that** also lacks a `packages/` subdir, `mip.paths.root()` raises `mip:rootNotFound` with a hint suggesting the user `setenv('MIP_ROOT', ...)` explicitly.
- **Set to empty string** (`""`): treated the same as unset. `getenv` returns `''` for both unset and empty values, and `mip.paths.root()` makes no attempt to distinguish them.
- **Set to a path that does not exist or is not a directory**: raises `mip:rootInvalid`.
- **Set to an existing directory that does not contain a `packages/` subdirectory**: raises `mip:rootInvalid`. `mip.paths.root()` does **not** auto-create `packages/`. The use case for `MIP_ROOT` is pointing at an existing mip installation, so a missing `packages/` indicates a misconfiguration rather than a fresh setup.

### 11.6 Channel Index Cache

Channel index downloads are cached on disk under `<root>/cache/index/<org>/<channel>.json`. The file stores the raw index JSON exactly as downloaded; the file's modification time is the cache timestamp.

- **TTL**: 30 seconds. A cache entry whose age is `< 30s` is served without contacting the network.
- **Bypass**: `mip avail` always re-downloads, bypassing the cache, so the displayed list reflects the current state of the channel. All other commands (`mip install`, `mip update`, `mip info`, etc.) use the cache.
- **Successes only**: only successful downloads are cached. A failed fetch (`mip:indexFetchFailed`) does not write a cache entry, so the next call retries immediately.
- **Corrupt cache**: if a cache file exists but cannot be read or parsed, it is treated as a miss and a fresh download is attempted.
- **Cache write failure**: if the cache write itself fails (read-only filesystem, etc.), the fetched index is still returned -- caching is best-effort.
- The cache directory is created on first write and is not pruned automatically.

---

## 12. Architecture Detection

`mip.build.arch()` returns a tag based on the platform:

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

`mip.build.arch()` itself only performs **detection** and always returns the exact platform tag (e.g. `numbl_linux_x86_64`). The `numbl_wasm` tag serves as a cross-`numbl_*` fallback during **variant selection** (see [§3.1.4](#314-architecture-selection-select_best_variant)), not at detection time.

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
| `mip:update:versionNotInChannel` | `mip update` target: installed non-numeric branch or version is no longer in the channel |
| `mip:circularDependency` | Circular dependency detected |
| `mip:dependencyNotFound` | A dependency is not installed |
| `mip:cannotUnloadMip` | Attempt to unload `mip-org/core/mip` |
| `mip:loadNotFound` | `mip.json` has no `paths` field |
| `mip:load:missingChannel` | `--channel` flag without a value in `mip load` |
| `mip:load:missingAddpathValue` | `--addpath` flag without a value |
| `mip:load:missingRmpathValue` | `--rmpath` flag without a value |
| `mip:load:addpathSinglePackage` | `--addpath` / `--rmpath` used with multiple positional packages |
| `mip:mipYamlNotFound` | `mip.yaml` missing in source directory |
| `mip:invalidMipYaml` | `mip.yaml` missing required `name` field |
| `mip:mipJsonNotFound` | `mip.json` missing in package directory |
| `mip:unknownPackage` | Package not installed and not found in any channel |
| `mip:install:noPackage` | No package specified for install |
| `mip:install:abortedNoMipYaml` | Local install aborted because user declined to auto-generate `mip.yaml` |
| `mip:install:urlRequiresName` | `--url` given without a positional package name |
| `mip:install:urlTakesSingleName` | `--url` given with 0 or 2+ positional args, or a non-bare-name positional |
| `mip:install:urlMustBeZip` | `--url` value does not point to a `.zip` archive |
| `mip:install:multipleUrls` | `--url` passed more than once |
| `mip:install:missingUrlValue` | `--url` flag provided without a value |
| `mip:install:zipDownloadFailed` | Download of a `.zip` URL failed |
| `mip:install:zipExtractFailed` | Extraction of a downloaded `.zip` failed |
| `mip:install:fexResolveFailed` | File Exchange URL resolution failed (network error, non-2xx, or resolved URL is not a `.zip`) |
| `mip:install:editableRequiresLocal` | `--editable` used without a local directory |
| `mip:install:noCompileRequiresEditable` | `--no-compile` used without `--editable` |
| `mip:digestMismatch` | Downloaded `.mhl` failed SHA-256 verification against the channel index digest |
| `mip:pathTraversal` | `.mhl` archive contains an entry that escapes the extraction root (absolute path, drive letter, null byte, out-of-tree `..`, central-directory/local-header mismatch, or escaping symlink) |
| `mip:update:notInstalled` | Package not installed |
| `mip:update:sourceNotFound` | Source directory no longer exists |
| `mip:compile:notInstalled` | Package not installed |
| `mip:compile:noCompileScript` | Package has no `compile_script` |
| `mip:uninstall:noPackage` | No package specified for uninstall |
| `mip:uninstall:corrupted` | Self-uninstall invoked but packages directory is missing |
| `mip:pin:noPackage` | No package specified for `mip pin` |
| `mip:pin:notInstalled` | Package named in `mip pin` is not installed |
| `mip:unpin:noPackage` | No package specified for `mip unpin` |
| `mip:unpin:notInstalled` | Package named in `mip unpin` is not installed |
| `mip:init:notADirectory` | `mip init` target path does not exist or is not a directory |
| `mip:init:invalidName` | Package name for `mip init` contains invalid characters |
| `mip:init:missingNameValue` | `mip init --name` given without a value |
| `mip:init:missingRepositoryValue` | `mip init --repository` given without a value |
| `mip:init:unexpectedArg` | `mip init` received an unrecognized argument |
| `mip:init:writeFailed` | `mip init` could not write the generated `mip.yaml` or test script |
| `mip:noPackage` | Generic "no package specified" from CLI dispatch (command-specific variants are preferred) |
| `mip:noDirectory` | No directory specified where one was required |
| `mip:unknownCommand` | `mip <cmd>` where `<cmd>` is not a recognized subcommand |
| `mip:notAFileOrDirectory` | A path argument resolves to neither a file nor a directory |
| `mip:invalidPackageFormat` | Package argument has a structurally invalid format (distinct from §2.1 spec violations) |
| `mip:rootNotFound` | `MIP_ROOT` unset and both path-based detection and the `<userpath>/mip` fallback lack a `packages/` subdir (see [§11.5](#115-mip_root-environment-variable)) |
| `mip:indexFetchFailed` | Channel index could not be fetched (network failure or non-2xx) |
| `mip:availFailed` | `mip avail` failed to fetch the channel index |
| `mip:downloadFailed` | Download of a file (e.g. `.mhl`) failed |
| `mip:fileNotFound` | A required file does not exist |
| `mip:fileError` | Generic file I/O failure (open/read/write) |
| `mip:copyFailed` | `copyfile` operation failed |
| `mip:noBuild` | `mip.yaml` has no `builds` entries |
| `mip:noMatchingBuild` | No `builds` entry matches the current architecture (and no `any` fallback) |
| `mip:mhlNotFound` | `.mhl` archive is missing where expected |
| `mip:extractFailed` | `.mhl` or `.zip` extraction failed |
| `mip:invalidPackage` | Extracted archive is not a well-formed mip package |
| `mip:invalidMipJson` | `mip.json` has an invalid structure |
| `mip:jsonParseFailed` | `mip.json` could not be parsed as JSON |
| `mip:yamlParseFailed` | `mip.yaml` could not be parsed (see `mip:parse_yaml:*` for the low-level cause) |
| `mip:parse_yaml:*` | Low-level YAML parser errors: `type`, `trailing`, `unterminatedString`, `noProgress`, `expectColon`, `expectKey`, `keyNewline`, `unterminatedFlow`, `flowSeparator`, `badEscape` |
| `mip:name:invalidInput` | Input passed to `mip.name.normalize` / `mip.name.match` is not a valid string |
| `mip:version:noMipYaml` | `mip version` cannot locate `mip.yaml` in the package root |
| `mip:install:invalidPackageSpec` | Install argument has 2 or 4+ slash-separated parts (see [§3.0](#30-argument-categorization)) |
| `mip:install:notADirectory` | Local install target exists but is not a directory |
| `mip:update:noPackage` | `mip update` called with no arguments and no `--all` |
| `mip:update:allWithPackages` | `mip update --all foo` — `--all` cannot be combined with explicit package names |
| `mip:update:noCompileRequiresEditable` | `mip update --no-compile` used with a package that is not an editable local install |
| `mip:update:unavailable` | Updated package has no build available for the current architecture |
| `mip:update:notInIndex` | Updated package is not present in its channel index |
| `mip:compile:noPackage` | `mip compile` called with no package argument |
| `mip:compile:sourceMissing` | Compile target's source directory does not exist |
| `mip:compileScriptNotFound` | The configured `compile_script` file is missing on disk |
| `mip:compileFailed` | Compile script threw an error |
| `mip:uninstallFailed` | Uninstall failed while removing package files |
| `mip:bundle:noDirectory` | `mip bundle` called with no directory argument |
| `mip:bundle:noMipYaml` | `mip bundle` target directory has no `mip.yaml` |
| `mip:bundle:missingOutput` | `mip bundle --output` given without a value |
| `mip:bundle:missingArch` | `mip bundle --arch` given without a value |
| `mip:bundle:unexpectedArg` | `mip bundle` received an unrecognized argument |
| `mip:test:noPackage` | `mip test` called with no package argument |
| `mip:test:notInstalled` | `mip test` target is not installed |
| `mip:test:dirMissing` | `mip test` target's source directory does not exist |
| `mip:test:scriptNotFound` | `mip test` target's configured `test_script` is missing on disk |
| `mip:test:failed` | Test script threw an error |

The following **warning** identifiers are also issued:

| Warning ID | Trigger |
|---|---|
| `mip:unloadNotFound` | `mip unload <pkg>` on a package whose `mip.json` has no `paths` field (see [§5.8](#58-path-removal-from-mipjson)) |
| `mip:brokenDependencies` | After an unload/uninstall, at least one still-loaded or still-installed package has a dependency that is no longer loaded/installed |

---

## 14. Open Questions and Gaps

This section collects unresolved design questions and untested behaviors. Items that were previously open but have since been resolved are documented in the relevant sections above (see issues [#94](https://github.com/mip-org/mip/issues/94), [#95](https://github.com/mip-org/mip/issues/95), [#99](https://github.com/mip-org/mip/issues/99)--[#105](https://github.com/mip-org/mip/issues/105)).

### 14.4 No Lock File

There is no lock file recording exact versions/commits of installed dependencies. The installed state on disk (`<root>/packages/` and `directly_installed.txt`) is the only record, so installs are not reproducible across machines or over time. Lock file support is **not planned for the first release**.

### 14.5 Ambiguous Unload Uses Load Order

When multiple loaded packages share a bare name, `mip unload <bare>` unloads the most recently loaded one ([§5.2](#52-bare-name-disambiguation-for-unload)). This differs from `mip uninstall`, which refuses and requires FQN disambiguation ([§6.3](#63-bare-name-ambiguity)). Should these be consistent?

### 14.6 `mip load --install` Channel Handling

`mip load --install chebfun` installs from the default channel (or `--channel`) if not installed. There is no disambiguation check when the package name exists on multiple channels. Should this error like `mip uninstall` does?

**Untested.**

### 14.7 Concurrent MATLAB Sessions

Running multiple MATLAB sessions that share the same mip root directory is **not supported**. In-memory state (`setappdata`) is per-session, while file state (`directly_installed.txt`, installed packages on disk) is shared with no file locking. Concurrent `mip install`/`mip uninstall` operations can race on `directly_installed.txt` (read-modify-write without locking) and one session's `mip uninstall` can remove packages another session has loaded. Users should avoid running `mip` commands that modify state from multiple sessions simultaneously.

### 14.8 Missing Test Coverage

Behaviors specified in this document but not covered by tests:

- `mip load --install` with `--channel` ([§14.6](#146-mip-load---install-channel-handling))
- `mip install` from URL (`https://...`)
- `mip avail` ([§9.3](#93-mip-avail)), `mip info` remote-only display with `--channel`

# mip as a Package

Working guide. This document describes the intended behavior of mip as a
package — installed, loaded, updated, and uninstalled by itself. It is the
reference we will use to adjust the working specification and the
implementation; it is not bound by either.

## Overview

mip is a package manager and a MATLAB package. mip is a package in mip's
core channel (`mip-org/core`).

When a user runs the install script of mip, it bootstraps a mip root
(default location: `<userpath>/mip`, e.g. `~/Documents/MATLAB/mip`) and puts
the mip MATLAB package in that root the same way any channel package is
installed:

```
<root>/packages/gh/mip-org/core/mip/        the installed package
<root>/packages/gh/mip-org/core/mip/mip/    its source: mip.m and +mip/
```

And it adds mip — the source directory above — to the MATLAB saved path, so
`mip` is available in every MATLAB session.

This is the default way that mip can be installed. mip can also be installed
as a standalone package, not bootstrapped into a root. In this case, the
`MIP_ROOT` environment variable must be defined and point to a root folder.

## Definitions

**Definition (root).** A root is a folder with a `packages/` subfolder
holding installed packages. Any folder with a `packages/` subfolder is a
root, and nothing more is required; all other per-root state (cache, trash,
pins, channel subscriptions, install tracking) lives inside the root and is
created lazily as needed.

**Definition (main root).** The main root is the root in effect at MATLAB
startup: the folder pointed to by the `MIP_ROOT` environment variable if it
is set when MATLAB starts, otherwise the root mip was bootstrapped into
(recovered from the installed mip's own location). The main root does not
change for the lifetime of the MATLAB session.

**Definition (main mip).** The main mip is the mip command that is active at
MATLAB startup — the `mip` reached through the MATLAB saved path. For a
default installation this is the copy installed in the main root; for a
standalone installation it is the standalone copy.

**Definition (active mip).** The active mip is the mip that is running
commands: the `mip` that MATLAB dispatches to when `mip` is invoked — the
first `mip` on the MATLAB path (`which mip`). At startup the active mip is
the main mip; it changes when another mip is placed ahead of it on the path,
e.g. by loading a different mip package.

**Definition (active root).** The active root is the root that mip commands
act on. At startup the active root is the main root. Activating an
environment makes that environment's root the active root; deactivating
restores the main root.

## Scenarios

Each scenario describes a current state, an action, and the outcome.

### Scenario 1

**State:** mip was installed with the install script: bootstrapped into the
main root and on the MATLAB saved path. The active root is the main root,
the active mip is the main mip, and no other copy of mip is installed
anywhere.

**Action:** `mip load mip`

**Outcome:** Nothing changes. mip is always loaded; a message says so.

### Scenario 2

**State:** As in Scenario 1.

**Action:** `mip unload mip`

**Outcome:** Refused with an error. mip cannot be unloaded; it is the code
that is running.

### Scenario 3

**State:** As in Scenario 1.

**Action:** `mip install mip`

**Outcome:** Nothing changes. mip is already installed; a message says so.

### Scenario 4

**State:** As in Scenario 1. The core channel has a newer version of mip
than the one installed.

**Action:** `mip update mip`

**Outcome:** mip replaces its own installed files in the main root with the
newer version. The session continues on the new version — no restart, no
change to the saved path. If no newer version had been available, the
command would report up to date and change nothing.

### Scenario 5

**State:** As in Scenario 1.

**Action:** `mip install mip@<version>`, where `<version>` differs from the
installed one.

**Outcome:** Same mechanism as Scenario 4: the installed files in the main
root are replaced with the requested version, and the session continues on
it. This works in both directions — it is also how a user downgrades mip.

### Scenario 6

**State:** As in Scenario 1.

**Action:** `mip uninstall mip`

**Outcome:** The full teardown, after confirmation: mip removes itself from
the MATLAB saved path and deletes the entire main root, including every
installed package. This is how mip is uninstalled.

### Scenario 7

**State:** As in Scenario 1.

**Action:** `mip install other/channel/mip`

**Outcome:** The mip package published on another channel is installed into
the active root as an ordinary package. It is not loaded; the active mip is
unchanged.

### Scenario 8

**State:** As in Scenario 1, plus `other/channel/mip` is installed (the
result of Scenario 7).

**Action:** `mip load other/channel/mip`

**Outcome:** Loaded like any other package: its paths are placed ahead on
the MATLAB path, so it becomes the active mip. Subsequent `mip` commands
are run by it. The main root is unchanged, and the main mip is untouched —
still installed, still on the saved path.

### Scenario 9

**State:** `other/channel/mip` is installed and loaded; it is the active
mip (the result of Scenario 8).

**Action:** `mip unload other/channel/mip`

**Outcome:** Allowed — naming it explicitly is the way to unload it. Its
paths are removed and the main mip becomes the active mip again. The
session is back to the state of Scenario 8's starting point.

### Scenario 10

**State:** As in Scenario 9's starting point, plus some ordinary packages
are loaded.

**Action:** `mip unload --all`

**Outcome:** The ordinary packages are unloaded. The core mip and the
loaded `other/channel/mip` are both spared: no bulk operation ever pulls
running code off the path. Explicitly naming `other/channel/mip`
(Scenario 9) remains the only way to unload it.

### Scenario 11

**State:** As in Scenario 9's starting point: `other/channel/mip` is loaded
and is the active mip. The core channel has a newer version of mip.

**Action:** `mip update mip`

**Outcome:** Refused with an error. The main mip cannot be updated or
uninstalled while any other mip is loaded; the error says to
`mip unload other/channel/mip` first. The same rule applies to
`mip install mip@<version>` (Scenario 5), which is the same mechanism.

### Scenario 12

**State:** As in Scenario 9's starting point: `other/channel/mip` is loaded
and is the active mip.

**Action:** `mip uninstall mip`

**Outcome:** Refused with an error, by the same rule as Scenario 11: the
main mip cannot be updated or uninstalled while any other mip is loaded.
The error says to `mip unload other/channel/mip` first; after that, the
teardown of Scenario 6 is available.

### Scenario 13

**State:** As in Scenario 9's starting point: `other/channel/mip` is loaded
and is the active mip.

**Action:** `mip update other/channel/mip` (or
`mip uninstall other/channel/mip`)

**Outcome:** Refused with an error, by the same principle as Scenarios 11
and 12: a mip whose code is currently running cannot be updated or
uninstalled while loaded. The error says to `mip unload other/channel/mip`
first. Once unloaded, it is an ordinary package again — updating or
uninstalling it proceeds normally (run by the main mip).

### Scenario 14

**State:** mip is installed standalone: the mip package sits somewhere on
the MATLAB path (e.g. a checkout or a download), not installed in any root.
The `MIP_ROOT` environment variable points to a root folder, which is the
main root. No mip package is installed in that root. The active mip is the
main mip — the standalone copy.

**Action:** `mip update mip`

**Outcome:** Refused with a message: the running mip is standalone, not
installed in any root, so mip does not manage its own files here. A
standalone mip is updated by updating the standalone copy itself (pulling
the checkout, or downloading a new copy). The main root is untouched.

### Scenario 15

**State:** As in Scenario 14 (standalone mip, `MIP_ROOT` set).

**Action:** `mip uninstall mip`

**Outcome:** Refused with a message, for the same reason as Scenario 14:
mip is not installed in the root, and mip does not own the root, so there
is no teardown to run. The root is never deleted in standalone mode. A
standalone mip is removed by the user — delete the copy and remove it from
the path.

### Scenario 16

**State:** As in Scenario 14 (standalone mip, `MIP_ROOT` set).

**Action:** `mip install mip`

**Outcome:** Refused with a message: installing the core mip package into
the root while a standalone mip is running would put a second, non-running
mip on disk and only cause confusion. Installing a **non-core** mip is
allowed — `mip install other/channel/mip` proceeds as an ordinary package
install (Scenario 7), and it can be loaded to become the active mip
(Scenario 8).

### Scenario 17

**State:** As in Scenario 1 (default install), plus an environment `myenv`
has been created with `mip env create myenv`.

**Action:** `mip activate myenv`

**Outcome:** The environment's root becomes the active root: install,
update, uninstall, load, and list now act on it. All packages loaded from
the base environment are unloaded. The active mip is unchanged — the main
mip keeps running commands; activation never changes which mip runs. mip
itself is not installed in the environment, and does not need to be. The
main root is unchanged.

### Scenario 18

**State:** As in Scenario 9's starting point — `other/channel/mip` is
loaded and is the active mip — plus an environment `myenv` exists.

**Action:** `mip activate myenv`

**Outcome:** As in Scenario 17, all loaded packages are unloaded — including
`other/channel/mip` as a package. But its code stays on the MATLAB path, so
it remains the active mip and keeps running commands; it is simply no longer
a loaded package. Activation never changes which mip runs.

### Scenario 19

**State:** As in Scenario 17's result: the environment `myenv` is active.

**Action:** `mip install any/channel/mip` or `mip load` of any mip package

**Outcome:** Refused with an error: no mip — core or otherwise — may be
installed into or loaded from an environment. This restriction may be
relaxed later.

### Scenario 20

**State:** As in Scenario 17's result: `myenv` is active. Some packages
were loaded in the base environment before activation; some packages have
been loaded from the environment since.

**Action:** `mip deactivate`

**Outcome:** The packages loaded from the environment are unloaded. The
main root becomes the active root again, and the packages that were loaded
in the base environment before activation are loaded again, in their
original order. The session is back exactly where it was before
activation.

### Scenario 21

**State:** As in Scenario 18's result: `myenv` is active, and
`other/channel/mip` is the active mip — on the path but not a loaded
package.

**Action:** `mip deactivate`

**Outcome:** As in Scenario 20, and the restored package set includes
`other/channel/mip`: it becomes a loaded package again. The session
returns to Scenario 8's result — `other/channel/mip` loaded and active.
It was the active mip the whole time; deactivation, like activation, never
changes which mip runs.

### Scenario 22

**State:** As in Scenario 17's result: `myenv` is active.

**Action:** `mip update mip` (or `mip uninstall mip`, or
`mip install mip@<version>`)

**Outcome:** Refused with an error saying to `mip deactivate` first. This
completes the rule of Scenarios 11 and 12: **the main mip may be updated or
uninstalled only when the active root is the main root and no other mip is
loaded.** Operations on the main mip happen from the state it was installed
in — a plain session on the main root — and nowhere else.

### Scenario 23

**State:** As in Scenario 14 (standalone mip, `MIP_ROOT` set), plus an
environment `myenv` has been created.

**Action:** `mip activate myenv`, work, then `mip deactivate`

**Outcome:** Exactly as in Scenarios 17 and 20 — environments behave the
same regardless of how mip is installed. The standalone mip stays the
active mip throughout; it was never a loaded package to begin with (it is
on the path, unmanaged, much like `other/channel/mip` in Scenario 18), so
the activation and deactivation swaps never touch it. The self-operation
refusals of Scenarios 14–16 hold inside the environment as well.

### Scenario 24

**State:** As in Scenario 1 (default install, main root active). The core
channel has a newer version of mip than the one installed.

**Action:** Any command that consults the core channel (e.g. `mip install`,
`mip avail`).

**Outcome:** Alongside its normal output, the command prints a one-line
notice that a newer mip is available, suggesting `mip update mip` — and
running that suggestion works, because in this state Scenario 4 applies.
The notice is advisory: printed at most once per command, and a failure in
the check can never break the command that triggered it.

### Scenario 25

**State/Action:** As in Scenario 24, but in a state where the suggestion
would be wrong or unusable: a standalone mip (Scenarios 14–16), a non-main
mip is the active mip (Scenarios 8–13), or an environment is active
(Scenario 22).

**Outcome:** No notice. The notice appears only when its suggestion would
actually work — the state of Scenario 24 — and stays quiet in every other
state rather than advising something mip would refuse.

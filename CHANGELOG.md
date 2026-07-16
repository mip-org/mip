# Changelog

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

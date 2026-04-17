# mip

A package manager for MATLAB.

`mip` installs MATLAB packages from channel repositories, resolves their
dependencies, and manages your path.

> **Status:** early stage, under active development. Expect occasional
> breaking changes before the first stable release.

Docs and command reference: [mip.sh](https://mip.sh).

## Install

From inside MATLAB:

```matlab
eval(webread('https://mip.sh/install.txt'))
```

## Quick tour

```matlab
mip avail                    % list packages available in the default channel
mip install chebfun          % install a package and its dependencies
mip load chebfun             % add it to the MATLAB path
mip list                     % show installed / loaded packages
mip unload chebfun           % remove from path
mip uninstall chebfun        % remove the package (prunes orphaned deps)
```

Install several at once, ask for a specific version, or install from a local
directory:

```matlab
mip install chebfun chunkie            % install multiple packages
mip install chunkie                    % automatically installs dependencies
mip install kdtree                     % automatically installs MEX files
mip install chebfun@1.2.0              % request version 1.2.0
mip install --channel user/repo pkg    % install from a channel
mip install ./my-package               % local install
mip install -e ./my-package            % editable install (pip -e style)
```

Run `mip help` for the full command list, or see
[mip.sh/docs](https://mip.sh/docs).

## Concepts

- **Channel**: a package repository hosted on GitHub Pages. The default is
  `mip-org/core`. Anyone can publish their own channel.
- **Package**: a MATLAB library with a `mip.yaml` describing its sources,
  build steps, and dependencies. Packages can ship pre-compiled MEX binaries
  per architecture so users don't have to compile anything locally.

For the rest — version selection, dependency pruning, editable installs,
channel layout — see [mip.sh/docs](https://mip.sh/docs).

## Publishing a package or channel

See [mip.sh/docs](https://mip.sh/docs). Starting point for a new channel:
[mip-channel-template](https://github.com/mip-org/mip-channel-template).

## Authors

Dan Fortunato and Jeremy Magland
Center for Computational Mathematics, Flatiron Institute

## License

Apache 2.0. See [LICENSE](LICENSE).

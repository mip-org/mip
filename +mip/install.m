function install(varargin)
%INSTALL   Install one or more mip packages.
%
% Usage:
%   mip install <package>
%   mip install <package1> <package2> ...
%   mip install --channel <owner>/<channel> <package>
%   mip install --channel <owner> <package>                        - Shorthand for --channel <owner>/<owner>
%   mip install <owner>/<channel>/<package>
%   mip install <owner>/<package>                                  - Shorthand for <owner>/<owner>/<package>
%   mip install /path/to/package.mhl                               - Install under mhl/<name>
%   mip install https://example.com/package.mhl                    - Install under mhl/<name>
%   mip install --channel <owner>/<channel> /path/to/package.mhl   - Install under gh/<owner>/<channel>/<name>
%   mip install /path/to/local/package                             - Install from local directory
%   mip install . --editable                                       - Editable install (like pip -e)
%   mip install -e /path/to/package                                - Editable install (short form)
%   mip install -e . --no-compile                                  - Editable install, skip compilation
%   mip install https://example.com/pkg.zip --name mypkg           - Install from a remote .zip URL
%   mip install https://www.mathworks.com/matlabcentral/fileexchange/23629-export_fig
%                                                                   - Install from the File Exchange
%
% Options:
%   --channel <name>    Install from a specific channel (default: mip-org/core)
%                       Format: '<owner>/<channel>' (e.g. 'mip-org/core'). A bare
%                       single name '<owner>' is shorthand for '<owner>/<owner>'
%                       — the user's personal channel repo at
%                       github.com/<owner>/mip-<owner>.
%   --editable, -e      Install in editable mode (local packages only)
%   --no-compile        Skip compilation (editable installs only)
%   --name <name>       Package name for a .zip / File Exchange URL install.
%                       If omitted, mip prompts for the name with a default
%                       derived from the URL. Requires the argument list to
%                       be a single URL; incompatible with --editable.
%
% Remote .zip / File Exchange URLs:
%   An http(s):// URL whose path ends in .zip, or a File Exchange landing
%   URL (https://www.mathworks.com/matlabcentral/fileexchange/...), is
%   downloaded, extracted, and installed under web/<name> (or fex/<name>
%   for File Exchange). File Exchange landing URLs are auto-resolved to
%   their .zip download. https:// is required.
%
% Local packages:
%   To install a local directory, the path must start with '~', '.', '/',
%   or a Windows drive letter (e.g. 'C:\path\mypkg', 'C:/path/mypkg').
%   The directory must contain a mip.yaml file. Missing channel
%   dependencies declared in mip.yaml are installed automatically (as
%   transitive dependencies, like remote installs). In editable mode,
%   changes to the source directory are reflected immediately without
%   reinstalling.
%   '@' in local paths is treated as a literal character, not a version
%   separator (e.g. './@MyClass', './pkg@dev' are valid local paths).
%
%   Bare names like 'chebfun' are always resolved against channels, even
%   if a directory of the same name exists in the current folder. Use
%   './chebfun' to force a local install.
%
% Packages can be specified by bare name or fully qualified name
% (<owner>/<channel>/<package>). Fully qualified names override the --channel
% flag.

    if nargin < 1
        error('mip:install:noPackage', 'At least one package name is required for install command.');
    end

    % Show the target when an environment is active (session state has no
    % shell prompt to reflect it).
    mip.env.print_banner();

    % Reclaim any package dirs left in the trash by an earlier removal that
    % could only move them aside (a binary was still loaded at the time).
    mip.paths.purge_trash();

    % Check for --editable / -e, --no-compile, --name, and --channel flags
    % (--url is retained in the spec only to give a migration error)
    [opts, args] = mip.parse.flags(varargin, ...
        struct('editable', false, 'no_compile', false, 'url', '', 'name', '', 'channel', ''), ...
        struct('e', 'editable'));
    channel = opts.channel;
    if ~isempty(channel)
        channel = mip.parse.normalize_channel_spec(channel);
    end

    if opts.no_compile && ~opts.editable
        error('mip:install:noCompileRequiresEditable', ...
              '--no-compile can only be used with --editable local installs.');
    end

    if ~isempty(opts.url)
        if isscalar(args)
            hint = sprintf('mip install %s --name %s', opts.url, char(args{1}));
        else
            hint = sprintf('mip install %s --name <name>', opts.url);
        end
        error('mip:install:urlFlagRemoved', ...
              ['The --url flag has been removed. Pass the URL directly:\n' ...
               '  %s'], hint);
    end

    if isempty(args)
        error('mip:install:noPackage', 'At least one package name is required for install command.');
    end

    % Categorize each argument by how it should be installed:
    %   - URL source   (File Exchange landing URL or http(s) .zip URL)
    %   - mhl source   (.mhl file or other http(s) URL)
    %   - local path   (starts with ~, ., /, or a Windows drive letter)
    %   - repo package (bare name or <owner>/<channel>/<package> FQN)
    urlSources = {};
    mhlSources = {};
    localPaths = {};
    repoPackages = {};
    for i = 1:length(args)
        pkg = char(args{i});
        if mip.install.is_url_source(pkg)
            urlSources{end+1} = pkg; %#ok<AGROW>
        elseif endsWith(pkg, '.mhl') || startsWith(pkg, 'http://') || startsWith(pkg, 'https://')
            mhlSources{end+1} = pkg; %#ok<AGROW>
        elseif mip.parse.is_explicit_path(pkg)
            localPaths{end+1} = pkg; %#ok<AGROW>
        else
            try
                parsed = mip.parse.parse_package_arg(pkg);
            catch
                error('mip:install:invalidPackageSpec', ...
                      ['Invalid package specifier "%s".\n' ...
                       'Use "<package>" for a bare name or "<owner>/<channel>/<package>" for a fully qualified name.\n' ...
                       'To install a local package, prefix the path with "./":\n' ...
                       '  mip install ./%s'], pkg, pkg);
            end
            if parsed.is_fqn && ~strcmp(parsed.type, 'gh')
                error('mip:install:invalidPackageSpec', ...
                      ['Invalid package specifier "%s".\n' ...
                       'Only GitHub channel packages can be installed from a repository.\n' ...
                       'To install a local package, prefix the path with "./":\n' ...
                       '  mip install ./%s'], pkg, pkg);
            end
            repoPackages{end+1} = pkg; %#ok<AGROW>
        end
    end

    if ~isempty(opts.name)
        if isempty(urlSources)
            error('mip:install:nameRequiresUrl', ...
                  '--name can only be used when installing from a .zip or File Exchange URL.');
        end
        if length(args) > 1
            error('mip:install:nameTakesSingleUrl', ...
                  '--name can only be used with a single URL argument; got %d arguments.', ...
                  length(args));
        end
    end

    if opts.editable && isempty(localPaths)
        error('mip:install:editableRequiresLocal', ...
              '--editable can only be used with local directory packages.');
    end

    % Process local directory installs first
    for i = 1:length(localPaths)
        localPath = localPaths{i};
        if ~isfolder(localPath)
            error('mip:install:notADirectory', ...
                  '"%s" is not a directory.', localPath);
        end
        if ~isfile(fullfile(localPath, 'mip.yaml'))
            if confirmAutoInit(localPath)
                mip.init(localPath);
                fprintf('\n');
            else
                error('mip:install:abortedNoMipYaml', ...
                      ['Directory "%s" does not contain a mip.yaml file ' ...
                       'and the user declined to auto-generate one. ' ...
                       'Install aborted.'], localPath);
            end
        end
        mip.install.from_local(localPath, opts.editable, opts.no_compile, 'local');
    end

    % Process .zip / File Exchange URL installs. opts.name is only
    % non-empty when there is a single URL argument (checked above);
    % with no --name, from_url prompts for each URL's name.
    for i = 1:length(urlSources)
        mip.install.from_url(urlSources{i}, opts.name, opts.editable, opts.no_compile);
    end

    % If only local and URL installs were requested, we're done
    if isempty(repoPackages) && isempty(mhlSources)
        return;
    end

    packagesDir = mip.paths.get_packages_dir();
    if ~exist(packagesDir, 'dir')
        mkdir(packagesDir);
    end

    % Handle repository packages
    installedFqns = {};

    if ~isempty(repoPackages)
        try
            installedFqns = [installedFqns, mip.install.from_repository(repoPackages, channel)];
        catch ME
            hint = buildLocalDirHint(repoPackages);
            if ~isempty(hint)
                throw(MException(ME.identifier, '%s\n\n%s', ME.message, hint));
            end
            rethrow(ME);
        end
    end

    % Handle .mhl file installations
    for i = 1:length(mhlSources)
        fqn = mip.install.from_mhl(mhlSources{i}, channel);
        if ~isempty(fqn)
            installedFqns = [installedFqns, {fqn}]; %#ok<AGROW>
        end
    end

    % Summary
    if isempty(installedFqns) && isempty(mhlSources)
        fprintf('\nAll packages already installed.\n');
    elseif ~isempty(installedFqns)
        fprintf('\nSuccessfully installed %d package(s).\n', length(installedFqns));
        % mip itself is always loaded, so it never gets a "mip load" hint.
        loadable = installedFqns(~strcmp(installedFqns, 'gh/mip-org/core/mip'));
        if ~isempty(loadable)
            fprintf('\nTo use installed packages, run:\n');
            for i = 1:length(loadable)
                fprintf('  mip load %s\n', mip.resolve.get_shortest_name(loadable{i}));
            end
        end
    end
end

function tf = confirmAutoInit(localPath)
% Ask the user whether to auto-generate a mip.yaml in localPath.
% Honors MIP_CONFIRM as a non-interactive override (matching uninstall.m).
% Returns true on "y"/"yes", false otherwise.
    fprintf('\nDirectory "%s" does not contain a mip.yaml file.\n', localPath);
    fprintf('mip can auto-generate one for you (equivalent to running `mip init`).\n');
    confirm = getenv('MIP_CONFIRM');
    if isempty(confirm)
        confirm = input('Auto-generate mip.yaml? (y/n): ', 's');
    end
    tf = strcmpi(confirm, 'y') || strcmpi(confirm, 'yes');
end

function hint = buildLocalDirHint(repoPackages)
% If any of the repo-style args also exists as a relative directory in
% the current folder, build a hint suggesting the './' form.
% Also checks the base name after stripping any @version suffix, since
% local paths treat '@' as a literal character (not a version separator).
    lines = {};
    for i = 1:length(repoPackages)
        dirName = matchLocalDir(repoPackages{i});
        if ~isempty(dirName)
            lines{end+1} = sprintf( ... %#ok<AGROW>
                ['Note: a local directory "%s" exists in the current folder.\n' ...
                 'To install it as a local package instead, run:\n' ...
                 '  mip install ./%s'], dirName, dirName);
        end
    end
    hint = strjoin(lines, sprintf('\n\n'));
end

function dirName = matchLocalDir(pkg)
% Check if pkg matches a local directory, either as-is or after stripping
% a trailing @version suffix.
    dirName = '';
    if isfolder(pkg)
        dirName = pkg;
    else
        atIdx = strfind(pkg, '@');
        if ~isempty(atIdx)
            baseName = pkg(1:atIdx(end)-1);
            if isfolder(baseName)
                dirName = baseName;
            end
        end
    end
end

function compile(varargin)
%COMPILE   Compile (or recompile) an installed package's MEX files.
%
% Usage:
%   mip.compile('packageName')
%   mip.compile('org/channel/packageName')
%
% Runs the compile script defined in the package's mip.yaml (or stored
% in mip.json for editable installs). For editable installs, compilation
% runs in the original source directory. For non-editable local installs,
% compilation runs in the installed package directory.
%
% Accepts both bare package names and fully qualified names.

if nargin < 1
    error('mip:compile:noPackage', 'Package name is required for compile command.');
end

packageArg = varargin{1};
if isstring(packageArg)
    packageArg = char(packageArg);
end

% Resolve to FQN
result = mip.utils.parse_package_arg(packageArg);

if result.is_fqn
    fqn = packageArg;
    org = result.org;
    channelName = result.channel;
    packageName = result.name;
else
    fqn = mip.utils.resolve_bare_name(result.name);
    if isempty(fqn)
        error('mip:compile:notInstalled', ...
              'Package "%s" is not installed.', result.name);
    end
    r = mip.utils.parse_package_arg(fqn);
    org = r.org;
    channelName = r.channel;
    packageName = r.name;
end

pkgDir = mip.utils.get_package_dir(org, channelName, packageName);

if ~exist(pkgDir, 'dir')
    error('mip:compile:notInstalled', ...
          'Package "%s" is not installed.', fqn);
end

% Read mip.json
pkgInfo = mip.utils.read_package_json(pkgDir);

% Determine compile script and working directory
compileScript = '';
compileDir = '';

if isfield(pkgInfo, 'compile_script') && ~isempty(pkgInfo.compile_script)
    % compile_script stored in mip.json (editable installs)
    compileScript = pkgInfo.compile_script;
    if isfield(pkgInfo, 'source_path') && ~isempty(pkgInfo.source_path)
        compileDir = pkgInfo.source_path;
    else
        compileDir = pkgDir;
    end
else
    % Try reading compile_script from mip.yaml in source or package dir
    yamlSearchDir = pkgDir;
    if isfield(pkgInfo, 'source_path') && ~isempty(pkgInfo.source_path) ...
            && isfolder(pkgInfo.source_path)
        yamlSearchDir = pkgInfo.source_path;
    end

    mipYamlPath = fullfile(yamlSearchDir, 'mip.yaml');
    if isfile(mipYamlPath)
        mipConfig = mip.utils.read_mip_yaml(yamlSearchDir);
        [buildEntry, ~] = mip.build.match_build(mipConfig);
        resolvedConfig = mip.build.resolve_build_config(mipConfig, buildEntry);
        if isfield(resolvedConfig, 'compile_script') && ~isempty(resolvedConfig.compile_script)
            compileScript = resolvedConfig.compile_script;
        end
    end

    % Non-editable installs compile in the package subdirectory
    % (prepare_package copies source into pkgDir/<package_name>/)
    compileDir = fullfile(pkgDir, pkgInfo.name);
end

if isempty(compileScript)
    error('mip:compile:noCompileScript', ...
          'Package "%s" does not have a compile script defined.', fqn);
end

if ~isfolder(compileDir)
    error('mip:compile:sourceMissing', ...
          'Compile directory "%s" does not exist.', compileDir);
end

fprintf('Compiling "%s"...\n', fqn);
mip.build.run_compile(compileDir, compileScript);

end

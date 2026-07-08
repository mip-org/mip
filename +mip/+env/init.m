function init(varargin)
%INIT   Create a new project environment (mipenv.yaml + .mip root).
%
% Usage:
%   mip env init
%   mip env init --directory <dir>
%   mip env init --name <name>
%
% Options:
%   --directory <dir>  Project directory to initialize (default: current).
%   --name <name>      Project name recorded in mipenv.yaml (default: the
%                      project directory's basename).
%
% Creates an empty mipenv.yaml (the hand-authored dependency spec) and the
% project-local install root at <dir>/.mip. Does nothing if a mipenv.yaml
% already exists.

    [opts, positionals] = mip.parse.flags(varargin, ...
        struct('directory', '', 'name', ''));
    if ~isempty(positionals)
        error('mip:env:unexpectedArg', ...
              'Unexpected argument: %s', positionals{1});
    end

    projectDir = mip.env.project_dir(opts.directory);
    specFile = mip.env.spec_path(projectDir);
    if exist(specFile, 'file')
        fprintf('mipenv.yaml already exists at %s. Nothing to do.\n', specFile);
        return
    end

    name = opts.name;
    if isempty(name)
        normalized = regexprep(projectDir, '[/\\]+$', '');
        [~, base, ext] = fileparts(normalized);
        name = [base, ext];
    end

    spec = struct('name', name, 'dependencies', {{}}, 'channels', {{}});
    mip.env.write_spec(projectDir, spec);
    mip.env.env_root(projectDir, true);

    fprintf('Created %s\n', specFile);
    fprintf('Created %s\n', mip.env.env_root(projectDir));
    fprintf('\nNext steps:\n');
    fprintf('  - Add dependencies:  mip env add <package>\n');
    fprintf('  - Or edit %s, then: mip env sync\n', specFile);
end

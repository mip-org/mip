function init(varargin)
%INIT   Initialize a new mip package by generating a mip.yaml.
%
% Usage:
%   mip init [<path>]
%   mip init [<path>] [--name <package>] [--repository <url>]
%   mip init [<path>] -g                - Also prepare to host on GitHub as a
%                                         single-package repository
%
% Generates a mip.yaml in the given directory (defaults to the current
% directory if no path is provided). The package name defaults to the
% directory's basename and can be overridden with --name. Optional
% string fields (description, version, license, homepage, repository)
% are emitted blank for the user to fill in (--repository fills in that
% field instead of leaving it blank). The list of paths is determined
% automatically by walking the directory and identifying folders that
% contain runtime MATLAB code.
%
% If the target directory contains a .git/config with a remote URL, the
% repo name (derived from the URL) is used as the default package name
% in place of the directory basename, and the URL is filled into the
% `repository` field. Both are still overridable via --name and
% --repository.
%
% A blank `test_<name>.m` script is created (if not already present) and
% referenced from the generated mip.yaml's `test_script` field.
%
% If the target directory already contains a mip.yaml, init prints a
% message and exits without modifying anything.
%
% With -g (--github), init also writes .github/workflows/repo-build.yml, a
% workflow that builds and publishes the package from its own GitHub
% repository on each pushed tag v* (and each push to main) by calling the
% reusable workflow repo-build.yml in mip-org/mip_channel_tools. Users then
% install it with "mip install <owner>/<repo>". -g can be given together
% with a first init, or on its own in a directory that already has a
% mip.yaml; an existing workflow file is replaced, so running it again
% updates the workflow. Plain init does not write the workflow, since a
% package may not be hosted on GitHub, or may be built by a channel that
% includes it, in which case a workflow in the package repository would
% publish a second, unintended set of releases.

    [opts, positionals] = mip.parse.flags(varargin, ...
        struct('name', '', 'repository', '', 'github', false), ...
        struct('g', 'github'));
    repository = opts.repository;

    if length(positionals) > 1
        error('mip:init:unexpectedArg', 'Unexpected argument: %s', positionals{2});
    end
    if isempty(positionals)
        targetPath = '.';
    else
        targetPath = positionals{1};
    end

    targetDir = mip.paths.get_absolute_path(targetPath);
    if exist(targetDir, 'dir') ~= 7
        error('mip:init:notADirectory', ...
              '"%s" is not a directory.', targetDir);
    end

    mipYamlPath = fullfile(targetDir, 'mip.yaml');
    [gitRepoName, gitRepoUrl] = mip.init.git_info(targetDir);
    if exist(mipYamlPath, 'file')
        if opts.github
            mipConfig = mip.config.read_mip_yaml(targetDir);
            write_github_workflow(targetDir, mipConfig.name, gitRepoName);
        else
            fprintf('mip.yaml already exists at %s. Nothing to do.\n', mipYamlPath);
        end
        return;
    end

    if ~isempty(opts.name)
        pkgName = opts.name;
    elseif ~isempty(gitRepoName)
        % Lowercase the git repo name to produce a canonical name. Other
        % non-canonical characters (dots, spaces) still cause a failure
        % below — use --name for those.
        pkgName = lower(gitRepoName);
    else
        normalizedDir = regexprep(targetDir, '[/\\]+$', '');
        [~, baseName, ext] = fileparts(normalizedDir);
        % Lowercase the directory basename to produce a canonical name.
        % Other non-canonical characters (dots, spaces, leading/trailing
        % separators) still cause a failure below — use --name for those.
        pkgName = lower([baseName, ext]);
    end

    if isempty(repository) && ~isempty(gitRepoUrl)
        repository = gitRepoUrl;
    end

    if ~mip.name.is_valid_canonical(pkgName)
        error('mip:init:invalidName', ...
              ['"%s" is not a valid canonical package name. Canonical names ' ...
               'must consist of lowercase letters, digits, hyphens, and ' ...
               'underscores, and must start and end with a letter or digit. ' ...
               'Use --name to override.'], pkgName);
    end

    % Discover paths before creating the test script so the new file
    % doesn't cause the root to be auto-included.
    [pathsList, extraPaths] = mip.init.auto_add_paths(targetDir);

    testScript = sprintf('test_%s.m', pkgName);
    testScriptPath = fullfile(targetDir, testScript);
    if ~exist(testScriptPath, 'file')
        fid = fopen(testScriptPath, 'w');
        if fid == -1
            error('mip:init:writeFailed', ...
                  'Could not create test script: %s', testScriptPath);
        end
        fclose(fid);
    end

    write_mip_yaml(mipYamlPath, pkgName, pathsList, extraPaths, testScript, repository);

    fprintf('Created %s\n', mipYamlPath);
    fprintf('Created %s\n', testScriptPath);
    if opts.github
        write_github_workflow(targetDir, pkgName, gitRepoName);
    end
    fprintf('\nNext steps:\n');
    fprintf('  - Edit %s to fill in description, version, license, etc.\n', mipYamlPath);
    fprintf('  - Add tests to %s\n', testScript);
end


function write_github_workflow(targetDir, pkgName, gitRepoName)
% Write .github/workflows/repo-build.yml, which publishes the package from its
% own GitHub repository (see "mip init -g" above).
    workflowDir = fullfile(targetDir, '.github', 'workflows');
    if ~isfolder(workflowDir)
        mkdir(workflowDir);
    end
    workflowPath = fullfile(workflowDir, 'repo-build.yml');
    existed = isfile(workflowPath);

    lines = { ...
        'name: mip'
        'on:'
        '  push:'
        '    tags: [''v*'']'
        '    branches: [main]      # optional: publish a rolling "main" build'
        '  workflow_dispatch:'
        'permissions:'
        '  contents: write'
        'jobs:'
        '  mip:'
        '    uses: mip-org/mip_channel_tools/.github/workflows/repo-build.yml@main'
        };
    fid = fopen(workflowPath, 'w');
    if fid == -1
        error('mip:init:writeFailed', ...
              'Could not open %s for writing.', workflowPath);
    end
    fprintf(fid, '%s\n', lines{:});
    fclose(fid);

    if existed
        fprintf('Updated %s\n', workflowPath);
    else
        fprintf('Created %s\n', workflowPath);
    end
    fprintf(['Pushing a tag such as v1.0.0 to GitHub builds and publishes the ' ...
             'package; users install it with "mip install <owner>/<repo>". ' ...
             'The repository must be public.\n']);
    if ~isempty(gitRepoName) && ~mip.name.match(gitRepoName, pkgName)
        warning('mip:init:nameMismatch', ...
                ['The package name "%s" differs from the repository name "%s". ' ...
                 'A package published from its own repository must have the ' ...
                 'same name as the repository.'], pkgName, gitRepoName);
    end
end


function write_mip_yaml(yamlPath, pkgName, pathsList, extraPaths, testScript, repository)
    fid = fopen(yamlPath, 'w');
    if fid == -1
        error('mip:init:writeFailed', ...
              'Could not open %s for writing.', yamlPath);
    end
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, 'name: %s\n', pkgName);
    fprintf(fid, 'description: ""\n');
    fprintf(fid, 'version: ""\n');
    fprintf(fid, 'license: ""\n');
    fprintf(fid, 'homepage: ""\n');
    fprintf(fid, 'repository: "%s"\n', repository);
    fprintf(fid, 'dependencies: []\n');
    fprintf(fid, '\n');

    if isempty(pathsList)
        fprintf(fid, 'paths: []\n');
    else
        fprintf(fid, 'paths:\n');
        for k = 1:numel(pathsList)
            fprintf(fid, '  - path: "%s"\n', pathsList{k});
        end
    end
    fprintf(fid, '\n');

    if ~isempty(fieldnames(extraPaths))
        fprintf(fid, 'extra_paths:\n');
        for g = fieldnames(extraPaths)'
            fprintf(fid, '  %s:\n', g{1});
            for k = 1:numel(extraPaths.(g{1}))
                fprintf(fid, '    - path: "%s"\n', extraPaths.(g{1}){k});
            end
        end
        fprintf(fid, '\n');
    end

    fprintf(fid, 'test_script: %s\n', testScript);
    fprintf(fid, '\n');

    fprintf(fid, 'builds:\n');
    fprintf(fid, '  - architectures: [any]\n');
end

function init(varargin)
%INIT   Initialize a new mip package by generating a mip.yaml.
%
% Usage:
%   mip init [<path>]
%   mip init [<path>] [--name <packagename>] [--repository <url>]
%
% Generates a mip.yaml in the given directory (defaults to the current
% directory if no path is provided). The package name defaults to the
% directory's basename and can be overridden with --name. Optional
% string fields (description, version, license, homepage, repository)
% are emitted blank for the user to fill in (--repository fills in that
% field instead of leaving it blank). The list of addpaths is determined
% automatically by walking the directory and identifying folders that
% contain runtime MATLAB code.
%
% A blank `test_<name>.m` script is created (if not already present) and
% referenced from the generated mip.yaml's `test_script` field.
%
% If the target directory already contains a mip.yaml, init prints a
% message and exits without modifying anything.

    targetPath = '';
    overrideName = '';
    repository = '';

    i = 1;
    while i <= numel(varargin)
        arg = varargin{i};
        if ischar(arg) && strcmp(arg, '--name')
            if i + 1 > numel(varargin)
                error('mip:init:missingNameValue', '--name requires a value.');
            end
            overrideName = varargin{i + 1};
            i = i + 2;
        elseif ischar(arg) && strcmp(arg, '--repository')
            if i + 1 > numel(varargin)
                error('mip:init:missingRepositoryValue', ...
                      '--repository requires a value.');
            end
            repository = varargin{i + 1};
            i = i + 2;
        elseif isempty(targetPath)
            targetPath = arg;
            i = i + 1;
        else
            error('mip:init:unexpectedArg', 'Unexpected argument: %s', arg);
        end
    end

    if isempty(targetPath)
        targetPath = '.';
    end

    targetDir = mip.paths.get_absolute_path(targetPath);
    if exist(targetDir, 'dir') ~= 7
        error('mip:init:notADirectory', ...
              '"%s" is not a directory.', targetDir);
    end

    mipYamlPath = fullfile(targetDir, 'mip.yaml');
    if exist(mipYamlPath, 'file')
        fprintf('mip.yaml already exists at %s. Nothing to do.\n', mipYamlPath);
        return;
    end

    if ~isempty(overrideName)
        pkgName = overrideName;
    else
        normalizedDir = regexprep(targetDir, '[/\\]+$', '');
        [~, baseName, ext] = fileparts(normalizedDir);
        % Lowercase the directory basename to produce a canonical name.
        % Other non-canonical characters (dots, spaces, leading/trailing
        % separators) still cause a failure below — use --name for those.
        pkgName = lower([baseName, ext]);
    end

    if ~mip.name.is_valid_canonical(pkgName)
        error('mip:init:invalidName', ...
              ['"%s" is not a valid canonical package name. Canonical names ' ...
               'must consist of lowercase letters, digits, hyphens, and ' ...
               'underscores, and must start and end with a letter or digit. ' ...
               'Use --name to override.'], pkgName);
    end

    % Discover addpaths before creating the test script so the new file
    % doesn't cause the root to be auto-included.
    addpaths = mip.init.auto_add_paths(targetDir);

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

    write_mip_yaml(mipYamlPath, pkgName, addpaths, testScript, repository);

    fprintf('Created %s\n', mipYamlPath);
    fprintf('Created %s\n', testScriptPath);
    fprintf('\nNext steps:\n');
    fprintf('  - Edit %s to fill in description, version, license, etc.\n', mipYamlPath);
    fprintf('  - Add tests to %s\n', testScript);
end


function write_mip_yaml(yamlPath, pkgName, addpaths, testScript, repository)
    fid = fopen(yamlPath, 'w');
    if fid == -1
        error('mip:init:writeFailed', ...
              'Could not open %s for writing.', yamlPath);
    end
    cleaner = onCleanup(@() fclose(fid));

    fprintf(fid, 'name: %s\n', pkgName);
    fprintf(fid, 'description: ""\n');
    fprintf(fid, 'version: "unknown"\n');
    fprintf(fid, 'license: ""\n');
    fprintf(fid, 'homepage: ""\n');
    fprintf(fid, 'repository: "%s"\n', repository);
    fprintf(fid, 'dependencies: []\n');
    fprintf(fid, '\n');

    if isempty(addpaths)
        fprintf(fid, 'addpaths: []\n');
    else
        fprintf(fid, 'addpaths:\n');
        for k = 1:numel(addpaths)
            fprintf(fid, '  - path: "%s"\n', addpaths{k});
        end
    end
    fprintf(fid, '\n');

    fprintf(fid, 'test_script: %s\n', testScript);
    fprintf(fid, '\n');

    fprintf(fid, 'builds:\n');
    fprintf(fid, '  - architectures: [any]\n');
end

function result = parse_package_arg(arg)
%PARSE_PACKAGE_ARG   Parse a package argument into its components.
%
% Handles bare names, fully qualified names (variable-length), and an
% optional @version suffix.
%
% The canonical internal FQN shapes are:
%   gh/<owner>/<channel>/<name>   - GitHub channel package
%   gh/<owner>/<repo>             - Package published from its own GitHub
%                                   repository (the package name equals
%                                   the repository name)
%   local/<name>                  - Local directory / editable install
%   fex/<name>                    - File Exchange URL install
%   web/<name>                    - Generic remote .zip URL install
%   mhl/<name>                    - .mhl install with no --channel given
%
% On input, the 'gh/' prefix may be omitted for channel packages: a 3-part
% '<owner>/<channel>/<name>' input is treated as 'gh/<owner>/<channel>/<name>'.
% A 2-part '<owner>/<name>' input, when '<owner>' is not a reserved
% source-type prefix, refers to the repository github.com/<owner>/<name>
% (FQN 'gh/<owner>/<name>'). Because this form used to mean the package
% <name> in the personal channel <owner>/<owner>, the personal-channel FQN
% is returned in .fallback_fqn; callers that install fall back to it when
% the repository publishes no mip package, and callers that act on
% installed packages use it when the repository package is not installed
% (see mip.resolve.installed_fqn). The URL forms
% 'https://github.com/<owner>/<repo>' and 'github.com/<owner>/<repo>'
% (optionally ending in '/' or '.git') also refer to the repository, with
% no fallback. Non-gh source types must be written explicitly
% ('local/<name>', 'fex/<name>', 'mhl/<name>', etc.).
%
% Args:
%   arg - Package string. One of:
%           '<name>'                         (bare name)
%           '<name>@<version>'               (bare name with version)
%           '<category>/<name>'              (2-part non-gh FQN, e.g. 'local/foo')
%           '<owner>/<repo>'                 (repository, with personal-channel
%                                             fallback 'gh/<owner>/<owner>/<repo>')
%           'gh/<owner>/<repo>'              (repository, explicit)
%           'https://github.com/<owner>/<repo>' or 'github.com/<owner>/<repo>'
%                                            (repository, URL form)
%           '<owner>/<channel>/<name>'       (3-part, implicit gh/)
%           'gh/<owner>/<channel>/<name>'    (4-part, explicit gh/)
%         Any of the FQN forms may include an @version suffix on the last
%         component.
%
% Returns:
%   result - Struct with fields:
%     .name         - Package name (always set)
%     .type         - Source type: 'gh', or the top-level category for non-gh
%                     FQNs (e.g. 'local', 'fex'). Empty for bare names.
%     .owner        - GitHub owner (set for type='gh', empty otherwise)
%     .channel      - Channel name (set for gh channel packages; empty for
%                     repository packages and non-gh FQNs)
%     .is_repo      - True for a repository package ('gh/<owner>/<repo>')
%     .fallback_fqn - Personal-channel FQN 'gh/<owner>/<owner>/<name>' for
%                     the 2-part '<owner>/<name>' form, '' otherwise
%     .fqn          - Canonical internal FQN (empty for bare names)
%     .is_fqn       - True if any FQN form was given
%     .version      - Requested version (empty string if not specified)
%
% Examples:
%   parse_package_arg('chebfun')
%     -> name='chebfun', type='', is_fqn=false
%
%   parse_package_arg('mip-org/core/chebfun')
%     -> name='chebfun', type='gh', owner='mip-org', channel='core',
%        fqn='gh/mip-org/core/chebfun', is_fqn=true
%
%   parse_package_arg('gh/mip-org/core/chebfun')
%     -> same as above (explicit form)
%
%   parse_package_arg('fastalgorithms/chunkie')
%     -> name='chunkie', type='gh', owner='fastalgorithms', channel='',
%        is_repo=true, fqn='gh/fastalgorithms/chunkie',
%        fallback_fqn='gh/fastalgorithms/fastalgorithms/chunkie'
%
%   parse_package_arg('https://github.com/fastalgorithms/chunkie@1.2.0')
%     -> same as above, with fallback_fqn='' and version='1.2.0'
%
%   parse_package_arg('local/mypkg')
%     -> name='mypkg', type='local', owner='', channel='',
%        fqn='local/mypkg', is_fqn=true
%
%   parse_package_arg('fex/some_pkg@1.0')
%     -> name='some_pkg', type='fex', fqn='fex/some_pkg', version='1.0'

reservedTypes = mip.parse.reserved_types();

% Extract @version suffix if present
atIdx = strfind(arg, '@');
if ~isempty(atIdx)
    lastAt = atIdx(end);
    requestedVersion = arg(lastAt+1:end);
    arg = arg(1:lastAt-1);
else
    requestedVersion = '';
end

result.name = '';
result.type = '';
result.owner = '';
result.channel = '';
result.is_repo = false;
result.fallback_fqn = '';
result.fqn = '';
result.is_fqn = false;

% Repository URL forms: 'https://github.com/<owner>/<repo>' and
% 'github.com/<owner>/<repo>', with an optional trailing '/' or '.git'.
repoPath = mip.parse.repo_url_path(arg);
if ~isempty(repoPath)
    parts = strsplit(repoPath, '/');
    result = setRepo(result, parts{1}, parts{2});
    result.version = requestedVersion;
    validateParts(result, arg);
    return
end

parts = strsplit(arg, '/');

switch length(parts)
    case 1
        result.name = parts{1};
    case 2
        if strcmp(parts{1}, 'gh')
            error('mip:invalidPackageSpec', ...
                  ['Invalid package spec "%s". A gh FQN must have the form ' ...
                   '"gh/<owner>/<repo>" or "gh/<owner>/<channel>/<name>".'], arg);
        end
        if ismember(parts{1}, reservedTypes)
            % Non-gh source-type FQN (local, fex, web, mhl).
            result.type = parts{1};
            result.name = parts{2};
            result.fqn = [result.type '/' result.name];
            result.is_fqn = true;
        else
            % '<owner>/<name>' refers to the repository github.com/<owner>/<name>,
            % with the personal channel <owner>/<owner> as the fallback.
            result = setRepo(result, parts{1}, parts{2});
            result.fallback_fqn = ['gh/' parts{1} '/' parts{1} '/' parts{2}];
        end
    case 3
        if strcmp(parts{1}, 'gh')
            % Explicit repository FQN 'gh/<owner>/<repo>'.
            result = setRepo(result, parts{2}, parts{3});
        else
            result.type = 'gh';
            result.owner = parts{1};
            result.channel = parts{2};
            result.name = parts{3};
            result.fqn = ['gh/' result.owner '/' result.channel '/' result.name];
            result.is_fqn = true;
        end
    case 4
        if ~strcmp(parts{1}, 'gh')
            error('mip:invalidPackageSpec', ...
                  ['Invalid package spec "%s". A 4-part FQN must start with ' ...
                   '"gh/" (the GitHub source-type prefix).'], arg);
        end
        result.type = 'gh';
        result.owner = parts{2};
        result.channel = parts{3};
        result.name = parts{4};
        result.fqn = arg;
        result.is_fqn = true;
    otherwise
        error('mip:invalidPackageSpec', ...
              ['Invalid package spec "%s". Use "<name>[@<version>]", ' ...
               '"<category>/<name>[@<version>]", "<owner>/<repo>[@<version>]", ' ...
               '"<owner>/<channel>/<name>[@<version>]", ' ...
               'or "gh/<owner>/<channel>/<name>[@<version>]".'], arg);
end

validateParts(result, arg);

result.version = requestedVersion;

end

function result = setRepo(result, owner, repo)
result.type = 'gh';
result.owner = owner;
result.channel = '';
result.name = repo;
result.is_repo = true;
result.fqn = ['gh/' owner '/' repo];
result.is_fqn = true;
end

function validateParts(result, arg)
% Validate each component: letters, digits, hyphens, underscores; must
% start and end with a letter or digit. Mixed case is accepted — lookup
% is case-insensitive and hyphens/underscores are interchangeable in
% user input (see mip.name.normalize). The canonical form written to
% disk / mip.yaml is stricter (lowercase) and is enforced separately by
% mip.name.is_valid_canonical.
allParts = {result.name, result.type, result.owner, result.channel};
for k = 1:length(allParts)
    if ~isempty(allParts{k}) && ~mip.name.is_valid(allParts{k})
        error('mip:invalidPackageSpec', ...
              'Invalid package spec "%s".', arg);
    end
end

end

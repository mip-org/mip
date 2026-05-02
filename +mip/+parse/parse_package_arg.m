function result = parse_package_arg(arg)
%PARSE_PACKAGE_ARG   Parse a package argument into its components.
%
% Handles bare names, fully qualified names (variable-length), and an
% optional @version suffix.
%
% The canonical internal FQN shapes are:
%   gh/<owner>/<channel>/<name>   - GitHub channel package
%   local/<name>                  - Local directory / editable install
%   fex/<name>                    - File Exchange / --url zip install
%   web/<name>                    - Generic remote .zip / --url install
%   mhl/<name>                    - .mhl install with no --channel given
%
% On input, the 'gh/' prefix may be omitted: a 3-part 'owner/channel/name'
% input is treated as 'gh/owner/channel/name'. Non-gh source types must be
% written explicitly ('local/<name>', 'fex/<name>', 'mhl/<name>', etc.).
%
% Args:
%   arg - Package string. One of:
%           'name'                           (bare name)
%           'name@version'                   (bare name with version)
%           'category/name'                  (2-part non-gh FQN, e.g. 'local/foo')
%           'owner/channel/name'             (3-part, implicit gh/)
%           'gh/owner/channel/name'          (4-part, explicit gh/)
%         Any of the FQN forms may include an @version suffix on the last
%         component.
%
% Returns:
%   result - Struct with fields:
%     .name    - Package name (always set)
%     .type    - Source type: 'gh', or the top-level category for non-gh
%                FQNs (e.g. 'local', 'fex'). Empty for bare names.
%     .owner   - GitHub repo owner (set for type='gh', empty otherwise)
%     .channel - Channel name (set for type='gh', empty otherwise)
%     .fqn     - Canonical internal FQN (empty for bare names)
%     .is_fqn  - True if any FQN form was given
%     .version - Requested version (empty string if not specified)
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
%   parse_package_arg('local/mypkg')
%     -> name='mypkg', type='local', owner='', channel='',
%        fqn='local/mypkg', is_fqn=true
%
%   parse_package_arg('fex/some_pkg@1.0')
%     -> name='some_pkg', type='fex', fqn='fex/some_pkg', version='1.0'

% Extract @version suffix if present
atIdx = strfind(arg, '@');
if ~isempty(atIdx)
    lastAt = atIdx(end);
    requestedVersion = arg(lastAt+1:end);
    arg = arg(1:lastAt-1);
else
    requestedVersion = '';
end

parts = strsplit(arg, '/');

result.name = '';
result.type = '';
result.owner = '';
result.channel = '';
result.fqn = '';
result.is_fqn = false;

switch length(parts)
    case 1
        result.name = parts{1};
    case 2
        if strcmp(parts{1}, 'gh')
            error('mip:invalidPackageSpec', ...
                  ['Invalid package spec "%s". A gh FQN must have the form ' ...
                   '"gh/<owner>/<channel>/<name>" (or the 3-part shorthand ' ...
                   '"<owner>/<channel>/<name>").'], arg);
        end
        result.type = parts{1};
        result.name = parts{2};
        result.fqn = [result.type '/' result.name];
        result.is_fqn = true;
    case 3
        result.type = 'gh';
        result.owner = parts{1};
        result.channel = parts{2};
        result.name = parts{3};
        result.fqn = ['gh/' result.owner '/' result.channel '/' result.name];
        result.is_fqn = true;
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
              ['Invalid package spec "%s". Use "name[@version]", ' ...
               '"category/name[@version]", "owner/channel/name[@version]", ' ...
               'or "gh/owner/channel/name[@version]".'], arg);
end

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

result.version = requestedVersion;

end

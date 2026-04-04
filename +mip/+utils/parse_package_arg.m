function result = parse_package_arg(arg)
%PARSE_PACKAGE_ARG   Parse a package argument into its components.
%
% Handles bare names, fully qualified names, and optional @version suffix.
%
% Args:
%   arg - Package string: 'package_name', 'package@version',
%         'org/channel/package', or 'org/channel/package@version'
%
% Returns:
%   result - Struct with fields:
%     .name    - Package name (always set)
%     .org     - Organization (empty if bare name)
%     .channel - Channel name (empty if bare name)
%     .is_fqn  - True if fully qualified
%     .version - Requested version (empty string if not specified)
%
% Examples:
%   r = parse_package_arg('chebfun')
%     -> name='chebfun', org='', channel='', is_fqn=false, version=''
%
%   r = parse_package_arg('chebfun@1.2.0')
%     -> name='chebfun', org='', channel='', is_fqn=false, version='1.2.0'
%
%   r = parse_package_arg('mip-org/core/chebfun')
%     -> name='chebfun', org='mip-org', channel='core', is_fqn=true, version=''
%
%   r = parse_package_arg('mip-org/core/mip@main')
%     -> name='mip', org='mip-org', channel='core', is_fqn=true, version='main'

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

if length(parts) == 1
    result.name = parts{1};
    result.org = '';
    result.channel = '';
    result.is_fqn = false;
elseif length(parts) == 3
    result.org = parts{1};
    result.channel = parts{2};
    result.name = parts{3};
    result.is_fqn = true;
else
    error('mip:invalidPackageSpec', ...
          'Invalid package spec "%s". Use "package[@version]" or "org/channel/package[@version]".', arg);
end

% Validate components: alphanumeric, hyphens, underscores, periods.
% Reject '.' and '..' which are reserved filesystem names.
validName = @(s) ~isempty(regexp(s, '^[-a-zA-Z0-9_.]+$', 'once')) && ...
                  ~strcmp(s, '.') && ~strcmp(s, '..');
allParts = {result.name, result.org, result.channel};
for k = 1:length(allParts)
    if ~isempty(allParts{k}) && ~validName(allParts{k})
        error('mip:invalidPackageSpec', ...
              'Invalid package spec "%s".', arg);
    end
end

result.version = requestedVersion;

end

function msg = mip_update_message(index, installedVersion)
%MIP_UPDATE_MESSAGE   Compose the mip self-update notice for a channel index.
%
% Args:
%   index            - Parsed index struct (from fetch_index)
%   installedVersion - Version string of the running mip installation
%
% Returns:
%   msg - Notice text suggesting "mip update mip", or '' when no notice
%         applies.
%
% Two checks are performed, in priority order:
%
%   1. If the index carries a numeric top-level min_mip_version field and
%      the installed version is below it, the notice states that an update
%      is REQUIRED by the channel.
%   2. Otherwise, if the latest numeric version of the "mip" package
%      published in the index is greater than the installed version, the
%      notice suggests updating.
%
% No notice is produced when the installed version is non-numeric (e.g. a
% branch like 'main', or 'unspecified' from a source checkout): there is
% no meaningful ordering against numeric releases.

msg = '';

if isstring(installedVersion) && isscalar(installedVersion)
    installedVersion = char(installedVersion);
end
if ~ischar(installedVersion) || isempty(installedVersion) || ...
        ~mip.resolve.is_numeric_version(installedVersion)
    return
end

minRequired = read_min_mip_version(index);
if ~isempty(minRequired) && ...
        mip.resolve.compare_versions(installedVersion, minRequired) < 0
    msg = sprintf(['This channel requires mip %s or newer (installed: %s). ' ...
                   'An update is required: run "mip update mip".'], ...
                  minRequired, installedVersion);
    return
end

latest = latest_numeric_mip_version(index);
if ~isempty(latest) && ...
        mip.resolve.compare_versions(latest, installedVersion) > 0
    msg = sprintf(['A newer version of mip is available (%s; installed: %s). ' ...
                   'Run "mip update mip" to update.'], ...
                  latest, installedVersion);
end

end


function minRequired = read_min_mip_version(index)
% Optional top-level index field. Ignored unless it is a numeric version.
minRequired = '';
if ~isstruct(index) || ~isfield(index, 'min_mip_version')
    return
end
v = index.min_mip_version;
if isstring(v) && isscalar(v)
    v = char(v);
end
if ischar(v) && ~isempty(v) && mip.resolve.is_numeric_version(v)
    minRequired = v;
end
end


function latest = latest_numeric_mip_version(index)
% Highest numeric version among index entries named "mip" (name
% equivalence, see mip.name.match). Non-numeric versions (e.g. a branch
% release like 'main') are ignored.
latest = '';
if ~isstruct(index) || ~isfield(index, 'packages')
    return
end
packages = index.packages;
if ~iscell(packages)
    packages = num2cell(packages);
end
for i = 1:length(packages)
    pkg = packages{i};
    if ~isstruct(pkg) || ~isfield(pkg, 'name') || ~isfield(pkg, 'version')
        continue
    end
    if ~ischar(pkg.name) && ~(isstring(pkg.name) && isscalar(pkg.name))
        continue
    end
    if ~mip.name.match(pkg.name, 'mip')
        continue
    end
    v = pkg.version;
    if isstring(v) && isscalar(v)
        v = char(v);
    end
    if ~ischar(v) || isempty(v) || ~mip.resolve.is_numeric_version(v)
        continue
    end
    if isempty(latest) || mip.resolve.compare_versions(v, latest) > 0
        latest = v;
    end
end
end

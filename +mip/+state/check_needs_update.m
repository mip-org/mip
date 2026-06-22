function tf = check_needs_update(installedInfo, latestInfo)
%CHECK_NEEDS_UPDATE   Compare installed vs latest version and build timestamp.
%
% Returns true if the latest version differs from installed, or if the
% versions match but the channel's build timestamp differs.
%
% The build timestamp (ISO 8601 UTC, written by mip.build.create_mip_json)
% is used rather than the commit hash so that a fresh build of the same
% version -- e.g. a branch like "main" -- is detected as an update.

    installedVersion = installedInfo.version;
    latestVersion = latestInfo.version;

    if ~strcmp(installedVersion, latestVersion)
        tf = true;
        return
    end

    installedTimestamp = '';
    if isfield(installedInfo, 'timestamp')
        installedTimestamp = installedInfo.timestamp;
    end
    latestTimestamp = '';
    if isfield(latestInfo, 'timestamp')
        latestTimestamp = latestInfo.timestamp;
    end

    % Update whenever the channel reports a different build timestamp. If
    % the channel entry has no timestamp (e.g. a legacy release), there is
    % nothing to compare against and the package is left as-is.
    tf = ~isempty(latestTimestamp) && ~strcmp(installedTimestamp, latestTimestamp);
end

function check_mip_update(index, installedVersion)
%CHECK_MIP_UPDATE   Print a notice when the core channel offers a newer mip.
%
% Args:
%   index            - Parsed index struct (from fetch_index)
%   installedVersion - Optional. Version string of the running mip; defaults
%                      to mip.version(). Exposed as an argument for testing.
%
% Called by mip.channel.fetch_index whenever the mip-org/core index is
% loaded (from cache or network). Composes the notice via
% mip.channel.mip_update_message and prints it. Each distinct notice is
% printed at most once per mip command: the printed text is remembered in
% the MIP_UPDATE_NOTICE_SHOWN state key, which mip.m clears at dispatch, so
% repeated index loads within a single command do not repeat the notice.
%
% Best-effort: never raises, so the notice can never break the command in
% progress.

try
    if nargin < 2 || isempty(installedVersion)
        installedVersion = mip.version();
    end
    msg = mip.channel.mip_update_message(index, installedVersion);
    if isempty(msg)
        return
    end
    shown = mip.state.key_value_get('MIP_UPDATE_NOTICE_SHOWN');
    if ischar(shown) && strcmp(shown, msg)
        return
    end
    mip.state.key_value_set('MIP_UPDATE_NOTICE_SHOWN', msg);
    fprintf('%s\n', msg);
catch
    % The update notice is advisory only; ignore any failure.
end

end

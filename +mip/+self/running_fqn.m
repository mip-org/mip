function fqn = running_fqn()
%RUNNING_FQN   FQN of the installed package the running mip code belongs to.
%
% Usage:
%   fqn = mip.self.running_fqn()
%
% Returns the FQN of the installed copy of mip that this code is running
% from, derived from this file's location:
%   <root>/packages/gh/<owner>/<channel>/<name>/<src>/+mip/+self/running_fqn.m
%   <root>/packages/<type>/<name>/<src>/+mip/+self/running_fqn.m
% Returns '' when the running copy is not an installed package (a source
% checkout, or an editable install whose source lives outside packages/).
%
% Used to protect the running copy from being unloaded implicitly (see
% mip.unload --all): a session may be running mip from a copy other than
% gh/mip-org/core/mip, e.g. a preview build loaded with
% `mip load mip-org/labs/mip`.
%
% Tests may override the result via the MIP_SELF_FQN appdata key (see
% tests/helpers/clearMipState.m), since the running copy under test is a
% source checkout.

override = getappdata(0, 'MIP_SELF_FQN');
if ~isempty(override) && ischar(override)
    fqn = override;
    return
end

fqn = '';

self_dir   = fileparts(mfilename('fullpath')); % .../+self
mip_dir    = fileparts(self_dir);              % .../+mip
source_dir = fileparts(mip_dir);               % .../<src>
pkg_dir    = fileparts(source_dir);            % .../<name>
d4         = fileparts(pkg_dir);               % channel dir (gh) or type dir (non-gh)
d5         = fileparts(d4);                    % owner dir (gh) or packages dir (non-gh)
d6         = fileparts(d5);                    % gh dir (gh)
d7         = fileparts(d6);                    % packages dir (gh)

[~, name]    = fileparts(pkg_dir);
[~, d4name]  = fileparts(d4);
[~, d5name]  = fileparts(d5);
[~, d6name]  = fileparts(d6);
[~, d7name]  = fileparts(d7);

if strcmp(d7name, 'packages') && strcmp(d6name, 'gh')
    % <root>/packages/gh/<owner>/<channel>/<name>/<src>/+mip/+self
    fqn = ['gh/' d5name '/' d4name '/' name];
elseif strcmp(d5name, 'packages') && ismember(d4name, mip.parse.reserved_types())
    % <root>/packages/<type>/<name>/<src>/+mip/+self
    fqn = [d4name '/' name];
end

end

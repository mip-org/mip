function tf = is_active_root()
%IS_ACTIVE_ROOT   Check whether the active root is the running mip's own root.
%
% Usage:
%   tf = mip.self.is_active_root()
%
% The self- flows (self-uninstall in mip.uninstall, self-update in
% mip.update, the install-time hot swap in mip.install.from_repository)
% tear down or replace the running copy of mip, so they must only trigger
% when the root the session's commands act on is the root the running mip
% code is installed into. In any other root - an activated environment,
% or an external root targeted via MIP_ROOT - gh/mip-org/core/mip is an
% ordinary, inert package that can be installed, updated, and uninstalled
% without affecting the running mip.
%
% Tests run mip from a source checkout, which is not installed into any
% root; they opt into the self- flows by setting the MIP_SELF_ROOT
% appdata key to the root under test (see tests/helpers/clearMipState.m).

runningRoot = getappdata(0, 'MIP_SELF_ROOT');
if isempty(runningRoot) || ~ischar(runningRoot)
    runningRoot = mip.paths.derived_root();
end
if isempty(runningRoot)
    tf = false;
    return
end

tf = mip.paths.is_same(mip.paths.root(), runningRoot);

end

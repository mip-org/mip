function assert_no_mip(packageName, action)
%ASSERT_NO_MIP   Refuse mip packages in environments.
%
% Usage:
%   mip.env.assert_no_mip(packageName, action)
%
% While an environment is active, no package named "mip" (name
% equivalence — core or otherwise) may be installed into or loaded from
% it; raises mip:env:noMip. A no-op when no environment is active or the
% name is not "mip". This restriction may be relaxed later. See
% docs/mip_self_scenarios.md (Scenario 19).
%
% Args:
%   packageName - bare package name to check
%   action      - 'installed into' or 'loaded from' (used in the message)

if isempty(mip.state.get_env_state())
    return
end
if ~mip.name.match(packageName, 'mip')
    return
end

error('mip:env:noMip', ...
      ['No mip package — core or otherwise — may be %s an environment ' ...
       '("%s"). Run "mip deactivate" to work in the base root.'], ...
      action, packageName);

end

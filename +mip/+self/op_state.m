function s = op_state()
%OP_STATE   Classify the session for self operations on the main mip.
%
% Usage:
%   s = mip.self.op_state()
%
% The main mip — the gh/mip-org/core/mip installed in the main (base)
% root — may be updated, uninstalled, or version-switched only from the
% state it was installed in: a plain session on the main root with no
% other mip loaded. This helper classifies the session so the self flows
% (and the self-update notice) can decide whether that precondition
% holds. See docs/mip_self_scenarios.md.
%
% Returns a struct with fields:
%   state    - one of:
%              'ok'         - main root active, main mip running, no other
%                             mip loaded: self operations may proceed.
%              'standalone' - the running mip is not installed in the main
%                             root (a standalone checkout/download, or an
%                             external MIP_ROOT pointing away from the
%                             root mip was bootstrapped into): mip does
%                             not manage its own files here.
%              'env'        - an environment is active: self operations
%                             require "mip deactivate" first.
%              'mip-loaded' - another mip is loaded over the main one:
%                             self operations require unloading it first.
%   blockers - cellstr of loaded package FQNs standing in the way (only
%              populated for state 'mip-loaded').
%
% Precedence: 'standalone' wins over 'env' (deactivating would not make
% the main mip manageable), and 'env' wins over 'mip-loaded'.

s = struct('state', '', 'blockers', {{}});

% Standalone: the base (main) root does not contain the running mip.
baseRoot = '';
try
    baseRoot = mip.paths.root('base');
catch
    % No resolvable base root at all (e.g. a bare checkout with no
    % MIP_ROOT): mip is certainly not installed in one.
end
if isempty(baseRoot) || ~mip.self.is_own_root(baseRoot)
    s.state = 'standalone';
    return
end

if ~isempty(mip.state.get_env_state())
    s.state = 'env';
    return
end

% Another mip loaded: any loaded package named "mip" (name equivalence)
% other than the core identity, plus — defensively — whatever loaded
% package provides the running mip code even if it is not named "mip".
blockers = {};
loaded = mip.state.key_value_get('MIP_LOADED_PACKAGES');
for i = 1:numel(loaded)
    fqn = loaded{i};
    if strcmp(fqn, 'gh/mip-org/core/mip')
        continue
    end
    try
        parsed = mip.parse.parse_package_arg(fqn);
    catch
        continue
    end
    if mip.name.match(parsed.name, 'mip')
        blockers{end+1} = fqn; %#ok<AGROW>
    end
end
runningMip = mip.self.running_mip_fqn();
if ~isempty(runningMip) && ~ismember(runningMip, blockers)
    blockers{end+1} = runningMip;
end

if ~isempty(blockers)
    s.state = 'mip-loaded';
    s.blockers = blockers;
else
    s.state = 'ok';
end

end

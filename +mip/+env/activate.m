function activate(varargin)
%ACTIVATE   Point the session at an environment.
%
% Usage:
%   mip activate <name>            - Activate <baseline root>/envs/<name>
%   mip activate <path>            - Activate the environment at a path
%   mip activate                   - Activate ./.mip in the current directory
%   mip activate ... --load        - Also load the env's directly installed packages
%
% Activation moves the single session-wide root pointer (MIP_ROOT, saved
% and restored by mip deactivate) and swaps the session's load state with
% it: everything loaded — including sticky packages — is unloaded via the
% normal unload machinery, and the session starts cold in the new
% environment. Only the running mip stays: gh/mip-org/core/mip, plus the
% loaded package actually providing the running mip code when that is a
% different one, e.g. a preview build loaded over the released mip (see
% mip.self.running_mip_fqn). Child processes spawned from the session
% inherit the active environment.
%
% Activation is exclusive (one env at a time; activating another env
% deactivates the current one first) and never installs or executes
% package code. By default it is pointer-only: nothing is on the path
% until you "mip load" it. With --load, each of the environment's
% directly installed packages is loaded as a direct load (dependencies
% load transitively), best-effort, ending with a summary.

[opts, args] = mip.parse.flags(varargin, struct('load', false));

if length(args) > 1
    error('mip:env:tooManyArgs', ...
          '"mip activate" takes at most one name or path argument.');
end

% Resolve the target and require it to be an environment before touching
% any session state.
name = '';
if isempty(args)
    target = fullfile(pwd, '.mip');
    createHint = 'mip env create';
else
    arg = char(args{1});
    if mip.env.is_path_arg(arg)
        target = arg;
        createHint = sprintf('mip env create %s', arg);
    else
        if ~mip.name.is_valid(arg)
            error('mip:env:invalidName', ...
                  ['Invalid environment name "%s". Names may contain ' ...
                   'letters, digits, hyphens, and underscores, and must ' ...
                   'start and end with a letter or digit.'], arg);
        end
        name = arg;
        target = fullfile(mip.env.store_dir(), arg);
        createHint = sprintf('mip env create %s', arg);
    end
end

if ~mip.paths.is_root(target)
    error('mip:env:notAnEnvironment', ...
          '"%s" is not a mip environment — create one with "%s".', ...
          target, createHint);
end
targetAbs = mip.paths.get_absolute_path(target);

s = mip.env.active();
if ~isempty(s) && strcmp(s.root, targetAbs)
    fprintf('Environment %s is already active\n', mip.env.describe(s));
    if opts.load
        load_env_packages();
    end
    return
end
if ~isempty(s)
    % Exclusive activation: fully deactivate the current environment
    % (restoring the baseline session) before activating the new one, so
    % the state saved below is always the baseline session's.
    mip.env.deactivate();
end

% Save the session state, then swap: unload everything including sticky
% packages (only the running mip stays) while the old root is still in
% effect, so path entries and MEX binaries resolve against the root they
% were loaded from (no DLL from another root stays locked). The running
% mip is detected now — against the root it was loaded from — and carried
% in the saved state, so deactivation (and any bulk unload while the env
% is active) spares it too.
saved = struct( ...
    'root', targetAbs, ...
    'name', name, ...
    'running_mip', mip.self.running_mip_fqn(), ...
    'saved_mip_root', getenv('MIP_ROOT'), ...
    'saved_loaded', {mip.state.key_value_get('MIP_LOADED_PACKAGES')}, ...
    'saved_direct', {mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES')}, ...
    'saved_sticky', {mip.state.key_value_get('MIP_STICKY_PACKAGES')});

if any_swappable(saved.saved_loaded, saved.running_mip)
    mip.unload('--all', '--force');
end

setenv('MIP_ROOT', targetAbs);
ensure_session_baseline();
mip.state.key_value_set('MIP_ENV_STATE', saved);

fprintf('Activated environment: %s\n', mip.env.describe(saved));

if opts.load
    load_env_packages();
end

end

function tf = any_swappable(loaded, runningMip)
% True if anything besides the running mip is loaded.
    other = ~strcmp(loaded, 'gh/mip-org/core/mip');
    if ~isempty(runningMip)
        other = other & ~strcmp(loaded, runningMip);
    end
    tf = any(other);
end

function ensure_session_baseline()
% The usual session baseline: mip always loaded and sticky. The swap
% above already reduced the lists to the running mip with its flags
% preserved, so only the core identity needs ensuring here.
    mip.state.key_value_append('MIP_LOADED_PACKAGES', 'gh/mip-org/core/mip');
    mip.state.key_value_append('MIP_STICKY_PACKAGES', 'gh/mip-org/core/mip');
end

function load_env_packages()
% Load each directly installed package of the (now active) environment as
% a direct load; dependencies load transitively via the normal machinery.
% Best-effort: the pointer swap has already completed, so a failed load
% leaves the environment active.
    directs = mip.state.get_directly_installed();
    directs = directs(~strcmp(directs, 'gh/mip-org/core/mip'));
    if isempty(directs)
        fprintf('No directly installed packages to load\n');
        return
    end
    nLoaded = 0;
    nFailed = 0;
    for i = 1:length(directs)
        fqn = directs{i};
        try
            mip.load(fqn);
            nLoaded = nLoaded + 1;
        catch ME
            nFailed = nFailed + 1;
            fprintf('Error loading "%s": %s\n', ...
                    mip.parse.display_fqn(fqn), ME.message);
        end
    end
    if nFailed > 0
        fprintf('Loaded %d package(s), %d failed\n', nLoaded, nFailed);
    else
        fprintf('Loaded %d package(s)\n', nLoaded);
    end
end

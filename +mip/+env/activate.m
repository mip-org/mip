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
% it: everything loaded — including sticky packages, mip excepted — is
% unloaded via the normal unload machinery, and the session starts cold
% in the new environment. Child processes spawned from the session
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
% packages (only gh/mip-org/core/mip stays) while the old root is still
% in effect, so path entries and MEX binaries resolve against the root
% they were loaded from (no DLL from another root stays locked).
saved = struct( ...
    'root', targetAbs, ...
    'name', name, ...
    'saved_mip_root', getenv('MIP_ROOT'), ...
    'saved_loaded', {mip.state.key_value_get('MIP_LOADED_PACKAGES')}, ...
    'saved_direct', {mip.state.key_value_get('MIP_DIRECTLY_LOADED_PACKAGES')}, ...
    'saved_sticky', {mip.state.key_value_get('MIP_STICKY_PACKAGES')});

if has_loaded_besides_mip(saved.saved_loaded)
    mip.unload('--all', '--force');
end

setenv('MIP_ROOT', targetAbs);
reset_session_baseline();
mip.state.key_value_set('MIP_ENV_STATE', saved);

fprintf('Activated environment: %s\n', mip.env.describe(saved));

if opts.load
    load_env_packages();
end

end

function tf = has_loaded_besides_mip(loaded)
    tf = any(~strcmp(loaded, 'gh/mip-org/core/mip'));
end

function reset_session_baseline()
% The usual session baseline: mip always loaded and sticky, nothing else.
    mip.state.key_value_set('MIP_LOADED_PACKAGES', {'gh/mip-org/core/mip'});
    mip.state.key_value_set('MIP_DIRECTLY_LOADED_PACKAGES', {});
    mip.state.key_value_set('MIP_STICKY_PACKAGES', {'gh/mip-org/core/mip'});
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

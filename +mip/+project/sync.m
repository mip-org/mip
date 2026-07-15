function sync(varargin)
%SYNC   Make the project's .mip environment match mip.lock.
%
% Usage:
%   mip project sync                 - Base dependencies + dev group
%   mip project sync --no-dev        - Base dependencies only
%   mip project sync --group <name>  - Also install a named group (repeatable)
%   mip project sync --all-groups    - Install every group
%   mip project sync --yes           - Skip the first-sync prune confirmation
%
% Installs each selected lock entry directly from its recorded .mhl URL
% (verifying the locked SHA-256 when present) and removes installed
% packages the lock does not select - the environment is a disposable
% copy of the lock, rebuilt identically on any machine. Creates ./.mip
% (marker and all) if it does not exist; errors if there is no mip.lock.
%
% The dev group is installed by default, so "clone, sync, run the tests"
% just works. When the spec carries package identity (name:), sync
% finishes by installing the project itself into the environment as an
% editable install, and never prunes it.
%
% The first sync of a formerly hand-managed environment lists what it
% would remove and confirms first (--yes skips; the MIP_CONFIRM
% environment variable is honored, as in "mip env delete").

    [opts, args] = mip.parse.flags(varargin, ...
        struct('no_dev', false, 'group', {{}}, 'all_groups', false, ...
               'yes', false, 'directory', ''));
    if ~isempty(args)
        error('mip:project:tooManyArgs', '"mip project sync" takes no arguments.');
    end

    proj = mip.project.locate(opts.directory);
    mip.project.sync_project(proj, opts);

end

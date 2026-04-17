function unpin(varargin)
%UNPIN   Unpin one or more packages.
%
% Usage:
%   mip.unpin('packageName')
%   mip.unpin('org/channel/packageName')
%   mip.unpin('package1', 'package2')
%
% Unpinned packages will be updated normally by "mip update --all".
%
% Accepts both bare package names and fully qualified names.

    if nargin < 1
        error('mip:unpin:noPackage', ...
              'At least one package name is required for unpin command.');
    end

    for i = 1:length(varargin)
        packageArg = varargin{i};
        r = mip.resolve.resolve_to_installed(packageArg);
        if isempty(r)
            error('mip:unpin:notInstalled', ...
                  'Package "%s" is not installed.', packageArg);
        end

        if ~mip.state.is_pinned(r.fqn)
            fprintf('Package "%s" is not pinned.\n', r.fqn);
        else
            mip.state.remove_pinned(r.fqn);
            fprintf('Unpinned "%s".\n', r.fqn);
        end
    end
end

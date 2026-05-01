function pin(varargin)
%PIN   Pin one or more installed packages to their current version.
%
% Usage:
%   mip pin <package>
%   mip pin org/channel/<package>
%   mip pin <package1> <package2> ...
%
% Pinned packages are skipped by "mip update --all". Use "mip update
% --force" to override the pin (which also unpins the package).
%
% Accepts both bare package names and fully qualified names.

    if nargin < 1
        error('mip:pin:noPackage', ...
              'At least one package name is required for pin command.');
    end

    for i = 1:length(varargin)
        packageArg = varargin{i};
        r = mip.resolve.resolve_to_installed(packageArg);
        if isempty(r)
            error('mip:pin:notInstalled', ...
                  'Package "%s" is not installed.', packageArg);
        end

        displayFqn = mip.parse.display_fqn(r.fqn);
        if mip.state.is_pinned(r.fqn)
            fprintf('Package "%s" is already pinned.\n', displayFqn);
        else
            mip.state.add_pinned(r.fqn);
            fprintf('Pinned "%s".\n', displayFqn);
        end
    end
end

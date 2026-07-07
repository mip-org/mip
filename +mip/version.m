function v = version()
%VERSION   Return the mip package manager version string.
%
% Usage:
%   mip version
%
% Returns the version string for mip.

% Resolve the version of the running copy of mip (the one this file
% belongs to), whether installed or a source checkout.
thisDir = fileparts(mfilename('fullpath'));  % +mip directory
sourceDir = fileparts(thisDir);              % source root (contains mip.yaml)
v = mip.self.read_version(sourceDir);

end

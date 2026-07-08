function write_spec(projectDir, spec)
%WRITE_SPEC   Write a project's mipenv.yaml from a spec struct.
%
% Args:
%   projectDir - Project directory (from mip.env.project_dir).
%   spec       - Struct with fields name, dependencies, channels (as
%                produced by mip.env.read_spec).
%
% The file is emitted directly (not via a YAML library) to keep the output
% stable, comment-friendly, and dependency-free, matching how mip.init
% writes mip.yaml.

specFile = mip.env.spec_path(projectDir);
fid = fopen(specFile, 'w');
if fid == -1
    error('mip:env:specWriteFailed', 'Could not open %s for writing.', specFile);
end
cleaner = onCleanup(@() fclose(fid));

fprintf(fid, '# mip project environment specification\n');
fprintf(fid, '# Edit this file, then run "mip env lock" and "mip env sync".\n');

name = '';
if isfield(spec, 'name') && ~isempty(spec.name)
    name = spec.name;
end
fprintf(fid, 'name: %s\n\n', name);

deps = get_list(spec, 'dependencies');
if isempty(deps)
    fprintf(fid, 'dependencies: []\n');
else
    fprintf(fid, 'dependencies:\n');
    for i = 1:numel(deps)
        fprintf(fid, '  - %s\n', deps{i});
    end
end
fprintf(fid, '\n');

channels = get_list(spec, 'channels');
if isempty(channels)
    fprintf(fid, '# channels: extra channels (besides mip-org/core) to search\n');
    fprintf(fid, '#           for bare-name dependencies, in priority order.\n');
    fprintf(fid, 'channels: []\n');
else
    fprintf(fid, 'channels:\n');
    for i = 1:numel(channels)
        fprintf(fid, '  - %s\n', channels{i});
    end
end

end

function items = get_list(spec, field)
items = {};
if isfield(spec, field) && ~isempty(spec.(field))
    items = spec.(field);
    if ~iscell(items)
        items = {items};
    end
end
end

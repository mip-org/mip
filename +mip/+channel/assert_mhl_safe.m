function assert_mhl_safe(mhlPath)
%ASSERT_MHL_SAFE   Error unless a .mhl archive is safe to extract.
%
% Parses the archive's End of Central Directory Record and Central
% Directory to locate every entry, then seeks to each Local File
% Header and validates the LOCAL HEADER name. MATLAB's unzip() honors
% local-header names (verified empirically), so those are the names
% that actually determine where files get written and therefore the
% ones we must check.
%
% Central-directory names are validated too, as a secondary check:
% a crafted archive whose CD disagrees with its local headers is a
% spec violation and is treated as malicious.
%
% An entry name is unsafe if it is absolute, contains a Windows drive
% letter, contains a null byte, or contains ".." components that
% resolve outside the extraction root. Benign in-tree ".." like
% "foo/../bar" is allowed.
%
% Symlink entries (Unix S_IFLNK in the high 16 bits of the central
% directory's external file attributes) receive an additional check.
% Their target, resolved relative to the link's own directory, must
% stay inside the extraction root; otherwise a later entry named
% "<link>/<path>" could escape by following the link. Benign in-tree
% symlinks (e.g. "sub/link" -> "../other") are allowed. Compressed
% symlink payloads are rejected as a safe fallback because the target
% cannot be read without a deflate implementation.
%
% This runs BEFORE unzip() so malicious entries are rejected before
% any bytes are written to disk.
%
% Args:
%   mhlPath - Path to the .mhl / .zip archive.
%
% Errors:
%   mip:pathTraversal  - an entry would escape its extraction root.
%   mip:invalidPackage - the file is not a parseable ZIP archive.

if ~exist(mhlPath, 'file')
    error('mip:invalidPackage', 'Archive not found: %s', mhlPath);
end

fid = fopen(mhlPath, 'r');
if fid < 0
    error('mip:invalidPackage', 'Cannot open archive: %s', mhlPath);
end
cleanup = onCleanup(@() fclose(fid));

fseek(fid, 0, 'eof');
fileSize = ftell(fid);
if fileSize < 22
    error('mip:invalidPackage', 'File too small to be a ZIP archive: %s', mhlPath);
end

% Scan the last (22 + 65535) bytes for the End of Central Directory
% signature 0x06054b50 (little-endian bytes: 50 4B 05 06).
searchLen = min(fileSize, 22 + 65535);
fseek(fid, fileSize - searchLen, 'bof');
tail = fread(fid, searchLen, '*uint8');
tail = tail(:)';

eocdOffset = find_signature(tail, uint8([80 75 5 6]));
if eocdOffset < 0
    error('mip:invalidPackage', 'Not a valid ZIP archive (EOCD not found): %s', mhlPath);
end

eocd = tail(eocdOffset:end);
if numel(eocd) < 22
    error('mip:invalidPackage', 'Truncated End of Central Directory record');
end

totalEntries = double(typecast(eocd(11:12), 'uint16'));
cdSize       = double(typecast(eocd(13:16), 'uint32'));
cdOffset     = double(typecast(eocd(17:20), 'uint32'));

U16_MAX = double(intmax('uint16'));
U32_MAX = double(intmax('uint32'));
if totalEntries == U16_MAX || cdSize == U32_MAX || cdOffset == U32_MAX
    error('mip:invalidPackage', 'ZIP64 archives are not supported');
end

if cdOffset + cdSize > fileSize
    error('mip:invalidPackage', 'Central directory extends past end of file');
end

fseek(fid, cdOffset, 'bof');
cd = fread(fid, cdSize, '*uint8');
cd = cd(:)';

pos = 1;
cdHeaderSig = uint8([80 75 1 2]);
for i = 1:totalEntries
    if pos + 45 > numel(cd)
        error('mip:invalidPackage', 'Truncated central directory entry');
    end
    if ~isequal(cd(pos:pos+3), cdHeaderSig)
        error('mip:invalidPackage', 'Bad central directory entry signature');
    end

    nameLen         = double(typecast(cd(pos+28:pos+29), 'uint16'));
    extraLen        = double(typecast(cd(pos+30:pos+31), 'uint16'));
    commentLen      = double(typecast(cd(pos+32:pos+33), 'uint16'));
    extAttr         = typecast(cd(pos+38:pos+41), 'uint32');
    localHeaderOffs = double(typecast(cd(pos+42:pos+45), 'uint32'));

    nameStart = pos + 46;
    nameEnd   = nameStart + nameLen - 1;
    if nameEnd > numel(cd)
        error('mip:invalidPackage', 'Truncated central directory entry name');
    end
    cdName = char(cd(nameStart:nameEnd));
    validate_name(cdName);

    % Read the matching local file header. Its name is the one unzip()
    % actually honors, so it is the authoritative name check.
    lh = read_local_header_info(fid, localHeaderOffs, fileSize);

    % A well-formed ZIP has identical names in the CD and local header.
    % Any disagreement is either a bug in the producer or a deliberate
    % attempt to confuse extractors — either way, refuse to extract.
    if ~strcmp(cdName, lh.name)
        error('mip:pathTraversal', ...
              ['Archive entry name disagrees between central directory ' ...
               '(%s) and local file header (%s)'], cdName, lh.name);
    end
    validate_name(lh.name);

    % Symlink entries are safe only if their target, when resolved
    % relative to the link's own directory, stays inside destDir.
    % Validate the target; benign in-tree symlinks are permitted.
    fileType = bitand(bitshift(extAttr, -16), uint32(hex2dec('F000')));
    if fileType == uint32(hex2dec('A000'))
        target = read_symlink_target(fid, lh, fileSize);
        validate_symlink_target(lh.name, target);
    end

    pos = nameEnd + 1 + extraLen + commentLen;
end

end

function info = read_local_header_info(fid, offset, fileSize)
if offset + 30 > fileSize
    error('mip:invalidPackage', 'Local file header offset past end of file');
end
fseek(fid, offset, 'bof');
hdr = fread(fid, 30, '*uint8');
hdr = hdr(:)';
if ~isequal(hdr(1:4), uint8([80 75 3 4]))
    error('mip:invalidPackage', 'Bad local file header signature at offset %d', offset);
end
info.method         = double(typecast(hdr(9:10),  'uint16'));
info.compressedSize = double(typecast(hdr(19:22), 'uint32'));
nameLen             = double(typecast(hdr(27:28), 'uint16'));
extraLen            = double(typecast(hdr(29:30), 'uint16'));
if offset + 30 + nameLen > fileSize
    error('mip:invalidPackage', 'Local file header name extends past end of file');
end
nameBytes = fread(fid, nameLen, '*uint8');
info.name = char(nameBytes(:)');
info.dataOffset = offset + 30 + nameLen + extraLen;
end

function target = read_symlink_target(fid, lh, fileSize)
% Unix ZIP symlinks store the link target as the entry's payload. We
% require stored (uncompressed) data so we can read the target without
% a deflate implementation; compressed symlinks are vanishingly rare
% in practice (targets are short strings) and rejecting them is safe.
if lh.method ~= 0
    error('mip:pathTraversal', ...
          'Symlink "%s" has compressed payload (method %d); cannot validate target', ...
          lh.name, lh.method);
end
if lh.compressedSize == 0
    error('mip:pathTraversal', 'Symlink "%s" has an empty target', lh.name);
end
if lh.dataOffset + lh.compressedSize > fileSize
    error('mip:invalidPackage', 'Symlink payload extends past end of file');
end
fseek(fid, lh.dataOffset, 'bof');
bytes = fread(fid, lh.compressedSize, '*uint8');
target = char(bytes(:)');
end

function validate_symlink_target(linkName, target)
% A symlink is safe if "dirname(linkName) / target", resolved
% component-by-component, stays inside the extraction root.
if any(target == 0)
    error('mip:pathTraversal', 'Symlink "%s" target contains a null byte', linkName);
end
normalizedTarget = strrep(target, '\', '/');
if startsWith(normalizedTarget, '/')
    error('mip:pathTraversal', ...
          'Symlink "%s" targets an absolute path: %s', linkName, target);
end
if ~isempty(regexp(normalizedTarget, '^[A-Za-z]:', 'once'))
    error('mip:pathTraversal', ...
          'Symlink "%s" targets a drive letter: %s', linkName, target);
end
% Build the full sequence of components: the symlink's parent-directory
% parts followed by the target's parts. Then walk them with the same
% stack rule used for entry names.
linkParts    = strsplit(strrep(linkName, '\', '/'), '/');
parentParts  = linkParts(1:end-1);  % drop the link's own name component
targetParts  = strsplit(normalizedTarget, '/');
allParts     = [parentParts, targetParts];
depth = 0;
for k = 1:numel(allParts)
    p = allParts{k};
    if isempty(p) || strcmp(p, '.')
        continue
    end
    if strcmp(p, '..')
        if depth == 0
            error('mip:pathTraversal', ...
                  'Symlink "%s" targets outside the destination directory: %s', ...
                  linkName, target);
        end
        depth = depth - 1;
    else
        depth = depth + 1;
    end
end
end

function offset = find_signature(buf, sig)
n = numel(buf);
m = numel(sig);
for k = n-m+1:-1:1
    if isequal(buf(k:k+m-1), sig)
        offset = k;
        return
    end
end
offset = -1;
end

function validate_name(name)
if any(name == 0)
    error('mip:pathTraversal', 'Archive entry contains a null byte in its name');
end
normalized = strrep(name, '\', '/');
if startsWith(normalized, '/')
    error('mip:pathTraversal', 'Archive entry has an absolute path: %s', name);
end
if ~isempty(regexp(normalized, '^[A-Za-z]:', 'once'))
    error('mip:pathTraversal', 'Archive entry has a drive letter: %s', name);
end
% Simulate path resolution: accept ".." as long as the resolved path
% stays within the extraction root. "foo/../bar" -> "bar" (OK);
% "../bar" or "a/../../b" -> escapes the root (REJECT).
parts = strsplit(normalized, '/');
depth = 0;
for k = 1:numel(parts)
    p = parts{k};
    if isempty(p) || strcmp(p, '.')
        continue
    end
    if strcmp(p, '..')
        if depth == 0
            error('mip:pathTraversal', ...
                  'Archive entry escapes the destination directory: %s', name);
        end
        depth = depth - 1;
    else
        depth = depth + 1;
    end
end
end

function hex = sha256(filePath)
%SHA256   Compute SHA-256 of a file as a lowercase hex string.
%
% Returns '' if the JVM is not available (e.g. numbl), which callers can
% treat as "unable to verify" and skip digest checks.
%
% Args:
%   filePath - Absolute or relative path to a readable file.
%
% Returns:
%   hex - 64-char lowercase hex string, or '' if the JVM is unavailable
%         or the file could not be read.

hex = '';
if ~usejava('jvm')
    return
end
fid = -1;
try
    md = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(filePath, 'r');
    if fid == -1
        return
    end
    while true
        chunk = fread(fid, 65536, '*uint8');
        if isempty(chunk)
            break
        end
        md.update(chunk);
    end
    fclose(fid);
    fid = -1;
    digest = typecast(md.digest(), 'uint8');
    hex = lower(sprintf('%02x', digest));
catch
    if fid ~= -1
        fclose(fid);
    end
    hex = '';
end
end

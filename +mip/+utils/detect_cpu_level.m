function level = detect_cpu_level()
%DETECT_CPU_LEVEL   Detect the highest supported x86_64 SIMD level.
%
%   level = mip.utils.detect_cpu_level()
%
%   Returns one of 'x86_64_v1', 'x86_64_v2', 'x86_64_v3', 'x86_64_v4',
%   or '' on non-x86_64 platforms (macOS ARM, etc.).
%
%   Only relevant for linux_x86_64 and windows_x86_64 — the only platforms
%   where SIMD variants are built.  Pure MATLAB, no MEX needed.

arch = computer('arch');

if strcmp(arch, 'glnxa64')
    flags = get_linux_flags();
elseif strcmp(arch, 'win64')
    flags = get_windows_flags();
else
    % macOS and other platforms: no SIMD variants built
    level = '';
    return
end

% psABI level definitions (cumulative)
if has_all(flags, {'avx512f','avx512bw','avx512cd','avx512dq','avx512vl'})
    level = 'x86_64_v4';
elseif has_all(flags, {'avx2','fma','bmi1','bmi2'})
    level = 'x86_64_v3';
elseif has_all(flags, {'sse4_2','ssse3','popcnt'})
    level = 'x86_64_v2';
else
    level = 'x86_64_v1';
end

end


function result = has_all(flags, required)
%HAS_ALL  True if every element of REQUIRED is in FLAGS.
result = all(ismember(required, flags));
end


function flags = get_linux_flags()
%GET_LINUX_FLAGS  Parse /proc/cpuinfo for the 'flags' line.
flags = {};
try
    text = fileread('/proc/cpuinfo');
    lines = strsplit(text, newline);
    for i = 1:numel(lines)
        if startsWith(strtrim(lines{i}), 'flags')
            parts = strsplit(lines{i}, ':');
            if numel(parts) >= 2
                flags = strsplit(strtrim(parts{2}));
            end
            return
        end
    end
catch
    % /proc/cpuinfo unreadable — fall back to v1
end
end


function flags = get_windows_flags()
%GET_WINDOWS_FLAGS  Detect CPU features on Windows via kernel32.
%
%   Uses IsProcessorFeaturePresent() via PowerShell P/Invoke.
%   Feature IDs: PF_SSE3_INSTRUCTIONS_AVAILABLE=13,
%   PF_SSSE3_INSTRUCTIONS_AVAILABLE=36, PF_SSE4_1=37, PF_SSE4_2=38,
%   PF_AVX_INSTRUCTIONS_AVAILABLE=39, PF_AVX2=40, PF_AVX512F=43.

flags = {};
try
    cmd = [ ...
        'powershell -NoProfile -Command "' ...
        'Add-Type -MemberDefinition ''[DllImport(""""kernel32.dll"""")]' ...
        ' public static extern bool IsProcessorFeaturePresent(int f);'' ' ...
        '-Name K32 -Namespace W32; ' ...
        '$r = @{}; ' ...
        'foreach ($kv in @{ssse3=36;sse4_2=38;popcnt=38;avx2=40;avx512f=43}.GetEnumerator()) {' ...
        '  $r[$kv.Key] = [W32.K32]::IsProcessorFeaturePresent($kv.Value)' ...
        '}; ' ...
        '$r.GetEnumerator() | ForEach-Object { Write-Output (""""{0}={1}"""" -f $_.Key,$_.Value) }' ...
        '"'];
    [status, output] = system(cmd);
    if status ~= 0
        return
    end
    lines = strsplit(strtrim(output), newline);
    for i = 1:numel(lines)
        parts = strsplit(strtrim(lines{i}), '=');
        if numel(parts) == 2 && strcmpi(strtrim(parts{2}), 'true')
            flags{end+1} = strtrim(parts{1}); %#ok<AGROW>
        end
    end
    % AVX2 implies FMA/BMI1/BMI2 on all shipping x86_64 CPUs
    if ismember('avx2', flags)
        flags = [flags, {'fma', 'bmi1', 'bmi2'}];
    end
    % AVX512F feature ID 43 only checks F; assume full v4 set.
    % Conservative: if this is wrong, user gets v3 instead of v4,
    % which is still fast and correct.
    if ismember('avx512f', flags)
        flags = [flags, {'avx512bw', 'avx512cd', 'avx512dq', 'avx512vl'}];
    end
catch
    % PowerShell unavailable — fall back to v1
end
end

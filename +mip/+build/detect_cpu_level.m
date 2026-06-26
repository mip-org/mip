function level = detect_cpu_level()
%DETECT_CPU_LEVEL   Highest x86-64 microarchitecture (psABI) level the CPU supports.
%
% Usage:
%   level = mip.build.detect_cpu_level()
%
% Returns an integer in 1..4 giving the highest x86-64 psABI microarchitecture
% level the current CPU can run:
%
%   1  x86-64 baseline (SSE2)            - runs on any x86-64 CPU
%   2  + SSE3/SSSE3/SSE4.1/SSE4.2/POPCNT
%   3  + AVX/AVX2/FMA/BMI1/BMI2/F16C
%   4  + AVX-512 F/BW/CD/DQ/VL
%
% This selects which SIMD build variant of a package (e.g. linux_x86_64_v3) is
% safe to install: a binary compiled for level N runs only on CPUs of level N
% or higher, so the client must never install a build above the host's level.
%
% On non-x86-64 platforms (e.g. Apple Silicon) the level is meaningless and 1
% is returned. Pure MATLAB plus a lightweight shell probe — no MEX — so it can
% run before any compiled package is installed.

switch computer('arch')
    case 'glnxa64'
        level = level_from_flags(linux_cpu_flags());
    case 'win64'
        level = windows_cpu_level();
    otherwise
        % Non-x86-64 (e.g. maca64): microarchitecture levels do not apply.
        level = 1;
end

end


function level = level_from_flags(flags)
%LEVEL_FROM_FLAGS  Map a set of CPU feature flag tokens to a psABI level.
has = @(name) any(strcmp(flags, name));
hasAll = @(names) all(cellfun(has, names));

if hasAll({'avx512f', 'avx512bw', 'avx512cd', 'avx512dq', 'avx512vl'})
    level = 4;
elseif hasAll({'avx2', 'fma', 'bmi1', 'bmi2'})
    level = 3;
elseif hasAll({'sse4_2', 'ssse3', 'popcnt'})
    level = 2;
else
    level = 1;
end
end


function flags = linux_cpu_flags()
%LINUX_CPU_FLAGS  Tokens from the first 'flags' line of /proc/cpuinfo.
flags = {};
try
    txt = fileread('/proc/cpuinfo');
    lines = strsplit(txt, sprintf('\n'));
    for i = 1:numel(lines)
        ln = strtrim(lines{i});
        if startsWith(ln, 'flags')
            parts = strsplit(ln, ':');
            if numel(parts) >= 2
                flags = strsplit(strtrim(parts{2}));
            end
            return
        end
    end
catch
    % /proc/cpuinfo unreadable -> treat as baseline.
end
end


function level = windows_cpu_level()
%WINDOWS_CPU_LEVEL  Probe AVX2 / AVX-512 via the bundled PowerShell helper.
%
% The helper calls the documented kernel32 IsProcessorFeaturePresent, which
% needs no MEX and no PowerShell 7. It prints the psABI level integer; any
% failure falls back to the baseline (1). Windows distinguishes only baseline
% / AVX2 (3) / AVX-512 (4) — there is no published v2 build, so v2 is not
% probed.
level = 1;
scriptPath = fullfile(fileparts(mfilename('fullpath')), 'private', 'cpu_level.ps1');
if ~isfile(scriptPath)
    return
end
try
    cmd = sprintf('powershell -NoProfile -ExecutionPolicy Bypass -File "%s"', scriptPath);
    [status, out] = system(cmd);
    if status == 0
        n = str2double(strtrim(out));
        if ~isnan(n) && n >= 1 && n <= 4
            level = n;
        end
    end
catch
    % PowerShell unavailable -> baseline.
end
end

# Print the highest x86-64 psABI microarchitecture level the CPU supports, as a
# single integer:
#
#   1  baseline (SSE2)
#   3  + AVX2   (psABI v3)
#   4  + AVX-512 F (psABI v4)
#
# Used by mip.build.detect_cpu_level on Windows and by the channel build's
# test-capability gate (mip_channel_tools build-package.yml). Uses the
# documented kernel32 IsProcessorFeaturePresent — works in Windows PowerShell
# 5.1 (no PowerShell 7 / System.Runtime.Intrinsics needed) and requires no
# compiler. Feature ids:
#   PF_AVX2_INSTRUCTIONS_AVAILABLE   = 40
#   PF_AVX512F_INSTRUCTIONS_AVAILABLE = 41
#
# Windows distinguishes only baseline / AVX2 / AVX-512: there is no reliable
# IsProcessorFeaturePresent id for SSE4.2, and no published v2 Windows build,
# so v2 is not detected (such a CPU correctly falls back to the baseline build).

$ErrorActionPreference = 'Stop'

Add-Type -Name MipCpu -Namespace Mip -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern bool IsProcessorFeaturePresent(uint feature);
'@

$avx2   = [Mip.MipCpu]::IsProcessorFeaturePresent(40)
$avx512 = [Mip.MipCpu]::IsProcessorFeaturePresent(41)

if ($avx512) {
    Write-Output 4
} elseif ($avx2) {
    Write-Output 3
} else {
    Write-Output 1
}

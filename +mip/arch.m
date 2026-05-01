function arch = arch()
%ARCH   Get the current architecture tag.
%
% Usage:
%   mip arch
%
% Returns the architecture tag for the current system.

is_numbl = exist('isnumbl', 'builtin') && isnumbl();

switch computer('arch')
    case 'glnxa64'
        if is_numbl
            arch = 'numbl_linux_x86_64';
        else
            arch = 'linux_x86_64';
        end
    case 'maca64'
        if is_numbl
            arch = 'numbl_macos_arm64';
        else
            arch = 'macos_arm64';
        end
    case 'maci64'
        if is_numbl
            arch = 'numbl_macos_x86_64';
        else
            arch = 'macos_x86_64';
        end
    case 'win64'
        arch = 'windows_x86_64';
    case 'browser'
        arch = 'numbl_wasm';
end

end

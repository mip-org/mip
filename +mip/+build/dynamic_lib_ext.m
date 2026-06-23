function libext = dynamic_lib_ext()
%DYNAMIC_LIB_EXT   Return the platform's dynamic-library extension.

persistent libext_

if isempty(libext_)
    switch computer('arch')
        case 'glnxa64'
            libext_ = 'so';
        case {'maca64', 'maci64'}
            libext_ = 'dylib';
        case 'win64'
            libext_ = 'dll';
        otherwise
            libext_ = 'so';
    end
end

libext = libext_;

end

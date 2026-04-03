function cleanupTestPaths(rootDir)
%CLEANUPTESTPATHS   Remove any MATLAB path entries under rootDir.

pathDirs = strsplit(path, pathsep);
for i = 1:length(pathDirs)
    if startsWith(pathDirs{i}, rootDir)
        rmpath(pathDirs{i});
    end
end

end

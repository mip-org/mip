function [status, cmdout] = echo_and_run(cmd)
%ECHO_AND_RUN   Echo a shell command, then run it via system().

fprintf('  %s\n', cmd);
[status, cmdout] = system(cmd);
if ~isempty(cmdout)
    lines = splitlines(cmdout);
    fprintf('    %s\n', lines{1:end-1});
end

end

function [status, output] = unix(command)
% Dry-run stand-in: print the shell command that linuxmakeit64 would run.
printf('  %% unix: %s\n', command);
status = 0;
output = '';
end

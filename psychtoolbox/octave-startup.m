% Put Psychtoolbox-3 on the Octave path. This does what
% PsychtoolboxPostInstallRoutine does for a downloaded copy, but without
% savepath(), because the Nix store is read-only.
ptbRoot = '@out@/share/psychtoolbox-3';
addpath(genpath(ptbRoot));

% genpath also adds folders for other platforms and for the Wayland build of
% Screen. Their files must not shadow the X11 build.
ptbDirs = strsplit(path(), pathsep());
ptbDrop = ptbDirs(strncmp(ptbDirs, ptbRoot, numel(ptbRoot)) ...
                  & ~cellfun('isempty', regexp(ptbDirs, ...
                      '/([^/]*(OSX|Windows)[^/]*|ARM64|ArmArch|Wayland|Octave3[^/]*)(/|$)', 'once')));
if ~isempty(ptbDrop)
  rmpath(ptbDrop{:});
end

% Prepend the mex folder last. PsychBasic has help-only m-files (Screen.m,
% GetSecs.m, ...) that otherwise shadow the mex files.
addpath([ptbRoot '/PsychBasic/Octave5LinuxFiles64']);
clear ptbRoot ptbDirs ptbDrop;

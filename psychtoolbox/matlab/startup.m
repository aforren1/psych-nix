% Put Psychtoolbox-3 and its MATLAB mex files on the MATLAB path. This does
% what SetupPsychtoolbox does for a downloaded copy, but without savepath(),
% because the Nix store is read-only. matlab-psychtoolbox runs this file
% before the user's -r or -batch command.
ptbRoot = '@ptbRoot@';
ptbMexDir = '@mexDir@';
addpath(genpath(ptbRoot));

% genpath also adds folders for Octave, other platforms and the Wayland build
% of Screen. Their files must not shadow the MATLAB files.
ptbDirs = strsplit(path(), pathsep());
ptbDrop = ptbDirs(strncmp(ptbDirs, ptbRoot, numel(ptbRoot)) ...
                  & ~cellfun('isempty', regexp(ptbDirs, ...
                      '/([^/]*(OSX|Windows)[^/]*|ARM64|ArmArch|Wayland|Octave[^/]*)(/|$)', 'once')));
if ~isempty(ptbDrop)
  rmpath(ptbDrop{:});
end

% Prepend the mex folder last. PsychBasic in the store has help-only m-files
% (Screen.m, GetSecs.m, ...) that otherwise shadow the mex files.
if exist(fullfile(ptbMexDir, 'Screen.mexa64'), 'file')
  addpath(ptbMexDir);
else
  warning('matlab-psychtoolbox:noMex', ...
          ['No Psychtoolbox mex files in %s. Build them with ' ...
           'ptb-matlab-mex-builder --release %s'], ptbMexDir, ['R' version('-release')]);
end

% The store copy of PsychJava has no class files (the package deletes
% prebuilt binaries). GetChar and ListenChar need GetCharJava on MATLAB
% releases with the Java desktop (before R2025a).
if usejava('jvm')
  javaaddpath('@getCharJava@');
end
clear ptbRoot ptbMexDir ptbDirs ptbDrop;

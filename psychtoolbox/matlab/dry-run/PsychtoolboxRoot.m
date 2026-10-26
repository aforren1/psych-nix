function root = PsychtoolboxRoot()
% Dry-run stand-in: the Psychtoolbox folder of the build copy (PTB_ROOT), or
% of the source tree.
root = getenv('PTB_ROOT');
if isempty(root)
  root = [getenv('PTB_SOURCE') '/Psychtoolbox/'];
end
end

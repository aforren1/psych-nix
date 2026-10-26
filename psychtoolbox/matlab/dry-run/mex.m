function mex(varargin)
% Dry-run stand-in for the MATLAB mex command. It prints the call in MATLAB
% function syntax and does not compile. ptb-matlab-mex-builder puts this
% folder first on the Octave path. If PTB_MEX_RECORDS is set, it also
% appends the folder and the arguments to that file, separated by
% char(31), so that --check-env can preprocess the same sources.
src = getenv('PTB_SOURCE');
here = pwd();
if strncmp(here, src, numel(src))
  here = here(numel(src) + 2:end);
end
quoted = cellfun(@(a) ['''' strrep(a, '''', '''''') ''''], varargin, 'UniformOutput', false);
printf('cd %s; mex(%s)\n', here, strjoin(quoted, ', '));
records = getenv('PTB_MEX_RECORDS');
if ~isempty(records)
  fid = fopen(records, 'a');
  fprintf(fid, '%s\n', strjoin([{pwd()}, varargin], char(31)));
  fclose(fid);
end
end

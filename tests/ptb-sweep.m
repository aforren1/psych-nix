% Psychtoolbox-3 demo and test sweep, modeled on the Debian package test
% (debian/rules override_dh_auto_test and debian/run_tests).
%
% Usage, with octave-cli and xdotool on PATH and an X display:
%
%   octave-cli --no-init-file --no-site-file -q ptb-sweep.m STARTUP [LISTFILE]
%
% STARTUP is the startup.m of psychtoolbox-3. LISTFILE replaces the built-in
% list. It has one entry per line: name, call, limit and keys, separated by
% tabs. Use it to try new candidates without editing this file. Set
% PTB_SWEEP_VERBOSE=1 to print the end of the log of each entry, not only of
% the failed ones: some demos catch their own errors and return normally. Set
% PTB_SWEEP_TIME_SCALE to multiply all time limits, for slow hosts such as
% nested virtualization or loaded CI runners. The key schedules do not scale:
% they count from the start of the demo, and the last key repeats until the
% demo ends.
%
% Each entry runs in its own Octave process: a demo that segfaults or hangs
% must not take the rest of the sweep with it, and Octave cannot interrupt a
% running mex call. Output is one line per entry:
%
%   SWEEP <name> ok|fail|skip <seconds> [<first line of the error>]
%
% The seconds count from the start of the demo. They exclude the start of the
% child Octave, which takes 4 to 15 s in the VM test, depending on the load on
% the host. The child reads the site octaverc, so that it sees the same Octave
% packages as the users.
1;

function list = sweep_list()
  % Columns: name, call, limit in seconds, keys.
  % keys is a space-separated list of DELAY:KEYSYM[:HOLD] that xdotool sends
  % to the display DELAY seconds after the start of the demo, for demos that
  % end only on a key press. The key stays down for HOLD seconds, 0.2 by
  % default; use more for demos that poll the keyboard only once a second.
  % The last key repeats until the demo ends. An empty call means "skip";
  % keys then holds the reason.
  movie = '[PsychtoolboxRoot ''PsychDemos/MovieDemos/DualDiscs.mov'']';
  list = {
    % No window.
    'PsychtoolboxVersion', 'disp(PsychtoolboxVersion)', 30, ''
    'WaitSecs', 't = GetSecs; WaitSecs(0.5); d = GetSecs - t, assert(d >= 0.5 && d < 0.75)', 30, ''
    'PsychHIDDevices', 'd = PsychHID(''Devices''); printf(''%d devices\n'', numel(d)); assert(numel(d) > 0)', 30, ''
    'KbCheck', 'assert(~KbCheck)', 30, ''
    'PsychPortAudioGetDevices', 'd = PsychPortAudio(''GetDevices''); printf(''%d audio devices\n'', numel(d)); assert(numel(d) > 0)', 30, ''
    'BasicSoundOutputDemo', 'BasicSoundOutputDemo(1)', 30, '3:space:1.5'
    'Oneliners_Test_Structs', 'assert(Oneliners_Test_Structs)', 30, ''
    'Files_Test_LineTerminators', 'assert(Files_Test_LineTerminators)', 30, ''
    'CIEXYZPhysTest', 'CIEXYZPhysTest', 30, ''
    % Onscreen and offscreen windows, OpenGL, text, shaders.
    'DriftDemo', 'DriftDemo', 60, ''
    'FastNoiseDemo', 'FastNoiseDemo', 30, ''
    'FastFilteredNoiseDemo', 'FastFilteredNoiseDemo', 30, '3:Escape'
    'AlphaAdditionTest', 'assert(~AlphaAdditionTest)', 30, ''
    'AlphaBlendSettingTest', 'assert(~AlphaBlendSettingTest)', 30, ''
    'TextInOffscreenWindowTest', 'TextInOffscreenWindowTest', 30, ''
    'DrawTextFontSwitchSpeedTest', 'DrawTextFontSwitchSpeedTest', 30, ''
    'DrawHighQualityUnicodeTextDemo', 'DrawHighQualityUnicodeTextDemo', 30, '2:Return'
    'HelloWorldDemo', 'HelloWorldDemo', 30, '2:Return'
    'HelloGaborArrayDemo', 'HelloGaborArrayDemo', 30, '2:Return'
    'GratingDemo', 'GratingDemo', 30, '3:Escape'
    'ExpandingRingsDemo', 'ExpandingRingsDemo', 30, '3:Escape'
    'ClutAnimDemo', 'ClutAnimDemo', 60, '3:Escape'
    % Selects the gnuplot graphics toolkit, which octave-psychtoolbox puts on
    % PATH for it. Runs a fixed number of frames; the limit covers slow hosts.
    'ProceduralGaborDemo', 'ProceduralGaborDemo', 90, '5:Escape'
    % GStreamer movie playback and writing.
    'SimpleMovieDemo', ['SimpleMovieDemo(' movie ')'], 30, ''
    'LosslessMovieWritingTest', ['s = evalc(''LosslessMovieWritingTest''); disp(s);' ...
                                 ' assert(any(strfind(s, ''are identical'')))'], 60, ...
                                '4:Return'
    % Not run in the VM test.
    'ImagingStereoDemo', '', 0, 'does not end within 15 s, also not on Escape'
    'MandelbrotDemo', '', 0, 'waits for a mouse click'
    'AlphaImageDemo', '', 0, 'ends only on a mouse click'
    'GetSecsTest', '', 0, 'upstream supports it only on Windows'
  };
end

function list = read_list(file)
  list = cell(0, 4);
  fid = fopen(file, 'r');
  if fid < 0
    error('cannot open %s', file);
  end
  line = fgetl(fid);
  while ischar(line)
    f = strsplit(line, "\t", "CollapseDelimiters", false);
    if ~isempty(strtrim(line)) && line(1) ~= '#'
      f(end+1:4) = {''};
      list(end+1, :) = {f{1}, f{2}, str2double(f{3}), f{4}};
    end
    line = fgetl(fid);
  end
  fclose(fid);
end

function s = demo_secs()
  s = time() - str2double(getenv('PTB_SWEEP_T0'));
end

% Runs in the child. A function, not the script workspace, so that demos
% that are scripts and call "clear all" do not wipe the state of the sweep.
function child_run(startup, call, ready)
  % The child reads the site octaverc, like the Octave of the users. That of
  % octave-psychtoolbox already puts PTB on the path.
  if isempty(which('PsychtoolboxVersion'))
    source(startup);
  end
  % Starts the key sender and the time limit. The start time goes into the
  % environment, because demos that are scripts may "clear" this workspace.
  setenv('PTB_SWEEP_T0', sprintf('%.3f', time()));
  fclose(fopen(ready, 'w'));
  try
    Screen('Preference', 'SkipSyncTests', 2);
    Screen('Preference', 'Verbosity', 2);
    eval([call ';']);
    printf('\nSWEEPCHILD ok %.1f\n', demo_secs());
  catch err
    msg = strtrim(strsplit(err.message, "\n"){1});
    printf('\nSWEEPCHILD fail %.1f %s\n', demo_secs(), msg);
  end
  try
    sca;
  catch
  end
  try
    Screen('CloseAll');
  catch
  end
end

function [cmd, release] = key_cmd(keys)
  % Shell commands that send the keys in order, with sleeps in between, and
  % commands that release them. Each key stays down for HOLD seconds, 0.2 by
  % default: KbCheck loops poll once per frame and KbWait every few ms, so a
  % plain "xdotool key" tap is sometimes missed. After the schedule, the last
  % key repeats every 1.5 s until the demo ends, in case one was missed.
  cmd = '';
  release = '';
  t = 0;
  for k = strsplit(strtrim(keys), ' ')
    if isempty(k{1})
      continue;
    end
    p = strsplit(k{1}, ':');
    d = str2double(p{1});
    key = p{2};
    hold = 0.2;
    if numel(p) >= 3
      hold = str2double(p{3});
    end
    press = sprintf(['echo "$(date +%%T.%%N) %s"; xdotool keydown %s; sleep %g;' ...
                     ' xdotool keyup %s; '], key, key, hold, key);
    cmd = [cmd sprintf('sleep %g; ', max(0, d - t)) press];
    t = d + hold;
    if isempty(strfind(release, [' ' key ';']))
      release = [release sprintf('xdotool keyup %s; ', key)];
    end
  end
  if ~isempty(cmd)
    cmd = [cmd sprintf('while :; do sleep 1.5; %s done; ', press)];
  end
end

function [status, msg, secs, log, sent] = parent_run(script, startup, workdir, e, scale)
  [name, call, limit, keys] = e{:};
  limit = limit * scale;
  start_limit = 120 * scale;
  base = fullfile(workdir, name);
  logfile = [base '.log'];
  ready = [base '.ready'];
  expired = [base '.timeout'];
  keylog = [base '.keys'];
  setenv('PTB_SWEEP_CALL', call);
  setenv('PTB_SWEEP_READY', ready);
  % The watchdog gives the child start_limit seconds to start the demo, then
  % applies the limit from the start of the demo. The octave-cli wrappers
  % exec, so $c is the Octave process.
  wait_ready = sprintf(['n=0; while [ ! -e "%s" ] && [ $n -lt %d ]; do' ...
                        ' sleep 0.2; n=$((n+1)); done; '], ready, round(start_limit / 0.2));
  sh = { ...
    sprintf(['octave-cli --no-init-file -q "%s" "%s" --child' ...
             ' </dev/null >"%s" 2>&1 & c=$!'], script, startup, logfile), ...
    sprintf(['(%s [ -e "%s" ] && sleep %g; touch "%s"; kill $c; sleep 5;' ...
             ' kill -9 $c) & w=$!'], wait_ready, ready, limit, expired)};
  [send, release] = key_cmd(keys);
  if ~isempty(send)
    sh{end+1} = sprintf('(%s %s) >"%s" 2>&1 & k=$!', wait_ready, send, keylog);
  else
    sh{end+1} = 'k=';
  end
  % Stop the watchdog and the key sender when the demo ends early, so that
  % they do not hit the next demo. A key that is still held would block the
  % KbReleaseWait of the next demo. The sleep lets an xdotool call that the
  % killed sender started finish first.
  sh{end+1} = sprintf(['wait $c; rc=$?; kill $w $k 2>/dev/null;' ...
                       ' [ -n "$k" ] && { sleep 0.3; %s} >/dev/null 2>&1; exit $rc'], release);
  t0 = tic;
  rc = system(sprintf('cd "%s" || exit 1; %s', workdir, strjoin(sh, '; ')));
  secs = toc(t0);
  log = fileread(logfile);
  sent = '';
  if exist(keylog, 'file')
    sent = strtrim(fileread(keylog));
  end
  m = regexp(log, 'SWEEPCHILD (ok|fail) ([0-9.]+) ?([^\n]*)', 'tokens');
  if ~isempty(m)
    secs = str2double(m{end}{2});
  end
  if exist(expired, 'file') && ~exist(ready, 'file')
    status = 'fail';
    msg = sprintf('demo did not start within %g s', start_limit);
  elseif exist(expired, 'file')
    status = 'fail';
    secs = limit;
    msg = sprintf('timeout after %g s', limit);
  elseif rc > 128
    status = 'fail';
    msg = sprintf('killed by signal %d', rc - 128);
  elseif isempty(m)
    status = 'fail';
    msg = sprintf('exit status %d without result', rc);
  else
    status = m{end}{1};
    msg = strtrim(m{end}{3});
    if rc ~= 0 && strcmp(status, 'ok')
      status = 'fail';
      msg = sprintf('exit status %d', rc);
    end
  end
end

% A demo killed by the time limit would otherwise write octave-workspace.
sigterm_dumps_octave_core(false);
crash_dumps_octave_core(false);

args = argv();
startup = args{1};
if numel(args) >= 2 && strcmp(args{2}, '--child')
  child_run(startup, getenv('PTB_SWEEP_CALL'), getenv('PTB_SWEEP_READY'));
  exit(0);
end

more off;
if numel(args) >= 2
  list = read_list(args{2});
else
  list = sweep_list();
end
verbose = strcmp(getenv('PTB_SWEEP_VERBOSE'), '1');
scale = str2double(getenv('PTB_SWEEP_TIME_SCALE'));
if ~(scale > 0)
  scale = 1;
end
script = mfilename('fullpathext');
workdir = tempname();
mkdir(workdir);
printf('SWEEP-START %d entries, time scale %g, logs in %s\n', rows(list), scale, workdir);
counts = struct('ok', 0, 'fail', 0, 'skip', 0);
t0 = tic;
for i = 1:rows(list)
  e = list(i, :);
  if isempty(e{2})
    status = 'skip'; secs = 0; msg = e{4};
  else
    [status, msg, secs, log, sent] = parent_run(script, startup, workdir, e, scale);
  end
  counts.(status) += 1;
  printf('SWEEP %s %s %.1f %s\n', e{1}, status, secs, msg);
  if strcmp(status, 'fail') || (verbose && ~strcmp(status, 'skip'))
    lines = strsplit(strtrim(log), "\n");
    printf('  | %s\n', lines{max(1, end-14):end});
    if ~isempty(sent)
      printf('  | keys sent at: %s\n', strjoin(strsplit(sent, "\n"), ', '));
    end
  end
  fflush(stdout);
end
printf('SWEEP-DONE ok=%d fail=%d skip=%d total=%.0f s\n', ...
       counts.ok, counts.fail, counts.skip, toc(t0));

# Lab Streaming Layer in each environment that experiments run in: PsychoPy
# 2026 (psychopy-env), PsychoPy 2024 (psychopy-2024-env) and Octave with
# Psychtoolbox (octave-psychtoolbox). Each one creates an outlet, resolves
# it, and receives one marker through an inlet. The build sandbox has only
# the loopback interface and no multicast, so this shows that a recorder on
# the same machine (for example LabRecorder) finds the stream. It does not
# test discovery across the lab network.
{
  runCommand,
  writeText,
  psychopy-env,
  psychopy-2024-env,
  octave-psychtoolbox,
}:

let
  pyScript = writeText "lsl-check.py" ''
    import sys
    import time

    import pylsl

    print(sys.version)
    print("pylsl", pylsl.__version__, "liblsl", pylsl.library_version())
    info = pylsl.StreamInfo("NixCheck", "Markers", 1, 0, "string", "psych-nix-lsl-check")
    outlet = pylsl.StreamOutlet(info)
    found = pylsl.resolve_byprop("source_id", "psych-nix-lsl-check", timeout=10)
    assert len(found) == 1, "the outlet did not resolve"
    inlet = pylsl.StreamInlet(found[0])
    inlet.open_stream(timeout=10)
    # The outlet drops samples pushed before the inlet connects.
    time.sleep(0.5)
    outlet.push_sample(["hello"])
    sample, ts = inlet.pull_sample(timeout=10)
    assert sample == ["hello"], f"unexpected sample {sample}"
    print("LSL_OK")
  '';

  octScript = writeText "lsl-check.m" ''
    lib = lsl_loadlib();
    printf('liblsl %d\n', lsl_library_version(lib));
    info = lsl_streaminfo(lib, 'NixCheck', 'Markers', 1, 0, 'cf_string', 'psych-nix-lsl-check');
    outlet = lsl_outlet(info);
    found = lsl_resolve_byprop(lib, 'source_id', 'psych-nix-lsl-check', 1, 10);
    assert(numel(found) == 1, 'the outlet did not resolve');
    inlet = lsl_inlet(found{1});
    inlet.open_stream(10);
    pause(0.5);
    outlet.push_sample({'hello'});
    [sample, ts] = inlet.pull_sample(10);
    assert(isequal(sample, {'hello'}), 'the sample did not arrive');
    disp('LSL_OK');
  '';
in
runCommand "psych-nix-lsl-check" { } ''
  export HOME=$TMPDIR
  # liblsl logs every failed multicast join. Show the log only on failure.
  check() {
    name=$1
    shift
    echo "== $name"
    if ! "$@" > $TMPDIR/$name.log 2>&1 || ! grep -q LSL_OK $TMPDIR/$name.log; then
      cat $TMPDIR/$name.log
      echo "error: LSL check failed for $name" >&2
      exit 1
    fi
    grep -v 'INFO|\|WARN|\|ERR|' $TMPDIR/$name.log | grep -v '^$'
  }

  check psychopy-2026 ${psychopy-env}/bin/python ${pyScript}
  check psychopy-2024 ${psychopy-2024-env}/bin/python ${pyScript}
  # The full octaverc, as a user gets it: it sources the PTB startup and adds
  # the LSL bindings.
  check octave ${octave-psychtoolbox}/bin/octave-cli --quiet ${octScript}

  touch $out
''

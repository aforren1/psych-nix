# Runs PsychoPy's own test suite against psychopy-env, with the selection that
# upstream CI uses on Ubuntu, under Xvfb and Mesa llvmpipe in the build
# sandbox. There is no network, no audio device, and no realtime priority.
#
# Upstream CI is green on the tag, but this environment is not CI, so some
# tests fail for known reasons (see expectedFailures). The check fails only on
# a regression: a failure that is not in expectedFailures, or fewer passes
# than minPassed.
#
# To update the baseline after a PsychoPy or nixpkgs bump:
#   1. nix build .#checks.x86_64-linux.psychopy-pytest --keep-failed
#      (or set minPassed = 0 and expectedFailures = all failures temporarily).
#   2. Read summary.txt in the output or in the kept build directory. It lists
#      the unexpected failures, the expected failures that now pass, and the
#      pass count.
#   3. Remove the IDs that now pass, add new IDs only with a reason, and set
#      minPassed to the new pass count.
{
  lib,
  runCommand,
  writeText,
  xvfb-run,
  mesa,
  psychopy-env,
  psychopyPython,
}:

let
  inherit (psychopyPython.pkgs) psychopy;

  # The test dependencies from upstream's `tests` extra that the suite
  # imports, plus pytest-timeout. Upstream CI also installs javascripthon
  # (metapensiero.pj) before the tests; without it all PsychoJS transpiler
  # tests fail. mock is left out as in upstream CI: with mock installed,
  # test_getCRSPhotometers runs and fails on a stale assertion.
  testEnv = psychopy-env.override {
    extraPackages = ps: [
      ps.javascripthon
      ps.pytest
      ps.pytest-asyncio
      ps.pytest-timeout
      ps.xmlschema
    ];
  };

  # Upstream CI's marker selection.
  markers = "not needs_sound and not needs_wx and not needs_qt and not needs_pygame and not emulator";

  # Paths are relative to the copied psychopy/tests directory.
  ignore = [
    # Imports wx at module level; psychopy-env does not include wxPython.
    "test_gui/test_DlgFromDictWx.py"
  ];

  deselect = [
    # The PsychHID keyboard queue thread fails to get realtime priority (no
    # CAP_SYS_NICE or RLIMIT_RTPRIO in the sandbox; upstream CI uses setcap)
    # and then prints without the GIL, which kills the interpreter with
    # SIGSEGV. That ends the whole pytest session.
    "test_experiment/test_components/test_KeyboardComponent.py::TestKeyboardComponent"
    # Posts codecov.yml to codecov.io. Needs the network and a Git checkout.
    "test_codecov.py::test_valid_yaml"
    # Need the git binary, a Git checkout of PsychoPy and the network.
    "test_tools/test_versionchooser.py::TestVersionChooser::test_same_version"
    "test_tools/test_versionchooser.py::TestVersionChooser::test_version_folder"
    "test_tools/test_versionchooser.py::TestGitInstallation::test_git_installed"
    "test_tools/test_versionchooser.py::TestGitClone::test_git_can_clone_repo"
    # Fetch psychopy.org and Google Fonts.
    "test_plugins/test_plugin_stubs.py::test_plugin_stub_links"
    "test_visual/test_textbox.py::test_font_manager"
    "test_visual/test_textbox.py::Test_textbox::test_glyph_rendering"
    "test_visual/test_textbox.py::Test_uax14_textbox::test_glyph_rendering"
  ];

  # JUnit IDs (classname::name) that fail in this environment.
  expectedFailures = [
    # Writes Darwin.spec into psychopy/preferences, which is read-only in the
    # store.
    "psychopy.tests.test_preferences.test_prefs::testGenerateSpec"

    # The experiment subprocess creates a PsychHID keyboard and dies with
    # SIGSEGV, for the same reason as the deselected keyboard tests.
    "psychopy.tests.test_experiment.test_components.test_ButtonBoxComponent.TestButtonBoxComponent::test_values"
    "psychopy.tests.test_experiment.test_loops.TestLoops::test_output_length"
    "psychopy.tests.test_experiment.test_loops.TestLoops::test_current_loop_attr"

    # Small glyph raster differences against upstream's screenshots (RMS
    # just over the threshold): system FreeType versus the one in upstream's
    # freetype-py wheel.
    "psychopy.tests.test_visual.test_textbox.Test_textbox::test_formatting"
    "psychopy.tests.test_visual.test_textbox.Test_uax14_textbox::test_formatting"
    "psychopy.tests.test_visual.test_textbox.Test_textbox::test_pos_size"
    "psychopy.tests.test_visual.test_textbox.Test_textbox::test_ori"
    "psychopy.tests.test_visual.test_textbox.Test_textbox::test_alignment"
    "psychopy.tests.test_visual.test_textbox.Test_textbox::test_speechpoint"
  ];

  # Passed tests in the last recorded sandbox run (PsychoPy 2026.2.4,
  # nixos-26.05).
  minPassed = 812;

  expectedFailuresFile = writeText "psychopy-expected-failures" (lib.concatLines expectedFailures);

  checkScript = writeText "check-junit.py" ''
    import sys
    import xml.etree.ElementTree as ET

    junit, expectedFile, minPassed, summary = sys.argv[1:5]
    expected = {l.strip() for l in open(expectedFile) if l.strip()}
    passed, failed, skipped = [], [], []
    for tc in ET.parse(junit).getroot().iter("testcase"):
        tid = f'{tc.get("classname")}::{tc.get("name")}'
        tags = {child.tag for child in tc}
        if tags & {"failure", "error"}:
            failed.append(tid)
        elif "skipped" in tags:
            skipped.append(tid)
        else:
            passed.append(tid)
    unexpected = sorted(set(failed) - expected)
    fixed = sorted(expected & set(passed))
    lines = [
        f"passed {len(passed)} (minimum {minPassed})",
        f"failed {len(failed)} (expected {len(expected)})",
        f"skipped {len(skipped)}",
        "",
        "unexpected failures:",
        *unexpected,
        "",
        "expected failures that passed (remove them from expectedFailures):",
        *fixed,
    ]
    open(summary, "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    sys.exit(1 if unexpected or len(passed) < int(minPassed) else 0)
  '';
in
runCommand "psychopy-pytest-${psychopy.version}"
  {
    nativeBuildInputs = [
      mesa.llvmpipeHook
      xvfb-run
    ];

    # Keeps psychopy from adding a user plugin directory to sys.path.
    PSYCHOPYNOPACKAGES = "1";
    # Any value makes systemtools.isVM_CI() report a CI VM, so the suite
    # skips what upstream skips on CI: timing, refresh rate and gamma tests.
    GITHUB_WORKFLOW = "nix-sandbox";

    meta = {
      description = "PsychoPy's upstream test suite run against psychopy-env";
      platforms = [ "x86_64-linux" ];
    };
  }
  ''
    export HOME=$TMPDIR
    build=$PWD

    # The suite writes into its own directory (tests/fails, data outputs), so
    # run a writable copy of psychopy/tests inside a symlinked copy of the
    # installed package, and put that copy first on sys.path.
    src=$(readlink -f ${testEnv}/${psychopyPython.sitePackages}/psychopy)
    mkdir -p work/psychopy
    for f in "$src"/*; do
      [ "$(basename "$f")" = tests ] || ln -s "$f" work/psychopy/
    done
    cp -r --no-preserve=mode "$src"/tests work/psychopy/tests
    export PYTHONPATH=$build/work
    # --deselect matches node IDs, which are relative to the rootdir.
    cd work

    args=(
      -c ${psychopy.src}/pytest.ini
      --rootdir .
      -p no:cacheprovider
      -q
      -rfE
      --disable-warnings
      --timeout 300
      --junitxml "$build/junit.xml"
      -m "${markers}"
      ${lib.concatMapStringsSep " " (p: "--ignore psychopy/tests/${p}") ignore}
      ${lib.concatMapStringsSep " " (p: "--deselect psychopy/tests/${p}") deselect}
    )

    start=$SECONDS
    rc=0
    xvfb-run -a -s "-screen 0 1280x1024x24" \
      ${testEnv}/bin/python -m pytest "''${args[@]}" psychopy/tests > "$build/pytest.log" 2>&1 || rc=$?
    cd "$build"
    echo "pytest exit code $rc after $((SECONDS - start)) s"
    grep -v -e DEBUG -e 'GameMode ERROR' pytest.log | tail -n 60

    # Exit code 1 means some tests failed; anything else means pytest itself
    # did not finish (crash, interrupt, usage error, nothing collected).
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
      exit 1
    fi
    ${testEnv}/bin/python -I ${checkScript} junit.xml ${expectedFailuresFile} ${toString minPassed} summary.txt

    mkdir -p $out
    cp junit.xml summary.txt pytest.log $out/
  ''

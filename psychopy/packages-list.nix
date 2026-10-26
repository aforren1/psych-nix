# Python packages in every PsychoPy interpreter: the library, the plugins the
# lab uses, and Lab Streaming Layer. Shared by env.nix and app.nix so the GUI
# runs experiments with the same packages as the headless environment.
# psychopy-glfw is left out: its only release (0.0.2) predates the 2026
# backend API, so winType glfw fails inside Window creation.
ps: with ps; [
  # Builder's PsychoJS export translates Python code components to JavaScript.
  javascripthon
  psychopy
  psychopy-legacy
  psychopy-mri-emulator
  psychopy-sounddevice
  psychopy-visionscience
  pylsl
]

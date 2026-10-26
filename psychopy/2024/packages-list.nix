# Python packages in every PsychoPy 2024 interpreter. Like
# ../packages-list.nix, but 2024.2.4 has the sounddevice backend built in, so
# it takes sounddevice itself instead of the psychopy-sounddevice plugin.
ps: with ps; [
  # Builder's PsychoJS export translates Python code components to JavaScript.
  javascripthon
  psychopy
  psychopy-legacy
  psychopy-mri-emulator
  psychopy-visionscience
  pylsl
  sounddevice
]

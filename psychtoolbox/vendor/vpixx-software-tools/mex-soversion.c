/*
 * Intentionally empty. Octave 10.2 and later refuse to load a .mex file
 * that does not export __octave_mex_soversion__, and VPixx's Datapixx.mex
 * (built with Octave 5.2) predates that symbol. `mkoctfile --mex` adds the
 * symbol, with the value of the Octave that runs it, to everything it links,
 * so linking this file gives a library that contains only that symbol.
 * Datapixx.mex gets the library as DT_NEEDED: Octave looks the symbol up
 * with dlsym() on the mex handle, which also searches its dependencies.
 */

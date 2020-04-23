 ising

A sequencer for Monome norns based on a simple [2D Ising model](https://en.wikipedia.org/wiki/Ising_model).

Ising is a modified version of [zellen](https://github.com/sarweiler/zellen), a sequencer based on [Conway's Game of Life](https://en.wikipedia.org/wiki/Conway%27s_Game_of_Life).

## Usage

* Grid: enter/modify cell pattern
* KEY2: play/pause current generation (semi-manual mode), advance sequence (manual mode), play/pause sequence (automatic mode)
* KEY3: advance generation
* hold KEY1 and press KEY3: erase the board
* ENC1: set speed (bpm)
* ENC2: set play mode (see below)
* ENC3: set play direction (see below)
* hold KEY3 + ENC3: time jog
* hold KEY1 + ENC2: change temperature
* hold KEY1 + ENC3: change coupling constant

### Play Modes

Set the play mode with ENC2.
* spin up: Play a note for every cell that has spin up
* spin down: Play a note for every cell that has spin down
* spin flip (default): Play a note for every cell that flipped its spin since the last generation

### Play Direction

Set the play direction with ENC3.
* up: Cells on grid are played from top left (lowest note) to bottom right (highest note).
* down: Cells on grid are played from bottom right (highest note) to top left (lowest note).
* random: Cells are played in random order. The randomized order will be stable for a generation and will be re-randomized for every new generation.
* drunken up: Like up, but decides for each step randomly if it goes up or down.
* drunken down: Like down, but decides for each step randomly if it goes up or down.

### Sequencing modes
Set the sequencing mode in the parameters screen. Default is semi-automatic.
* manual: Press KEY2 to play the next step in the sequence for a single generation.
* semi-automatic: Plays the sequence for a single generation (and loops it if "loop seq in semi-auto mode" is enabled).
* automatic: Like semi-automatic, but automatically calculates the next generation and plays it (default).

## Crow support

Ising supports CV out via [Crow](https://monome.org/docs/crow/). Crow CV output can be configured in Norns's parameters menu.

Crow configuration for Ising:
* Input 1: Clock
* Input 2: CV offset
* Output 1: CV
* Output 2: Trigger
* Output 3: CV 2
* Output 4: Clock

CV offset (input 2) can be set to pre or post quantization in the parameters menu.

CV 2 is, just like the main sequence, a CV derived from the current play position on the board. The CV can be calculated with these methods (configurable in the parameters menu):
* x/y (default)
* x%y
* x+y (same as the main sequence)

## Just Friends support (via ii)

Ising supports playing notes on [Mannequins Just Friends](https://www.whimsicalraps.com/products/just-friends) via Crow and a ii connection. The note value can be determined with the same methods as the CV 2 value for Crow (configurable in the parameters menu).

## MIDI
Set the MIDI channel (default: 1), MIDI velocity (default: 100), and MIDI clock in the parameters screen.

## More Parameters
There is lots more to discover in the parameters screen, like root note, scale, and flip offset.

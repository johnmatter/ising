-- constants
local config = {
  GRID = {
    SIZE = {
      X = 16, -- default, will be replaced with g.cols
      Y = 8 -- default, will be replaced with g.rows
    },
    LEVEL = {
      SPIN_DOWN = 0,
      SPIN_UP = 6, -- this should be an even number for get_spin() to work
      ACTIVE = 15
    }
  },
  MUSIC = {
    NOTE_NAMES_OCTAVE = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"},
    NOTES = {}, -- constructed on init
    NOTE_NAMES = {}, -- constructed on init
    SCALE_NAMES = {}, -- constructed on init
    SCALE_LENGTH = 32
  },
  SEQ = {
    MODES = {
      "manual",
      "semi-automatic",
      "automatic"
    },
    PLAY_DIRECTIONS = {
      "up",
      "down",
      "random",
      "drunken up",
      "drunken down"
    },
    PLAY_MODES = {
      "spin up",
      "spin down",
      "spin flip"
    },
  },
  CROW = {
    SUPPORT_MODES = {
      "x/y",
      "x%y",
      "x+y"
    }
  },
  SYNTHS = {
    "internal",
    "midi",
    "both"
  },
}

return config

-- ising v1.0.0
--
-- sequencer based on
-- a simple 2D Ising model;
-- based on zellen
--
-- grid: enter cell pattern
--
-- KEY2: play/pause sequence
-- KEY3: advance generation
-- hold KEY1 + press KEY3:
--   delete board
-- hold KEY1 + press KEY2:
--   save parameters
--
-- ENC1: set speed (bpm)
-- ENC2: set play mode
-- ENC3: set play direction
--
-- hold KEY3 + ENC3: time jog
--
-- see the parameters screen
-- for more settings.

engine.name = "PolyPerc"

local helpers = include("lib/helpers")
local cs = include("lib/crowservice")
local config = include("lib/config")
local state = include("lib/state")

--borrowed circular linked list library we dont use the circular part... yet.
local list = include("lib/linkedlist")

local music = require("musicutil")
local beatclock = require("beatclock")
local er = require("er")
local g = grid.connect()

-- determine grid size
config.GRID.SIZE.X = g.cols
config.GRID.SIZE.Y = g.rows

-- beatclock
local clk = beatclock.new()
local midi_out = midi.connect(1)
local midi_in = midi.connect(1)
midi_in.event = function(data) clk:process_midi(data) end

-- note on/off
local function note_on(note, support_note)
  local note_num = math.min((note + state.note_offset), 127)
  local synth_modes = {
    internal = params:get("synth_internal") == 1,
    midi = params:get("synth_midi") == 1,
    crow = params:get("synth_crow") == 1
  }
  if(synth_modes.internal) then
    local amp = params:get("amp")
    local amp_variance = math.random(params:get("midi_velocity_var")) / 100
    if(math.random(2) > 1) then
      amp = math.min(amp + amp_variance, 1.0)
    else
      amp = math.max(amp - amp_variance, 0)
    end
    engine.amp(amp)
    engine.hz(music.note_num_to_freq(note_num))
  end
  if(synth_modes.midi) then
    local velocity_variance = math.random(params:get("midi_velocity_var"))
    local velocity = params:get("midi_note_velocity")
    if(math.random(2) > 1) then
      velocity = math.min(velocity + velocity_variance, 127)
    else
      velocity = math.max(velocity - velocity_variance, 0)
    end
    midi_out:note_on(note_num, velocity, params:get("midi_channel"))
  end

  if(synth_modes.crow) then
    local crow_octave_offset = params:get("crow_octave_offset")
    local crow_note_divider = params:get("crow_note_divider")
    local crow_support_mode_note_offset = params:get("crow_support_mode_note_offset")
    local crow_cv_offset = state.crow.cv_offset
    local note_offset = state.note_offset/crow_note_divider
    if(params:get("crow_cv_offset") == 1) then
      local note_with_offset = note + (math.floor(crow_cv_offset * crow_note_divider))
      cr:set_cv(1, note_with_offset/crow_note_divider + note_offset + crow_octave_offset)
    else
      cr:set_cv(1, note/crow_note_divider + crow_cv_offset + note_offset + crow_octave_offset)
    end
    cr:execute_action(2)
    cr:set_cv(3, support_note/crow_note_divider + crow_support_mode_note_offset/crow_note_divider + crow_octave_offset)
  end
  table.insert(state.active_notes, note_num)
end

local function notes_off()
  for i=1,#state.active_notes do
    midi_out:note_off(state.active_notes[i], 0, params:get("midi_channel"))
  end
  state.active_notes = {}
end

-- game logic
local function x_coord_wrap(x)
  x_mod = (x == 0 or x == config.GRID.SIZE.X) and config.GRID.SIZE.X or math.max(1, x % config.GRID.SIZE.X)
  return (x == 0 or x == config.GRID.SIZE.X) and config.GRID.SIZE.X or math.max(1, x % config.GRID.SIZE.X)
end

local function y_coord_wrap(y)
  y_mod = (y == 0 or y == config.GRID.SIZE.Y) and config.GRID.SIZE.Y or math.max(1, y % config.GRID.SIZE.Y)
  return (y == 0 or y == config.GRID.SIZE.Y) and config.GRID.SIZE.Y or math.max(1, y % config.GRID.SIZE.Y)
end

local function is_spin_up(x, y)
  return state.board.current[x_coord_wrap(x)][y_coord_wrap(y)] == config.GRID.LEVEL.SPIN_UP
end

local function is_spin_down(x, y)
  return state.board.current[x_coord_wrap(x)][y_coord_wrap(y)] == config.GRID.LEVEL.SPIN_DOWN
end

local function spin_flipped(x, y)
  local spin_diff = state.board.current[x_coord_wrap(x)][y_coord_wrap(y)] - state.board.the_past.value[x_coord_wrap(x)][y_coord_wrap(y)]
  return (spin_diff ~= 0)
end


local function get_spin(b, x, y)
  -- Spin for the energy calculation should be plus or minus one.
  -- Spin down currently has a brightness of 0.
  -- Let N be config's spin up brightness. Then,
  -- spin down : (0 - N/2)/(N/2) = (-6)/6 = -1
  -- spin up   : (N - N/2)/(N/2) = (+6)/6 = +1
  local spin = b[x_coord_wrap(x)][y_coord_wrap(y)] - (config.GRID.LEVEL.SPIN_UP/2)
  spin = spin / (config.GRID.LEVEL.SPIN_UP/2)
  return spin
end

local function get_J(x1,y1,x2,y2)
  -- This is currently just a constant.
  -- TODO: implement a distance-dependent coupling
  return params:get("J")
end

local function get_energy(b, x, y)
  local energy = 0
  -- find neighbors' positions based on boundary conditions
  if (params:get("wrap_mode") == 1) then -- periodic BCs
    if (x == 1) then
      left = config.GRID.SIZE.X
    else
      down = x-1
    end
    if (x == config.GRID.SIZE.X) then
      right = 1
    else
      right = x+1
    end
    if (y == 1) then
      down = config.GRID.SIZE.Y
    else
      down = y-1
    end
    if (y == config.GRID.SIZE.Y) then
      up = 1
    else
      up = y+1
    end
  else -- closed BCs
    -- an index of -1 indicates we're at the boundary
    -- These nonexistent neighbors will be ignored in the energy calculation
    if (x == 1) then
      left = -1
    else
      down = x-1
    end
    if (x == config.GRID.SIZE.X) then
      right = -1
    else
      right = x+1
    end
    if (y == 1) then
      down = -1
    else
      down = y-1
    end
    if (y == config.GRID.SIZE.Y) then
      up = -1
    else
      up = y+1
    end
  end
  -- calculate energy
  if (left>0) then
    energy = energy - get_J(x,y,left,y)  * get_spin(b,x,y) * get_spin(b,left,y)
  end
  if (right>0) then
    energy = energy - get_J(x,y,right,y) * get_spin(b,x,y) * get_spin(b,right,y)
  end
  if (up>0) then
    energy = energy - get_J(x,y,x,up)    * get_spin(b,x,y) * get_spin(b,x,up)
  end
  if (down>0) then
    energy = energy - get_J(x,y,x,down)  * get_spin(b,x,y) * get_spin(b,x,down)
  end
  return energy
end

local function flip_test(b,x,y)
  flipped = false
  -- dE is the change in energy we would see from a flip
  dE = -2*get_energy(b,x,y)
  -- flip because it yields lower energy?
  if (dE<0) then
    flipped = true
  end
  -- flip because thermal excitation?
  if (params:get("temperature") == 0) then -- edge case T=0 never flips
    flipped = false
  end
  if (math.random() < math.exp(-dE/params:get("temperature"))) then
    flipped = true
  end
  return flipped
end

local function collect_playable_cells()
  state.playable_cells = {}
  local mode = params:get("play_mode")
  for x=1,config.GRID.SIZE.X do
    for y=1,config.GRID.SIZE.Y do
      if (is_spin_up(x, y) and mode == 1) then
        table.insert(state.playable_cells, {
          ["x"] = x,
          ["y"] = y
        })
      end
      if (is_spin_down(x, y) and mode == 2) then
        table.insert(state.playable_cells, {
          ["x"] = x,
          ["y"] = y
        })
      end
      if (spin_flipped(x, y) and mode == 3) then
        table.insert(state.playable_cells, {
          ["x"] = x,
          ["y"] = y
        })
      end
    end
  end

  local play_direction = params:get("play_direction")
  if(play_direction == 2 or play_direction == 5) then
    state.playable_cells = helpers.table.reverse(state.playable_cells)
  elseif(play_direction == 3) then
    state.playable_cells = helpers.table.shuffle(state.playable_cells)
  end
end

local function do_the_time_warp()
  state.board.current = helpers.clone_board(state.board.the_past.value) --set the board equal to the first entry in the past (last generation)
  state.board.the_past = list.eraseBackward(state.board.the_past) --remove the future. Because the future is deterministic.
  state.play_pos = 1
  collect_playable_cells()
  grid_redraw()
end

local function generation_step()
  state.board.the_past = list.insert(state.board.the_past, helpers.clone_board(state.board.current))
  notes_off()
  local board_c = helpers.clone_board(state.board.current)
  for x=1,config.GRID.SIZE.X do
    for y=1,config.GRID.SIZE.Y do
      if (flip_test(board_c, x, y)) then
        if (is_spin_up(x,y)) then
          board_c[x][y] = config.GRID.LEVEL.SPIN_DOWN
        end
        if (is_spin_down(x,y)) then
          board_c[x][y] = config.GRID.LEVEL.SPIN_UP
        end
      end
    end
  end
  state.board.current = board_c
  state.play_pos = 1
  collect_playable_cells()
  grid_redraw()
end


-- sequencing
local function init_position()
  state.seq.position = {
    ["x"] = -1,
    ["y"] = -1
  }
end

local function reset_sequence()
  local seq_mode = params:get("seq_mode")
  state.play_pos = 1
  if (params:get("euclid_reset") == 1) then
    state.beat_step = 1
  end

  if(seq_mode == 3 or (seq_mode == 2 and params:get("loop_semi_auto_seq") == 1)) then
    if(seq_mode == 3) then
      init_position()
      generation_step()
    end
    if(not state.seq_running) then
      if(params:get("crow_clock") == 1) then
        clk:start()
      end
      state.seq_running = true
      state.show_playing_indicator = true
    end
  else
    clk:stop()
    state.seq_running = false
    state.show_playing_indicator = false
  end
end

local function play_seq_step()

  local play_direction = params:get("play_direction")
  local seq_mode = params:get("seq_mode")
  notes_off()

  cr:execute_action(4)

  state.show_playing_indicator = not state.show_playing_indicator

  local beat_seq_lengths = #state.beats

  if (state.beats[(state.beat_step % beat_seq_lengths) + 1] or seq_mode == 1) then
    if (state.play_pos <= #state.playable_cells) then
      state.seq.position = state.playable_cells[state.play_pos]
      local midi_note = math.min(state.scale[(state.seq.position.x - 1) + (state.seq.position.y)], 127)
      local support_mode = params:get("crow_support_mode")

      -- crow support note
      local support_note_value = state.seq.position.x / state.seq.position.y
      if(support_mode == 1) then
        support_note_value = state.seq.position.x / state.seq.position.y
      elseif support_mode == 2 then
        support_note_value = math.max(state.seq.position.x % state.seq.position.y, 1)
      elseif support_mode == 3 then
        support_note_value = state.seq.position.x + state.seq.position.y
      end

      local support_note = state.scale[math.ceil(support_note_value)]
      note_on(midi_note, support_note)
      if(play_direction == 4 or play_direction == 5) then
        if(math.random(2) == 1 and state.play_pos > 1) then
          state.play_pos = state.play_pos - 1
        else
          state.play_pos = state.play_pos + 1
        end
        state.beat_step = state.beat_step + 1
      else
        if (state.play_pos < #state.playable_cells or (seq_mode == 2  and not params:get("loop_semi_auto_seq") == 1)) then
          state.play_pos = state.play_pos + 1
          state.beat_step = state.beat_step + 1
        else
          reset_sequence()
        end
      end
    else
      init_position()
      reset_sequence()
    end
  else
    state.beat_step = state.beat_step + 1
  end
  redraw()
  grid_redraw()
end

local function clear_board()
  for x=1,config.GRID.SIZE.X do
    for y=1,config.GRID.SIZE.Y do
      state.board.current[x][y] = config.GRID.LEVEL.SPIN_DOWN
    end
  end
  notes_off()
  init_position()
  state.playable_cells = {}
  grid_redraw()
end


-- parameter callbacks

local function set_play_mode(play_mode)
  if(play_mode == 3) then
    state.note_offset = params:get("flip_offset")
  else
    state.note_offset = 0
  end
  collect_playable_cells()
end

local function set_play_direction()
  collect_playable_cells()
end

local function set_flip_offset()
  set_play_mode(params:get("play_mode"))
end

local function set_scale(new_scale_name)
  state.scale= music.generate_scale_of_length(state.root_note, new_scale_name, config.MUSIC.SCALE_LENGTH)
end

local function set_root_note(new_root_note)
  state.root_note = new_root_note
  state.scale= music.generate_scale_of_length(new_root_note, state.scale_name, config.MUSIC.SCALE_LENGTH)
end

local function set_euclid_seq_len(new_euclid_seq_len)
  if (new_euclid_seq_len < state.euclid_seq_beats) then
    new_euclid_seq_len = state.euclid_seq_beats
    params:set("euclid_seq_len", new_euclid_seq_len)
  end
  state.euclid_seq_len = new_euclid_seq_len
  state.beats = er.gen(state.euclid_seq_beats, new_euclid_seq_len)
end

local function set_euclid_seq_beats(new_euclid_seq_beats)
  if(new_euclid_seq_beats > state.euclid_seq_len) then
    new_euclid_seq_beats = state.euclid_seq_len
    params:set("euclid_seq_beats", new_euclid_seq_beats)
  end
  state.euclid_seq_beats = new_euclid_seq_beats
  state.beats = er.gen(new_euclid_seq_beats, state.euclid_seq_len)
end

local function set_release(r)
  engine.release(r)
end

local function set_cutoff(f)
  engine.cutoff(f)
end

local function set_midi_out_device_number()
  midi_out = midi.connect(params:get("midi_out_device_number"))
end

local function set_midi_in_device_number()
  midi_in.event = nil
  midi_in = midi.connect(params:get("midi_in_device_number"))
  midi_in.event = function(data) clk:process_midi(data) end
end

local function set_crow_clock()
  if(params:get("crow_clock") == 1) then
    -- use internal clock, set crow trigger callback to dummy function
    cr:set_trigger_input(1, function() end)
  else
    -- use external clock
    cr:set_trigger_input(1, play_seq_step)
  end
end


-------------
-- GLOBALS --
-------------


-- init
function init()
  cr = cs:new(crow)

  for i=0, 72 do
    config.MUSIC.NOTES[i] = {
      ["number"] = i,
      ["name"] = config.MUSIC.NOTE_NAMES_OCTAVE[i % 12 + 1] .. math.floor(i / 12),
      ["octave"] = math.floor(i / 12)
    }
  end
  config.MUSIC.NOTE_NAMES = helpers.table.map(function(note) return note.name end, config.MUSIC.NOTES)
  config.MUSIC.SCALE_NAMES = helpers.table.map(function(scale) return scale.name end, music.SCALES)

  -- params
  params:add_option("seq_mode", "seq mode", config.SEQ.MODES, 3)
  params:add_option("loop_semi_auto_seq", "loop seq in semi-auto mode", {"Y", "N"}, 1)

  params:add_option("scale", "scale", config.MUSIC.SCALE_NAMES, 1)
  params:set_action("scale", set_scale)

  params:add_option("state.root_note", "root note", config.MUSIC.NOTE_NAMES, 36)
  params:set_action("state.root_note", set_root_note)

  params:add_number("flip_offset", "flip offset", -24, 24, 0)
  params:set_action("flip_offset", set_flip_offset)

  params:add_option("play_mode", "play mode", config.SEQ.PLAY_MODES, 3)
  params:set_action("play_mode", set_play_mode)

  params:add_option("play_direction", "play direction", config.SEQ.PLAY_DIRECTIONS, 1)
  params:set_action("play_direction", set_play_direction)

  params:add_option("wrap_mode", "wrap board at edges", {"Y", "N"}, 1)

  params:add_separator()

  params:add_control("temperature", "temperature", controlspec.new(0.0, 100.0, "lin", 0.1, 5.0, ""))
  params:add_control("J", "interaction strength", controlspec.new(-20.0, 20.0, "lin", 0.1, 3.0, ""))

  params:add_separator()

  params:add_number("euclid_seq_len", "euclid seq length", 1, 100, 1)
  params:set_action("euclid_seq_len", set_euclid_seq_len)

  params:add_number("euclid_seq_beats", "euclid seq beats", 1, 100, 1)
  params:set_action("euclid_seq_beats", set_euclid_seq_beats)

  params:add_option("euclid_reset", "reset seq at start of gen", { "Y", "N" }, 2)

  params:add_separator()
  params:add_option("synth_internal", "internal sound (polyperc)", {"on", "off"}, 1)
  params:add_control("amp", "internal amp", controlspec.new(0.1, 1.0, "lin", 0.01, 0.8, ""))

  params:add_control("release", "internal release", controlspec.new(0.1, 5.0, "lin", 0.01, 0.5, "s"))
  params:set_action("release", set_release)

  params:add_control("cutoff", "internal cutoff", controlspec.new(50, 5000, "exp", 0, 1000, "hz"))
  params:set_action("cutoff", set_cutoff)

  params:add_separator()
  params:add_option("synth_crow", "crow cv output", {"on", "off"}, 1)
  params:add_control("crow_note_divider", "crow note divider", controlspec.new(1, 100, "lin", 1, 12, ""))
  params:add_control("crow_octave_offset", "crow cv octave offset", controlspec.new(-10, 10, "lin", 1, -3, ""))
  params:add_option("crow_cv_offset", "quantize crow cv offset", {"y", "n"}, 1)
  params:add_option("crow_support_mode", "crow alternative mode", config.CROW.SUPPORT_MODES, 1)
  params:add_control("crow_support_mode_note_offset", "crow alt. note offset", controlspec.new(-36, 36, "lin", 1, 0, ""))
  params:add_option("crow_clock", "crow clock", {"internal", "input 1"}, 1)
  params:set_action("crow_clock", set_crow_clock)

  params:add_separator()
  params:add_option("synth_midi", "midi output", {"on", "off"}, 1)
  params:add_control("midi_note_velocity", "midi note velocity", controlspec.new(1, 127, "lin", 1, 100, ""))
  params:add_control("midi_velocity_var", "midi velocity variance", controlspec.new(1, 100, "lin", 1, 20, ""))

  params:add_number("midi_channel", "midi channel", 1, 16, 1)

  params:add_number("midi_out_device_number", "midi out device number", 1, 4, 1)
  params:set_action("midi_out_device_number", set_midi_out_device_number)

  params:add_number("midi_in_device_number", "midi in device number", 1, 4, 1)
  params:set_action("midi_in_device_number", set_midi_in_device_number)

  params:add_separator()
  clk:add_clock_params()

  state.scale_name = config.MUSIC.SCALE_NAMES[13]
  state.scale= music.generate_scale_of_length(state.root_note, state.scale_name, config.MUSIC.SCALE_LENGTH)

  for x=1,config.GRID.SIZE.X do
    state.board.current[x] = {}
    for y=1,config.GRID.SIZE.Y do
      state.board.current[x][y] = config.GRID.LEVEL.SPIN_DOWN
    end
  end
  state.board.the_past = list.construct(helpers.clone_board(state.board.current)) -- initial construction of the past with a single 'dead' board
  helpers.load_params()

  init_position()
  helpers.init_engine(engine)

  clk.on_step = play_seq_step

  -- crow init
  cr:set_action(2, "{to(5,0), to(0, 0.25)}")
  cr:set_action(4, "{to(5,0), to(0, 0.1)}")
  cr:set_cv_input(2, function(v)
    state.crow.cv_offset = v
  end)
end


-- display UI
function redraw()
  screen.clear()
  screen.move(0, 8)
  screen.level(15)
  if not clk.external then
    screen.text(params:get("bpm"))
  else
    screen.text("(midi clock)")
  end
  screen.level(7)
  screen.move(0, 16)
  screen.text("bpm")

  screen.move(0, 28)
  screen.level(15)
  screen.text(config.SEQ.PLAY_MODES[params:get("play_mode")])
  screen.level(7)
  screen.move(0, 36)
  screen.text("play mode")

  screen.move(0, 48)
  screen.level(15)
  screen.text(config.SEQ.PLAY_DIRECTIONS[params:get("play_direction")])
  screen.level(7)
  screen.move(0, 56)
  screen.text("play direction")

  helpers.update_playing_indicator(state.show_playing_indicator)

  screen.update()
end

-- grid UI
function grid_redraw()
  g:all(0)
  for x=1,config.GRID.SIZE.X do
    for y=1,config.GRID.SIZE.Y do
      if (state.seq.position.x == x and state.seq.position.y == y) then
        g:led(x, y, config.GRID.LEVEL.ACTIVE)
      else
        g:led(x, y, state.board.current[x][y])
      end
    end
  end
  g:refresh()
end


-- ENC input handling
function enc(n, d)
  if (n == 1) then
    params:delta("bpm", d)
  end
  if (n == 2) then
    params:delta("play_mode", d)
  end
  if (n == 3) then
    if (state.keys.key3_down == false) then
      params:delta("play_direction", d)
    else
      if (d == 1) then
        generation_step()
      else
        do_the_time_warp()
      end
    end
  end
  redraw()
end


-- KEY input handling
function key(n, z)
  local seq_mode = params:get("seq_mode")
  if (n == 1) then
    state.keys.key1_down = z == 1
  end
  if (n == 2) then
    state.keys.key2_down = z == 1
    if(state.keys.key2_down and state.keys.key1_down) then
      -- TODO: save board state
      --save_state()
    elseif (state.keys.key2_down) then
      if(seq_mode == 1) then
        if (#state.playable_cells == 0) then
          generation_step()
        end
        play_seq_step()
      elseif(seq_mode == 2 or seq_mode == 3) then
        if(state.seq_running) then
          clk:stop()
          state.seq_running = false
          state.show_playing_indicator = false
        else
          if (#state.playable_cells == 0) then
            generation_step()
          end
          if(params:get("crow_clock") == 1) then
            clk:start()
          end
          state.seq_running = true
          state.show_playing_indicator = true
        end
      end
    end
  end
  if (n == 3) then
    state.keys.key3_down = z == 1
    if(state.keys.key3_down and state.keys.key1_down) then
      clear_board()
    elseif(state.keys.key3_down) then
      if(not (seq_mode == 2 and params:get("loop_semi_auto_seq") == 1)) then --true only if semi-auto and loop
        clk:stop()
        state.seq_running = false
        state.show_playing_indicator = false
      end
      generation_step() --if you continue to hold key 3 you can twist enc3 for lots of generations
    end
  end
  redraw()
end


-- GRID input handling
g.key = function(x, y, z)
  if (z == 1) then
    if (is_spin_up(x, y)) then
      state.board.current[x][y] = config.GRID.LEVEL.SPIN_DOWN
    else
      state.board.current[x][y] = config.GRID.LEVEL.SPIN_UP
    end
  end
  grid_redraw()
end

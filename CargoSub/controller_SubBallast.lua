-- ============================================================================
-- STORMWORKS LUA MICROCONTROLLER TEMPLATE
-- ============================================================================

-- Global State & Persistent Variables
local tick_count = 0

-- ----------------------------------------------------------------------------
-- HELPER FUNCTIONS
-- ----------------------------------------------------------------------------
function clamp(val, min_val, max_val)
    return math.max(min_val, math.min(max_val, val))
end

function map(val, in_min, in_max, out_min, out_max)
    return out_min + (val - in_min) * (out_max - out_min) / (in_max - in_min)
end

-- ----------------------------------------------------------------------------
-- MAIN LOGIC LOOP (Executes at 60 Hz)
-- ----------------------------------------------------------------------------
function onTick()
    tick_count = tick_count + 1

    -- 1. READ NUMERIC INPUTS (Channels 1 - 32)
    local BowTopBallastLevel = input.getNumber(1)
    local BowBottomBallastLevel = input.getNumber(2)
    local BowPortBallastLevel = input.getNumber(3)
    local BowStbdBallastLevel = input.getNumber(4)
  local SternTopBallastLevel = input.getNumber(5)
  local SternBottomBallastLevel = input.getNumber(6)
  local SternPortBallastLevel = input.getNumber(7)
  local SternStbdBallastLevel = input.getNumber(8)
  local BowTopBallastPress = input.getNumber(9)
    local BowBottomBallastPress = input.getNumber(10)
    local BowPortBallastPress = input.getNumber(11)
    local BowStbdBallastPress = input.getNumber(12)
  local SternTopBallastPress = input.getNumber(13)
  local SternBottomBallastPress = input.getNumber(14)
  local SternPortBallastPress = input.getNumber(15)
  local SternStbdBallastPress = input.getNumber(16)
  local Pamb = input.getNumber(17)
  local ChargeAirPress = input.getNumber(18)
  local SubRoll = input.getNumber(19)
  local SubPitch = input.getNumber(20)
  local SubDepth = input.getNumber(21)
  local SubDepthTgt = input.getNumber(22)
  -- Add RCS commands here so ballast can trim out pitch, roll, and heave.
  -- Add SubElevator and SubBowPlane so ballast can trim out pitch, roll, and heave while UAA.

    -- 2. READ BOOLEAN INPUTS (Channels 1 - 32)
    local TrimSubCmd = input.getBool(1) --instruction from Supervisor to actively keep the sub trimmed. Suspended for some maneuvering
    local ReweighActive = input.getBool(2) --instruction from Supervisor that a big load change has commenced, and it is safe to trim rapidly.

    -- 3. PROCESSING & LOGIC
  

    -- 4. WRITE NUMERIC OUTPUTS (Channels 1 - 32)
    output.setNumber(1, BowTopBallastCmd)
    output.setNumber(2, BowBottomBallastCmd)
    output.setNumber(3, BowPortBallastCmd)
    output.setNumber(4, BowStbdBallastCmd)
    output.setNumber(5, SternTopBallastCmd)
    output.setNumber(6, SternBottomBallastCmd)
    output.setNumber(7, SternPortBallastCmd)
    output.setNumber(8, SternStbdBallastCmd)
    output.setNumber(1, BowTopBlstAirCmd)
    output.setNumber(2, BowBottomBlstAirCmd)
    output.setNumber(3, BowPortBlstAirCmd)
    output.setNumber(4, BowStbdBlstAirCmd)
    output.setNumber(5, SternTopBlstAirCmd)
    output.setNumber(6, SternBottomBlstCmd)
    output.setNumber(7, SternPortBlstCmd)
    output.setNumber(8, SternStbdBlstCmd)

    -- 5. WRITE BOOLEAN OUTPUTS (Channels 1 - 32)
    output.setBool(1, SubRollInTrim)
    output.setBool(2, SubPitchInTrim)
    output.setBool(3, SubBouyancyInTrim)
end

-- ----------------------------------------------------------------------------

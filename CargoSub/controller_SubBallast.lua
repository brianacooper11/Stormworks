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
    local BowStarboardBallastLevel = input.getNumber(4)
  local SternTopBallastLevel = input.getNumber(5)
  local SternBottomBallastLevel = input.getNumber(6)
  local SternPortBallastLevel = input.getNumber(7)
  local SternStarboardBallastLevel = input.getNumber(8)
  local BowTopBallastPress = input.getNumber(9)
    local BowBottomBallastPress = input.getNumber(10)
    local BowPortBallastPress = input.getNumber(11)
    local BowStarboardBallastPress = input.getNumber(12)
  local SternTopBallastPress = input.getNumber(13)
  local SternBottomBallastPress = input.getNumber(14)
  local SternPortBallastPress = input.getNumber(15)
  local SternStarboardBallastPress = input.getNumber(16)
  local Pamb = input.getNumber(17)
  local ChargeAirPress = input.getNumber(18)
  local SubRoll = input.getNumber(19)
  local SubPitch = input.getNumber(20)
  local SubDepth = input.getNumber(21)
  local SubDepthTgt = input.getNumber(22)

    -- 2. READ BOOLEAN INPUTS (Channels 1 - 32)
    local TrimSubCmd = input.getBool(1)
    local ReweighActive = input.getBool(2)

    -- 3. PROCESSING & LOGIC
    local out_num1 = in_num1
    local out_num2 = in_num2

    local out_bool1 = in_bool1
    local out_bool2 = in_bool2

    -- 4. WRITE NUMERIC OUTPUTS (Channels 1 - 32)
    output.setNumber(1, BowTopBallastCmd)
    output.setNumber(2, BowBottomBallastCmd)
  output.setNumber(3, BowPortBallastCmd)
    output.setNumber(4, BowStarboardBallastCmd)

    -- 5. WRITE BOOLEAN OUTPUTS (Channels 1 - 32)
    output.setBool(1, out_bool1)
    output.setBool(2, out_bool2)
end

-- ----------------------------------------------------------------------------

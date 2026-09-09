-- ============================================================================
-- STORMWORKS LUA MICROCONTROLLER: SUBMARINE BALLAST & TRIM CONTROLLER
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PHYSICAL CONSTANTS & PLACEHOLDERS (Adjust to match your vessel)
-- ----------------------------------------------------------------------------
-- Mass & Center of Gravity (Dry Hull)
local EMPTY_MASS = 15000.0         -- kg (Unballasted dry mass)
local X_G0 = 0.0                   -- m  (Dry CG X offset relative to Center of Buoyancy)
local Y_G0 = -0.5                  -- m  (Dry CG Y vertical offset below CB)
local Z_G0 = 0.0                   -- m  (Dry CG Z offset)

local X_B = 0.0                    -- m  (Center of Buoyancy X)
local Z_B = 0.0                    -- m  (Center of Buoyancy Z)
local WATER_DENSITY = 1.0          -- Mass scale per unit volume

-- Ballast Tank Coordinates [X (Forward), Y (Up), Z (Starboard)]
-- Coordinate convention: +X Forward, +Y Up, +Z Starboard
local TANK_POS = {
    BT = { x =  8.0, y =  1.5, z =  0.0 }, -- Bow Top
    BB = { x =  8.0, y = -1.5, z =  0.0 }, -- Bow Bottom
    BP = { x =  8.0, y =  0.0, z = -1.5 }, -- Bow Port
    BS = { x =  8.0, y =  0.0, z =  1.5 }, -- Bow Starboard
    ST = { x = -8.0, y =  1.5, z =  0.0 }, -- Stern Top
    SB = { x = -8.0, y = -1.5, z =  0.0 }, -- Stern Bottom
    SP = { x = -8.0, y =  0.0, z = -1.5 }, -- Stern Port
    SS = { x = -8.0, y =  0.0, z =  1.5 }  -- Stern Starboard
}

-- Control Gains & Low-Pass Filter Coefficients
local ALPHA_LPF_SLOW = 0.02        -- LPF alpha for steady-state filtering (~1s lag)
local ALPHA_LPF_FAST = 0.10        -- LPF alpha when ReweighActive is true

local K_P_DEPTH = 0.15             -- Depth error gain to heave demand
local K_P_PITCH = 2.50             -- Pitch error gain to pitch demand
local K_P_ROLL  = 2.50             -- Roll error gain to roll demand

local K_FF_PITCH = 1.20            -- Feedforward gain for longitudinal mass offset (X_G - X_B)
local K_FF_ROLL  = 1.20            -- Feedforward gain for transverse mass offset (Z_G - Z_B)

-- Air / Pneumatic Constants
local DELTA_P_BLOW   = 0.4         -- bar above Pamb needed to push water out
local PRESS_DEADBAND = 0.05        -- bar deadband for steady-state Pamb matching
local MIN_AIR_MARGIN = 0.5         -- bar manifold must exceed Pamb to blow

-- Deadbands / In-Trim Thresholds
local TRIM_TOL_PITCH = 0.01        -- Radians (~0.5 deg)
local TRIM_TOL_ROLL  = 0.01        -- Radians (~0.5 deg)
local TRIM_TOL_DEPTH = 0.25        -- Meters

-- ----------------------------------------------------------------------------
-- GLOBAL STATE & PERSISTENT VARIABLES
-- ----------------------------------------------------------------------------
local tick_count = 0
local roll_lpf = 0.0
local pitch_lpf = 0.0
local depth_lpf = 0.0

-- ----------------------------------------------------------------------------
-- HELPER FUNCTIONS
-- ----------------------------------------------------------------------------
function clamp(val, min_val, max_val)
    return math.max(min_val, math.min(max_val, val))
end

local function computeAirCmd(water_cmd, tank_press, p_amb, p_charge)
    local air_cmd = 0.0

    if water_cmd > 0.05 then
        -- CASE 1: FILLING TANK (Water in / Air out)
        air_cmd = -water_cmd

    elseif water_cmd < -0.05 then
        -- CASE 2: BLOWING TANK (Water out / Air in)
        local target_p = p_amb + DELTA_P_BLOW
        
        if p_charge > (p_amb + MIN_AIR_MARGIN) then
            if tank_press < target_p then
                air_cmd = math.abs(water_cmd)
            else
                air_cmd = 0.0
            end
        else
            -- Low manifold air: hold isolated state
            air_cmd = 0.0
        end

    else
        -- CASE 3: STEADY STATE / ISOLATED (Equalize P_tank == P_amb)
        local p_err = tank_press - p_amb

        if p_err > PRESS_DEADBAND then
            air_cmd = -clamp(p_err * 2.0, 0.1, 0.5)
        elseif p_err < -PRESS_DEADBAND and p_charge > (p_amb + MIN_AIR_MARGIN) then
            air_cmd = clamp(-p_err * 2.0, 0.1, 0.5)
        else
            air_cmd = 0.0
        end
    end

    return clamp(air_cmd, -1.0, 1.0)
end

-- ----------------------------------------------------------------------------
-- MAIN LOGIC LOOP (Executes at 60 Hz)
-- ----------------------------------------------------------------------------
function onTick()
    tick_count = tick_count + 1

    -- 1. READ NUMERIC INPUTS (Channels 1 - 27)
    local BT_Level = input.getNumber(1)
    local BB_Level = input.getNumber(2)
    local BP_Level = input.getNumber(3)
    local BS_Level = input.getNumber(4)
    local ST_Level = input.getNumber(5)
    local SB_Level = input.getNumber(6)
    local SP_Level = input.getNumber(7)
    local SS_Level = input.getNumber(8)

    local BowTopBallastPress     = input.getNumber(9)
    local BowBottomBallastPress  = input.getNumber(10)
    local BowPortBallastPress    = input.getNumber(11)
    local BowStbdBallastPress    = input.getNumber(12)
    local SternTopBallastPress   = input.getNumber(13)
    local SternBottomBallastPress= input.getNumber(14)
    local SternPortBallastPress  = input.getNumber(15)
    local SternStbdBallastPress  = input.getNumber(16)

    local Pamb           = input.getNumber(17)
    local ChargeAirPress = input.getNumber(18)
    local SubRoll        = input.getNumber(19) -- Radians (+ = Roll Right)
    local SubPitch       = input.getNumber(20) -- Radians (+ = Nose Up)
    local SubDepth       = input.getNumber(21) -- Meters
    local SubDepthTgt    = input.getNumber(22) -- Meters

    local RCSPitchCmd    = input.getNumber(23)
    local RCSRollCmd     = input.getNumber(24)
    local RCSHeaveCmd    = input.getNumber(25)
    local SubElevator    = input.getNumber(26)
    local SubBowPlane    = input.getNumber(27)

    -- 2. READ BOOLEAN INPUTS
    local TrimSubCmd    = input.getBool(1) -- Active trimming enabled
    local ReweighActive = input.getBool(2) -- Fast-trim mode for major weight shifts

    -- 3. PROCESSING & LOGIC

    -- A. Low-Pass Filter State Estimation
    local alpha = ReweighActive and ALPHA_LPF_FAST or ALPHA_LPF_SLOW
    roll_lpf  = roll_lpf  + alpha * (SubRoll  - roll_lpf)
    pitch_lpf = pitch_lpf + alpha * (SubPitch - pitch_lpf)
    depth_lpf = depth_lpf + alpha * (SubDepth - depth_lpf)

    -- B. Feedforward Center of Gravity ('G') Tracking
    local w_BT = BT_Level * WATER_DENSITY
    local w_BB = BB_Level * WATER_DENSITY
    local w_BP = BP_Level * WATER_DENSITY
    local w_BS = BS_Level * WATER_DENSITY
    local w_ST = ST_Level * WATER_DENSITY
    local w_SB = SB_Level * WATER_DENSITY
    local w_SP = SP_Level * WATER_DENSITY
    local w_SS = SS_Level * WATER_DENSITY

    local total_water_mass = w_BT + w_BB + w_BP + w_BS + w_ST + w_SB + w_SP + w_SS
    local total_mass = EMPTY_MASS + total_water_mass

    local current_x_g = (EMPTY_MASS * X_G0 
        + w_BT * TANK_POS.BT.x + w_BB * TANK_POS.BB.x + w_BP * TANK_POS.BP.x + w_BS * TANK_POS.BS.x
        + w_ST * TANK_POS.ST.x + w_SB * TANK_POS.SB.x + w_SP * TANK_POS.SP.x + w_SS * TANK_POS.SS.x) / total_mass

    local current_z_g = (EMPTY_MASS * Z_G0 
        + w_BT * TANK_POS.BT.z + w_BB * TANK_POS.BB.z + w_BP * TANK_POS.BP.z + w_BS * TANK_POS.BS.z
        + w_ST * TANK_POS.ST.z + w_SB * TANK_POS.SB.z + w_SP * TANK_POS.SP.z + w_SS * TANK_POS.SS.z) / total_mass

    -- Mass Offsets relative to Buoyancy Center
    local offset_x = current_x_g - X_B
    local offset_z = current_z_g - Z_B

    local ff_pitch_cmd = -offset_x * K_FF_PITCH
    local ff_roll_cmd  = -offset_z * K_FF_ROLL

    -- C. Feedback Loop Calculations
    local err_depth = SubDepthTgt - depth_lpf  -- + depth err = Sub too high, needs water
    local err_pitch = 0.0 - pitch_lpf          -- + pitch err = Nose down needed (+ water to Bow)
    local err_roll  = 0.0 - roll_lpf           -- + roll err  = Roll left needed (+ water to Port)

    local fb_heave_cmd = clamp(err_depth * K_P_DEPTH, -1.0, 1.0)
    local fb_pitch_cmd = clamp(err_pitch * K_P_PITCH, -1.0, 1.0)
    local fb_roll_cmd  = clamp(err_roll  * K_P_ROLL,  -1.0, 1.0)

    -- Gate feedback trim when TrimSubCmd is disabled
    if not TrimSubCmd then
        fb_pitch_cmd = 0.0
        fb_roll_cmd  = 0.0
        fb_heave_cmd = 0.0
    end

    -- D. Mix Demands across 3 Axes
    local net_heave = fb_heave_cmd + RCSHeaveCmd
    local net_pitch = fb_pitch_cmd + ff_pitch_cmd + RCSPitchCmd
    local net_roll  = fb_roll_cmd  + ff_roll_cmd  + RCSRollCmd

    -- E. 8-Tank Water Mixing Matrix (Outputs 1 - 8)
    local BowTopCmd     = clamp(net_heave + net_pitch,            -1.0, 1.0)
    local BowBottomCmd  = clamp(net_heave + net_pitch,            -1.0, 1.0)
    local BowPortCmd    = clamp(net_heave + net_pitch + net_roll, -1.0, 1.0)
    local BowStbdCmd    = clamp(net_heave + net_pitch - net_roll, -1.0, 1.0)

    local SternTopCmd   = clamp(net_heave - net_pitch,            -1.0, 1.0)
    local SternBottomCmd= clamp(net_heave - net_pitch,            -1.0, 1.0)
    local SternPortCmd  = clamp(net_heave - net_pitch + net_roll, -1.0, 1.0)
    local SternStbdCmd  = clamp(net_heave - net_pitch - net_roll, -1.0, 1.0)

    -- F. Air Pressure Control Calculations (Outputs 9 - 16)
    local BowTopAirCmd    = computeAirCmd(BowTopCmd,     BowTopBallastPress,     Pamb, ChargeAirPress)
    local BowBottomAirCmd = computeAirCmd(BowBottomCmd,  BowBottomBallastPress,  Pamb, ChargeAirPress)
    local BowPortAirCmd   = computeAirCmd(BowPortCmd,    BowPortBallastPress,    Pamb, ChargeAirPress)
    local BowStbdAirCmd   = computeAirCmd(BowStbdCmd,    BowStbdBallastPress,    Pamb, ChargeAirPress)

    local SternTopAirCmd   = computeAirCmd(SternTopCmd,   SternTopBallastPress,   Pamb, ChargeAirPress)
    local SternBottomAirCmd= computeAirCmd(SternBottomCmd, SternBottomBallastPress,Pamb, ChargeAirPress)
    local SternPortAirCmd  = computeAirCmd(SternPortCmd,  SternPortBallastPress,  Pamb, ChargeAirPress)
    local SternStbdAirCmd  = computeAirCmd(SternStbdCmd,  SternStbdBallastPress,  Pamb, ChargeAirPress)

    -- G. Evaluate In-Trim Status Flags
    local pitch_in_trim = math.abs(pitch_lpf) <= TRIM_TOL_PITCH
    local roll_in_trim  = math.abs(roll_lpf)  <= TRIM_TOL_ROLL
    local depth_in_trim = math.abs(err_depth) <= TRIM_TOL_DEPTH

    -- 4. WRITE NUMERIC OUTPUTS
    -- Water Add-Rate Commands (Channels 1 - 8)
    output.setNumber(1, BowTopCmd)
    output.setNumber(2, BowBottomCmd)
    output.setNumber(3, BowPortCmd)
    output.setNumber(4, BowStbdCmd)
    output.setNumber(5, SternTopCmd)
    output.setNumber(6, SternBottomCmd)
    output.setNumber(7, SternPortCmd)
    output.setNumber(8, SternStbdCmd)

    -- Air Pressure / Pneumatic Valve Commands (Channels 9 - 16)
    output.setNumber(9,  BowTopAirCmd)
    output.setNumber(10, BowBottomAirCmd)
    output.setNumber(11, BowPortAirCmd)
    output.setNumber(12, BowStbdAirCmd)
    output.setNumber(13, SternTopAirCmd)
    output.setNumber(14, SternBottomAirCmd)
    output.setNumber(15, SternPortAirCmd)
    output.setNumber(16, SternStbdAirCmd)

    -- 5. WRITE BOOLEAN OUTPUTS (Channels 1 - 3)
    output.setBool(1, roll_in_trim)
    output.setBool(2, pitch_in_trim)
    output.setBool(3, depth_in_trim)
end

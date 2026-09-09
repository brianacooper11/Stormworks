-- ============================================================================
-- STORMWORKS LUA MICROCONTROLLER: CARGOSUB NUCLEAR POWERPLANT CONTROLLER
-- Script: controller_powerplant.lua
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CONSTANTS & SETPOINTS
-- ----------------------------------------------------------------------------
local SETPOINT_COOLANT_TEMP     = 130.0 -- Target reactor coolant temp (°C)
local SETPOINT_STEAM_PRESS_RUN  = 9.0   -- Target steam chest pressure operating (bar)
local SETPOINT_STEAM_PRESS_OFF  = 1.0   -- Target steam chest pressure shutdown (bar)

-- Safety Limits
local MAX_FUEL_ROD_TEMP         = 350.0 -- SCRAM threshold for fuel rod temp (°C)
local MAX_COOLANT_TEMP          = 200.0 -- SCRAM threshold for coolant temp (°C)
local MAX_STEAM_PRESS           = 9.8   -- Overpressure relief trigger (bar)

-- Control Gains
local GAIN_TEMP_TO_REACTIVITY   = 5.0   -- Outer loop: Temp err -> Target Reactivity
local GAIN_REACTIVITY_TO_ROD    = 0.01  -- Inner loop: Reactivity err -> Rod Cmd

local KP_THROTTLE               = 0.25  -- Proportional gain for main steam throttle
local KI_THROTTLE               = 0.01  -- Integral gain for main steam throttle

local KP_FEEDWATER              = 0.10  -- Steam chest pressure error to feedwater valve
local KP_COOLANT_VALVE          = 0.05  -- Primary coolant flow regulation gain

-- ----------------------------------------------------------------------------
-- GLOBAL STATE & PERSISTENT VARIABLES
-- ----------------------------------------------------------------------------
local tick_count = 0
local integral_rps_err = 0.0

local current_reactivity = 0.0
local target_reactivity = 0.0
local desalinator_active = false

-- Output Command States
local cmd_main_throttle = 0.0
local cmd_feedwater_valve = 0.0
local cmd_pwc_valve = 0.0
local cmd_control_rods = 0.0
local cmd_steam_bypass = 0.0
local cmd_heat_dump = false
local cmd_primary_pumps = false
local cmd_condenser_pumps = false
local cmd_desalinator = false

-- ----------------------------------------------------------------------------
-- HELPER FUNCTIONS
-- ----------------------------------------------------------------------------
function clamp(val, min_val, max_val)
    return math.max(min_val, math.min(max_val, val))
end

-- ----------------------------------------------------------------------------
-- MAIN LOGIC LOOP (60 Hz)
-- ----------------------------------------------------------------------------
function onTick()
    tick_count = tick_count + 1

    -- ========================================================================
    -- 1. READ NUMERIC INPUTS (Channels 1 - 14)
    -- ========================================================================
    local RPSCmd                = input.getNumber(1)
    local PropPitchCmd          = input.getNumber(2)
    local ReactorCounter        = input.getNumber(3)  -- Geiger counts/sec (Reactivity)
    local ReactorControlRodPos  = input.getNumber(4)
    local ReactorCoolantTemp    = input.getNumber(5)
    local ReactorFuelRodXTemp   = input.getNumber(6)  -- Peak fuel rod temp
    local ReactorCoolantFlow    = input.getNumber(7)
    local FeedwaterPressure     = input.getNumber(8)
    local FeedwaterFlowRate     = input.getNumber(9)
    local SteamChestPressure    = input.getNumber(10)
    local MainSteamFlowRate     = input.getNumber(11)
    local MainSteamFlowPressure = input.getNumber(12)
    local EngRPS                = input.getNumber(13)
    local FreshwaterTankPct     = input.getNumber(14) -- Freshwater level (0.0 to 1.0)

    -- ========================================================================
    -- 2. READ BOOLEAN INPUTS (Channels 1)
    -- ========================================================================
    local ReactorRunReq         = input.getBool(1)

    -- ========================================================================
    -- 3. SUPERVISOR LOGIC & SAFETY INTERLOCKS
    -- ========================================================================
    -- Safety Interlocks (Automatic SCRAM checks)
    local is_temp_safe  = (ReactorFuelRodXTemp < MAX_FUEL_ROD_TEMP) and (ReactorCoolantTemp < MAX_COOLANT_TEMP)
    local is_press_safe = (SteamChestPressure < MAX_STEAM_PRESS)
    local ReactorSafeToRun = is_temp_safe and is_press_safe

    -- Operating State
    local system_active = ReactorRunReq and ReactorSafeToRun

    -- Steam Available Flag (Indicates to electrical controller that steam loop is ready)
    local SteamAvailable = system_active and (SteamChestPressure >= 5.0) and (ReactorCoolantTemp >= 100.0)

    -- ========================================================================
    -- 4. CONTROL LOOPS
    -- ========================================================================
    if system_active then
        -- --------------------------------------------------------------------
        -- A. CONTROL RODS (Two-Loop Cascade Control)
        -- --------------------------------------------------------------------
        -- Outer Loop: Coolant Temp Error -> Target Reactivity
        local temp_error = SETPOINT_COOLANT_TEMP - ReactorCoolantTemp
        target_reactivity = clamp(temp_error * GAIN_TEMP_TO_REACTIVITY, 0.0, 1000.0)

        -- Inner Loop: Reactivity Error -> Rod Position Command
        current_reactivity = ReactorCounter
        local reactivity_error = target_reactivity - current_reactivity
        cmd_control_rods = clamp(cmd_control_rods + (reactivity_error * GAIN_REACTIVITY_TO_ROD), 0.0, 1.0)

        -- --------------------------------------------------------------------
        -- B. MAIN STEAM THROTTLE VALVE (Transient RPS Regulation)
        -- --------------------------------------------------------------------
        local rps_error = RPSCmd - EngRPS
        integral_rps_err = clamp(integral_rps_err + rps_error * (1.0 / 60.0), -5.0, 5.0)
        cmd_main_throttle = clamp((rps_error * KP_THROTTLE) + (integral_rps_err * KI_THROTTLE), 0.0, 1.0)

        -- --------------------------------------------------------------------
        -- C. FEEDWATER VALVE (Steady-State Pressure & Supply)
        -- --------------------------------------------------------------------
        local press_error = SETPOINT_STEAM_PRESS_RUN - SteamChestPressure
        cmd_feedwater_valve = clamp((RPSCmd * 0.05) + (press_error * KP_FEEDWATER), 0.0, 1.0)

        -- --------------------------------------------------------------------
        -- D. PRIMARY COOLANT VALVE (Boiler Heat Transfer Control)
        -- --------------------------------------------------------------------
        cmd_pwc_valve = clamp(0.5 + (ReactorCoolantTemp - SETPOINT_COOLANT_TEMP) * KP_COOLANT_VALVE, 0.1, 1.0)

        -- --------------------------------------------------------------------
        -- E. OVERPRESSURE & STEAM BYPASS TO CONDENSER (Zero Water-Loss)
        -- --------------------------------------------------------------------
        local overpressure_err = SteamChestPressure - SETPOINT_STEAM_PRESS_RUN
        local rapid_throttle_drop = (RPSCmd < 0.5) and (EngRPS > 5.0)

        if overpressure_err > 0.0 or rapid_throttle_drop then
            -- Route excess steam directly to Condenser Bank to save freshwater
            local bp_gain = overpressure_err * 0.5 + (rapid_throttle_drop and 0.5 or 0.0)
            cmd_steam_bypass = clamp(bp_gain, 0.0, 1.0)
        else
            cmd_steam_bypass = 0.0
        end

        cmd_primary_pumps = true
        cmd_condenser_pumps = (cmd_steam_bypass > 0.05) or (cmd_main_throttle > 0.05)
        cmd_heat_dump = false

    else
        -- --------------------------------------------------------------------
        -- SCRAM / SHUTDOWN MODE (Conditions Not Met)
        -- --------------------------------------------------------------------
        integral_rps_err = 0.0
        cmd_control_rods = 0.0          -- Insert control rods
        cmd_feedwater_valve = 0.0       -- Cut off feedwater
        cmd_main_throttle = 0.0         -- Close main engine throttle
        
        -- Route residual boiler steam to condensers to depressurize safely
        if SteamChestPressure > SETPOINT_STEAM_PRESS_OFF then
            cmd_steam_bypass = clamp((SteamChestPressure - SETPOINT_STEAM_PRESS_OFF) * 0.5, 0.1, 1.0)
            cmd_condenser_pumps = true
        else
            cmd_steam_bypass = 0.0
            cmd_condenser_pumps = false
        end

        -- Keep primary pumps active until reactor cools down
        if ReactorCoolantTemp > 40.0 then
            cmd_primary_pumps = true
            cmd_pwc_valve = 1.0
            cmd_heat_dump = true        -- Rapid heat dump via seawater heat exchanger
        else
            cmd_primary_pumps = false
            cmd_pwc_valve = 0.0
            cmd_heat_dump = false
        end
    end

    -- ------------------------------------------------------------------------
    -- F. BACKGROUND DESALINATOR MAKEUP TRICKLE LOGIC
    -- ------------------------------------------------------------------------
    -- Desalinator runs continuously in background when power/steam is available
    if SteamAvailable or cmd_primary_pumps then
        if FreshwaterTankPct < 0.95 then
            desalinator_active = true
        elseif FreshwaterTankPct >= 0.99 then
            desalinator_active = false
        end
    else
        desalinator_active = false
    end
    cmd_desalinator = desalinator_active

    -- ========================================================================
    -- 5. WRITE NUMERIC OUTPUTS (Channels 1 - 12)
    -- ========================================================================
    output.setNumber(1,  cmd_main_throttle)
    output.setNumber(2,  cmd_feedwater_valve)
    output.setNumber(3,  cmd_pwc_valve)
    output.setNumber(4,  cmd_control_rods)
    output.setNumber(5,  cmd_steam_bypass)
    output.setNumber(6,  cmd_heat_dump and 1.0 or 0.0)
    output.setNumber(7,  cmd_desalinator and 1.0 or 0.0)
    output.setNumber(8,  cmd_primary_pumps and 1.0 or 0.0)
    output.setNumber(9,  cmd_condenser_pumps and 1.0 or 0.0)
    output.setNumber(10, current_reactivity)     -- Telemetry
    output.setNumber(11, ReactorCoolantTemp)     -- Telemetry
    output.setNumber(12, ReactorFuelRodXTemp)    -- Telemetry

    -- ========================================================================
    -- 6. WRITE BOOLEAN OUTPUTS (Channels 1 - 2)
    -- ========================================================================
    output.setBool(1, ReactorSafeToRun)
    output.setBool(2, SteamAvailable)
end

-- Global Constants
tickRate=30  -- rate in Hz that the main function executes
WaterTWarn = 240  --  Maximum water temperature to trigger warning in F
sxCan = 1 -- What CAN bus ShiftX2 is connected to. 0=CAN1, 1=CAN2
sxId=0 -- 0=first ShiftX2 on bus, 1=second ShiftX2 (if ADR1 jumper is cut)


-- Global Variables
maxRpm = 0  -- variable for tracking max rpm
maxAvg = 100  -- number of samples for the average fuel calculation
fuelAvg={}  -- array for storing average fuel samples
fuel2Index = 1  -- index for tracking average fuel offset
fuelsampcnt = 1 -- counter to adjust for sample rate

-- Dynamic RCP Channels
Fuel1Id = addChannel("FuelRaw", 10, 1, 0,17,"GAL")
Fuel2Id = addChannel("FuelRemain", 10, 1, 0,17,"GAL")
overRevId = addChannel("OverRev", 10, 0, 0,1)
maxRpmId = addChannel("RPMMax", 10, 0, 0,15000,"RPM")
speeddiff_id = addChannel("SpeedAxle",10,0,0,160,"MPH")
gear_id = addChannel("GearCurrent",5,0,0,5,"Gear")
ShiftXButton = addChannel("SXButton",20,0,0,1)

-- Initalize settings
setTickRate(tickRate) -- Set execution interval in Hz
sxCanId = 0xE3600 + (256 * sxId)
--println('shiftx2 base id ' ..sxCanId)
sxInit()


-- Custom Functions

-- If Start/Finish is detected, start logging to the SD Card
function BeginSDLogging()
 if getAtStartFinish() == 1 then
  if isLogging() == 0 then
   startLogging()
  end
 end
end


-- WarnCheck controls the state of a GPIO for a master warning light based on OT, WT, OP constants
-- For Oil Pressure, it will only sound if the engine is running over 500 RPMs
function WarnCheck()
 local OilPWarn = 20  --  Minimum oil pressure to trigger warning in PSI when TPS is more than 50 percent
 local OilIdleWarn = 6 --  Minimum oil pressure to trigger warning in PSI at idle
 local OilTWarn = 275  --  Maximum oil temperature to trigger warning in F
 
 local Warning = 0
 local EngineRPM = getTimerRpm(0)
 local TPS = getAnalog(5)
 local OilPress = getAnalog(0)
 local OilTemp = getAnalog(1)
 local WaterTemp = getAnalog(2)

 if EngineRPM > 500 then
  if TPS > 50 then
   if OilPress < OilPWarn then Warning = 1 end
  else
   if OilPress < OilIdleWarn then Warning = 1 end
  end
 end

 if OilTemp > OilTWarn then Warning = 1 end

 if WaterTemp > WaterTWarn then Warning = 1 end

 setGpio(2,Warning)
end


-- updateSpeedDiff updates the dynamic channel for speed messured at the Differential in MPH
function updateSpeedDiff()

end


-- updateGear updates the dynamic channel that indicates the current gear in which the car is operating
function  updateSpdDiff_Gear()
 local first = 4.20  -- transmission ratio for 1st gear
 local second = 2.49  -- transmission ratio for 2nd gear
 local third = 1.66  -- transmission ratio for 3rd gear
 local fourth = 1.24  -- transmission ratio for 4th gear
 local fifth = 1.00  -- transmission ratio for 5th gear
 local final = 3.73  -- final drive ratio
 local tirediameter = 24.8 -- The diamater in inches of the driven tire
 local gearErr = 0.15
 local gear = 0
 local ratio = 0
 
 local rpm = getTimerRpm(0)
 local rpm_diff = getTimerRpm(1)
 local speed = rpm_diff*tirediameter*0.002975
 
 speed = speed + 0.5 -- round because 0 prec. truncates
 setChannel(speeddiff_id, speed)
 
  if speed > 2 then
  ratio = rpm/(rpm_diff*final)
  if ((first  - ratio)^2) < (gearErr^2) then gear = 1 end
  if ((second - ratio)^2) < (gearErr^2) then gear = 2 end
  if ((third  - ratio)^2) < (gearErr^2) then gear = 3 end
  if ((fourth - ratio)^2) < (gearErr^2) then gear = 4 end
  if ((fifth  - ratio)^2) < (gearErr^2) then gear = 5 end
 end
 setChannel(gear_id, gear)
end


-- RevCheck updates the dynamic channels that records the maximum RPM and the over rev flag.
function RevCheck()
 local OverRevRPM = 7600  -- Any RPM value above this value will be considered an over rev
 
 local chkrpm = getTimerRpm(0)
 
 if chkrpm > maxRpm then
  maxRpm = chkrpm
  setChannel(maxRpmId, maxRpm)
 end

 if chkrpm > OverRevRPM then  setChannel(overRevId, 1) end

end


--  updateFuel updates both the dynamic channels for raw fuel and average fuel level.
--  If GPS speed is below 10 mph, average fuel level is set to raw.
--  The function accepts an argument value for the current fuel reading.
function updateFuel(value)
--adjust sample rate for tickrate
 if fuelsampcnt < (tickRate / 10) then
  fuelsampcnt = fuelsampcnt + 1
 else
  fuelsampcnt = 1
  local i
  local SpeedMPH = getGpsSpeed()
  local AccX = math.abs(getImu(0))
  local AccY = math.abs(getImu(1))
  local LowAcc = 0
 
  if AccX < 0.35 then
   if AccY < 0.35 then
    LowAcc = 1
   end
  end

  if #fuelAvg == 0 then
   for i = 1, maxAvg do fuelAvg[i]=value end
  end

-- only update fuel average if G are less than .35 in any direction
  if LowAcc == 1 then 
   fuelAvg[fuel2Index] = value
  
   fuel2Index = fuel2Index + 1
  
   if fuel2Index > maxAvg then fuel2Index = 1 end
  end

  local sum = 0

  for i = 1, #fuelAvg do
   sum = sum + fuelAvg[i]
  end

  if SpeedMPH < 10 then
   setChannel(Fuel2Id, value)
  else
   setChannel(Fuel2Id, round((sum / maxAvg),1))
  end
  
  setChannel(Fuel1Id, value)
 end
end

-- round simply rounds a number to the specified number of decimal places.
function round(num, numDecimalPlaces)
 local mult = 10^(numDecimalPlaces or 0)
 return math.floor(num * mult + 0.5) / mult
end


-- GetFuelLevelRaw converts the current reading of the OEM E36 fuel level senders into gallons in the tank.
function GetFuelLevelRaw()
 local FuelPullUp = 1100 -- The value of the resistor in the divider circuit for fuel level
 local FuelLevelVolts = getAnalog(4)
 local BatteryVolts = getAnalog(7)
 
 return (round((((FuelLevelVolts*FuelPullUp)/(BatteryVolts-FuelLevelVolts))-21)/29.625,1))
end


--  FanControl set the state of a GPIO that controls the engine cooling fan.
--  It uses constants for the set points of temperature and speed.
--  Both the speed and thresholds have to be met before the fan will turn on.
function FanControl()
 local FanOnTemp = 180  -- Temperature in F that the fan should be on
local FanMaxSpeed = 45 -- Above this speed the fan will not operate
 local WaterTemp = getAnalog(2)
 local SpeedMPH = getGpsSpeed()

 if SpeedMPH < FanMaxSpeed then
  if WaterTemp < (FanOnTemp-5) then
   setGpio(0,0)
  else
   if WaterTemp > FanOnTemp then
    setGpio(0,1)
   end
  end
 else
  setGpio(0,0)
 end
end

-- Update ShiftX2 alerts or linear graph during run time.
-- Runs continuously based on tickRate.
function sxOnUpdate()
  --Update Direct RPM on input 0
  sxUpdateLinearGraph(getTimerRpm(0))

  --update engine temp alert
  sxUpdateAlert(0, getAnalog(2))

  --update Fuel Remaining alert
  sxUpdateAlert(1, getChannel("FuelRemain"))
end

function sxOnInit()
  local ShiftLightGrn = 5000 -- power band begins
  local ShiftlightRed = 6800 -- red aproaching redline
  local ShiftlightBlu = 7100 -- Redline - blue
  local ShiftlightFlash = 7200 -- Shift already! (flashing blue)
  local FuelRed = 1 -- number of gallons remaining when the warning light flashes red
  
  --config shift light
  sxCfgLinearGraph(0,0,0,7500) --left to right graph, linear style, 0 - 7000 RPM range

  sxSetLinearThresh(0,0,ShiftLightGrn,0,255,0,0) --green 
  sxSetLinearThresh(1,0,ShiftlightRed,255,0,0,0) --red 
  sxSetLinearThresh(2,0,ShiftlightBlu,0,0,255,0) --blue
    sxSetLinearThresh(3,0,ShiftlightFlash,0,0,255,10) --blue+flash  

  --configure first alert (right LED) as engine temperature (F)
  sxSetAlertThresh(0,0,(WaterTWarn-20),255,255,0,0) --yellow warning
  sxSetAlertThresh(0,1,WaterTWarn,255,0,0,10) -- red flash

  --configure second alert (left LED) as Fuel Remaining (Gal)
  sxSetAlertThresh(1,0,FuelRed,255,0,0,10) --red flash
  sxSetAlertThresh(1,1,FuelRed+1,255,255,0,5) --yellow flash
  sxSetAlertThresh(1,2,FuelRed+2,255,255,0,0) --yellow flash
  sxSetAlertThresh(1,3,FuelRed+3,0,0,0,0) -- no alert
end

function sxOnBut(b)
  --called if the button state changes
    setChannel(ShiftXButton, b)
end

---ShiftX2 functions
function sxSetLed(i,l,r,g,b,f)
  sxTx(10,{i,l,r,g,b,f})
end

function sxSetLinearThresh(id,s,th,r,g,b,f)
  sxTx(41,{id,s,spl(th),sph(th),r,g,b,f})
end

function sxSetAlertThresh(id,tid,th,r,g,b,f)
  sxTx(21,{id,tid,spl(th),sph(th),r,g,b,f})
end

function setBaseConfig(bright)
  sxTx(3,{bright})
end

function sxSetAlert(id,r,g,b,f)
  sxTx(20,{id,r,g,b,f})
end

function sxUpdateAlert(id,v)
  if v~=nil then sxTx(22,{id,spl(v),sph(v)}) end
end

function sxCfgLinearGraph(rs,ls,lr,hr) 
  sxTx(40,{rs,ls,spl(lr),sph(lr),spl(hr),sph(hr)})
end

function sxUpdateLinearGraph(v)
  if v ~= nil then sxTx(42,{spl(v),sph(v)}) end
end

function sxInit()
  local sxBright=0 --Brightness, 0-100. 0=automatic brightness
  --println('config shiftX2')
  setBaseConfig(sxBright)
  if sxOnInit~=nil then sxOnInit() end
end

function sxChkCan()
  id,ext,data=rxCAN(sxCan,0)
  if id==sxCanId then sxInit() end
  if id==sxCanId+60 and sxOnBut~=nil then sxOnBut(data[1]) end
end

function sxProcess()
  sxChkCan()
  if sxOnUpdate~=nil then sxOnUpdate() end
end

function sxTx(offset, data)
  txCAN(sxCan, sxCanId + offset, 1, data)
  sleep(10)
end

function spl(v) return bit.band(v,0xFF) end
function sph(v) return bit.rshift(bit.band(v,0xFF00),8) end


-- Master execution function
function onTick()
 BeginSDLogging()
 FanControl()
 updateFuel(GetFuelLevelRaw())
 RevCheck()
 updateSpdDiff_Gear()
 WarnCheck()
 sxProcess()
end
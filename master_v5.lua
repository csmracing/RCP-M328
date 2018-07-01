-- Global Variables
lasttime=0 --last execute time
sxb = 0 --shiftx button state

-- Dynamic RCP Channels
Fuel1Id = addChannel("FuelRaw", 10, 1, 0,17,"GAL")
Fuel2Id = addChannel("FuelRemain", 10, 1, 0,17,"GAL")
maxRpmId = addChannel("RPMMax", 10, 0, 0,15000,"RPM")
speeddiff_id = addChannel("SpeedWheel",10,0,0,160,"MPH")
gear_id = addChannel("GearCurrent",5,0,0,5,"Gear")

-- Custom Functions

-- WarnCheck controls the state of a GPIO for a master warning light based on OT, WT, OP constants
-- For Oil Pressure, it will only sound if the engine is running over 500 RPMs
function WarnCheck()
 local Warning = 0
 local OilPress = getAnalog(0)
 local OilTemp = getAnalog(1)

 if getTimerRpm(0) > 500 then  -- make sure engine is running, if not don't check oil pressure
  if getAnalog(5) > 50 then -- check TPS
   if OilPress < 20 then Warning = 1 end  --  on more than 50% thottle check for minimum pressure of 20 psi
  else
   if OilPress < 6 then Warning = 1 end  -- on less than 50% throttle check for idle pressureof 6 psi
  end
 end

 if OilTemp > 275 then Warning = 1 end  --  check oil temp activate master warning if above 275*F

 if getAnalog(2) > 240 then Warning = 1 end --  check water temp activate master warning if above 240*F
 
 setGpio(2,Warning)
end


-- updateGear updates the dynamic channel that indicates the current gear in which the car is operating and the road speed measured at the wheels
function updateGear()
 local rpm_diff = getTimerRpm(1)
 local speed = rpm_diff*24.8*0.002975  -- The diamater in inches of the driven tire
 speed = speed + 0.5 -- round because 0 prec. truncates
 
 setChannel(speeddiff_id, speed)
 
 local rpm = getTimerRpm(0)
 local gearErr = 0.15
 local gear = 0
 if speed > 2 then
  local ratio = rpm/(rpm_diff*3.73)  -- final drive ratio
  if ((4.20  - ratio)^2) < (gearErr^2) then gear = 1 end -- transmission ratio for 1st gear
  if ((2.49 - ratio)^2) < (gearErr^2) then gear = 2 end --  transmission ratio for 2nd gear
  if ((1.66  - ratio)^2) < (gearErr^2) then gear = 3 end  -- transmission ratio for 3rd gear
  if ((1.24 - ratio)^2) < (gearErr^2) then gear = 4 end -- transmission ratio for 4th gear
  if ((1.00  - ratio)^2) < (gearErr^2) then gear = 5 end -- transmission ratio for 5th gear
 end
 setChannel(gear_id, gear)
end


-- RevCheck updates the dynamic channels that records the maximum RPM and the over rev flag.
function RevCheck()
 local rpmChk = getTimerRpm(0)
 local maxRpm = getChannel(maxRpmId)
 
 if rpmChk > maxRpm then
  maxRpm = rpmChk
  setChannel(maxRpmId, maxRpm)
 end
end


--  updateFuel updates both the dynamic channels for raw fuel and average fuel level.
--  If GPS speed is below 10 mph, average fuel level is set to raw.
--  The function accepts an argument value for the current fuel reading.
-- Fuel remaining is only updated when the G forces in any direction are less than .35G
function updateFuel(value)
 local SpeedMPH = getGpsSpeed()
 local AccX = getImu(0)
 local AccY = getImu(1)
 local bfl = getChannel(Fuel2Id)
 
 if AccX < 0 then AccX = AccX*(-1) end
 if AccY < 0 then AccY = AccY*(-1) end
 
 if AccX < 0.35 and AccY < 0.35 then 
    bfl=((bfl*2)+value)/3
 end

 if SpeedMPH < 10 then -- if less than 10 MPH write raw fuel level to fuel remaining
   setChannel(Fuel2Id, value)
 else
   setChannel(Fuel2Id, bfl,1)
 end

 setChannel(Fuel1Id, value)
end


-- GetFuelLevelRaw converts the current reading of the OEM E36 fuel level senders into gallons in the tank.
function GetFuelLevelRaw()
 local FuelLevelVolts = getAnalog(4)
 local BatteryVolts = getAnalog(7)
 
 return ((((FuelLevelVolts*1100)/(BatteryVolts-FuelLevelVolts))-21)/29.625) --Fuel PullUp resistor value 1100
end


--  FanControl set the state of a GPIO that controls the engine cooling fan.
--  It uses constants for the set points of temperature and speed.
--  Both the speed and thresholds have to be met before the fan will turn on.
function FanControl()
 local WaterTemp = getAnalog(2)
 local SpeedMPH = getGpsSpeed()

 if SpeedMPH < 45 then --Only activate the fan below 45 MPH
  if WaterTemp < 175 then  --- If water temo is 5*F less than the on temp then turn off
   setGpio(0,0)
  else
   if WaterTemp > 180  then --Fan On at water temp of 180*F
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
  sxUpdateAlert(1, getChannel(Fuel2Id))
end

function sxShift()
 --config shift light
  sxCfgLinearGraph(0,0,0,7200) --left to right graph, linear style, 0 - 7200 RPM range

  sxSetLinearThresh(0,0,5000,0,255,0,0) -- green 
  sxSetLinearThresh(1,0,6700,255,0,0,0) -- red 
  sxSetLinearThresh(2,0,7100,0,0,255,10) -- blue+flash 
 end

function sxPit()
  --config pit speedo
  sxCfgLinearGraph(1,0,30,40) --center-out graph, linear style, 30-45 mph 35 center

  sxSetLinearThresh(0,0,30,0,255,0,0) --Green, too slow, go faster
  sxSetLinearThresh(1,0,35,0,0,255,0) --blue right at 35 mph
  sxSetLinearThresh(2,0,40,255,0,0,0) --red, too fast, slow down
 end

function sxOnInit()
  --config shift light
  sxShift()

  --configure first alert (right LED) as engine temperature (F)
  sxSetAlertThresh(0,0,220,255,255,0,0) --  yellow warning at 220*F
  sxSetAlertThresh(0,1,240,255,0,0,10) --  red flash at 240*F

  --configure second alert (left LED) as Fuel Remaining (Gal)
  sxSetAlertThresh(1,0,0,255,0,0,10) -- red flash from 2-0 Gal
  sxSetAlertThresh(1,1,2,255,255,0,0) -- yellow from 4-2 Gal
  sxSetAlertThresh(1,2,4,0,0,0,0) --  no alert above 4 Gal
end

function sxOnBut(b)
  if sxb == 1 and (lasttime+1500) < getUpTime() then
     sxShift()
	 sxb=0
  else
     sxPit()
	 sxb=1
  end
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
  setBaseConfig(0) --Brightness set to 0=auto
  if sxOnInit~=nil then sxOnInit() end
end

function sxChkCan()
  id,ext,data=rxCAN(1,0)  
  if id==sxCanId then sxInit() end
  if id==sxCanId+60 and sxOnBut~=nil then sxOnBut(data[1]) end
end

function sxProcess()
  sxChkCan()
  if sxOnUpdate~=nil then sxOnUpdate() end
end

function sxTx(offset, data)
  txCAN(1, sxCanId + offset, 1, data) 
  sleep(10)
end

function spl(v) return bit.band(v,0xFF) end
function sph(v) return bit.rshift(bit.band(v,0xFF00),8) end

-- Initalize settings
setTickRate(30) -- tickRate, Set execution interval in Hz
sxCanId = 0xE3600 -- + (256 * sxId)
sxInit()
setChannel(Fuel2Id,GetFuelLevelRaw())


-- Master execution function
function onTick()
 RevCheck()
 updateGear()
 WarnCheck()
 sxProcess()
 
 -- Functions in this section are only executed once a second regardless of tickrate
 if (lasttime+1000) < getUptime() then
  lasttime = getUptime() 
  FanControl()
  updateFuel(GetFuelLevelRaw())
 end
end

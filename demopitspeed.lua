--This is a demo script to show using the ShiftX2 for multiple functions.
--It also displays using the centered graph style as a pit lane speedometer.

-- Global Variables
btntime=0 --last time shiftx button pressesd
sxb = 0 --shiftx mode, 0 = Shift Light, 1 = Pit Lane Speed

-- Dynamic RCP Channels
PSId = addChannel("Spd", 25, 1, 0,150,"MPH")  -- Speed channel
RevId = addChannel("Rev", 25, 1, 0,7000,"RPM") -- RPM channel
FLId = addChannel("Fuel", 25, 1, 0,15,"GAL")  -- Fuel level channel
WTId = addChannel("WT", 25, 1, 0,250,"F") -- Water temp channel

-- Custom Functions

-- This function is used to generate dummy data for the demo
function UpdateData()
	-- Speed (MPH) data
	if getChannel(PSId) >= 50 then
	  setChannel(PSId, 20)
	else
	  setChannel(PSId, getChannel(PSId) + .1)
	end
	
	-- RPM data
	if getChannel(RevId) >= 7000 then
	  setChannel(RevId, 0)
	else
	  setChannel(RevId, getChannel(RevId) + 25)
	end
	
	-- Fuel level data in gallons
	if getChannel(FLId) <= 0 then
	  setChannel(FLId, 15)
	else
	  setChannel(FLId, getChannel(FLId) - .1)
	end	

    -- Water temperature data
	if getChannel(WTId) >= 250 then
	  setChannel(WTId, 200)
	else
	  setChannel(WTId, getChannel(WTId) + .5)
	end		
end


-- Update ShiftX2 alerts or linear graph during run time.
-- Runs continuously based on tickRate.
function sxOnUpdate()
  if sxb == 1 then  
    -- Pit lane speed mode.  Ensure speed values don't exceed either end of the range.
	local pitspeed = getChannel(PSId)
	if pitspeed > 40 then pitspeed = 40 end
	if pitspeed < 30 then pitspeed = 30 end
	sxUpdateLinearGraph((pitspeed-30)*10)
  else
    -- Shift light mode.  Ensure speed values don't exceed either end of the range.
	local pitrevs = getChannel(RevId)
	if pitrevs > 7000 then pitrevs = 7000 end
	if pitrevs < 4000 then pitrevs = 4000 end
	sxUpdateLinearGraph(pitrevs-4000)
  end
  --update engine temp alert
  sxUpdateAlert(0, getChannel(WTId))
    
  --update Fuel Remaining alert
  sxUpdateAlert(1, getChannel(FLId))
end

function sxShift()
 --config shift light
  sxCfgLinearGraph(0,0,0,3000) --left to right graph, linear style, 4000 - 7000 RPM range, Subtract 4000 from redline to use all LED for progression.

  sxSetLinearThresh(0,0,0001,0,255,0,0) -- green, on at 4001 RPM (7000-4000+1)
  sxSetLinearThresh(1,0,1500,255,0,0,0) -- red, on at 5500 RPM (5500-4000)
  sxSetLinearThresh(2,0,2750,0,0,255,10) -- blue+flash  on at 6750 (6750-4000)
 end

function sxPit()
  --config pit speedo
  sxCfgLinearGraph(1,0,0,100) --center-out graph, linear style, 30-40 (0-100) mph 35 center scaled * 10

  sxSetLinearThresh(0,0,0,0,255,0,0) --Green, too slow, go faster (30-33.4 mph)
  sxSetLinearThresh(1,0,35,0,0,255,0) --blue right at 35 mph (33.5-35.1 mph)
  sxSetLinearThresh(2,0,52,255,0,0,10) --red, too fast, slow down (35.2-40 mph)
 end

function sxOnInit()
  --config shift light
  sxShift() -- start in shift light mode

  --configure first alert (right LED) as engine temperature (F)
  sxSetAlertThresh(0,0,220,255,255,0,0) --  yellow warning at 220*F
  sxSetAlertThresh(0,1,240,255,0,0,10) --  red flash at 240*F

  --configure second alert (left LED) as Fuel Remaining (Gal)
  sxSetAlertThresh(1,0,0,255,0,0,10) -- red flash from 2-0 Gal
  sxSetAlertThresh(1,1,2,255,255,0,0) -- yellow from 4-2 Gal
  sxSetAlertThresh(1,2,4,0,0,0,0) --  no alert above 4 Gal
end

function sxOnBut(b)
  -- create a toggle for the button.  This locks out the button for 2 seconds after the press to prevent acidental multiple presses.
  if (btntime+2000) < getUptime() then
    btntime=getUptime()	 
    if sxb == 1 then
      sxShift()
	  sxb=0
    else
      sxPit()
	  sxb=1
    end
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
sxInit()  --Iniralize the ShiftX2
--  Set starting values for demo data channels
setChannel(PSId, 20)
setChannel(RevId, 0)
setChannel(FLId, 15)
setChannel(WTId, 200)



-- Master execution function
function onTick()
 sxProcess()
 UpdateData()
end

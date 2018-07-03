-- Speed is multipled  by 10.  30 MPH = 300, etc.
fakespeed = 300 

-- Update ShiftX2 alerts or linear graph during run time.
-- Runs continuously based on tickRate.
function sxOnUpdate()
  --Update Direct RPM on input 0
  sxUpdateLinearGraph(fakespeed)
  println('Speed: '..fakespeed)
  if fakespeed == 400 then
    fakespeed = 300 
  else
    fakespeed = fakespeed + 1
  end
 end


function sxOnInit()
  --config pit speedo
  sxCfgLinearGraph(1,0,300,400) --center-out graph, linear style, 30-40 mph 35 center scaled * 10

  sxSetLinearThresh(0,0,300,0,255,0,0) --Green, too slow, go faster (30-34 mph)
  sxSetLinearThresh(1,0,340,0,0,255,0) --blue right at 35 mph (34-36 mph)
  sxSetLinearThresh(2,0,360,255,0,0,10) --red, too fast, slow down (36-40 mph)
end

function sxOnBut(b)
  --ShiftX Button Press
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


-- Master execution function
function onTick()
 sxProcess()
end

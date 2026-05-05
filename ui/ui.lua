-- Dragonsz Admin v2 | LocalScript
-- Abas: Funções | RAID | Teleport | Config

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

return function(Modules)
    local FlyModule       = Modules.Fly
    local HighlightModule = Modules.Highlight
    local NoclipModule    = Modules.Noclip
    local AutofarmModule  = Modules.Autofarm
    local VoidModule      = Modules.Void
    local EspModule       = Modules.Esp
    local TeleportModule  = Modules.Teleport

local FLY_SPEED_DEFAULT = 60
local FLY_SPEED_MIN     = 10
local FLY_SPEED_MAX     = 300
local FLY_SPEED_STEP    = 10
local HL_COLOR          = Color3.fromRGB(77, 184, 255)
local HL_FILL           = Color3.fromRGB(30, 100, 200)

local KB = {
	FLY      = Enum.KeyCode.F1,
	HL       = Enum.KeyCode.F2,
	NC       = Enum.KeyCode.F3,
	TP_MARK  = Enum.KeyCode.F4,
	TP_GO    = Enum.KeyCode.F5,
	MIN      = Enum.KeyCode.K,
	SPD_UP   = Enum.KeyCode.KeypadPlus,
	SPD_DOWN = Enum.KeyCode.KeypadMinus,
}
local KB_LABELS = {
	FLY="Voar", HL="Highlight", NC="NoClip",
	TP_MARK="Marcar Posição", TP_GO="Teleportar",
	MIN="Minimizar", SPD_UP="Vel. +", SPD_DOWN="Vel. -",
}

local flySpeed     = FLY_SPEED_DEFAULT
local flying       = false
local hlOn         = false
local ncOn         = false
local farmRaidOn   = false
local espOn        = false
local autofarmOn   = false
local autofarmDist = 3
local minimized    = false
local closed       = false
local inputConn    = nil
local listeningFor = nil

local C = {
	bg=Color3.fromRGB(11,13,18), panel=Color3.fromRGB(15,18,25),
	header=Color3.fromRGB(9,20,33), row=Color3.fromRGB(18,23,34),
	rowOn=Color3.fromRGB(13,28,46), stroke=Color3.fromRGB(28,40,58),
	strokeB=Color3.fromRGB(40,65,100), blue=Color3.fromRGB(77,184,255),
	blueD=Color3.fromRGB(22,80,145), blueDim=Color3.fromRGB(30,55,85),
	text=Color3.fromRGB(195,215,235), sub=Color3.fromRGB(70,95,120),
	togOff=Color3.fromRGB(22,32,48), knobOff=Color3.fromRGB(60,85,110),
	red=Color3.fromRGB(255,80,80), redBg=Color3.fromRGB(55,14,14),
	redD=Color3.fromRGB(100,22,22), green=Color3.fromRGB(80,220,130),
	greenD=Color3.fromRGB(18,65,38), orange=Color3.fromRGB(255,170,60),
	orangeD=Color3.fromRGB(65,38,10), purple=Color3.fromRGB(170,100,255),
	purpleD=Color3.fromRGB(50,25,80), gold=Color3.fromRGB(255,210,80),
	teal=Color3.fromRGB(60,210,180), tealD=Color3.fromRGB(12,58,50),
}

local function mkCorner(obj,r) Instance.new("UICorner",obj).CornerRadius=UDim.new(0,r or 7) end
local function mkStroke(obj,col,thick) local s=Instance.new("UIStroke",obj); s.Color=col or C.stroke; s.Thickness=thick or 1 end

local function keyName(kc)
	local map={KeypadPlus="Num+",KeypadMinus="Num-",LeftControl="LCtrl",
		RightControl="RCtrl",LeftShift="LShift",RightShift="RShift",
		LeftAlt="LAlt",RightAlt="RAlt"}
	return map[kc.Name] or kc.Name
end

-- GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name="DragonsZ_v2"; screenGui.ResetOnSpawn=false
screenGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
screenGui.Parent=player.PlayerGui

local panel = Instance.new("Frame")
panel.Name="Panel"; panel.Size=UDim2.new(0,270,0,400)
panel.Position=UDim2.new(0,24,0,24); panel.BackgroundColor3=C.panel
panel.BorderSizePixel=0; panel.Active=true; panel.Parent=screenGui
mkCorner(panel,10); mkStroke(panel,C.stroke)
local pg=Instance.new("UIGradient",panel)
pg.Color=ColorSequence.new({ColorSequenceKeypoint.new(0,Color3.fromRGB(15,20,32)),ColorSequenceKeypoint.new(1,Color3.fromRGB(11,14,20))})
pg.Rotation=135

-- Header
local header=Instance.new("Frame")
header.Size=UDim2.new(1,0,0,38); header.BackgroundColor3=C.header
header.BorderSizePixel=0; header.Active=true; header.Parent=panel
mkCorner(header,10)
local hFix=Instance.new("Frame"); hFix.Size=UDim2.new(1,0,0,10)
hFix.Position=UDim2.new(0,0,1,-10); hFix.BackgroundColor3=C.header
hFix.BorderSizePixel=0; hFix.Parent=header
local ha=Instance.new("Frame"); ha.Size=UDim2.new(0,40,0,2)
ha.Position=UDim2.new(0,10,0,0); ha.BackgroundColor3=C.blue
ha.BorderSizePixel=0; ha.Parent=header; mkCorner(ha,1)

local titleLbl=Instance.new("TextLabel"); titleLbl.Size=UDim2.new(1,-90,1,0)
titleLbl.Position=UDim2.new(0,12,0,0); titleLbl.BackgroundTransparency=1
titleLbl.Text="DRAGONSZ"; titleLbl.TextColor3=C.blue; titleLbl.TextSize=13
titleLbl.Font=Enum.Font.GothamBold; titleLbl.TextXAlignment=Enum.TextXAlignment.Left
titleLbl.Parent=header

local verLbl=Instance.new("TextLabel"); verLbl.Size=UDim2.new(0,30,0,12)
verLbl.Position=UDim2.new(0,82,0.5,-6); verLbl.BackgroundColor3=C.blueDim
verLbl.BorderSizePixel=0; verLbl.Text="v2"; verLbl.TextColor3=C.blue
verLbl.TextSize=9; verLbl.Font=Enum.Font.GothamBold; verLbl.Parent=header
mkCorner(verLbl,3)

local minBtn=Instance.new("TextButton"); minBtn.Size=UDim2.new(0,26,0,26)
minBtn.Position=UDim2.new(1,-60,0.5,-13); minBtn.BackgroundColor3=C.togOff
minBtn.BorderSizePixel=0; minBtn.Text="—"; minBtn.TextColor3=C.sub
minBtn.TextSize=12; minBtn.Font=Enum.Font.GothamBold; minBtn.Parent=header
mkCorner(minBtn,6); mkStroke(minBtn,C.stroke)

local closeBtn=Instance.new("TextButton"); closeBtn.Size=UDim2.new(0,26,0,26)
closeBtn.Position=UDim2.new(1,-30,0.5,-13); closeBtn.BackgroundColor3=C.redBg
closeBtn.BorderSizePixel=0; closeBtn.Text="✕"; closeBtn.TextColor3=C.red
closeBtn.TextSize=11; closeBtn.Font=Enum.Font.GothamBold; closeBtn.Parent=header
mkCorner(closeBtn,6); mkStroke(closeBtn,C.redD)

-- Tab Bar
local tabBar=Instance.new("Frame"); tabBar.Size=UDim2.new(1,-16,0,30)
tabBar.Position=UDim2.new(0,8,0,42); tabBar.BackgroundColor3=C.togOff
tabBar.BorderSizePixel=0; tabBar.Parent=panel; mkCorner(tabBar,7); mkStroke(tabBar,C.stroke)
local tbl=Instance.new("UIListLayout",tabBar); tbl.FillDirection=Enum.FillDirection.Horizontal
tbl.SortOrder=Enum.SortOrder.LayoutOrder; tbl.Padding=UDim.new(0,2)
local tp=Instance.new("UIPadding",tabBar); tp.PaddingLeft=UDim.new(0,3)
tp.PaddingRight=UDim.new(0,3); tp.PaddingTop=UDim.new(0,3); tp.PaddingBottom=UDim.new(0,3)

local function makeTabBtn(label,order)
	local b=Instance.new("TextButton"); b.Size=UDim2.new(0.25,-2,1,0)
	b.BackgroundColor3=Color3.fromRGB(0,0,0); b.BackgroundTransparency=1
	b.BorderSizePixel=0; b.Text=label; b.TextColor3=C.sub; b.TextSize=10
	b.Font=Enum.Font.GothamBold; b.LayoutOrder=order; b.Parent=tabBar; mkCorner(b,5)
	return b
end
local tabMain=makeTabBtn("FUNÇÕES",1); local tabRaid=makeTabBtn("RAID",2)
local tabTeleport=makeTabBtn("TELEPORT",3); local tabConfig=makeTabBtn("CONFIG",4)

-- Content frames
local function makeContent(visible)
	local f=Instance.new("ScrollingFrame")
	f.Size=UDim2.new(1,-16,0,310); f.Position=UDim2.new(0,8,0,78)
	f.BackgroundTransparency=1; f.BorderSizePixel=0; f.ScrollBarThickness=3
	f.ScrollBarImageColor3=C.blueD; f.CanvasSize=UDim2.new(0,0,0,0)
	f.AutomaticCanvasSize=Enum.AutomaticSize.Y; f.Visible=visible; f.Parent=panel
	local l=Instance.new("UIListLayout",f); l.SortOrder=Enum.SortOrder.LayoutOrder
	l.Padding=UDim.new(0,6)
	return f
end
local contentMain=makeContent(true); local contentRaid=makeContent(false)
local contentTeleport=makeContent(false); local contentConfig=makeContent(false)

-- Helpers
local function makeCard(parent,lo,h)
	local c=Instance.new("Frame"); c.Size=UDim2.new(1,0,0,h or 50)
	c.BackgroundColor3=C.row; c.BorderSizePixel=0; c.LayoutOrder=lo; c.Parent=parent
	mkCorner(c,8); mkStroke(c,C.stroke); return c
end
local function makeIcon(parent,text,color,bg)
	local ic=Instance.new("TextLabel"); ic.Size=UDim2.new(0,32,0,32)
	ic.Position=UDim2.new(0,10,0.5,-16); ic.BackgroundColor3=bg or C.header
	ic.BorderSizePixel=0; ic.Text=text; ic.TextColor3=color or C.blue
	ic.TextSize=10; ic.Font=Enum.Font.GothamBold
	ic.TextXAlignment=Enum.TextXAlignment.Center
	ic.TextYAlignment=Enum.TextYAlignment.Center
	ic.Parent=parent; mkCorner(ic,6); return ic
end
-- makeToggle: FUNÇÃO QUE ESTAVA FALTANDO
local function makeToggle(parent)
	local tog=Instance.new("Frame"); tog.Size=UDim2.new(0,40,0,22)
	tog.Position=UDim2.new(1,-50,0.5,-11); tog.BackgroundColor3=C.togOff
	tog.BorderSizePixel=0; tog.Parent=parent; mkCorner(tog,11); mkStroke(tog,C.stroke)
	local knob=Instance.new("Frame"); knob.Size=UDim2.new(0,16,0,16)
	knob.Position=UDim2.new(0,3,0.5,-8); knob.BackgroundColor3=C.knobOff
	knob.BorderSizePixel=0; knob.Parent=tog; mkCorner(knob,8)
	return tog,knob
end
local function makeToggleRow(parent,icon,ic,ib,label,hotkey,order)
	local card=makeCard(parent,order,52); makeIcon(card,icon,ic,ib)
	local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(0,120,0,16)
	lbl.Position=UDim2.new(0,52,0.5,-18); lbl.BackgroundTransparency=1
	lbl.Text=label; lbl.TextColor3=C.text; lbl.TextSize=13
	lbl.Font=Enum.Font.GothamBold; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=card
	local klbl=Instance.new("TextLabel"); klbl.Size=UDim2.new(0,140,0,13)
	klbl.Position=UDim2.new(0,52,0.5,4); klbl.BackgroundTransparency=1
	klbl.Text="[ "..hotkey.." ]"; klbl.TextColor3=C.sub; klbl.TextSize=10
	klbl.Font=Enum.Font.Code; klbl.TextXAlignment=Enum.TextXAlignment.Left; klbl.Parent=card
	local tog,knob=makeToggle(card)
	return card,tog,knob,klbl
end

-- ABA MAIN
local flyRow,flyTog,flyKnob,flyKlbl=makeToggleRow(contentMain,"FLY",C.blue,C.header,"Voar",keyName(KB.FLY),1)
local hlRow,hlTog,hlKnob,hlKlbl=makeToggleRow(contentMain,"HL",C.blue,C.header,"Highlight",keyName(KB.HL),2)
local ncRow,ncTog,ncKnob,ncKlbl=makeToggleRow(contentMain,"NC",C.purple,C.purpleD,"NoClip",keyName(KB.NC),3)

-- Farm Raid card (ESTAVA FALTANDO)
local farmRow=makeCard(contentMain,4,52)
makeIcon(farmRow,"FARM",C.green,C.greenD)
local farmLbl=Instance.new("TextLabel"); farmLbl.Size=UDim2.new(0,120,0,16)
farmLbl.Position=UDim2.new(0,52,0.5,-8); farmLbl.BackgroundTransparency=1
farmLbl.Text="Farm Raid"; farmLbl.TextColor3=C.text; farmLbl.TextSize=13
farmLbl.Font=Enum.Font.GothamBold; farmLbl.TextXAlignment=Enum.TextXAlignment.Left; farmLbl.Parent=farmRow
local farmTog,farmKnob=makeToggle(farmRow)

-- Speed card
local spdCard=makeCard(contentMain,5,72)
makeIcon(spdCard,"SPD",C.gold,C.header)
local spdTitle=Instance.new("TextLabel"); spdTitle.Size=UDim2.new(0,140,0,14)
spdTitle.Position=UDim2.new(0,52,0,8); spdTitle.BackgroundTransparency=1
spdTitle.Text="Velocidade de Voo"; spdTitle.TextColor3=C.text; spdTitle.TextSize=12
spdTitle.Font=Enum.Font.GothamBold; spdTitle.TextXAlignment=Enum.TextXAlignment.Left; spdTitle.Parent=spdCard
local spdKey=Instance.new("TextLabel"); spdKey.Size=UDim2.new(0,180,0,12)
spdKey.Position=UDim2.new(0,52,0,24); spdKey.BackgroundTransparency=1
spdKey.Text="[ "..keyName(KB.SPD_UP).." / "..keyName(KB.SPD_DOWN).." ]"
spdKey.TextColor3=C.sub; spdKey.TextSize=10; spdKey.Font=Enum.Font.Code
spdKey.TextXAlignment=Enum.TextXAlignment.Left; spdKey.Parent=spdCard
local btnMinus=Instance.new("TextButton"); btnMinus.Size=UDim2.new(0,28,0,24)
btnMinus.Position=UDim2.new(0,10,1,-32); btnMinus.BackgroundColor3=C.togOff
btnMinus.BorderSizePixel=0; btnMinus.Text="−"; btnMinus.TextColor3=C.blue
btnMinus.TextSize=18; btnMinus.Font=Enum.Font.GothamBold; btnMinus.Parent=spdCard
mkCorner(btnMinus,6); mkStroke(btnMinus,C.strokeB)
local spdDisplay=Instance.new("TextLabel"); spdDisplay.Size=UDim2.new(0,50,0,24)
spdDisplay.Position=UDim2.new(0,44,1,-32); spdDisplay.BackgroundColor3=C.header
spdDisplay.BorderSizePixel=0; spdDisplay.Text=tostring(flySpeed)
spdDisplay.TextColor3=C.gold; spdDisplay.TextSize=13; spdDisplay.Font=Enum.Font.GothamBold
spdDisplay.Parent=spdCard; mkCorner(spdDisplay,5); mkStroke(spdDisplay,C.strokeB)
local btnPlus=Instance.new("TextButton"); btnPlus.Size=UDim2.new(0,28,0,24)
btnPlus.Position=UDim2.new(0,100,1,-32); btnPlus.BackgroundColor3=C.togOff
btnPlus.BorderSizePixel=0; btnPlus.Text="+"; btnPlus.TextColor3=C.blue
btnPlus.TextSize=18; btnPlus.Font=Enum.Font.GothamBold; btnPlus.Parent=spdCard
mkCorner(btnPlus,6); mkStroke(btnPlus,C.strokeB)
local sliderBg=Instance.new("Frame"); sliderBg.Size=UDim2.new(1,-148,0,6)
sliderBg.Position=UDim2.new(0,140,1,-22); sliderBg.BackgroundColor3=C.togOff
sliderBg.BorderSizePixel=0; sliderBg.Parent=spdCard; mkCorner(sliderBg,3)
local sliderFill=Instance.new("Frame"); sliderFill.Size=UDim2.new(0.5,0,1,0)
sliderFill.BackgroundColor3=C.gold; sliderFill.BorderSizePixel=0
sliderFill.Parent=sliderBg; mkCorner(sliderFill,3)

-- ABA RAID
local raidSep=Instance.new("TextLabel"); raidSep.Size=UDim2.new(1,0,0,18)
raidSep.BackgroundTransparency=1; raidSep.Text="——  RAID TOOLS  ——"
raidSep.TextColor3=C.sub; raidSep.TextSize=9; raidSep.Font=Enum.Font.GothamBold
raidSep.LayoutOrder=1; raidSep.Parent=contentRaid

local espCard=makeCard(contentRaid,2,54); makeIcon(espCard,"ESP",C.purple,C.purpleD)
local espTitle=Instance.new("TextLabel"); espTitle.Size=UDim2.new(1,-110,0,18)
espTitle.Position=UDim2.new(0,54,0,10); espTitle.BackgroundTransparency=1
espTitle.Text="ESP — NPCs"; espTitle.TextColor3=C.text; espTitle.TextSize=13
espTitle.Font=Enum.Font.GothamBold; espTitle.TextXAlignment=Enum.TextXAlignment.Left; espTitle.Parent=espCard
local espSub=Instance.new("TextLabel"); espSub.Size=UDim2.new(1,-110,0,14)
espSub.Position=UDim2.new(0,54,0,30); espSub.BackgroundTransparency=1
espSub.Text="Nome dos NPCs na tela"; espSub.TextColor3=C.sub; espSub.TextSize=10
espSub.Font=Enum.Font.Code; espSub.TextXAlignment=Enum.TextXAlignment.Left; espSub.Parent=espCard
local espTog,espKnob=makeToggle(espCard)

local voidCard=makeCard(contentRaid,3,54); makeIcon(voidCard,"VOID",C.teal,C.tealD)
local voidTitle=Instance.new("TextLabel"); voidTitle.Size=UDim2.new(1,-110,0,18)
voidTitle.Position=UDim2.new(0,54,0,10); voidTitle.BackgroundTransparency=1
voidTitle.Text="Void"; voidTitle.TextColor3=C.text; voidTitle.TextSize=13
voidTitle.Font=Enum.Font.GothamBold; voidTitle.TextXAlignment=Enum.TextXAlignment.Left; voidTitle.Parent=voidCard
local voidSub=Instance.new("TextLabel"); voidSub.Size=UDim2.new(1,-110,0,14)
voidSub.Position=UDim2.new(0,54,0,30); voidSub.BackgroundTransparency=1
voidSub.Text="-488, -448, -871"; voidSub.TextColor3=C.sub; voidSub.TextSize=10
voidSub.Font=Enum.Font.Code; voidSub.TextXAlignment=Enum.TextXAlignment.Left; voidSub.Parent=voidCard
local voidBtn=Instance.new("TextButton"); voidBtn.Size=UDim2.new(0,60,0,28)
voidBtn.Position=UDim2.new(1,-68,0.5,-14); voidBtn.BackgroundColor3=C.tealD
voidBtn.BorderSizePixel=0; voidBtn.Text="IR"; voidBtn.TextColor3=C.teal
voidBtn.TextSize=12; voidBtn.Font=Enum.Font.GothamBold; voidBtn.Parent=voidCard
mkCorner(voidBtn,7); mkStroke(voidBtn,Color3.fromRGB(20,80,70))

local afCard=makeCard(contentRaid,4,88); makeIcon(afCard,"AUTO",C.orange,C.orangeD)
local afTitle=Instance.new("TextLabel"); afTitle.Size=UDim2.new(1,-110,0,18)
afTitle.Position=UDim2.new(0,54,0,8); afTitle.BackgroundTransparency=1
afTitle.Text="Autofarm"; afTitle.TextColor3=C.text; afTitle.TextSize=13
afTitle.Font=Enum.Font.GothamBold; afTitle.TextXAlignment=Enum.TextXAlignment.Left; afTitle.Parent=afCard
local afSub=Instance.new("TextLabel"); afSub.Size=UDim2.new(1,-110,0,14)
afSub.Position=UDim2.new(0,54,0,27); afSub.BackgroundTransparency=1
afSub.Text="Ataca NPCs próximos"; afSub.TextColor3=C.sub; afSub.TextSize=10
afSub.Font=Enum.Font.Code; afSub.TextXAlignment=Enum.TextXAlignment.Left; afSub.Parent=afCard
local afTog,afKnob=makeToggle(afCard)
local afDistLabel=Instance.new("TextLabel"); afDistLabel.Size=UDim2.new(0,90,0,12)
afDistLabel.Position=UDim2.new(0,10,1,-26); afDistLabel.BackgroundTransparency=1
afDistLabel.Text="Dist: "..autofarmDist.." studs"; afDistLabel.TextColor3=C.sub
afDistLabel.TextSize=9; afDistLabel.Font=Enum.Font.Code
afDistLabel.TextXAlignment=Enum.TextXAlignment.Left; afDistLabel.Parent=afCard
local afSliderBg=Instance.new("Frame"); afSliderBg.Size=UDim2.new(1,-110,0,6)
afSliderBg.Position=UDim2.new(0,100,1,-20); afSliderBg.BackgroundColor3=C.togOff
afSliderBg.BorderSizePixel=0; afSliderBg.Parent=afCard; mkCorner(afSliderBg,3); mkStroke(afSliderBg,C.stroke)
local afSliderFill=Instance.new("Frame"); afSliderFill.BackgroundColor3=C.orange
afSliderFill.BorderSizePixel=0; afSliderFill.Parent=afSliderBg; mkCorner(afSliderFill,3)
afSliderFill.Size=UDim2.new(math.clamp((autofarmDist-1)/(15-1),0,1),0,1,0)

-- ABA TELEPORT
local savedPosCard=makeCard(contentTeleport,1,90); makeIcon(savedPosCard,"TP",C.orange,C.orangeD)
local tpTitle=Instance.new("TextLabel"); tpTitle.Size=UDim2.new(1,-55,0,14)
tpTitle.Position=UDim2.new(0,52,0,8); tpTitle.BackgroundTransparency=1
tpTitle.Text="Posição Salva"; tpTitle.TextColor3=C.text; tpTitle.TextSize=12
tpTitle.Font=Enum.Font.GothamBold; tpTitle.TextXAlignment=Enum.TextXAlignment.Left; tpTitle.Parent=savedPosCard
local raidTpCoords=Instance.new("TextLabel"); raidTpCoords.Size=UDim2.new(1,-16,0,14)
raidTpCoords.Position=UDim2.new(0,8,0,26); raidTpCoords.BackgroundTransparency=1
raidTpCoords.Text="X: --   Y: --   Z: --"; raidTpCoords.TextColor3=C.sub
raidTpCoords.TextSize=10; raidTpCoords.Font=Enum.Font.Code
raidTpCoords.TextXAlignment=Enum.TextXAlignment.Center; raidTpCoords.Parent=savedPosCard
local raidBtnMark=Instance.new("TextButton"); raidBtnMark.Size=UDim2.new(0.48,-4,0,24)
raidBtnMark.Position=UDim2.new(0,8,1,-32); raidBtnMark.BackgroundColor3=C.orangeD
raidBtnMark.BorderSizePixel=0; raidBtnMark.Text="📍 Marcar"; raidBtnMark.TextColor3=C.orange
raidBtnMark.TextSize=11; raidBtnMark.Font=Enum.Font.GothamBold; raidBtnMark.Parent=savedPosCard
mkCorner(raidBtnMark,6); mkStroke(raidBtnMark,Color3.fromRGB(100,60,10))
local raidBtnGo=Instance.new("TextButton"); raidBtnGo.Size=UDim2.new(0.48,-4,0,24)
raidBtnGo.Position=UDim2.new(0.52,-4,1,-32); raidBtnGo.BackgroundColor3=C.greenD
raidBtnGo.BorderSizePixel=0; raidBtnGo.Text="🚀 Ir"; raidBtnGo.TextColor3=C.green
raidBtnGo.TextSize=11; raidBtnGo.Font=Enum.Font.GothamBold; raidBtnGo.Parent=savedPosCard
mkCorner(raidBtnGo,6); mkStroke(raidBtnGo,Color3.fromRGB(20,80,40))

local coordCard=makeCard(contentTeleport,2,110); makeIcon(coordCard,"XYZ",C.blue,C.header)
local coordTitle=Instance.new("TextLabel"); coordTitle.Size=UDim2.new(1,-55,0,14)
coordTitle.Position=UDim2.new(0,52,0,8); coordTitle.BackgroundTransparency=1
coordTitle.Text="Teleport por Coordenadas"; coordTitle.TextColor3=C.text; coordTitle.TextSize=12
coordTitle.Font=Enum.Font.GothamBold; coordTitle.TextXAlignment=Enum.TextXAlignment.Left; coordTitle.Parent=coordCard
local coordHint=Instance.new("TextLabel"); coordHint.Size=UDim2.new(1,-55,0,12)
coordHint.Position=UDim2.new(0,52,0,24); coordHint.BackgroundTransparency=1
coordHint.Text="ex: 100, 50, -200"; coordHint.TextColor3=C.sub; coordHint.TextSize=9
coordHint.Font=Enum.Font.Code; coordHint.TextXAlignment=Enum.TextXAlignment.Left; coordHint.Parent=coordCard
local coordInput=Instance.new("TextBox"); coordInput.Size=UDim2.new(1,-16,0,26)
coordInput.Position=UDim2.new(0,8,0,42); coordInput.BackgroundColor3=C.header
coordInput.BorderSizePixel=0; coordInput.Text=""; coordInput.PlaceholderText="X, Y, Z"
coordInput.PlaceholderColor3=C.sub; coordInput.TextColor3=C.text; coordInput.TextSize=12
coordInput.Font=Enum.Font.Code; coordInput.ClearTextOnFocus=false; coordInput.Parent=coordCard
mkCorner(coordInput,6); mkStroke(coordInput,C.strokeB)
local coordFeedback=Instance.new("TextLabel"); coordFeedback.Size=UDim2.new(1,-16,0,14)
coordFeedback.Position=UDim2.new(0,8,0,72); coordFeedback.BackgroundTransparency=1
coordFeedback.Text=""; coordFeedback.TextColor3=C.sub; coordFeedback.TextSize=10
coordFeedback.Font=Enum.Font.Code; coordFeedback.TextXAlignment=Enum.TextXAlignment.Left; coordFeedback.Parent=coordCard
local coordBtnTp=Instance.new("TextButton"); coordBtnTp.Size=UDim2.new(1,-16,0,26)
coordBtnTp.Position=UDim2.new(0,8,1,-32); coordBtnTp.BackgroundColor3=C.blueD
coordBtnTp.BorderSizePixel=0; coordBtnTp.Text="Teleportar"; coordBtnTp.TextColor3=C.blue
coordBtnTp.TextSize=12; coordBtnTp.Font=Enum.Font.GothamBold; coordBtnTp.Parent=coordCard
mkCorner(coordBtnTp,6); mkStroke(coordBtnTp,Color3.fromRGB(30,70,120))

-- ABA CONFIG
local cfgHeader=Instance.new("TextLabel"); cfgHeader.Size=UDim2.new(1,0,0,20)
cfgHeader.BackgroundTransparency=1; cfgHeader.Text="TECLAS DE ATALHO"
cfgHeader.TextColor3=C.sub; cfgHeader.TextSize=10; cfgHeader.Font=Enum.Font.GothamBold
cfgHeader.LayoutOrder=0; cfgHeader.Parent=contentConfig

local rebindButtons={}
local function makeKeybindRow(kbKey,order)
	local card=makeCard(contentConfig,order,44)
	local lbl=Instance.new("TextLabel"); lbl.Size=UDim2.new(0,130,1,0)
	lbl.Position=UDim2.new(0,12,0,0); lbl.BackgroundTransparency=1
	lbl.Text=KB_LABELS[kbKey]; lbl.TextColor3=C.text; lbl.TextSize=12
	lbl.Font=Enum.Font.GothamBold; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Parent=card
	local btn=Instance.new("TextButton"); btn.Size=UDim2.new(0,80,0,26)
	btn.Position=UDim2.new(1,-88,0.5,-13); btn.BackgroundColor3=C.togOff
	btn.BorderSizePixel=0; btn.Text=keyName(KB[kbKey]); btn.TextColor3=C.blue
	btn.TextSize=11; btn.Font=Enum.Font.Code; btn.Parent=card
	mkCorner(btn,6); mkStroke(btn,C.strokeB)
	table.insert(rebindButtons,{key=kbKey,label=lbl,btn=btn})
	btn.MouseButton1Click:Connect(function()
		if closed then return end
		if listeningFor~=nil then
			for _,rb in ipairs(rebindButtons) do
				if rb.key==listeningFor then
					rb.btn.Text=keyName(KB[listeningFor]); rb.btn.BackgroundColor3=C.togOff; rb.btn.TextColor3=C.blue
				end
			end
		end
		listeningFor=kbKey; btn.Text="..."; btn.BackgroundColor3=C.blueD; btn.TextColor3=C.gold
	end)
end
makeKeybindRow("FLY",1); makeKeybindRow("HL",2); makeKeybindRow("NC",3)
makeKeybindRow("TP_MARK",4); makeKeybindRow("TP_GO",5); makeKeybindRow("MIN",6)
makeKeybindRow("SPD_UP",7); makeKeybindRow("SPD_DOWN",8)
local cfgNote=Instance.new("TextLabel"); cfgNote.Size=UDim2.new(1,0,0,30)
cfgNote.BackgroundTransparency=1; cfgNote.Text="Clique no botão e pressione a nova tecla.\nTeclas duplicadas são ignoradas."
cfgNote.TextColor3=C.sub; cfgNote.TextSize=9; cfgNote.Font=Enum.Font.Code
cfgNote.TextWrapped=true; cfgNote.LayoutOrder=20; cfgNote.Parent=contentConfig

-- Mini bar
local miniBar=Instance.new("Frame"); miniBar.Size=UDim2.new(0,140,0,30)
miniBar.Position=UDim2.new(0,24,0,24); miniBar.BackgroundColor3=C.panel
miniBar.BorderSizePixel=0; miniBar.Visible=false; miniBar.Active=true; miniBar.Parent=screenGui
mkCorner(miniBar,8); mkStroke(miniBar,C.stroke)
local miniLabel=Instance.new("TextLabel"); miniLabel.Size=UDim2.new(1,-40,1,0)
miniLabel.Position=UDim2.new(0,10,0,0); miniLabel.BackgroundTransparency=1
miniLabel.Text="DRAGONSZ"; miniLabel.TextColor3=C.blue; miniLabel.TextSize=12
miniLabel.Font=Enum.Font.GothamBold; miniLabel.TextXAlignment=Enum.TextXAlignment.Left; miniLabel.Parent=miniBar
local miniExpandBtn=Instance.new("TextButton"); miniExpandBtn.Size=UDim2.new(0,28,0,22)
miniExpandBtn.Position=UDim2.new(1,-32,0.5,-11); miniExpandBtn.BackgroundColor3=C.blueD
miniExpandBtn.BorderSizePixel=0; miniExpandBtn.Text="▲"; miniExpandBtn.TextColor3=C.blue
miniExpandBtn.TextSize=10; miniExpandBtn.Font=Enum.Font.GothamBold; miniExpandBtn.Parent=miniBar; mkCorner(miniExpandBtn,5)
local miniBtn=Instance.new("TextButton"); miniBtn.Size=UDim2.new(1,-36,1,0)
miniBtn.BackgroundTransparency=1; miniBtn.Text=""; miniBtn.Parent=miniBar

-- Arrastar
local function makeDraggable(frame,handle)
	local dragging,dragStart,startPos=false,nil,nil
	handle.InputBegan:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
			dragging=true; dragStart=i.Position; startPos=frame.Position
		end
	end)
	handle.InputEnded:Connect(function(i)
		if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
			local d=i.Position-dragStart
			frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
		end
	end)
end
makeDraggable(panel,header); makeDraggable(miniBar,miniBar)

-- Toggle visual
local knobColorMap={}
local function setToggleVisual(tog,knob,card,state,activeColor)
	activeColor=activeColor or C.blueD
	if not knobColorMap[C.blueD] then
		knobColorMap[C.blueD]=C.blue; knobColorMap[C.greenD]=C.green
		knobColorMap[C.purpleD]=C.purple; knobColorMap[C.orangeD]=C.orange
	end
	local kc=state and (knobColorMap[activeColor] or C.blue) or C.knobOff
	if state then
		TweenService:Create(tog,TweenInfo.new(0.18),{BackgroundColor3=activeColor}):Play()
		TweenService:Create(knob,TweenInfo.new(0.18),{Position=UDim2.new(0,21,0.5,-8),BackgroundColor3=kc}):Play()
		card.BackgroundColor3=C.rowOn
	else
		TweenService:Create(tog,TweenInfo.new(0.18),{BackgroundColor3=C.togOff}):Play()
		TweenService:Create(knob,TweenInfo.new(0.18),{Position=UDim2.new(0,3,0.5,-8),BackgroundColor3=C.knobOff}):Play()
		card.BackgroundColor3=C.row
	end
end

-- Speed
local function updateSpdUI()
	spdDisplay.Text=tostring(flySpeed)
	sliderFill.Size=UDim2.new(math.clamp((flySpeed-FLY_SPEED_MIN)/(FLY_SPEED_MAX-FLY_SPEED_MIN),0,1),0,1,0)
	spdKey.Text="[ "..keyName(KB.SPD_UP).." / "..keyName(KB.SPD_DOWN).." ]"
end
local function changeSpeed(delta)
	flySpeed=math.clamp(flySpeed+delta,FLY_SPEED_MIN,FLY_SPEED_MAX); updateSpdUI()
end
local sliderDragging=false
local function applySlider(mx)
	local pct=math.clamp((mx-sliderBg.AbsolutePosition.X)/sliderBg.AbsoluteSize.X,0,1)
	flySpeed=math.round((FLY_SPEED_MIN+pct*(FLY_SPEED_MAX-FLY_SPEED_MIN))/FLY_SPEED_STEP)*FLY_SPEED_STEP
	updateSpdUI()
end
sliderBg.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then sliderDragging=true; applySlider(i.Position.X) end end)
sliderBg.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then sliderDragging=false end end)
UserInputService.InputChanged:Connect(function(i) if sliderDragging and i.UserInputType==Enum.UserInputType.MouseMovement then applySlider(i.Position.X) end end)
btnMinus.MouseButton1Click:Connect(function() changeSpeed(-FLY_SPEED_STEP) end)
btnPlus.MouseButton1Click:Connect(function() changeSpeed(FLY_SPEED_STEP) end)
updateSpdUI()

-- Toggles
local function setFly(state)
	flying=state; setToggleVisual(flyTog,flyKnob,flyRow,state,C.blueD)
	flyKlbl.Text="[ "..keyName(KB.FLY).." ]"
	if state then FlyModule.enable(player,camera,function() return flySpeed end) else FlyModule.disable(player) end
end
local function setHl(state)
	hlOn=state; setToggleVisual(hlTog,hlKnob,hlRow,state,C.blueD)
	hlKlbl.Text="[ "..keyName(KB.HL).." ]"
	if state then HighlightModule.enable(player,HL_COLOR,HL_FILL,function() return hlOn end) else HighlightModule.disable() end
end
local function setNoclip(state)
	ncOn=state; setToggleVisual(ncTog,ncKnob,ncRow,state,C.purpleD)
	ncKlbl.Text="[ "..keyName(KB.NC).." ]"
	if state then NoclipModule.enable(player) else NoclipModule.disable(player) end
end
-- setFarmRaid — ESTAVA FALTANDO (referenciava farmRow/farmTog/farmKnob inexistentes)
local function setFarmRaid(state)
	farmRaidOn=state; setToggleVisual(farmTog,farmKnob,farmRow,state,C.greenD)
	if state then AutofarmModule.enable(player,function() return autofarmDist end) else AutofarmModule.disable() end
end
local function setEsp(state)
	espOn=state; setToggleVisual(espTog,espKnob,espCard,state,C.purpleD)
	if state then EspModule.enable(player,function() return espOn end) else EspModule.disable() end
end
local function setAutofarm(state)
	autofarmOn=state; setToggleVisual(afTog,afKnob,afCard,state,C.orangeD)
	if state then AutofarmModule.enable(player,function() return autofarmDist end) else AutofarmModule.disable() end
end

-- TP
local function updateTpCoords()
	local p=TeleportModule.getSavedPosition()
	if p then
		raidTpCoords.Text=string.format("X: %.0f   Y: %.0f   Z: %.0f",p.X,p.Y,p.Z)
		raidTpCoords.TextColor3=C.orange; savedPosCard.BackgroundColor3=Color3.fromRGB(22,18,10)
	else
		raidTpCoords.Text="X: --   Y: --   Z: --"; raidTpCoords.TextColor3=C.sub; savedPosCard.BackgroundColor3=C.row
	end
end
raidBtnMark.MouseButton1Click:Connect(function() if closed then return end; TeleportModule.markPosition(player); updateTpCoords() end)
raidBtnGo.MouseButton1Click:Connect(function() if closed then return end; TeleportModule.goToPosition(player) end)
coordBtnTp.MouseButton1Click:Connect(function()
	if closed then return end
	local ok,msg=TeleportModule.teleportToCoords(player,coordInput.Text)
	coordFeedback.Text=msg; coordFeedback.TextColor3=ok and C.green or C.red
end)
coordInput:GetPropertyChangedSignal("Text"):Connect(function() coordFeedback.Text="" end)
updateTpCoords()
voidBtn.MouseButton1Click:Connect(function() if closed then return end; VoidModule.teleport(player) end)

-- Autofarm slider
local afDragging=false
afSliderBg.InputBegan:Connect(function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1 then
		afDragging=true
		local function ud(inp)
			local pos=math.clamp((inp.Position.X-afSliderBg.AbsolutePosition.X)/afSliderBg.AbsoluteSize.X,0,1)
			afSliderFill.Size=UDim2.new(pos,0,1,0); autofarmDist=math.floor(1+pos*(15-1))
			afDistLabel.Text="Dist: "..autofarmDist.." studs"
		end
		ud(input)
		local mc,uc
		mc=UserInputService.InputChanged:Connect(function(i2) if afDragging and i2.UserInputType==Enum.UserInputType.MouseMovement then ud(i2) end end)
		uc=UserInputService.InputEnded:Connect(function(i3) if i3.UserInputType==Enum.UserInputType.MouseButton1 then afDragging=false; mc:Disconnect(); uc:Disconnect() end end)
	end
end)

-- Tab switching
local allTabs={{btn=tabMain,content=contentMain},{btn=tabRaid,content=contentRaid},{btn=tabTeleport,content=contentTeleport},{btn=tabConfig,content=contentConfig}}
local function setTab(target)
	for _,t in ipairs(allTabs) do
		t.content.Visible=(t.content==target)
		if t.content==target then TweenService:Create(t.btn,TweenInfo.new(0.15),{BackgroundColor3=C.blueD,BackgroundTransparency=0}):Play(); t.btn.TextColor3=C.blue
		else TweenService:Create(t.btn,TweenInfo.new(0.15),{BackgroundColor3=Color3.fromRGB(0,0,0),BackgroundTransparency=1}):Play(); t.btn.TextColor3=C.sub end
	end
end
tabMain.MouseButton1Click:Connect(function() setTab(contentMain) end)
tabRaid.MouseButton1Click:Connect(function() setTab(contentRaid) end)
tabTeleport.MouseButton1Click:Connect(function() setTab(contentTeleport) end)
tabConfig.MouseButton1Click:Connect(function() setTab(contentConfig) end)
setTab(contentMain)

-- Row clicks
flyRow.InputBegan:Connect(function(i) if closed then return end; if i.UserInputType==Enum.UserInputType.MouseButton1 then setFly(not flying) end end)
hlRow.InputBegan:Connect(function(i) if closed then return end; if i.UserInputType==Enum.UserInputType.MouseButton1 then setHl(not hlOn) end end)
ncRow.InputBegan:Connect(function(i) if closed then return end; if i.UserInputType==Enum.UserInputType.MouseButton1 then setNoclip(not ncOn) end end)
farmRow.InputBegan:Connect(function(i) if closed then return end; if i.UserInputType==Enum.UserInputType.MouseButton1 then setFarmRaid(not farmRaidOn) end end)
espCard.InputBegan:Connect(function(i) if closed then return end; if i.UserInputType==Enum.UserInputType.MouseButton1 then setEsp(not espOn) end end)
afCard.InputBegan:Connect(function(i) if closed then return end; if i.UserInputType==Enum.UserInputType.MouseButton1 then setAutofarm(not autofarmOn) end end)

-- Min/Close
local function setMinimized(state) minimized=state; panel.Visible=not state; miniBar.Visible=state end
local function closePanel()
	closed=true
	if flying then flying=false; FlyModule.disable(player) end
	if hlOn then hlOn=false; HighlightModule.disable() end
	if ncOn then ncOn=false; NoclipModule.disable(player) end
	if farmRaidOn then farmRaidOn=false; AutofarmModule.disable() end
	if autofarmOn then autofarmOn=false; AutofarmModule.disable() end
	if espOn then espOn=false; EspModule.disable() end
	if inputConn then inputConn:Disconnect(); inputConn=nil end
	screenGui:Destroy(); print("[Dragonsz] Encerrado.")
end
minBtn.MouseButton1Click:Connect(function() setMinimized(true) end)
miniBtn.MouseButton1Click:Connect(function() setMinimized(false) end)
miniExpandBtn.MouseButton1Click:Connect(function() setMinimized(false) end)
closeBtn.MouseButton1Click:Connect(closePanel)

-- Keybinds
local function refreshAllKeyLabels()
	flyKlbl.Text="[ "..keyName(KB.FLY).." ]"; hlKlbl.Text="[ "..keyName(KB.HL).." ]"
	ncKlbl.Text="[ "..keyName(KB.NC).." ]"
	spdKey.Text="[ "..keyName(KB.SPD_UP).." / "..keyName(KB.SPD_DOWN).." ]"
end
inputConn=UserInputService.InputBegan:Connect(function(input,gpe)
	if closed then return end
	if listeningFor~=nil then
		if input.UserInputType~=Enum.UserInputType.Keyboard then return end
		local nk=input.KeyCode
		if nk==Enum.KeyCode.Escape then
			for _,rb in ipairs(rebindButtons) do if rb.key==listeningFor then rb.btn.Text=keyName(KB[listeningFor]); rb.btn.BackgroundColor3=C.togOff; rb.btn.TextColor3=C.blue end end
			listeningFor=nil; return
		end
		for k,v in pairs(KB) do
			if v==nk and k~=listeningFor then
				for _,rb in ipairs(rebindButtons) do
					if rb.key==listeningFor then
						rb.btn.Text="DUPLICADA!"; rb.btn.BackgroundColor3=C.redBg; rb.btn.TextColor3=C.red
						task.delay(1,function() if listeningFor==nil then rb.btn.Text=keyName(KB[rb.key]); rb.btn.BackgroundColor3=C.togOff; rb.btn.TextColor3=C.blue end end)
					end
				end
				listeningFor=nil; return
			end
		end
		KB[listeningFor]=nk
		for _,rb in ipairs(rebindButtons) do if rb.key==listeningFor then rb.btn.Text=keyName(nk); rb.btn.BackgroundColor3=C.togOff; rb.btn.TextColor3=C.blue end end
		listeningFor=nil; refreshAllKeyLabels(); return
	end
	if gpe then return end
	if input.KeyCode==KB.FLY then setFly(not flying)
	elseif input.KeyCode==KB.HL then setHl(not hlOn)
	elseif input.KeyCode==KB.NC then setNoclip(not ncOn)
	elseif input.KeyCode==KB.TP_MARK then TeleportModule.markPosition(player); updateTpCoords()
	elseif input.KeyCode==KB.TP_GO then TeleportModule.goToPosition(player)
	elseif input.KeyCode==KB.MIN then setMinimized(not minimized)
	elseif input.KeyCode==KB.SPD_UP then changeSpeed(FLY_SPEED_STEP)
	elseif input.KeyCode==KB.SPD_DOWN then changeSpeed(-FLY_SPEED_STEP)
	end
end)

-- Respawn — CORRIGIDO (stopFlyPhysics/disableNoclip substituídos pelos módulos corretos)
player.CharacterRemoving:Connect(function()
	if flying then FlyModule.stopPhysics() end
	if ncOn then NoclipModule.disable(player) end
	if autofarmOn then AutofarmModule.disable() end
end)
player.CharacterAdded:Connect(function()
	if closed then return end
	if flying then task.wait(1); FlyModule.enable(player,camera,function() return flySpeed end) end
	if ncOn then task.wait(0.5); NoclipModule.enable(player) end
	if espOn then task.wait(0.5); EspModule.enable(player,function() return espOn end) end
	if autofarmOn then task.wait(0.5); AutofarmModule.enable(player,function() return autofarmDist end) end
end)

refreshAllKeyLabels()
print("[Dragonsz v2] Carregado | F1=Fly F2=HL F3=NC F4=Marcar F5=TP K=Min | Config para rebind")
end

-- Dragonsz Admin v2 | LocalScript
-- Abas: Funções | RAID | Teleport | Config | Inspector | Quest
-- Versão com suporte a MOBILE (toque)

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
    local InspectorModule = Modules.Inspector
    local QuestModule     = Modules.Quest

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
local questOn      = false
local autofarmDist = 3
local minimized    = false
local closed       = false
local inputConn    = nil
local listeningFor = nil

-- Detecção de dispositivo
local isTouch   = UserInputService.TouchEnabled
local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

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

local function hotkeyText(kc)
	if touchOnly then return "toque para alternar" end
	return "[ "..keyName(kc).." ]"
end

-- Entrada de ponteiro (mouse OU toque)
local function isPointerBegin(i)
	return i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch
end
local function isPointerMove(i)
	return i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch
end

-- ════════════════════════════════════════════════════════
-- GUI
-- ════════════════════════════════════════════════════════
-- Remove instância antiga (rodar o script 2x deixava uma UI por cima da outra bloqueando o toque)
do
	local old = player.PlayerGui:FindFirstChild("DragonsZ_v2")
	if old then old:Destroy() end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name="DragonsZ_v2"; screenGui.ResetOnSpawn=false
screenGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder=100
screenGui.Parent=player.PlayerGui

-- Tamanho adaptado à tela (celular em modo paisagem tem pouca altura)
local vp = (camera and camera.ViewportSize) or Vector2.new(800,600)
local PANEL_W = math.clamp(vp.X-48, 240, 270)
local PANEL_H = math.clamp(vp.Y-60, 280, 400)

local panel = Instance.new("Frame")
panel.Name="Panel"; panel.Size=UDim2.new(0,PANEL_W,0,PANEL_H)
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

-- Botões maiores para facilitar o toque
local minBtn=Instance.new("TextButton"); minBtn.Size=UDim2.new(0,30,0,30)
minBtn.Position=UDim2.new(1,-72,0.5,-15); minBtn.BackgroundColor3=C.togOff
minBtn.BorderSizePixel=0; minBtn.Text="—"; minBtn.TextColor3=C.sub
minBtn.TextSize=12; minBtn.Font=Enum.Font.GothamBold; minBtn.Parent=header
mkCorner(minBtn,6); mkStroke(minBtn,C.stroke)

local closeBtn=Instance.new("TextButton"); closeBtn.Size=UDim2.new(0,30,0,30)
closeBtn.Position=UDim2.new(1,-38,0.5,-15); closeBtn.BackgroundColor3=C.redBg
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
	local b=Instance.new("TextButton"); b.Size=UDim2.new(0.165,-2,1,0)
	b.BackgroundColor3=Color3.fromRGB(0,0,0); b.BackgroundTransparency=1
	b.BorderSizePixel=0; b.Text=label; b.TextColor3=C.sub; b.TextSize=9
	b.Font=Enum.Font.GothamBold; b.LayoutOrder=order; b.Parent=tabBar; mkCorner(b,5)
	return b
end
local tabMain=makeTabBtn("FUN",1); local tabRaid=makeTabBtn("RAID",2)
local tabTeleport=makeTabBtn("TP",3); local tabConfig=makeTabBtn("CFG",4)
local tabInspect=makeTabBtn("INS",5)
local tabQuest=makeTabBtn("QST",6)

-- Content frames (altura acompanha o painel)
local function makeContent(visible)
	local f=Instance.new("ScrollingFrame")
	f.Size=UDim2.new(1,-16,1,-88); f.Position=UDim2.new(0,8,0,78)
	f.BackgroundTransparency=1; f.BorderSizePixel=0; f.ScrollBarThickness=3
	f.ScrollBarImageColor3=C.blueD; f.CanvasSize=UDim2.new(0,0,0,0)
	f.AutomaticCanvasSize=Enum.AutomaticSize.Y; f.Visible=visible; f.Parent=panel
	local l=Instance.new("UIListLayout",f); l.SortOrder=Enum.SortOrder.LayoutOrder
	l.Padding=UDim.new(0,6)
	return f
end
local contentMain=makeContent(true); local contentRaid=makeContent(false)
local contentTeleport=makeContent(false); local contentConfig=makeContent(false)
local contentInspect=makeContent(false)
local contentQuest=makeContent(false)

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

-- ══ CLIQUE/TOQUE EM CARD (funciona no PC e no mobile) ══
-- Coloca um TextButton transparente sobre o card. TextButton + Activated
-- distingue toque de rolagem (não dispara quando o dedo está arrastando o scroll).
local function bindClick(card, callback, height)
	local b=Instance.new("TextButton")
	b.Name="ClickArea"
	b.Size = height and UDim2.new(1,0,0,height) or UDim2.new(1,0,1,0)
	b.Position=UDim2.new(0,0,0,0)
	b.BackgroundTransparency=1; b.BorderSizePixel=0
	b.Text=""; b.AutoButtonColor=false; b.ZIndex=10
	b.Parent=card
	b.Activated:Connect(function()
		if closed then return end
		callback()
	end)
	return b
end

-- ══ SLIDER (mouse + toque) ══
-- hit = área de toque (maior que a barra) | bar = barra visual
local function bindSlider(hit, bar, scrollFrame, onPct)
	local dragging=false
	local function update(pos)
		local w=bar.AbsoluteSize.X
		if w<=0 then return end
		onPct(math.clamp((pos.X-bar.AbsolutePosition.X)/w,0,1))
	end
	hit.InputBegan:Connect(function(i)
		if closed then return end
		if isPointerBegin(i) then
			dragging=true
			if scrollFrame then scrollFrame.ScrollingEnabled=false end -- evita rolar a lista enquanto arrasta
			update(i.Position)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and isPointerMove(i) then update(i.Position) end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if dragging and isPointerBegin(i) then
			dragging=false
			if scrollFrame then scrollFrame.ScrollingEnabled=true end
		end
	end)
end

-- ABA MAIN
local flyRow,flyTog,flyKnob,flyKlbl=makeToggleRow(contentMain,"FLY",C.blue,C.header,"Voar",keyName(KB.FLY),1)
local hlRow,hlTog,hlKnob,hlKlbl=makeToggleRow(contentMain,"HL",C.blue,C.header,"Highlight",keyName(KB.HL),2)
local ncRow,ncTog,ncKnob,ncKlbl=makeToggleRow(contentMain,"NC",C.purple,C.purpleD,"NoClip",keyName(KB.NC),3)

-- Farm Raid card
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
-- Área de toque maior que a barra (6px é impossível de tocar no celular)
local sliderHit=Instance.new("Frame"); sliderHit.Size=UDim2.new(1,-148,0,28)
sliderHit.Position=UDim2.new(0,140,1,-33); sliderHit.BackgroundTransparency=1
sliderHit.BorderSizePixel=0; sliderHit.Active=true; sliderHit.ZIndex=20; sliderHit.Parent=spdCard

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
local voidBtn=Instance.new("TextButton"); voidBtn.Size=UDim2.new(0,60,0,32)
voidBtn.Position=UDim2.new(1,-68,0.5,-16); voidBtn.BackgroundColor3=C.tealD
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
local afSliderHit=Instance.new("Frame"); afSliderHit.Size=UDim2.new(1,-110,0,26)
afSliderHit.Position=UDim2.new(0,100,1,-30); afSliderHit.BackgroundTransparency=1
afSliderHit.BorderSizePixel=0; afSliderHit.Active=true; afSliderHit.ZIndex=20; afSliderHit.Parent=afCard

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
local raidBtnMark=Instance.new("TextButton"); raidBtnMark.Size=UDim2.new(0.48,-4,0,28)
raidBtnMark.Position=UDim2.new(0,8,1,-36); raidBtnMark.BackgroundColor3=C.orangeD
raidBtnMark.BorderSizePixel=0; raidBtnMark.Text="📍 Marcar"; raidBtnMark.TextColor3=C.orange
raidBtnMark.TextSize=11; raidBtnMark.Font=Enum.Font.GothamBold; raidBtnMark.Parent=savedPosCard
mkCorner(raidBtnMark,6); mkStroke(raidBtnMark,Color3.fromRGB(100,60,10))
local raidBtnGo=Instance.new("TextButton"); raidBtnGo.Size=UDim2.new(0.48,-4,0,28)
raidBtnGo.Position=UDim2.new(0.52,-4,1,-36); raidBtnGo.BackgroundColor3=C.greenD
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
local coordBtnTp=Instance.new("TextButton"); coordBtnTp.Size=UDim2.new(1,-16,0,28)
coordBtnTp.Position=UDim2.new(0,8,1,-34); coordBtnTp.BackgroundColor3=C.blueD
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
	local btn=Instance.new("TextButton"); btn.Size=UDim2.new(0,80,0,28)
	btn.Position=UDim2.new(1,-88,0.5,-14); btn.BackgroundColor3=C.togOff
	btn.BorderSizePixel=0; btn.Text=keyName(KB[kbKey]); btn.TextColor3=C.blue
	btn.TextSize=11; btn.Font=Enum.Font.Code; btn.Parent=card
	mkCorner(btn,6); mkStroke(btn,C.strokeB)
	table.insert(rebindButtons,{key=kbKey,label=lbl,btn=btn})
	btn.Activated:Connect(function()
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
local cfgNote=Instance.new("TextLabel"); cfgNote.Size=UDim2.new(1,0,0,42)
cfgNote.BackgroundTransparency=1
cfgNote.Text = touchOnly
	and "Nenhum teclado detectado: os atalhos só funcionam com teclado físico.\nNo celular, use os toggles na tela."
	or  "Clique no botão e pressione a nova tecla.\nTeclas duplicadas são ignoradas."
cfgNote.TextColor3=C.sub; cfgNote.TextSize=9; cfgNote.Font=Enum.Font.Code
cfgNote.TextWrapped=true; cfgNote.LayoutOrder=20; cfgNote.Parent=contentConfig

-- Mini bar
local miniBar=Instance.new("Frame"); miniBar.Size=UDim2.new(0,150,0,34)
miniBar.Position=UDim2.new(0,24,0,24); miniBar.BackgroundColor3=C.panel
miniBar.BorderSizePixel=0; miniBar.Visible=false; miniBar.Active=true; miniBar.Parent=screenGui
mkCorner(miniBar,8); mkStroke(miniBar,C.stroke)
local miniLabel=Instance.new("TextLabel"); miniLabel.Size=UDim2.new(1,-50,1,0)
miniLabel.Position=UDim2.new(0,10,0,0); miniLabel.BackgroundTransparency=1
miniLabel.Text="DRAGONSZ"; miniLabel.TextColor3=C.blue; miniLabel.TextSize=12
miniLabel.Font=Enum.Font.GothamBold; miniLabel.TextXAlignment=Enum.TextXAlignment.Left; miniLabel.Parent=miniBar
local miniExpandBtn=Instance.new("TextButton"); miniExpandBtn.Size=UDim2.new(0,34,0,26)
miniExpandBtn.Position=UDim2.new(1,-38,0.5,-13); miniExpandBtn.BackgroundColor3=C.blueD
miniExpandBtn.BorderSizePixel=0; miniExpandBtn.Text="▲"; miniExpandBtn.TextColor3=C.blue
miniExpandBtn.TextSize=11; miniExpandBtn.Font=Enum.Font.GothamBold; miniExpandBtn.Parent=miniBar; mkCorner(miniExpandBtn,5)
-- (o botão transparente que cobria toda a miniBar foi removido: ele "engolia" o toque e impedia arrastar)

-- Arrastar (mouse + toque)
local function makeDraggable(frame,handle)
	local dragging,dragStart,startPos=false,nil,nil
	handle.InputBegan:Connect(function(i)
		if isPointerBegin(i) then
			dragging=true; dragStart=i.Position; startPos=frame.Position
		end
	end)
	handle.InputEnded:Connect(function(i)
		if isPointerBegin(i) then dragging=false end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and isPointerMove(i) then
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

-- ════════════════════════════════════════════════════════
-- ABA INSPECTOR (definida APÓS setToggleVisual)
-- ════════════════════════════════════════════════════════
local inspOn = false

-- Toggle card
local insTogCard = makeCard(contentInspect,1,52)
makeIcon(insTogCard,"INS",C.teal,C.tealD)
local insTogTitle=Instance.new("TextLabel"); insTogTitle.Size=UDim2.new(1,-110,0,16)
insTogTitle.Position=UDim2.new(0,54,0,9); insTogTitle.BackgroundTransparency=1
insTogTitle.Text="Inspector"; insTogTitle.TextColor3=C.text; insTogTitle.TextSize=13
insTogTitle.Font=Enum.Font.GothamBold; insTogTitle.TextXAlignment=Enum.TextXAlignment.Left; insTogTitle.Parent=insTogCard
local insTogSub=Instance.new("TextLabel"); insTogSub.Size=UDim2.new(1,-110,0,13)
insTogSub.Position=UDim2.new(0,54,0,28); insTogSub.BackgroundTransparency=1
insTogSub.Text="Mire / Clique-D p/ fixar"; insTogSub.TextColor3=C.sub; insTogSub.TextSize=10
insTogSub.Font=Enum.Font.Code; insTogSub.TextXAlignment=Enum.TextXAlignment.Left; insTogSub.Parent=insTogCard
local insTog,insKnob=makeToggle(insTogCard)

-- Info card
local insInfoCard=makeCard(contentInspect,2,290)
insInfoCard.BackgroundColor3=C.header

local insNameLbl=Instance.new("TextLabel"); insNameLbl.Size=UDim2.new(1,-16,0,18)
insNameLbl.Position=UDim2.new(0,8,0,6); insNameLbl.BackgroundTransparency=1
insNameLbl.Text="[ Nenhum alvo ]"; insNameLbl.TextColor3=C.sub; insNameLbl.TextSize=13
insNameLbl.Font=Enum.Font.GothamBold; insNameLbl.TextXAlignment=Enum.TextXAlignment.Left; insNameLbl.Parent=insInfoCard

local insKindLbl=Instance.new("TextLabel"); insKindLbl.Size=UDim2.new(1,-16,0,13)
insKindLbl.Position=UDim2.new(0,8,0,25); insKindLbl.BackgroundTransparency=1
insKindLbl.Text=""; insKindLbl.TextColor3=C.sub; insKindLbl.TextSize=10
insKindLbl.Font=Enum.Font.Code; insKindLbl.TextXAlignment=Enum.TextXAlignment.Left; insKindLbl.Parent=insInfoCard

local insSep=Instance.new("Frame"); insSep.Size=UDim2.new(1,-16,0,1)
insSep.Position=UDim2.new(0,8,0,41); insSep.BackgroundColor3=C.stroke; insSep.BorderSizePixel=0; insSep.Parent=insInfoCard

local insScroll=Instance.new("ScrollingFrame"); insScroll.Size=UDim2.new(1,-8,0,240)
insScroll.Position=UDim2.new(0,4,0,45); insScroll.BackgroundTransparency=1
insScroll.BorderSizePixel=0; insScroll.ScrollBarThickness=3
insScroll.ScrollBarImageColor3=C.teal; insScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
insScroll.CanvasSize=UDim2.new(0,0,0,0); insScroll.Parent=insInfoCard
local insLayout=Instance.new("UIListLayout",insScroll)
insLayout.SortOrder=Enum.SortOrder.LayoutOrder; insLayout.Padding=UDim.new(0,2)

local function insLine(txt,col,order)
	local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,13)
	l.BackgroundTransparency=1; l.Text=txt; l.TextColor3=col or C.text
	l.TextSize=10; l.Font=Enum.Font.Code
	l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=order; l.Parent=insScroll
	return l
end
local function insHeader(txt,col,order)
	local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,15)
	l.BackgroundTransparency=1; l.Text=txt; l.TextColor3=col or C.sub
	l.TextSize=10; l.Font=Enum.Font.GothamBold
	l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=order; l.Parent=insScroll
	return l
end

local insHpLbl    = insLine("❤ HP: —",C.red,1)
local insLvlLbl   = insLine("⭐ Nível: —",C.gold,2)
local insSpdLbl   = insLine("💨 Speed: —",C.blue,3)
local insDistLbl  = insLine("📍 Dist: —",C.orange,4)
local insTeamLbl  = insLine("🏳 Time: —",C.teal,5)
local _           = insHeader("── ARMAS ──",C.gold,9)
local insWepLbl   = insLine("  —",C.gold,10)
local _           = insHeader("── ANIMAÇÕES ──",C.purple,19)
local insAnimLbl  = insLine("  —",C.purple,20)
local _           = insHeader("── SKILLS ──",C.orange,29)
local insSkillLbl = insLine("  —",C.orange,30)
local _           = insHeader("── STATS ──",C.green,39)
local insStatLbl  = insLine("  —",C.green,40)

-- Log card
local insLogCard=makeCard(contentInspect,3,100)
insLogCard.BackgroundColor3=C.header
local insLogTitle=Instance.new("TextLabel"); insLogTitle.Size=UDim2.new(1,0,0,16)
insLogTitle.Position=UDim2.new(0,8,0,4); insLogTitle.BackgroundTransparency=1
insLogTitle.Text="📋 LOG"; insLogTitle.TextColor3=C.sub; insLogTitle.TextSize=10
insLogTitle.Font=Enum.Font.GothamBold; insLogTitle.TextXAlignment=Enum.TextXAlignment.Left; insLogTitle.Parent=insLogCard
local insLogBox=Instance.new("ScrollingFrame"); insLogBox.Size=UDim2.new(1,-8,0,72)
insLogBox.Position=UDim2.new(0,4,0,22); insLogBox.BackgroundTransparency=1
insLogBox.BorderSizePixel=0; insLogBox.ScrollBarThickness=3
insLogBox.ScrollBarImageColor3=C.stroke; insLogBox.AutomaticCanvasSize=Enum.AutomaticSize.Y
insLogBox.CanvasSize=UDim2.new(0,0,0,0); insLogBox.Parent=insLogCard
local insLogLayout=Instance.new("UIListLayout",insLogBox)
insLogLayout.SortOrder=Enum.SortOrder.LayoutOrder; insLogLayout.VerticalAlignment=Enum.VerticalAlignment.Bottom

local logCount=0
local function addLog(msg, color)
	logCount=logCount+1
	local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,12)
	l.BackgroundTransparency=1; l.Text=msg; l.TextColor3=color or C.text
	l.TextSize=9; l.Font=Enum.Font.Code
	l.TextXAlignment=Enum.TextXAlignment.Left; l.LayoutOrder=logCount; l.Parent=insLogBox
	-- Limita log a 30 linhas
	local children=insLogBox:GetChildren()
	local lbls={}; for _,c in ipairs(children) do if c:IsA("TextLabel") then table.insert(lbls,c) end end
	if #lbls>30 then table.sort(lbls,function(a,b) return a.LayoutOrder<b.LayoutOrder end); lbls[1]:Destroy() end
end

local function joinList(t) return type(t)=="table" and table.concat(t," | ") or tostring(t) end

local function updateInspectorUI(data)
	if not data then
		insNameLbl.Text="[ Nenhum alvo ]"; insNameLbl.TextColor3=C.sub
		insKindLbl.Text=""
		insHpLbl.Text="❤ HP: —"; insLvlLbl.Text="⭐ Nível: —"
		insSpdLbl.Text="💨 Speed: —"; insDistLbl.Text="📍 Dist: —"; insTeamLbl.Text="🏳 Time: —"
		insWepLbl.Text="  —"; insAnimLbl.Text="  —"; insSkillLbl.Text="  —"; insStatLbl.Text="  —"
		return
	end
	local icon = data.pinned and "📌" or "🔍"
	insNameLbl.Text = icon.." "..data.name
	insNameLbl.TextColor3 = data.kind=="Player" and C.blue or C.teal
	insKindLbl.Text = data.kind.." | "..data.username
	insHpLbl.Text   = "❤ HP: "..data.hp
	insLvlLbl.Text  = "⭐ Nível: "..data.level
	insSpdLbl.Text  = "💨 Speed: "..data.walkspeed
	insDistLbl.Text = "📍 Dist: "..data.distance
	insTeamLbl.Text = "🏳 Time: "..data.team
	insWepLbl.Text   = "  "..(#data.weapons>0 and joinList(data.weapons) or "—")
	insAnimLbl.Text  = "  "..(#data.animations>0 and joinList(data.animations) or "—")
	insSkillLbl.Text = "  "..(#data.skills>0 and joinList(data.skills) or "—")
	insStatLbl.Text  = "  "..(#data.stats>0 and joinList(data.stats) or "—")
	-- Log entry
	if data.pinned then
		local col = data.kind=="Player" and C.blue or C.teal
		addLog("["..os.date("%H:%M:%S").."] "..data.kind..": "..data.name, col)
		addLog("  HP:"..data.hp.." LVL:"..data.level.." SPD:"..data.walkspeed.." DIST:"..data.distance, C.sub)
		if data.weapons and data.weapons[1]~="Nenhuma" then
			addLog("  ARMAS: "..joinList(data.weapons), C.gold)
		end
		if data.skills and data.skills[1]~="Nao detectadas" then
			addLog("  SKILLS: "..joinList(data.skills), C.orange)
		end
	end
end

local function setInspector(state)
	inspOn=state
	setToggleVisual(insTog,insKnob,insTogCard,state,C.tealD)
	if state then
		if InspectorModule then
			InspectorModule.start(player,camera,function(data)
				pcall(updateInspectorUI,data)
			end)
			addLog("["..os.date("%H:%M:%S").."] Inspector ativado",C.teal)
		else
			addLog("["..os.date("%H:%M:%S").."] ERRO: módulo não carregado",C.red)
		end
	else
		if InspectorModule then InspectorModule.stop() end
		updateInspectorUI(nil)
		addLog("["..os.date("%H:%M:%S").."] Inspector desativado",C.sub)
	end
end

bindClick(insTogCard, function() setInspector(not inspOn) end)
-- ════════════════════════════════════════════════════════

do  -- ═══ ABA QUEST ══════════════════════════════════════════════

    -- (questOn agora é declarada no topo do arquivo, para o closePanel conseguir enxergá-la)

    -- ── Cabeçalho / toggle ──────────────────────────────────────
    local qTogCard = makeCard(contentQuest, 1, 52)
    makeIcon(qTogCard, "QST", C.gold, C.header)

    local qTogTitle = Instance.new("TextLabel")
    qTogTitle.Size = UDim2.new(1,-110,0,16)
    qTogTitle.Position = UDim2.new(0,54,0,9)
    qTogTitle.BackgroundTransparency = 1
    qTogTitle.Text = "Quest Reader"
    qTogTitle.TextColor3 = C.text; qTogTitle.TextSize = 13
    qTogTitle.Font = Enum.Font.GothamBold
    qTogTitle.TextXAlignment = Enum.TextXAlignment.Left
    qTogTitle.Parent = qTogCard

    local qTogSub = Instance.new("TextLabel")
    qTogSub.Size = UDim2.new(1,-110,0,13)
    qTogSub.Position = UDim2.new(0,54,0,28)
    qTogSub.BackgroundTransparency = 1
    qTogSub.Text = "Detecta quests abertas"
    qTogSub.TextColor3 = C.sub; qTogSub.TextSize = 10
    qTogSub.Font = Enum.Font.Code
    qTogSub.TextXAlignment = Enum.TextXAlignment.Left
    qTogSub.Parent = qTogCard

    local qTog, qKnob = makeToggle(qTogCard)

    -- ── Card de status (nenhuma quest / loading) ────────────────
    local qStatusCard = makeCard(contentQuest, 2, 36)
    local qStatusLbl = Instance.new("TextLabel")
    qStatusLbl.Size = UDim2.new(1,-16,1,0)
    qStatusLbl.Position = UDim2.new(0,8,0,0)
    qStatusLbl.BackgroundTransparency = 1
    qStatusLbl.Text = "Ative para escanear quests"
    qStatusLbl.TextColor3 = C.sub; qStatusLbl.TextSize = 10
    qStatusLbl.Font = Enum.Font.Code
    qStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
    qStatusLbl.TextWrapped = true
    qStatusLbl.Parent = qStatusCard

    -- ── Container dinâmico das quests detectadas ────────────────
    local qResultFrame = Instance.new("Frame")
    qResultFrame.Size = UDim2.new(1,0,0,0)
    qResultFrame.BackgroundTransparency = 1
    qResultFrame.AutomaticSize = Enum.AutomaticSize.Y
    qResultFrame.LayoutOrder = 3
    qResultFrame.Parent = contentQuest
    local qResultLayout = Instance.new("UIListLayout", qResultFrame)
    qResultLayout.SortOrder = Enum.SortOrder.LayoutOrder
    qResultLayout.Padding = UDim.new(0,6)

    -- ── Builder de card de quest ────────────────────────────────
    local function buildQuestCard(quest, order)
        local extraH = quest.location and 20 or 0
        local stepH  = math.max(1, #quest.steps) * 16
        local totalH = 28 + extraH + stepH + 18

        local card = makeCard(qResultFrame, order, totalH)
        card.BackgroundColor3 = C.header

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size = UDim2.new(1,-16,0,18)
        titleLbl.Position = UDim2.new(0,8,0,5)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Text = "📜 " .. quest.title
        titleLbl.TextColor3 = C.gold
        titleLbl.TextSize = 12
        titleLbl.Font = Enum.Font.GothamBold
        titleLbl.TextXAlignment = Enum.TextXAlignment.Left
        titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
        titleLbl.Parent = card

        local srcLbl = Instance.new("TextLabel")
        srcLbl.Size = UDim2.new(1,-16,0,11)
        srcLbl.Position = UDim2.new(0,8,0,23)
        srcLbl.BackgroundTransparency = 1
        srcLbl.Text = "origem: " .. quest.source
        srcLbl.TextColor3 = C.sub; srcLbl.TextSize = 9
        srcLbl.Font = Enum.Font.Code
        srcLbl.TextXAlignment = Enum.TextXAlignment.Left
        srcLbl.Parent = card

        local yOffset = 36

        if quest.location then
            local locLbl = Instance.new("TextLabel")
            locLbl.Size = UDim2.new(1,-16,0,16)
            locLbl.Position = UDim2.new(0,8,0,yOffset)
            locLbl.BackgroundTransparency = 1
            locLbl.Text = "🗺️ Local: " .. quest.location
            locLbl.TextColor3 = C.orange; locLbl.TextSize = 10
            locLbl.Font = Enum.Font.GothamBold
            locLbl.TextXAlignment = Enum.TextXAlignment.Left
            locLbl.TextTruncate = Enum.TextTruncate.AtEnd
            locLbl.Parent = card
            yOffset = yOffset + 18
        end

        local sep = Instance.new("Frame")
        sep.Size = UDim2.new(1,-16,0,1)
        sep.Position = UDim2.new(0,8,0,yOffset)
        sep.BackgroundColor3 = C.stroke
        sep.BorderSizePixel = 0
        sep.Parent = card
        yOffset = yOffset + 4

        for i, step in ipairs(quest.steps) do
            local stepLbl = Instance.new("TextLabel")
            stepLbl.Size = UDim2.new(1,-16,0,14)
            stepLbl.Position = UDim2.new(0,8,0,yOffset)
            stepLbl.BackgroundTransparency = 1

            local progText = step.prog and (" ["..step.prog.."]") or ""
            stepLbl.Text = step.icon .. " " .. step.text .. progText

            if step.icon == "🗺️" then
                stepLbl.TextColor3 = C.orange
            elseif step.icon == "⚔️" then
                stepLbl.TextColor3 = C.red
            else
                stepLbl.TextColor3 = C.text
            end

            stepLbl.TextSize = 10
            stepLbl.Font = Enum.Font.Code
            stepLbl.TextXAlignment = Enum.TextXAlignment.Left
            stepLbl.TextTruncate = Enum.TextTruncate.AtEnd
            stepLbl.Parent = card

            yOffset = yOffset + 15

            if i >= 10 then
                local moreLbl = Instance.new("TextLabel")
                moreLbl.Size = UDim2.new(1,-16,0,13)
                moreLbl.Position = UDim2.new(0,8,0,yOffset)
                moreLbl.BackgroundTransparency = 1
                moreLbl.Text = "  ... +" .. (#quest.steps - i) .. " itens"
                moreLbl.TextColor3 = C.sub; moreLbl.TextSize = 9
                moreLbl.Font = Enum.Font.Code
                moreLbl.TextXAlignment = Enum.TextXAlignment.Left
                moreLbl.Parent = card
                break
            end
        end

        return card
    end

    -- ── Callback chamado pelo QuestModule ───────────────────────
    local function onQuestUpdate(data)
        for _, child in ipairs(qResultFrame:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end

        if not data or not data.found then
            qStatusLbl.Text = questOn
                and "🔍 Nenhuma quest detectada na tela"
                or  "Ative para escanear quests"
            qStatusLbl.TextColor3 = C.sub
            return
        end

        qStatusLbl.Text = "✅ " .. #data.quests .. " quest(s) detectada(s)"
        qStatusLbl.TextColor3 = C.green

        for i, quest in ipairs(data.quests) do
            buildQuestCard(quest, i)
        end
    end

    if QuestModule then
        QuestModule.OnUpdate(onQuestUpdate)
    end

    -- ── Toggle ──────────────────────────────────────────────────
    local function setQuest(state)
        questOn = state
        setToggleVisual(qTog, qKnob, qTogCard, state, C.header)
        if state then
            if QuestModule then
                QuestModule.start()
            else
                qStatusLbl.Text = "ERRO: módulo não carregado"
                qStatusLbl.TextColor3 = C.red
            end
        else
            if QuestModule then QuestModule.stop() end
            onQuestUpdate(nil)
        end
    end

    bindClick(qTogCard, function() setQuest(not questOn) end)

end  -- ═══ fim ABA QUEST ══════════════════════════════════════════

-- Speed
local function updateSpdUI()
	spdDisplay.Text=tostring(flySpeed)
	sliderFill.Size=UDim2.new(math.clamp((flySpeed-FLY_SPEED_MIN)/(FLY_SPEED_MAX-FLY_SPEED_MIN),0,1),0,1,0)
	spdKey.Text = touchOnly and "use  −  /  +  ou o slider" or ("[ "..keyName(KB.SPD_UP).." / "..keyName(KB.SPD_DOWN).." ]")
end
local function changeSpeed(delta)
	flySpeed=math.clamp(flySpeed+delta,FLY_SPEED_MIN,FLY_SPEED_MAX); updateSpdUI()
end
bindSlider(sliderHit, sliderBg, contentMain, function(pct)
	flySpeed=math.round((FLY_SPEED_MIN+pct*(FLY_SPEED_MAX-FLY_SPEED_MIN))/FLY_SPEED_STEP)*FLY_SPEED_STEP
	flySpeed=math.clamp(flySpeed,FLY_SPEED_MIN,FLY_SPEED_MAX)
	updateSpdUI()
end)
btnMinus.Activated:Connect(function() changeSpeed(-FLY_SPEED_STEP) end)
btnPlus.Activated:Connect(function() changeSpeed(FLY_SPEED_STEP) end)
updateSpdUI()

-- Autofarm slider (mouse + toque)
bindSlider(afSliderHit, afSliderBg, contentRaid, function(pct)
	afSliderFill.Size=UDim2.new(pct,0,1,0)
	autofarmDist=math.floor(1+pct*(15-1))
	afDistLabel.Text="Dist: "..autofarmDist.." studs"
end)

-- ════════════════════════════════════════════════════════
-- BOTÕES DE VOO PARA MOBILE (▲ subir / ▼ descer) — toque para ligar, toque de novo para parar
-- ════════════════════════════════════════════════════════
local vertDir=0
local flyPad=Instance.new("Frame"); flyPad.Name="FlyPad"
flyPad.Size=UDim2.new(0,56,0,116); flyPad.Position=UDim2.new(1,-80,0.5,-58)
flyPad.BackgroundTransparency=1; flyPad.Visible=false; flyPad.Parent=screenGui

local function makePadBtn(txt,y)
	local b=Instance.new("TextButton"); b.Size=UDim2.new(0,56,0,56); b.Position=UDim2.new(0,0,0,y)
	b.BackgroundColor3=C.blueD; b.BackgroundTransparency=0.1; b.BorderSizePixel=0
	b.Text=txt; b.TextColor3=C.blue; b.TextSize=24; b.Font=Enum.Font.GothamBold
	b.AutoButtonColor=false; b.Parent=flyPad
	mkCorner(b,12); mkStroke(b,C.blue)
	return b
end
local padUp=makePadBtn("▲",0)
local padDown=makePadBtn("▼",60)

local function setVert(d)
	vertDir=d
	if FlyModule and FlyModule.setVertical then FlyModule.setVertical(d) end
	padUp.BackgroundColor3   = (d==1)  and C.blue or C.blueD
	padUp.TextColor3         = (d==1)  and C.bg   or C.blue
	padDown.BackgroundColor3 = (d==-1) and C.blue or C.blueD
	padDown.TextColor3       = (d==-1) and C.bg   or C.blue
end
padUp.Activated:Connect(function() setVert(vertDir==1 and 0 or 1) end)
padDown.Activated:Connect(function() setVert(vertDir==-1 and 0 or -1) end)

-- Toggles
local function setFly(state)
	flying=state; setToggleVisual(flyTog,flyKnob,flyRow,state,C.blueD)
	flyKlbl.Text=hotkeyText(KB.FLY)
	if state then
		FlyModule.enable(player,camera,function() return flySpeed end)
	else
		setVert(0)
		FlyModule.disable(player)
	end
	flyPad.Visible = state and isTouch
end
local function setHl(state)
	hlOn=state; setToggleVisual(hlTog,hlKnob,hlRow,state,C.blueD)
	hlKlbl.Text=hotkeyText(KB.HL)
	if state then HighlightModule.enable(player,HL_COLOR,HL_FILL,function() return hlOn end) else HighlightModule.disable() end
end
local function setNoclip(state)
	ncOn=state; setToggleVisual(ncTog,ncKnob,ncRow,state,C.purpleD)
	ncKlbl.Text=hotkeyText(KB.NC)
	if state then NoclipModule.enable(player) else NoclipModule.disable(player) end
end
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
raidBtnMark.Activated:Connect(function() if closed then return end; TeleportModule.markPosition(player); updateTpCoords() end)
raidBtnGo.Activated:Connect(function() if closed then return end; TeleportModule.goToPosition(player) end)
coordBtnTp.Activated:Connect(function()
	if closed then return end
	local ok,msg=TeleportModule.teleportToCoords(player,coordInput.Text)
	coordFeedback.Text=msg; coordFeedback.TextColor3=ok and C.green or C.red
end)
coordInput:GetPropertyChangedSignal("Text"):Connect(function() coordFeedback.Text="" end)
updateTpCoords()
voidBtn.Activated:Connect(function() if closed then return end; VoidModule.teleport(player) end)

-- Tab switching
local allTabs={{btn=tabMain,content=contentMain},{btn=tabRaid,content=contentRaid},{btn=tabTeleport,content=contentTeleport},{btn=tabConfig,content=contentConfig},{btn=tabInspect,content=contentInspect},{btn=tabQuest,content=contentQuest}}
local function setTab(target)
	for _,t in ipairs(allTabs) do
		t.content.Visible=(t.content==target)
		if t.content==target then TweenService:Create(t.btn,TweenInfo.new(0.15),{BackgroundColor3=C.blueD,BackgroundTransparency=0}):Play(); t.btn.TextColor3=C.blue
		else TweenService:Create(t.btn,TweenInfo.new(0.15),{BackgroundColor3=Color3.fromRGB(0,0,0),BackgroundTransparency=1}):Play(); t.btn.TextColor3=C.sub end
	end
end
tabMain.Activated:Connect(function() setTab(contentMain) end)
tabRaid.Activated:Connect(function() setTab(contentRaid) end)
tabTeleport.Activated:Connect(function() setTab(contentTeleport) end)
tabConfig.Activated:Connect(function() setTab(contentConfig) end)
tabInspect.Activated:Connect(function() setTab(contentInspect) end)
tabQuest.Activated:Connect(function() setTab(contentQuest) end)
setTab(contentMain)

-- Toggles por clique/toque nos cards (ANTES: InputBegan só com MouseButton1 => não funcionava no celular)
bindClick(flyRow,  function() setFly(not flying) end)
bindClick(hlRow,   function() setHl(not hlOn) end)
bindClick(ncRow,   function() setNoclip(not ncOn) end)
bindClick(farmRow, function() setFarmRaid(not farmRaidOn) end)
bindClick(espCard, function() setEsp(not espOn) end)
bindClick(afCard,  function() setAutofarm(not autofarmOn) end, 56) -- só a parte de cima; o slider fica livre embaixo

-- Min/Close
local function setMinimized(state)
	minimized=state
	if state then miniBar.Position=panel.Position else panel.Position=miniBar.Position end
	panel.Visible=not state; miniBar.Visible=state
end
local function closePanel()
	closed=true
	if flying then flying=false; setVert(0); FlyModule.disable(player) end
	if hlOn then hlOn=false; HighlightModule.disable() end
	if ncOn then ncOn=false; NoclipModule.disable(player) end
	if farmRaidOn then farmRaidOn=false; AutofarmModule.disable() end
	if autofarmOn then autofarmOn=false; AutofarmModule.disable() end
	if espOn then espOn=false; EspModule.disable() end
	if inspOn then inspOn=false; if InspectorModule then InspectorModule.stop() end end
	if questOn then questOn=false; if QuestModule then QuestModule.stop() end end
	if inputConn then inputConn:Disconnect(); inputConn=nil end
	screenGui:Destroy(); print("[Dragonsz] Encerrado.")
end
minBtn.Activated:Connect(function() setMinimized(true) end)
miniExpandBtn.Activated:Connect(function() setMinimized(false) end)
closeBtn.Activated:Connect(closePanel)

-- Keybinds (teclado)
local function refreshAllKeyLabels()
	flyKlbl.Text=hotkeyText(KB.FLY); hlKlbl.Text=hotkeyText(KB.HL)
	ncKlbl.Text=hotkeyText(KB.NC)
	updateSpdUI()
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

-- Respawn
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
print("[Dragonsz v2] Carregado | "..(touchOnly and "Modo MOBILE (toque)" or "F1=Fly F2=HL F3=NC F4=Marcar F5=TP K=Min | Config para rebind"))
end

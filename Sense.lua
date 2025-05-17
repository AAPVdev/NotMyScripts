-- services
local runService = game:GetService("RunService")
local players = game:GetService("Players")
local workspace = game:GetService("Workspace")

-- variables
local localPlayer = players.LocalPlayer
local camera = workspace.CurrentCamera
local viewportSize = camera.ViewportSize
local container = Instance.new("Folder",
    gethui and gethui() or game:GetService("CoreGui"))

-- locals
local floor = math.floor
local round = math.round
local sin = math.sin
local cos = math.cos
local min = math.min
local max = math.max
local abs = math.abs
local insert = table.insert
local clear = table.clear
local fromMatrix = CFrame.fromMatrix

-- methods
local wtvp = camera.WorldToViewportPoint
local isA = workspace.IsA
local getPivot = workspace.GetPivot
local findFirstChild = workspace.FindFirstChild
local findFirstChildOfClass = workspace.FindFirstChildOfClass
local getChildren = workspace.GetChildren
local pointToObjectSpace = CFrame.identity.PointToObjectSpace
local lerpColor = Color3.new().Lerp
local min2 = Vector2.zero.Min
local max2 = Vector2.zero.Max
local lerp2 = Vector2.zero.Lerp
local min3 = Vector3.zero.Min
local max3 = Vector3.zero.Max

-- constants
local HEALTH_BAR_OFFSET = Vector2.new(5, 0)
local HEALTH_TEXT_OFFSET = Vector2.new(3, 0)
local HEALTH_BAR_OUTLINE_OFFSET = Vector2.new(0, 1)
local NAME_OFFSET = Vector2.new(0, 2)
local DISTANCE_OFFSET = Vector2.new(0, 2)
local VERTICES = {
    Vector3.new(-1, -1, -1),
    Vector3.new(-1, 1, -1),
    Vector3.new(-1, -1, 1),
    Vector3.new(1, -1, -1),
    Vector3.new(1, 1, -1),
    Vector3.new(1, -1, 1),
    Vector3.new(-1, 1, 1),
    Vector3.new(1, 1, 1)
}

-- Precomputed box3d connections
local BOX3D_INDICES = {
    {1,2}, {2,3}, {3,4}, {4,1},  -- Front face
    {5,6}, {6,7}, {7,8}, {8,5},  -- Back face
    {1,5}, {2,6}, {3,7}, {4,8}   -- Connections
}

-- Cache tables
local tempCorners = {}

-- functions
local function isBodyPart(name)
    return name == "Head" or name:find("Torso") or name:find("Leg") or name:find("Arm")
end

local function getBoundingBox(parts)
    local minPos, maxPos
    for i = 1, #parts do
        local part = parts[i]
        local cframe, size = part.CFrame, part.Size
        local partMin = (cframe - size * 0.5).Position
        local partMax = (cframe + size * 0.5).Position
        
        if not minPos then
            minPos = partMin
            maxPos = partMax
        else
            minPos = min3(minPos, partMin)
            maxPos = max3(maxPos, partMax)
        end
    end
    return CFrame.new((minPos + maxPos) * 0.5), maxPos - minPos
end

local function worldToScreen(world)
    local screen, inBounds = wtvp(camera, world)
    return Vector2.new(screen.X, screen.Y), inBounds, screen.Z
end

local function calculateCorners(cframe, size)
    for i = 1, 8 do
        tempCorners[i] = worldToScreen((cframe + size * 0.5 * VERTICES[i]).Position)
    end

    local min = min2(viewportSize, unpack(tempCorners))
    local max = max2(Vector2.zero, unpack(tempCorners))
    return {
        corners = tempCorners,
        topLeft = Vector2.new(floor(min.X), floor(min.Y)),
        topRight = Vector2.new(floor(max.X), floor(min.Y)),
        bottomLeft = Vector2.new(floor(min.X), floor(max.Y)),
        bottomRight = Vector2.new(floor(max.X), floor(max.Y))
    }
end

local function rotateVector(vector, radians)
    local x, y = vector.X, vector.Y
    local c, s = cos(radians), sin(radians)
    return Vector2.new(x * c - y * s, x * s + y * c)
end

local function parseColor(self, color, isOutline)
    if color == "Team Color" or (self.interface.sharedSettings.useTeamColor and not isOutline) then
        return self.interface.getTeamColor(self.player) or Color3.new(1,1,1)
    end
    return color
end

-- esp object
local EspObject = {}
EspObject.__index = EspObject

function EspObject.new(player, interface)
    local self = setmetatable({}, EspObject)
    self.player = player
    self.interface = interface
    self:Construct()
    return self
end

function EspObject:_create(class, properties)
    local drawing = Drawing.new(class)
    for property, value in next, properties do
        pcall(function() drawing[property] = value end)
    end
    self.bin[#self.bin + 1] = drawing
    return drawing
end

function EspObject:Construct()
    self.charCache = {}
    self.childCount = 0
    self.bin = {}
    self.lastValues = {
        health = 0,
        distance = 0,
        weapon = ""
    }

    -- Initialize all drawings upfront
    self.drawings = {
        box3d = {},
        visible = {
            tracerOutline = self:_create("Line", {Thickness = 3, Visible = false}),
            tracer = self:_create("Line", {Thickness = 1, Visible = false}),
            boxFill = self:_create("Square", {Filled = true, Visible = false}),
            boxOutline = self:_create("Square", {Thickness = 3, Visible = false}),
            box = self:_create("Square", {Thickness = 1, Visible = false}),
            healthBarOutline = self:_create("Line", {Thickness = 3, Visible = false}),
            healthBar = self:_create("Line", {Thickness = 1, Visible = false}),
            healthText = self:_create("Text", {Center = true, Visible = false}),
            name = self:_create("Text", {Text = self.player.DisplayName, Center = true, Visible = false}),
            distance = self:_create("Text", {Center = true, Visible = false}),
            weapon = self:_create("Text", {Center = true, Visible = false}),
        },
        hidden = {
            arrowOutline = self:_create("Triangle", {Thickness = 3, Visible = false}),
            arrow = self:_create("Triangle", {Filled = true, Visible = false})
        }
    }

    -- Pre-initialize box3d lines
    for _ = 1, 12 do
        insert(self.drawings.box3d, self:_create("Line", {Thickness = 1, Visible = false}))
    end

    self.renderConnection = runService.Heartbeat:Connect(function(deltaTime)
        self:Update(deltaTime)
        self:Render(deltaTime)
    end)
end

function EspObject:Destruct()
    self.renderConnection:Disconnect()
    for i = 1, #self.bin do
        self.bin[i]:Remove()
    end
    clear(self)
end

function EspObject:Update()
    local interface = self.interface
    self.options = interface.teamSettings[interface.isFriendly(self.player) and "friendly" or "enemy"]
    self.character = interface.getCharacter(self.player)
    self.health, self.maxHealth = interface.getHealth(self.player)
    self.weapon = interface.getWeapon(self.player)
    
    -- Whitelist optimization using hash table
    local whitelist = interface.whitelist
    self.enabled = self.options.enabled and self.character and 
        (not next(whitelist) or whitelist[self.player.UserId]

    local head = self.enabled and findFirstChild(self.character, "Head")
    if not head then
        self.charCache = {}
        self.onScreen = false
        return
    end

    local _, onScreen, depth = worldToScreen(head.Position)
    self.onScreen = onScreen
    self.distance = depth

    if interface.sharedSettings.limitDistance and depth > interface.sharedSettings.maxDistance then
        self.onScreen = false
    end

    if self.onScreen then
        local cache = self.charCache
        local children = getChildren(self.character)
        if not cache[1] or self.childCount ~= #children then
            clear(cache)
            for i = 1, #children do
                local part = children[i]
                if isA(part, "BasePart") and isBodyPart(part.Name) then
                    cache[#cache + 1] = part
                end
            end
            self.childCount = #children
        end
        self.corners = calculateCorners(getBoundingBox(cache))
    elseif self.options.offScreenArrow then
        local cframe = camera.CFrame
        local flat = fromMatrix(cframe.Position, cframe.RightVector, Vector3.yAxis)
        local objectSpace = pointToObjectSpace(flat, head.Position)
        self.direction = Vector2.new(objectSpace.X, objectSpace.Z).Unit
    end
end

function EspObject:Render()
    if not self.enabled then
        for _, drawing in pairs(self.drawings.visible) do drawing.Visible = false end
        for _, drawing in pairs(self.drawings.hidden) do drawing.Visible = false end
        for _, line in pairs(self.drawings.box3d) do line.Visible = false end
        return
    end

    local onScreen = self.onScreen
    local interface = self.interface
    local options = self.options
    local visible = self.drawings.visible
    local hidden = self.drawings.hidden
    local box3d = self.drawings.box3d
    local corners = self.corners
    local textSize = interface.sharedSettings.textSize
    local textFont = interface.sharedSettings.textFont

    -- Box rendering
    visible.box.Visible = onScreen and options.box
    visible.boxOutline.Visible = visible.box.Visible and options.boxOutline
    if visible.box.Visible then
        visible.box.Position = corners.topLeft
        visible.box.Size = corners.bottomRight - corners.topLeft
        visible.box.Color = parseColor(self, options.boxColor[1])
        visible.box.Transparency = options.boxColor[2]

        visible.boxOutline.Position = corners.topLeft
        visible.boxOutline.Size = visible.box.Size
        visible.boxOutline.Color = parseColor(self, options.boxOutlineColor[1], true)
        visible.boxOutline.Transparency = options.boxOutlineColor[2]
    end

    -- Health bar
    visible.healthBar.Visible = onScreen and options.healthBar
    visible.healthBarOutline.Visible = visible.healthBar.Visible and options.healthBarOutline
    if visible.healthBar.Visible then
        local barFrom = corners.topLeft - HEALTH_BAR_OFFSET
        local barTo = corners.bottomLeft - HEALTH_BAR_OFFSET

        visible.healthBar.To = barTo
        visible.healthBar.From = lerp2(barTo, barFrom, self.health/self.maxHealth)
        visible.healthBar.Color = lerpColor(options.dyingColor, options.healthyColor, self.health/self.maxHealth)

        visible.healthBarOutline.To = barTo + HEALTH_BAR_OUTLINE_OFFSET
        visible.healthBarOutline.From = barFrom - HEALTH_BAR_OUTLINE_OFFSET
        visible.healthBarOutline.Color = parseColor(self, options.healthBarOutlineColor[1], true)
        visible.healthBarOutline.Transparency = options.healthBarOutlineColor[2]
    end

    -- Health text
    visible.healthText.Visible = onScreen and options.healthText
    if visible.healthText.Visible and self.lastValues.health ~= self.health then
        visible.healthText.Text = round(self.health) .. "hp"
        visible.healthText.Size = textSize
        visible.healthText.Font = textFont
        visible.healthText.Color = parseColor(self, options.healthTextColor[1])
        visible.healthText.Transparency = options.healthTextColor[2]
        visible.healthText.Outline = options.healthTextOutline
        visible.healthText.OutlineColor = parseColor(self, options.healthTextOutlineColor, true)
        self.lastValues.health = self.health
    end

    -- Name
    visible.name.Visible = onScreen and options.name
    if visible.name.Visible then
        visible.name.Size = textSize
        visible.name.Font = textFont
        visible.name.Color = parseColor(self, options.nameColor[1])
        visible.name.Transparency = options.nameColor[2]
        visible.name.Outline = options.nameOutline
        visible.name.OutlineColor = parseColor(self, options.nameOutlineColor, true)
    end

    -- Distance
    visible.distance.Visible = onScreen and self.distance and options.distance
    if visible.distance.Visible and self.lastValues.distance ~= self.distance then
        visible.distance.Text = round(self.distance) .. " studs"
        visible.distance.Size = textSize
        visible.distance.Font = textFont
        visible.distance.Color = parseColor(self, options.distanceColor[1])
        visible.distance.Transparency = options.distanceColor[2]
        visible.distance.Outline = options.distanceOutline
        visible.distance.OutlineColor = parseColor(self, options.distanceOutlineColor, true)
        self.lastValues.distance = self.distance
    end

    -- Weapon
    visible.weapon.Visible = onScreen and options.weapon
    if visible.weapon.Visible and self.lastValues.weapon ~= self.weapon then
        visible.weapon.Text = self.weapon
        visible.weapon.Size = textSize
        visible.weapon.Font = textFont
        visible.weapon.Color = parseColor(self, options.weaponColor[1])
        visible.weapon.Transparency = options.weaponColor[2]
        visible.weapon.Outline = options.weaponOutline
        visible.weapon.OutlineColor = parseColor(self, options.weaponOutlineColor, true)
        self.lastValues.weapon = self.weapon
    end

    -- Tracer
    visible.tracer.Visible = onScreen and options.tracer
    visible.tracerOutline.Visible = visible.tracer.Visible and options.tracerOutline
    if visible.tracer.Visible then
        visible.tracer.Color = parseColor(self, options.tracerColor[1])
        visible.tracer.Transparency = options.tracerColor[2]
        visible.tracer.To = (corners.bottomLeft + corners.bottomRight) * 0.5
        visible.tracer.From = options.tracerOrigin == "Middle" and viewportSize * 0.5 or
            options.tracerOrigin == "Top" and viewportSize * Vector2.new(0.5, 0) or
            viewportSize * Vector2.new(0.5, 1)

        visible.tracerOutline.Color = parseColor(self, options.tracerOutlineColor[1], true)
        visible.tracerOutline.Transparency = options.tracerOutlineColor[2]
        visible.tracerOutline.To = visible.tracer.To
        visible.tracerOutline.From = visible.tracer.From
    end

    -- Off-screen arrow
    hidden.arrow.Visible = not onScreen and options.offScreenArrow
    hidden.arrowOutline.Visible = hidden.arrow.Visible and options.offScreenArrowOutline
    if hidden.arrow.Visible and self.direction then
        hidden.arrow.PointA = min2(max2(viewportSize * 0.5 + self.direction * options.offScreenArrowRadius, 
            Vector2.one * 25), viewportSize - Vector2.one * 25)
        hidden.arrow.PointB = hidden.arrow.PointA - rotateVector(self.direction, 0.45) * options.offScreenArrowSize
        hidden.arrow.PointC = hidden.arrow.PointA - rotateVector(self.direction, -0.45) * options.offScreenArrowSize
        hidden.arrow.Color = parseColor(self, options.offScreenArrowColor[1])
        hidden.arrow.Transparency = options.offScreenArrowColor[2]

        hidden.arrowOutline.PointA = hidden.arrow.PointA
        hidden.arrowOutline.PointB = hidden.arrow.PointB
        hidden.arrowOutline.PointC = hidden.arrow.PointC
        hidden.arrowOutline.Color = parseColor(self, options.offScreenArrowOutlineColor[1], true)
        hidden.arrowOutline.Transparency = options.offScreenArrowOutlineColor[2]
    end

    -- Box3D using precomputed indices
    local box3dEnabled = onScreen and options.box3d
    for i, line in ipairs(box3d) do
        line.Visible = box3dEnabled
        if box3dEnabled then
            local idx = BOX3D_INDICES[i]
            line.From = corners.corners[idx[1]]
            line.To = corners.corners[idx[2]]
            line.Color = parseColor(self, options.box3dColor[1])
            line.Transparency = options.box3dColor[2]
        end
    end
end

-- cham object
local ChamObject = {}
ChamObject.__index = ChamObject

function ChamObject.new(player, interface)
    local self = setmetatable({}, ChamObject)
    self.player = player
    self.interface = interface
    self:Construct()
    return self
end

function ChamObject:Construct()
    self.highlight = Instance.new("Highlight", container)
    self.lastTeam = nil
    self.updateConnection = runService.Heartbeat:Connect(function()
        self:Update()
    end)
end

function ChamObject:Destruct()
    self.updateConnection:Disconnect()
    self.highlight:Destroy()
    clear(self)
end

function ChamObject:Update()
    local interface = self.interface
    local character = interface.getCharacter(self.player)
    local options = interface.teamSettings[interface.isFriendly(self.player) and "friendly" or "enemy"]
    local enabled = options.enabled and character and not
        (next(interface.whitelist) and not interface.whitelist[self.player.UserId]

    self.highlight.Enabled = enabled and options.chams
    if self.highlight.Enabled then
        if self.highlight.Adornee ~= character then
            self.highlight.Adornee = character
        end
        
        if self.lastTeam ~= options then
            self.highlight.FillColor = parseColor(self, options.chamsFillColor[1])
            self.highlight.FillTransparency = options.chamsFillColor[2]
            self.highlight.OutlineColor = parseColor(self, options.chamsOutlineColor[1], true)
            self.highlight.OutlineTransparency = options.chamsOutlineColor[2]
            self.highlight.DepthMode = options.chamsVisibleOnly and "Occluded" or "AlwaysOnTop"
            self.lastTeam = options
        end
    end
end

-- instance class
local InstanceObject = {}
InstanceObject.__index = InstanceObject

function InstanceObject.new(instance, options)
    local self = setmetatable({}, InstanceObject)
    self.instance = instance
    self.options = options
    self.lastPosition = Vector3.zero
    self:Construct()
    return self
end

function InstanceObject:Construct()
    self.text = Drawing.new("Text")
    self.text.Center = true
    self.renderConnection = runService.Heartbeat:Connect(function()
        self:Render()
    end)
end

function InstanceObject:Destruct()
    self.renderConnection:Disconnect()
    self.text:Remove()
end

function InstanceObject:Render()
    if not self.instance or not self.instance.Parent then
        return self:Destruct()
    end

    if not self.options.enabled then
        self.text.Visible = false
        return
    end

    local world = getPivot(self.instance).Position
    if (world - self.lastPosition).Magnitude < 0.1 then return end
    self.lastPosition = world

    local position, visible, depth = worldToScreen(world)
    if self.options.limitDistance and depth > self.options.maxDistance then
        visible = false
    end

    self.text.Visible = visible
    if visible then
        self.text.Position = position
        self.text.Text = self.options.text
            :gsub("{name}", self.instance.Name)
            :gsub("{distance}", round(depth))
            :gsub("{position}", tostring(world))
        self.text.Color = self.options.textColor[1]
        self.text.Transparency = self.options.textColor[2]
        self.text.Outline = self.options.textOutline
        self.text.OutlineColor = self.options.textOutlineColor
        self.text.Size = self.options.textSize
        self.text.Font = self.options.textFont
    end
end

-- interface
local EspInterface = {
    _hasLoaded = false,
    _objectCache = {},
    whitelist = {},
    sharedSettings = {
        textSize = 13,
        textFont = 2,
        limitDistance = false,
        maxDistance = 150,
        useTeamColor = false
    },
    teamSettings = {
        enemy = {
            enabled = false,
            -- [Keep original team settings structure]
        },
        friendly = {
            enabled = false,
            -- [Keep original team settings structure]
        }
    }
}

function EspInterface.AddInstance(instance, options)
    local cache = EspInterface._objectCache
    if not cache[instance] then
        cache[instance] = InstanceObject.new(instance, options)
    end
    return cache[instance]
end

function EspInterface.Load()
    if EspInterface._hasLoaded then return end

    local function createObject(player)
        EspInterface._objectCache[player] = {
            EspObject.new(player, EspInterface),
            ChamObject.new(player, EspInterface)
        }
    end

    local function removeObject(player)
        local object = EspInterface._objectCache[player]
        if object then
            for i = 1, #object do
                object[i]:Destruct()
            end
            EspInterface._objectCache[player] = nil
        end
    end

    for _, player in ipairs(players:GetPlayers()) do
        if player ~= localPlayer then
            createObject(player)
        end
    end

    EspInterface.playerAdded = players.PlayerAdded:Connect(createObject)
    EspInterface.playerRemoving = players.PlayerRemoving:Connect(removeObject)
    EspInterface._hasLoaded = true
end

function EspInterface.Unload()
    if not EspInterface._hasLoaded then return end

    for index, object in pairs(EspInterface._objectCache) do
        if typeof(index) == "Instance" then
            object:Destruct()
        else
            for i = 1, #object do
                object[i]:Destruct()
            end
        end
        EspInterface._objectCache[index] = nil
    end

    EspInterface.playerAdded:Disconnect()
    EspInterface.playerRemoving:Disconnect()
    EspInterface._hasLoaded = false
end

-- Default game-specific implementations
function EspInterface.getWeapon(player)
    return "Unknown"
end

function EspInterface.isFriendly(player)
    return player.Team and player.Team == localPlayer.Team
end

function EspInterface.getTeamColor(player)
    return player.Team and player.Team.TeamColor and player.Team.TeamColor.Color
end

function EspInterface.getCharacter(player)
    return player.Character
end

function EspInterface.getHealth(player)
    local character = player and EspInterface.getCharacter(player)
    local humanoid = character and findFirstChildOfClass(character, "Humanoid")
    return humanoid and humanoid.Health or 100, humanoid and humanoid.MaxHealth or 100
end

return EspInterface

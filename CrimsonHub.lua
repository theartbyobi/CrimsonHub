--!nocheck
-- CRIMSON HUB 1.1 | Independent source | No downloaded code or external UI.
-- Live Blox Fruits / executor validation has NOT been performed.
-- Source-observed schemas are revalidated at runtime. Never writes NPC health,
-- quest progress, mastery, inventory, collision, hidden properties or hit packets.

-- Upload the supplied Luffy PNG to Roblox, then put its real image asset ID here.
-- Blank preserves the existing text opener; no unrelated image is substituted.
local Config = {LuffyImageAssetId = "", Debug = true}
local Hub = {Version = "1.1", Destroyed = false, Connections = {}, Logs = {}, Components = {}, DebugValues = {}}
local Services = {}
for _, name in ipairs({"Players", "Workspace", "ReplicatedStorage", "TweenService", "UserInputService", "RunService"}) do
    local ok, service = pcall(function() return game:GetService(name) end)
    if not ok or not service then warn("CRIMSON: missing service " .. name); return end
    Services[name] = service
end
local bootDeadline = os.clock() + 30
while not game:IsLoaded() or not Services.Players.LocalPlayer do
    if os.clock() >= bootDeadline then warn("CRIMSON: player load timeout"); return end
    task.wait(0.1)
end
local Player = Services.Players.LocalPlayer
local PlayerGui = Player:FindFirstChildOfClass("PlayerGui") or Player:WaitForChild("PlayerGui", 15)
if not PlayerGui then warn("CRIMSON: PlayerGui unavailable"); return end
local GUI_NAME, OWNER = "CrimsonHub_V1", "crimson-independent-v1"
for _, old in ipairs(PlayerGui:GetChildren()) do
    if old.Name == GUI_NAME and old:GetAttribute("CrimsonOwner") == OWNER then
        old:SetAttribute("ShutdownRequested", true)
        local shutdown = old:FindFirstChild("Shutdown")
        if shutdown and shutdown:IsA("BindableEvent") then pcall(function() shutdown:Fire() end) end
        old:Destroy()
    end
end

local Defaults = {
    Weapon = "", AutoEquip = true, FarmDistance = 5, AttackInterval = 0.4,
    Movement = "Walk", TweenSpeed = 90, ScanRadius = 1500,
    TargetOrder = "Nearest", AttackMethod = "Tool.Activate", AutoHaki = false,
    Boss = "", Destination = "", MinimizeOnStart = false,
}
local Settings = {}
for k, v in pairs(Defaults) do Settings[k] = v end
Hub.Settings = Settings
local Screen, UI, Manager, Observer

function Hub:IsAlive()
    return not self.Destroyed and Screen and Screen.Parent == PlayerGui
        and not Screen:GetAttribute("ShutdownRequested")
end
function Hub:Connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(self.Connections, connection)
    return connection
end
function Hub:Log(message, isError)
    message = tostring(message):sub(1, 240)
    if #self.Logs >= 50 then table.remove(self.Logs, 1) end
    table.insert(self.Logs, {Time = os.clock(), Message = message})
    if isError then self.LastError = message end
    if isError then warn("[Crimson] " .. message) end
    if UI then
        local ok, err = pcall(function() UI:Notify(self:Explain(message), isError) end)
        if not ok then warn("[Crimson] UI notification failed: " .. tostring(err)) end
    end
end
function Hub:Debug(field, value)
    value = tostring(value)
    if not Config.Debug or self.DebugValues[field] == value then return end
    self.DebugValues[field] = value
    print("[Crimson] " .. field .. ": " .. value)
end
function Hub:Explain(message)
    local code = tostring(message):match("^[A-Z_]+")
    local text = {
        NO_QUEST_FOR_LEVEL = "Chưa có quest hợp lệ cho level này. Gửi log level, Sea và Quest data.",
        QUEST_NPC_MAPPING_MISSING = "Có quest nhưng chưa xác định được NPC từ dữ liệu game.",
        QUEST_NPC_MAPPING_AMBIGUOUS = "Nhiều NPC trùng điều kiện quest; đã dừng để tránh nhận sai.",
        AMBIGUOUS_QUEST_LEVEL = "Nhiều quest cùng level; chưa đủ dữ liệu chọn chính xác.",
        QUEST_MODULES_MISSING = "Không tìm thấy Quests / GuideModule. Có thể dữ liệu game đã đổi.",
        QUEST_NOT_CONFIRMED_AFTER_ = "Máy chủ chưa xác nhận nhận quest sau 3 lần thử.",
        NO_MATCHING_TOOL = "Chưa có Tool Melee / Sword phù hợp. Kiểm tra Weapon và Backpack.",
        TOOL_TYPE_UNVERIFIED = "Tool đã chọn chưa có loại Melee / Sword được xác minh; không tự kích hoạt.",
        TOOL_CHANGED = "Bạn đã đổi vũ khí. Chọn Weapon rồi bật lại Auto Level.",
        COMBAT_NO_PROGRESS = "Chưa quan sát thấy sát thương. Phương thức đánh có thể không được game chấp nhận.",
        QUEST_UI_SCHEMA_CHANGED = "Không đọc được giao diện quest hiện tại của game.",
        LEVEL_DATA_MISSING_OR_CHANGED = "Chưa đọc được Player.Data.Level hợp lệ.",
        QUEST_NPC_NOT_LOADED = "NPC quest chưa tải sau thời gian chờ giới hạn.",
        MOVEMENT_BLOCKED_OR_CORRECTED = "Di chuyển bị chặn hoặc bị máy chủ điều chỉnh.",
    }
    return text[code] and (text[code] .. "\n" .. tostring(message)) or tostring(message)
end
function Hub:RefreshUI()
    if not UI or not UI.StatusLabel or self.UpdatingUI or self.Destroyed then return end
    self.UpdatingUI = true
    local ok, err = pcall(function() UI:Update(os.clock()) end)
    self.UpdatingUI = false
    if not ok and self.LastUIError ~= tostring(err) then
        self.LastUIError = tostring(err)
        warn("[Crimson] UI_UPDATE_FAILED: " .. tostring(err))
    end
end

-- Pure functions are also exercised by the offline test runner.
local Logic = {}
function Logic.Canonical(name)
    local s = tostring(name or ""):lower():gsub("<[^>]*>", ""):gsub("%b[]", "")
    return (s:gsub("[^%w%s]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$"))
end
function Logic.TitleMatches(title, target)
    local t, n = " " .. Logic.Canonical(title) .. " ", Logic.Canonical(target)
    if n == "" then return false end
    if t:find(" " .. n .. " ", 1, true) or t:find(" " .. n .. "s ", 1, true) then return true end
    if n:sub(-1) == "y" and t:find(" " .. n:sub(1, -2) .. "ies ", 1, true) then return true end
    return false
end
function Logic.Finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
function Logic.Integer(value, minimum)
    local number = type(value) == "number" and value or type(value) == "string" and tonumber(value) or nil
    if Logic.Finite(number) and number % 1 == 0 and number >= (minimum or 0) then return number end
    return nil
end
function Logic.Position(value)
    if typeof(value) == "CFrame" then value = value.Position end
    if typeof(value) == "Vector3" and Logic.Finite(value.X) and Logic.Finite(value.Y) and Logic.Finite(value.Z)
        and math.abs(value.X) < 10000000 and math.abs(value.Y) < 10000000 and math.abs(value.Z) < 10000000 then return value end
    return nil
end
-- Only factual metadata is used for this tie-break, never copied coordinates.
-- Sources and validation limits are listed in FIX_REPORT.md. Live quest data wins.
local StarterBinding = {Group = "BanditQuest1", Index = 1, Target = "Bandit", NPC = "Bandit Quest Giver"}
function Logic.QuestSea(level) return level >= 1500 and 3 or level >= 700 and 2 or 1 end
function Logic.BuildDatabase(quests, guide, sea)
    if type(quests) ~= "table" or type(guide) ~= "table" or type(guide.Data) ~= "table"
        or type(guide.Data.NPCList) ~= "table" then return nil, "QUEST_SCHEMA_CHANGED" end
    local levels, npcs, rows, examined = {}, {}, {}, 0
    local stats = {Examined = 0, Invalid = 0, OtherSea = 0, Unbound = 0, Ambiguous = 0}
    for _, npc in pairs(guide.Data.NPCList) do
        examined = examined + 1
        if examined > 1000 then return nil, "NPC_DATABASE_TOO_LARGE" end
        if type(npc) == "table" and type(npc.NPCName) == "string" and type(npc.Levels) == "table" then
            local pos = Logic.Position(npc.Position)
            do
                local record = {Name = npc.NPCName, Position = pos, Levels = {}}
                table.insert(npcs, record)
                for _, value in pairs(npc.Levels) do
                    local level = Logic.Integer(value, 0)
                    if level then
                        record.Levels[level] = true
                        levels[level] = levels[level] or {}
                        -- Duplicate entries for the same NPC do not create false ambiguity.
                        local duplicate = false
                        for _, previous in ipairs(levels[level]) do
                            if previous.Name == record.Name and (previous.Position == pos or previous.Position and pos and (previous.Position - pos).Magnitude < 1) then duplicate = true end
                        end
                        if not duplicate then table.insert(levels[level], record) end
                    end
                end
            end
        end
    end
    examined = 0
    for group, entries in pairs(quests) do
        if type(group) == "string" and type(entries) == "table" then
            for index, row in pairs(entries) do
                examined = examined + 1
                if examined > 4000 then return nil, "QUEST_DATABASE_TOO_LARGE" end
                local questIndex = Logic.Integer(index, 1)
                local minLevel = type(row) == "table" and Logic.Integer(row.LevelReq, 0)
                stats.Examined = stats.Examined + 1
                if questIndex and minLevel and type(row.Task) == "table" then
                    local target, amount, count
                    count = 0
                    for enemy, quantity in pairs(row.Task) do target, amount, count = enemy, quantity, count + 1 end
                    amount = Logic.Integer(amount, 2)
                    -- These story/training exclusions are observed in the referenced schema.
                    local excluded = row.Name == "Trainees" or row.Name == "Swan's Raid" or row.Name == "Town Raid"
                    if count == 1 and type(target) == "string" and target ~= "" and amount and not excluded then
                        if sea and Logic.QuestSea(minLevel) ~= sea then stats.OtherSea = stats.OtherSea + 1; continue end
                        table.insert(rows, {
                            Id = group .. ":" .. questIndex, Group = group, Index = questIndex,
                            MinLevel = minLevel, Target = target, Amount = amount, Sea = sea,
                            MaxLevel = Logic.Integer(row.MaxLevel, minLevel),
                        })
                    else stats.Invalid = stats.Invalid + 1 end
                else stats.Invalid = stats.Invalid + 1 end
            end
        end
    end
    if #rows == 0 then return nil, "NO_SUPPORTED_LEVEL_QUESTS" end
    table.sort(rows, function(a, b)
        if a.MinLevel == b.MinLevel then return a.Id < b.Id end
        return a.MinLevel > b.MinLevel
    end)
    for _, row in ipairs(rows) do
        local candidates = levels[row.MinLevel] or {}
        -- Starter guides may represent the first quest as 0 or 1. Only this
        -- source-observed quest/NPC identity permits that alias.
        if row.Group == StarterBinding.Group and row.Index == StarterBinding.Index
            and row.Target == StarterBinding.Target and row.MinLevel <= 1 then
            for _, npc in ipairs(npcs) do
                if Logic.Canonical(npc.Name) == Logic.Canonical(StarterBinding.NPC)
                    and (npc.Levels[0] or npc.Levels[1]) then candidates = {npc}; break end
            end
        end
        if #candidates > 1 then
            -- Match all ordinary thresholds in the same quest group. Do not use
            -- proximity as evidence that an unrelated NPC owns the quest.
            local matching = {}
            for _, npc in ipairs(candidates) do
                local matches = true
                for _, sibling in ipairs(rows) do
                    if sibling.Group == row.Group and not npc.Levels[sibling.MinLevel] then matches = false; break end
                end
                if matches then table.insert(matching, npc) end
            end
            if #matching > 0 then candidates = matching end
        end
        row.Candidates = candidates
        if #candidates == 1 then row.NPC, row.Position = candidates[1].Name, candidates[1].Position
        elseif #candidates == 0 then row.NPCError = "QUEST_NPC_MAPPING_MISSING"; stats.Unbound = stats.Unbound + 1
        else row.NPCError = "QUEST_NPC_MAPPING_AMBIGUOUS"; stats.Ambiguous = stats.Ambiguous + 1 end
        -- Preserve missing/ambiguous bindings as selection barriers, rather than
        -- silently dropping their level and falling back to an older quest.
        for i = #rows, 1, -1 do
            if rows[i].MinLevel > row.MinLevel then
                row.MaxLevel = math.min(row.MaxLevel or math.huge, rows[i].MinLevel - 1); break
            end
        end
    end
    return {Rows = rows, NPCs = npcs, Stats = stats, Sea = sea}
end
function Logic.SelectQuest(rows, level)
    level = Logic.Integer(level, 1)
    if not level then return nil, "INVALID_PLAYER_LEVEL" end
    local selected
    for _, row in ipairs(rows) do
        if row.MinLevel <= level and (not row.MaxLevel or level <= row.MaxLevel)
            and (not selected or row.MinLevel > selected.MinLevel) then selected = row end
    end
    if selected then
        for _, row in ipairs(rows) do
            if row.Id ~= selected.Id and row.MinLevel == selected.MinLevel and (not row.MaxLevel or level <= row.MaxLevel) then
                return nil, "AMBIGUOUS_QUEST_LEVEL"
            end
        end
        return selected
    end
    return nil, "NO_QUEST_FOR_LEVEL"
end
Hub.Components.Logic = Logic

local SeaDetector = {Places = {[2753915549] = 1, [4442272183] = 2, [7449423635] = 3}}
function SeaDetector:Get() return self.Places[game.PlaceId] end
local LevelDetector = {}
function LevelDetector:Get()
    local data = Player:FindFirstChild("Data")
    local level = data and data:FindFirstChild("Level")
    if not level then return nil, "LEVEL_DATA_LOADING" end
    if level:IsA("IntValue") or level:IsA("NumberValue") or level:IsA("StringValue") then
        local number = Logic.Integer(level.Value, 1)
        if number then return number end
    end
    return nil, "LEVEL_DATA_MISSING_OR_CHANGED"
end
function LevelDetector:Beli()
    local data = Player:FindFirstChild("Data")
    local value = data and data:FindFirstChild("Beli")
    if value and (value:IsA("IntValue") or value:IsA("NumberValue")) and Logic.Finite(value.Value) then return value.Value end
    return nil
end
local function characterContext()
    local c = Player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if c and c.Parent and h and h.Health > 0 and r and r:IsA("BasePart") then return {Character = c, Humanoid = h, Root = r} end
    return nil
end
local function pointOf(instance)
    if not instance or not instance.Parent then return nil end
    if instance:IsA("BasePart") then return Logic.Position(instance.Position) end
    if instance:IsA("Model") then return Logic.Position(instance:GetPivot()) end
    local handle = instance:FindFirstChild("Handle")
    return handle and handle:IsA("BasePart") and Logic.Position(handle.Position) or nil
end
local function commRemote()
    local remotes = Services.ReplicatedStorage:FindFirstChild("Remotes")
    local remote = remotes and remotes:FindFirstChild("CommF_")
    if remote and remote:IsA("RemoteFunction") then return remote end
    return nil
end

-- Yielding operations run outside the single farm tick, with finite deadlines.
-- A server request already transmitted cannot be retracted by Stop.
local Jobs = {Pending = {}, Detached = 0}
function Jobs:Start(key, operation, timeout, callback)
    if self.Pending[key] or self.Detached >= 2 or not Hub:IsAlive() then return false end
    local job = {Deadline = os.clock() + timeout, Callback = callback}
    self.Pending[key] = job
    job.Thread = task.spawn(function()
        if self.Pending[key] ~= job or not Hub:IsAlive() then return end
        job.OK, job.Result = pcall(operation)
        job.Done = true
        if job.Detached then self.Detached = math.max(0, self.Detached - 1); job.Detached = false end
    end)
    return true
end
function Jobs:Cancel(key)
    local job = self.Pending[key]
    if not job then return end
    self.Pending[key] = nil
    if not job.Done and job.Thread then
        local cancelled = false
        if type(task.cancel) == "function" then cancelled = pcall(task.cancel, job.Thread) end
        if not cancelled then job.Detached = true; self.Detached = self.Detached + 1 end
    end
end
function Jobs:CancelAll()
    local keys = {}
    for key in pairs(self.Pending) do table.insert(keys, key) end
    for _, key in ipairs(keys) do self:Cancel(key) end
end
function Jobs:Step(now)
    local completed = {}
    for key, job in pairs(self.Pending) do
        if job.Done or now >= job.Deadline then table.insert(completed, {Key = key, Job = job}) end
    end
    for _, item in ipairs(completed) do
        local key, job = item.Key, item.Job
        if self.Pending[key] == job then
            local ok, result = job.OK, job.Result
            if not job.Done then self:Cancel(key); ok, result = false, "ASYNC_TIMEOUT: " .. key
            else self.Pending[key] = nil end
            if Hub:IsAlive() then job.Callback(ok, result) end
        end
    end
end

local QuestDatabase = {Status = "NOT_LOADED", Rows = {}, NPCs = {}, Error = nil, Stats = {}}
function QuestDatabase:Load()
    if self.Status == "LOADING" then return end
    local quests, guide = Services.ReplicatedStorage:FindFirstChild("Quests"), Services.ReplicatedStorage:FindFirstChild("GuideModule")
    if not quests or not quests:IsA("ModuleScript") or not guide or not guide:IsA("ModuleScript") then
        self.Status, self.Error = "ERROR", "QUEST_MODULES_MISSING"; return
    end
    self.Status, self.Error = "LOADING", nil
    local started = Jobs:Start("database", function()
        local q, g = require(quests), require(guide)
        local result, err = Logic.BuildDatabase(q, g, SeaDetector:Get())
        if not result then error(err, 0) end
        return result
    end, 10, function(ok, result)
        if ok then
            self.Rows, self.NPCs, self.Stats, self.Sea, self.Status = result.Rows, result.NPCs, result.Stats, result.Sea, "READY"
            local low, high = self.Rows[#self.Rows].MinLevel, self.Rows[1].MinLevel
            Hub:Debug("Quest data", #self.Rows .. " rows; thresholds " .. low .. ".." .. high
                .. "; unbound=" .. self.Stats.Unbound .. "; ambiguous=" .. self.Stats.Ambiguous .. "; otherSea=" .. self.Stats.OtherSea)
            Hub:Log("Quest data ready: " .. #self.Rows .. " server rows; NPC binding is checked separately")
        else self.Status, self.Error = "ERROR", tostring(result); Hub:Log(self.Error, true) end
    end)
    if not started then self.Status, self.Error = "ERROR", "ASYNC_UNAVAILABLE" end
end
local QuestSelector = {}
function QuestSelector:Select(level) return Logic.SelectQuest(QuestDatabase.Rows, level) end
function QuestSelector:NPCPosition(row)
    if row.NPCError then return nil, row.NPCError .. ": " .. row.Id end
    if type(row.NPC) ~= "string" then return nil, "QUEST_NPC_MAPPING_MISSING: " .. row.Id end
    local folder = Services.Workspace:FindFirstChild("NPCs")
    local found, score, count = nil, nil, 0
    if folder then
        for _, npc in ipairs(folder:GetChildren()) do
            if Logic.Canonical(npc.Name) == Logic.Canonical(row.NPC) then
                local position = pointOf(npc)
                if position then
                    count = count + 1
                    local distance = row.Position and (position - row.Position).Magnitude or 0
                    if not score or distance < score then found, score = position, distance end
                end
            end
        end
    end
    if count > 1 and not row.Position then return nil, "QUEST_NPC_MAPPING_AMBIGUOUS: " .. row.NPC end
    if found then return found end
    local position = Logic.Position(row.Position)
    if position then return position end
    return nil, "QUEST_NPC_POSITION_UNAVAILABLE"
end
function QuestSelector:FromTitle(title, level)
    local match
    for _, row in ipairs(QuestDatabase.Rows) do
        if row.MinLevel <= level and Logic.TitleMatches(title, row.Target) then
            if match and match.Target ~= row.Target then return nil end
            match = match or row
        end
    end
    return match
end
local function questView()
    local main = PlayerGui:FindFirstChild("Main")
    local quest = main and main:FindFirstChild("Quest")
    if not quest or not quest:IsA("GuiObject") then return nil end
    if not quest.Visible then return {Visible = false, Text = "No active quest"} end
    local container = quest:FindFirstChild("Container")
    local title = container and container:FindFirstChild("QuestTitle")
    local text = title and title:FindFirstChild("Title")
    if not text or not (text:IsA("TextLabel") or text:IsA("TextButton")) then return nil end
    return {Visible = true, Text = text.Text}
end

local TargetManager = {}
function TargetManager:Alive(model)
    local folder = Services.Workspace:FindFirstChild("Enemies")
    if not folder or not model or model.Parent ~= folder or not model:IsA("Model") then return nil end
    if Services.Players:GetPlayerFromCharacter(model) then return nil end
    local humanoid, root = model:FindFirstChildOfClass("Humanoid"), model:FindFirstChild("HumanoidRootPart")
    if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then return humanoid, root end
    return nil
end
function TargetManager:Find(name, ctx)
    local folder = Services.Workspace:FindFirstChild("Enemies")
    if not folder then return nil end
    local selected, score
    for i, model in ipairs(folder:GetChildren()) do
        if i > 1500 then break end
        if Logic.Canonical(model.Name) == Logic.Canonical(name) then
            local h, r = self:Alive(model)
            if h then
                local distance = (r.Position - ctx.Root.Position).Magnitude
                local candidate = Settings.TargetOrder == "Lowest health" and h.Health or distance
                if distance <= Settings.ScanRadius and (not score or candidate < score) then selected, score = model, candidate end
            end
        end
    end
    return selected
end
function TargetManager:Spawn(name, ctx)
    local origin = Services.Workspace:FindFirstChild("_WorldOrigin")
    local spawns = origin and origin:FindFirstChild("EnemySpawns")
    local position, distance
    if spawns then
        for i, node in ipairs(spawns:GetChildren()) do
            if i > 2500 then break end
            if Logic.Canonical(node.Name) == Logic.Canonical(name) then
                local point = pointOf(node)
                local d = point and (point - ctx.Root.Position).Magnitude
                if d and (not distance or d < distance) then position, distance = point, d end
            end
        end
    end
    return position
end
function TargetManager:Bosses()
    local folder, names, seen = Services.Workspace:FindFirstChild("Enemies"), {}, {}
    if folder then
        for i, model in ipairs(folder:GetChildren()) do
            if i > 1500 then break end
            -- Only explicit, live labels. No invented static boss/spawn list.
            if (model.Name:find("[Boss]", 1, true) or model.Name:find("[Raid Boss]", 1, true)) and self:Alive(model) then
                if not seen[model.Name] then seen[model.Name] = true; table.insert(names, model.Name) end
            end
        end
    end
    table.sort(names)
    return names
end

local MovementController = {Tween = nil}
function MovementController:Stop()
    if self.Tween then pcall(function() self.Tween:Cancel() end); self.Tween = nil end
    if self.Humanoid and self.Humanoid.Parent and self.Root and self.Root.Parent then
        pcall(function() self.Humanoid:MoveTo(self.Root.Position); self.Humanoid:Move(Vector3.new(), false) end)
    end
    self.Goal, self.Started, self.LastProgress, self.LastDistance, self.Humanoid, self.LastPosition, self.Root = nil, nil, nil, nil, nil, nil, nil
end
function MovementController:Go(ctx, goal, now, tolerance)
    if not Logic.Position(goal) then return false, "INVALID_DESTINATION" end
    local distance = (ctx.Root.Position - goal).Magnitude
    if distance <= (tolerance or 5) then self.LastPosition = ctx.Root.Position; self:Stop(); return true end
    if self.Humanoid ~= ctx.Humanoid or not self.Goal or (self.Goal - goal).Magnitude > 7 then
        self:Stop()
        self.Goal, self.Started, self.LastProgress, self.LastDistance = goal, now, now, distance
        self.Humanoid, self.LastPosition, self.LastIssued, self.Root = ctx.Humanoid, ctx.Root.Position, 0, ctx.Root
    end
    self.LastPosition = ctx.Root.Position
    if distance < self.LastDistance - 1 then self.LastProgress, self.LastDistance = now, distance end
    if now - self.LastProgress > 10 then self:Stop(); return false, "MOVEMENT_BLOCKED_OR_CORRECTED" end
    if now - self.Started > 180 then self:Stop(); return false, "MOVEMENT_TIMEOUT" end
    if Settings.Movement == "Tween" then
        if not self.Tween then
            local duration = math.clamp(distance / Settings.TweenSpeed, 0.15, 180)
            local ok, tween = pcall(function()
                return Services.TweenService:Create(ctx.Root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = CFrame.new(goal)})
            end)
            if not ok then self:Stop(); return false, "TWEEN_UNAVAILABLE" end
            self.Tween = tween; tween:Play()
        end
    elseif now - self.LastIssued >= 0.8 then
        ctx.Humanoid:MoveTo(goal); self.LastIssued = now
    end
    return false
end

local CombatController = {Attempts = 0, MetadataWarnings = setmetatable({}, {__mode = "k"})}
function CombatController:Tools(kind)
    local result, seen = {}, {}
    local backpack = Player:FindFirstChildOfClass("Backpack")
    for _, holder in ipairs({Player.Character or false, backpack or false}) do
        if holder then
            for _, object in ipairs(holder:GetChildren()) do
                -- ToolTip belongs to Tool. Never inspect it on character Parts.
                if object:IsA("Tool") then
                    local ok, name, tooltip = pcall(function() return object.Name, object.ToolTip end)
                    if ok and (not kind or tooltip == kind) and not seen[name] then
                        self.MetadataWarnings[object] = nil
                        seen[name] = true; table.insert(result, object)
                    elseif not ok and not self.MetadataWarnings[object] then
                        self.MetadataWarnings[object] = true
                        Hub:Log("TOOL_METADATA_UNREADABLE: " .. tostring(name):sub(1, 100), true)
                    end
                end
            end
        end
    end
    table.sort(result, function(a, b) return a.Name < b.Name end)
    return result
end
function CombatController:UsableTools(kind)
    local result = {}
    for _, tool in ipairs(self:Tools(kind)) do
        if kind or tool.ToolTip == "Melee" or tool.ToolTip == "Sword" then table.insert(result, tool) end
    end
    return result
end
function CombatController:Stop()
    if self.Tool then pcall(function() self.Tool:Deactivate() end) end
    self.Tool, self.Target, self.LastHealth, self.LastProgress, self.LastAttack, self.EquippedAt = nil, nil, nil, nil, nil, nil
    self.Attempts = 0
end
function CombatController:Mastery()
    local tool = self.Tool
    if not tool and Player.Character then tool = Player.Character:FindFirstChildOfClass("Tool") end
    local level = tool and tool:FindFirstChild("Level")
    if level and (level:IsA("IntValue") or level:IsA("NumberValue")) then return tool.Name, level.Value end
    return tool and tool.Name or "None", nil
end
function CombatController:Tick(ctx, target, now, kind)
    local equipped = ctx.Character:FindFirstChildOfClass("Tool")
    if self.Tool and equipped ~= self.Tool then return false, "TOOL_CHANGED: restart after manual switch" end
    if not self.Tool then
        local selected
        if Settings.Weapon ~= "" then
            for _, tool in ipairs(self:UsableTools(kind)) do if tool.Name == Settings.Weapon then selected = tool; break end end
            if not selected and not kind then
                for _, tool in ipairs(self:Tools()) do
                    if tool.Name == Settings.Weapon then return false, "TOOL_TYPE_UNVERIFIED: " .. tool.Name .. " (" .. tool.ToolTip .. ")" end
                end
            end
        elseif equipped and (kind and equipped.ToolTip == kind or not kind and (equipped.ToolTip == "Melee" or equipped.ToolTip == "Sword")) then selected = equipped
        elseif Settings.AutoEquip then selected = self:UsableTools(kind)[1] end
        if not selected then return false, "NO_MATCHING_TOOL" end
        if selected ~= equipped then
            if not Settings.AutoEquip then return false, "EQUIP_SELECTED_TOOL_FIRST" end
            ctx.Humanoid:EquipTool(selected)
            if selected.Parent ~= ctx.Character then return false, "TOOL_EQUIP_NOT_CONFIRMED" end
        end
        self.Tool, self.EquippedAt = selected, now
    end
    local h, root = TargetManager:Alive(target)
    if not h then return true end
    if (root.Position - ctx.Root.Position).Magnitude > Settings.FarmDistance + 3 then return true end
    if self.Target ~= target then
        self.Target, self.LastHealth, self.LastProgress, self.LastAttack = target, h.Health, now, 0
    end
    if h.Health < self.LastHealth then self.LastProgress = now end
    self.LastHealth = h.Health
    if now - self.LastProgress > 12 then return false, "COMBAT_NO_PROGRESS: no observed damage" end
    if now - self.LastAttack < Settings.AttackInterval then return true end
    if not self.Tool.Enabled then
        if now - self.EquippedAt > 8 then return false, "TOOL_DISABLED" end
        return true
    end
    if self.Tool.RequiresHandle and not self.Tool:FindFirstChild("Handle") then return false, "TOOL_HANDLE_MISSING" end
    local ok, err = pcall(function()
        if Settings.AttackMethod == "VirtualUser (optional)" then
            local input = Services.VirtualUser
            if not input then input = game:GetService("VirtualUser"); Services.VirtualUser = input end
            input:CaptureController()
            input:ClickButton1(Vector2.new(0, 0))
        else self.Tool:Activate(); self.Tool:Deactivate() end
    end)
    if not ok then return false, "ATTACK_API_UNAVAILABLE: " .. tostring(err):sub(1, 90) end
    self.LastAttack, self.Attempts = now, self.Attempts + 1
    return true
end

-- Event listeners are replaced on respawn/backpack replacement, never appended
-- to the global connection list on every equip. Polling also catches metadata edits.
local InventoryController = {Connections = {}, Revision = 0, Signature = "", NextPoll = 0}
function InventoryController:Changed() self.Revision = self.Revision + 1 end
function InventoryController:Cleanup()
    for _, connection in ipairs(self.Connections) do connection:Disconnect() end
    self.Connections = {}
end
function InventoryController:Bind()
    self:Cleanup()
    for _, holder in ipairs({Player.Character or false, Player:FindFirstChildOfClass("Backpack") or false}) do
        if holder then
            for _, event in ipairs({holder.ChildAdded, holder.ChildRemoved}) do
                table.insert(self.Connections, event:Connect(function(object)
                    if object:IsA("Tool") then self:Changed() end
                end))
            end
        end
    end
    self:Changed()
end
function InventoryController:Step(now)
    if now < self.NextPoll then return end
    self.NextPoll = now + 0.5
    local names = {}
    for _, tool in ipairs(CombatController:Tools()) do
        table.insert(names, tool.Name .. "\0" .. tool.ToolTip .. "\0" .. (tool.Parent == Player.Character and "equipped" or "backpack"))
    end
    local signature = table.concat(names, "\1")
    if signature ~= self.Signature then self.Signature = signature; self:Changed() end
end

local RecoveryController = {}
function RecoveryController:Check(job, now)
    local ctx = characterContext()
    if ctx then job.RecoverySince = nil; return ctx end
    MovementController:Stop(); CombatController:Stop()
    job.RecoverySince = job.RecoverySince or now
    job:SetState("RECOVERING", "Waiting for a living character")
    if now - job.RecoverySince > 45 then job:Fail("RESPAWN_TIMEOUT") end
    return nil
end

local FarmController = {}
FarmController.__index = FarmController
function FarmController.new(mode)
    return setmetatable({Mode = mode, Running = false, State = "IDLE", Detail = "Ready"}, FarmController)
end
function FarmController:SetState(state, detail) self.State, self.Detail = state, detail or state end
function FarmController:Start()
    self:Cleanup()
    self.Running, self.Started, self.State, self.Detail = true, os.clock(), "CHECKING", "Checking live data"
    Hub.DebugValues = {}
    if self.Mode ~= "boss" and QuestDatabase.Status ~= "READY" and QuestDatabase.Status ~= "LOADING" then QuestDatabase:Load() end
    return true
end
function FarmController:Stop(reason)
    self.Running = false; self:SetState("STOPPED", reason or "Stopped")
    self:Cleanup()
end
function FarmController:IsRunning() return self.Running end
function FarmController:GetStatus() return {Running = self.Running, State = self.State, Detail = self.Detail} end
function FarmController:Cleanup()
    if self.Running then self:SetState("STOPPED", "Resources released") end
    self.Running = false
    Jobs:Cancel("action"); MovementController:Stop(); CombatController:Stop()
    self.Target, self.Quest, self.Awaiting, self.QuestAttempts, self.NoTargetSince, self.UIWait, self.QuestText = nil, nil, nil, 0, nil, nil, nil
    self.EncounterTarget, self.EncounterProgress, self.EncounterHealth = nil, nil, nil
    self.RecoverySince, self.HakiAttempted, self.NPCWait, self.Until, self.LevelWait = nil, false, nil, nil, nil
end
function FarmController:Fail(message)
    self:Stop(message); self:SetState("ERROR", message); Hub:Log(message, true); Hub:RefreshUI()
end
function FarmController:Respawn()
    local running = self.Running
    self:Cleanup()
    if running then self.Running = true; self.RecoverySince = os.clock(); self:SetState("RECOVERING", "Character respawn") end
end
function FarmController:PrepareQuest(ctx, level, now)
    if QuestDatabase.Status ~= "READY" then
        self:SetState("CHECKING", "Quest data: " .. QuestDatabase.Status)
        if QuestDatabase.Status == "ERROR" then self:Fail(QuestDatabase.Error) end
        return false
    end
    local view = questView()
    if not view then
        self.UIWait = self.UIWait or now; self:SetState("RECOVERING", "Quest UI not readable")
        if now - self.UIWait > 10 then self:Fail("QUEST_UI_SCHEMA_CHANGED") end
        return false
    end
    self.UIWait = nil
    Hub:Debug("Quest Status", view.Visible and view.Text or "No active quest")
    if view.Visible then
        local previous = self.Quest
        if not self.Quest or not Logic.TitleMatches(view.Text, self.Quest.Target) then
            self.Quest = QuestSelector:FromTitle(view.Text, level)
        end
        if not self.Quest then self:Fail("QUEST_MISMATCH: finish or abandon current quest"); return false end
        if previous and previous.Id ~= self.Quest.Id then
            MovementController:Stop(); CombatController:Stop()
            self.Target, self.NoTargetSince, self.EncounterTarget = nil, nil, nil
        end
        self.Awaiting, self.QuestAttempts, self.NPCWait = nil, 0, nil
        self.QuestText = view.Text
        Hub:Debug("Selected Quest", self.Quest.Id)
        Hub:Debug("Target Mob", self.Quest.Target)
        return true
    end
    self.QuestText = view.Text
    if self.Awaiting then
        self:SetState("CHECKING", "Waiting for quest UI confirmation")
        if now < self.Awaiting then return false end
        self.Awaiting = nil
        if self.QuestAttempts >= 3 then self:Fail("QUEST_NOT_CONFIRMED_AFTER_3_ATTEMPTS"); return false end
    end
    if Jobs.Pending.action then return false end
    CombatController:Stop(); self.Target = nil
    self:SetState("SELECTING_QUEST", "Selecting from validated quest data")
    local row, err = QuestSelector:Select(level)
    if not row then
        Hub:Debug("Selected Quest", "none (" .. err .. ")")
        self:Fail(err .. ": level=" .. level .. ", sea=" .. tostring(SeaDetector:Get()) .. ", rows=" .. #QuestDatabase.Rows); return false
    end
    self.Quest = row
    Hub:Debug("Selected Quest", row.Id .. " [" .. row.MinLevel .. ".." .. tostring(row.MaxLevel or "open") .. "]")
    Hub:Debug("Target Mob", row.Target)
    local npcPosition, bindingError = QuestSelector:NPCPosition(row)
    if not npcPosition then self:Fail(bindingError or "QUEST_NPC_POSITION_UNAVAILABLE"); return false end
    local arrived, moveError = MovementController:Go(ctx, npcPosition, now, 10)
    if moveError then self:Fail(moveError); return false end
    if not arrived then self:SetState("MOVING", "Quest NPC: " .. row.NPC); return false end
    local npcs, found = Services.Workspace:FindFirstChild("NPCs"), false
    if npcs then
        for _, npc in ipairs(npcs:GetChildren()) do
            if Logic.Canonical(npc.Name) == Logic.Canonical(row.NPC) then
                local pos = pointOf(npc)
                if pos and (pos - npcPosition).Magnitude <= 40 then found = true; break end
            end
        end
    end
    if not found then
        self.NPCWait = self.NPCWait or now; self:SetState("RECOVERING", "Waiting for quest NPC to load")
        if now - self.NPCWait > 15 then self:Fail("QUEST_NPC_NOT_LOADED") end
        return false
    end
    local remote = commRemote()
    if not remote then self:Fail("COMM_REMOTE_MISSING_OR_CHANGED"); return false end
    self.QuestAttempts = self.QuestAttempts + 1
    self.Awaiting = now + 7
    local started = Jobs:Start("action", function()
        if not self.Running or not Hub:IsAlive() then error("CANCELLED", 0) end
        return remote:InvokeServer("StartQuest", row.Group, row.Index)
    end, 6, function(ok, result)
        if self.Running and not ok then self:Fail("QUEST_REQUEST_FAILED: " .. tostring(result):sub(1, 120)) end
    end)
    if not started then self:Fail("ASYNC_UNAVAILABLE") end
    return false
end
function FarmController:Step(now)
    if not self.Running then return end
    local ctx = RecoveryController:Check(self, now)
    if not ctx then return end
    local sea = SeaDetector:Get()
    Hub:Debug("Current Sea", sea or ("unknown place " .. tostring(game.PlaceId)))
    if not sea then self:Fail("UNKNOWN_SEA: unsupported place ID"); return end
    local level, levelError = LevelDetector:Get()
    Hub:Debug("Player Level", level or "unreadable")
    if not level then
        if levelError == "LEVEL_DATA_LOADING" then
            self.LevelWait = self.LevelWait or now
            self:SetState("RECOVERING", "Waiting for Player.Data.Level")
            if now - self.LevelWait > 12 then self:Fail("LEVEL_DATA_MISSING_OR_CHANGED: 12s timeout") end
        else self:Fail(levelError) end
        return
    end
    self.LevelWait = nil
    local name, kind
    if self.Mode == "boss" then
        name = Settings.Boss
        if name == "" then self:Fail("SELECT_A_LIVE_LABELLED_BOSS"); return end
    else
        if not self:PrepareQuest(ctx, level, now) then return end
        name = self.Quest.Target
        kind = self.Mode == "melee" and "Melee" or self.Mode == "sword" and "Sword" or nil
    end
    if self.Target and not TargetManager:Alive(self.Target) then
        MovementController:Stop(); CombatController:Stop(); self.Target = nil
    end
    self.Target = self.Target or TargetManager:Find(name, ctx)
    if not self.Target then
        CombatController:Stop()
        self.NoTargetSince = self.NoTargetSince or now
        local spawn = self.Mode ~= "boss" and TargetManager:Spawn(name, ctx)
        if spawn then
            local _, moveError = MovementController:Go(ctx, spawn, now, 8)
            if moveError then self:Fail(moveError); return end
        else MovementController:Stop() end
        self:SetState(spawn and "MOVING" or "RECOVERING", "Waiting for " .. name)
        if now - self.NoTargetSince > (self.Mode == "boss" and 20 or 60) then self:Fail("TARGET_NOT_FOUND_TIMEOUT") end
        return
    end
    self.NoTargetSince = nil
    local targetHumanoid, targetRoot = TargetManager:Alive(self.Target)
    if self.EncounterTarget ~= self.Target then
        self.EncounterTarget, self.EncounterProgress, self.EncounterHealth = self.Target, now, targetHumanoid.Health
    end
    if targetHumanoid.Health < self.EncounterHealth then self.EncounterProgress = now end
    self.EncounterHealth = targetHumanoid.Health
    if now - self.EncounterProgress > 120 then self:Fail("TARGET_NO_PROGRESS_TIMEOUT"); return end
    local delta = ctx.Root.Position - targetRoot.Position
    local flat = Vector3.new(delta.X, 0, delta.Z)
    if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, 1) end
    local goal = targetRoot.Position + flat.Unit * Settings.FarmDistance
    local arrived, moveError = MovementController:Go(ctx, goal, now, 2)
    if moveError then self:Fail(moveError); return end
    if not arrived then
        CombatController.LastProgress = now
        self:SetState("MOVING", "Approaching " .. name); return
    end
    ctx.Root.CFrame = CFrame.lookAt(ctx.Root.Position, Vector3.new(targetRoot.Position.X, ctx.Root.Position.Y, targetRoot.Position.Z))
    if Settings.AutoHaki and not self.HakiAttempted then
        self.HakiAttempted = true
        if not ctx.Character:FindFirstChild("HasBuso") then
            local remote = commRemote()
            if not remote then
                Settings.AutoHaki = false; Hub:Log("Auto Haki disabled: remote unavailable", true)
            elseif not Jobs:Start("action", function()
                if not self.Running or not Hub:IsAlive() then error("CANCELLED", 0) end
                return remote:InvokeServer("Buso")
            end, 5, function(ok, result)
                if not ok then Hub:Log("Auto Haki disabled: " .. tostring(result):sub(1, 70), true); Settings.AutoHaki = false end
            end) then Settings.AutoHaki = false end
        end
    end
    self:SetState("FIGHTING", name)
    local ok, combatError = CombatController:Tick(ctx, self.Target, now, kind)
    if not ok then self:Fail(combatError) end
end

-- Incremental, bounded world inspection. Only dropped Tools and the observed
-- ChestModels folder; no assumed pickup remote or fake touch API.
Observer = {Manual = false, Running = false, Results = {}, Seen = {}, LastScan = -10, Truncated = false}
function Observer:Start() self.Manual, self.Running = true, true; return true end
function Observer:Stop()
    self.Manual, self.Running, self.Once, self.Queue, self.Building = false, false, false, nil, nil
end
function Observer:IsRunning() return self.Running end
function Observer:GetStatus() return {Running = self.Running, State = self.Queue and "SCANNING" or "IDLE", Detail = self.Truncated and "Scan capped at 12000 nodes" or "Loaded world only"} end
function Observer:Cleanup() self:Stop(); self.Results, self.Seen = {}, {} end
function Observer:ScanOnce() self.Once, self.Running = true, true; self.LastScan = -10 end
function Observer:Process(node)
    if node:IsA("Tool") and node.Name:lower():find("fruit", 1, true) then
        local handle = node:FindFirstChild("Handle")
        if handle and handle:IsA("BasePart") then
            table.insert(self.Building, {Kind = "Fruit", Object = node, Position = handle.Position, Name = node.Name})
            if self.Manual and not self.Seen[node] then
                local ctx = characterContext()
                if ctx and (handle.Position - ctx.Root.Position).Magnitude <= Settings.ScanRadius then
                    Hub:Log("Dropped fruit observed: " .. node.Name)
                    self.Seen[node] = true
                end
            end
        end
    end
end
function Observer:Step(now, demanded)
    self.Running = self.Manual or self.Once == true or demanded
    if not self.Running then self.Queue = nil; return end
    if not self.Queue and now - self.LastScan >= 4 then
        self.Queue, self.QueueIndex, self.Building, self.Visited, self.Truncated = {Services.Workspace}, 1, {}, 0, false
        local chests = Services.Workspace:FindFirstChild("ChestModels")
        if chests then
            for i, chest in ipairs(chests:GetChildren()) do
                if i > 1000 then break end
                local pos = pointOf(chest)
                if pos then table.insert(self.Building, {Kind = "Chest", Object = chest, Position = pos, Name = chest.Name}) end
            end
        end
    end
    if not self.Queue then return end
    for _ = 1, 200 do
        local node = self.Queue[self.QueueIndex]
        if not node then break end
        self.Queue[self.QueueIndex], self.QueueIndex, self.Visited = false, self.QueueIndex + 1, self.Visited + 1
        if node.Parent or node == Services.Workspace then
            local skip = node ~= Services.Workspace and node:IsA("Model") and node:FindFirstChildOfClass("Humanoid")
            if not skip then
                self:Process(node)
                if not node:IsA("Tool") then
                    for _, child in ipairs(node:GetChildren()) do
                        if #self.Queue < 12000 then table.insert(self.Queue, child) else self.Truncated = true end
                    end
                end
            end
        end
        if self.Visited >= 12000 then self.Truncated = true; break end
    end
    if not self.Queue[self.QueueIndex] or self.Visited >= 12000 then
        self.Results, self.Queue, self.LastScan = self.Building, nil, now
        self.Building = nil
        for object in pairs(self.Seen) do if not object:IsDescendantOf(Services.Workspace) then self.Seen[object] = nil end end
        if self.Once then self.Once = false; self.Running = self.Manual or demanded end
    end
end
function Observer:Nearest(kind, ctx)
    local chosen, distance
    for _, item in ipairs(self.Results) do
        if item.Kind == kind and item.Object:IsDescendantOf(Services.Workspace) then
            local pos = pointOf(item.Object)
            local d = pos and (pos - ctx.Root.Position).Magnitude
            if d and d <= Settings.ScanRadius and (not distance or d < distance) then item.Position = pos; chosen, distance = item, d end
        end
    end
    return chosen
end

local CollectionController = {}
CollectionController.__index = CollectionController
function CollectionController.new(kind) return setmetatable({Kind = kind, State = "IDLE", Detail = "Ready", Running = false}, CollectionController) end
function CollectionController:SetState(state, detail) self.State, self.Detail = state, detail end
function CollectionController:Start()
    self:Cleanup(); self.Running, self.Started, self.SearchSince = true, os.clock(), os.clock()
    self:SetState("CHECKING", "Scanning loaded items"); return true
end
function CollectionController:Stop(reason) self.Running = false; self:Cleanup(); self:SetState("STOPPED", reason or "Stopped") end
function CollectionController:IsRunning() return self.Running end
function CollectionController:GetStatus() return {Running = self.Running, State = self.State, Detail = self.Detail} end
function CollectionController:Cleanup()
    if self.Running then self:SetState("STOPPED", "Resources released") end
    self.Running = false
    MovementController:Stop(); self.Item, self.Arrived, self.CashBefore, self.RecoverySince = nil, nil, nil, nil
end
function CollectionController:Respawn()
    local running = self.Running
    self:Cleanup(); self.Running = running; self.SearchSince = os.clock()
end
function CollectionController:Fail(err) self:Stop(err); self:SetState("ERROR", err); Hub:Log(err, true) end
function CollectionController:Step(now)
    if not self.Running then return end
    local ctx = RecoveryController:Check(self, now)
    if not ctx then return end
    if not SeaDetector:Get() then self:Fail("UNKNOWN_SEA"); return end
    if self.Kind == "Chest" and LevelDetector:Beli() == nil then self:Fail("BELI_DATA_REQUIRED_TO_OBSERVE_PICKUP"); return end
    if not self.Item then
        self.Item = Observer:Nearest(self.Kind, ctx)
        if not self.Item then
            self:SetState("CHECKING", "No loaded " .. self.Kind:lower() .. " in range")
            if now - self.SearchSince > 20 then self:Fail("NO_ITEMS_IN_RANGE_TIMEOUT") end
            return
        end
        self.CashBefore = LevelDetector:Beli()
    end
    local item = self.Item
    local backpack = Player:FindFirstChildOfClass("Backpack")
    if self.Kind == "Fruit" and ((backpack and item.Object:IsDescendantOf(backpack)) or item.Object:IsDescendantOf(ctx.Character)) then
        Hub:Log("Fruit entered your inventory: " .. item.Name)
        self.Item, self.Arrived, self.SearchSince = nil, nil, now; return
    end
    if not item.Object:IsDescendantOf(Services.Workspace) then
        if self.Kind == "Chest" and self.Arrived and (LevelDetector:Beli() or 0) > (self.CashBefore or math.huge) then
            Hub:Log("Chest disappeared and Beli increased")
            self.Item, self.Arrived, self.CashBefore, self.SearchSince = nil, nil, nil, now
            return
        else Hub:Log("Item disappeared; pickup not confirmed", true) end
        self:Stop("Item observation finished; scan again to continue"); return
    end
    local pos = pointOf(item.Object)
    if not pos then self:Fail("ITEM_POSITION_UNAVAILABLE"); return end
    local arrived, err = MovementController:Go(ctx, pos, now, 2)
    if err then self:Fail(err); return end
    if not arrived then self:SetState("MOVING", item.Name); return end
    self.Arrived = self.Arrived or now
    self:SetState("CHECKING", "Waiting for physical pickup confirmation")
    if now - self.Arrived > 10 then self:Fail("PICKUP_UNCONFIRMED: interaction may have changed") end
end

local TravelController = {Running = false, State = "IDLE", Detail = "Ready"}
function TravelController:Locations()
    local origin = Services.Workspace:FindFirstChild("_WorldOrigin")
    local folder = origin and origin:FindFirstChild("Locations")
    local list = {}
    if folder then
        for i, node in ipairs(folder:GetChildren()) do
            if i > 500 then break end
            if pointOf(node) then table.insert(list, node) end
        end
    end
    table.sort(list, function(a, b) return a.Name < b.Name end)
    return list
end
function TravelController:SetState(state, detail) self.State, self.Detail = state, detail end
function TravelController:Start()
    self:Cleanup(); self.Running, self.Started = true, os.clock()
    self:SetState("CHECKING", "Resolving loaded destination"); return true
end
function TravelController:Stop(reason) self.Running = false; self:Cleanup(); self:SetState("STOPPED", reason or "Stopped") end
function TravelController:IsRunning() return self.Running end
function TravelController:GetStatus() return {Running = self.Running, State = self.State, Detail = self.Detail} end
function TravelController:Cleanup()
    if self.Running then self:SetState("STOPPED", "Resources released") end
    self.Running = false
    MovementController:Stop(); self.RecoverySince = nil
end
function TravelController:Respawn() self:Stop("Travel stopped on respawn") end
function TravelController:Fail(err) self:Stop(err); self:SetState("ERROR", err); Hub:Log(err, true) end
function TravelController:Step(now)
    if not self.Running then return end
    if not SeaDetector:Get() then self:Fail("UNKNOWN_SEA"); return end
    local ctx = RecoveryController:Check(self, now)
    if not ctx then return end
    local point
    for _, node in ipairs(self:Locations()) do if node.Name == Settings.Destination then point = pointOf(node); break end end
    if not point then self:Fail("DESTINATION_NOT_LOADED"); return end
    self:SetState("MOVING", Settings.Destination)
    local arrived, err = MovementController:Go(ctx, point, now, 4)
    if err then self:Fail(err) elseif arrived then self:Stop("Destination reached") end
end

Manager = {Tasks = {
    level = FarmController.new("level"), melee = FarmController.new("melee"), sword = FarmController.new("sword"),
    boss = FarmController.new("boss"), fruit = CollectionController.new("Fruit"), chest = CollectionController.new("Chest"), travel = TravelController,
}}
function Manager:Start(name)
    if not Hub:IsAlive() then return false end
    local job = self.Tasks[name]
    if not job then return false end
    if self.Active == job and job:IsRunning() then return true end
    self:StopAll("Switching task")
    self.Active, self.Name = job, name
    Hub.LastError = nil
    local ok, result = pcall(function() return job:Start() end)
    if not ok then job:Fail(tostring(result)); return false end
    if Settings.MinimizeOnStart and UI then UI:Minimize() end
    Hub:RefreshUI()
    return job:IsRunning()
end
function Manager:StopAll(reason)
    for _, job in pairs(self.Tasks) do job:Stop(reason or "Stopped by user") end
    Jobs:Cancel("action"); MovementController:Stop(); CombatController:Stop()
    Hub:RefreshUI()
end
function Manager:Step(now)
    if self.Active and self.Active:IsRunning() then
        local ok, err = pcall(function() self.Active:Step(now) end)
        if not ok then self.Active:Fail("RUNTIME_ERROR: " .. tostring(err):sub(1, 140)) end
    end
end
function Manager:Status()
    return self.Active and self.Active:GetStatus() or {State = "IDLE", Detail = "Ready", Running = false}
end

Hub.Components.SeaDetector, Hub.Components.LevelDetector = SeaDetector, LevelDetector
Hub.Components.QuestDatabase, Hub.Components.QuestSelector = QuestDatabase, QuestSelector
Hub.Components.TargetManager, Hub.Components.MovementController = TargetManager, MovementController
Hub.Components.CombatController, Hub.Components.RecoveryController = CombatController, RecoveryController
Hub.Components.Jobs, Hub.Components.Observer = Jobs, Observer
Hub.Components.InventoryController = InventoryController
Hub.TaskManager = Manager

-- Native Roblox UI; no downloaded code/library. Optional art uses a Roblox asset ID.
UI = {Bindings = {}, Pages = {}, Tabs = {}, Toasts = {}, Cards = {}, Toggles = {}, Dropdowns = {}, Canvases = {}, ActiveTab = "Dashboard"}
local Palette = {
    Background = Color3.fromRGB(9, 9, 9), Sidebar = Color3.fromRGB(18, 18, 18),
    Panel = Color3.fromRGB(27, 27, 27), Red = Color3.fromRGB(225, 29, 46),
    Hover = Color3.fromRGB(255, 51, 71), Text = Color3.fromRGB(255, 255, 255),
    Muted = Color3.fromRGB(161, 161, 170), Border = Color3.fromRGB(48, 48, 48),
}
local function make(class, parent, properties)
    local object = Instance.new(class)
    for key, value in pairs(properties or {}) do object[key] = value end
    object.Parent = parent
    return object
end
local function rounded(object, radius)
    make("UICorner", object, {CornerRadius = UDim.new(0, radius or 9)})
end
local function stroke(object) make("UIStroke", object, {Color = Palette.Border, Thickness = 1}) end
local function label(parent, text, pos, size, color, textSize)
    return make("TextLabel", parent, {
        BackgroundTransparency = 1, Text = text, Position = pos, Size = size,
        Font = Enum.Font.Gotham, TextSize = textSize or 13, TextColor3 = color or Palette.Text,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true, BorderSizePixel = 0,
    })
end
local function button(parent, text, pos, size, callback, subtle)
    local b = make("TextButton", parent, {
        Text = text, Position = pos, Size = size, Font = Enum.Font.GothamMedium,
        TextSize = 13, TextColor3 = Palette.Text, BorderSizePixel = 0,
        BackgroundColor3 = subtle and Palette.Sidebar or Palette.Red, AutoButtonColor = false,
    })
    rounded(b, 7)
    b.Activated:Connect(function()
        if not Hub:IsAlive() then return end
        local ok, err = pcall(callback)
        if not ok then Hub:Log("UI action: " .. tostring(err):sub(1, 140), true) end
    end)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = subtle and Palette.Panel or Palette.Hover end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = subtle and Palette.Sidebar or Palette.Red end)
    return b
end
function UI:Bind(callback) table.insert(self.Bindings, callback) end
function UI:TrackCanvas(scroll, layout, horizontal, extra)
    table.insert(self.Canvases, {Scroll = scroll, Layout = layout, Horizontal = horizontal, Extra = extra or 0})
    scroll.Active, scroll.ScrollingEnabled, scroll.ClipsDescendants = true, true, true
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
end
function UI:UpdateCanvases()
    for _, binding in ipairs(self.Canvases) do
        if binding.Scroll.Parent and binding.Layout.Parent then
            local horizontal = type(binding.Horizontal) == "function" and binding.Horizontal() or binding.Horizontal == true
            local size = binding.Layout.AbsoluteContentSize
            binding.Scroll.ScrollingDirection = horizontal and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y
            binding.Scroll.CanvasSize = horizontal and UDim2.fromOffset(size.X + binding.Extra, 0) or UDim2.fromOffset(0, size.Y + binding.Extra)
        end
    end
end
function UI:Notify(message, isError)
    if not self.Host then return end
    if #self.Toasts >= 3 then self.Toasts[1].Frame:Destroy(); table.remove(self.Toasts, 1) end
    local frame = make("Frame", self.Host, {Size = UDim2.new(0, 280, 0, 66), BackgroundColor3 = Palette.Panel, BorderSizePixel = 0, ZIndex = 30})
    rounded(frame); stroke(frame)
    local line = make("Frame", frame, {Size = UDim2.new(0, 3, 1, -18), Position = UDim2.fromOffset(0, 9), BackgroundColor3 = isError and Palette.Hover or Palette.Red, BorderSizePixel = 0, ZIndex = 31})
    label(frame, message, UDim2.fromOffset(14, 10), UDim2.new(1, -28, 1, -16), Palette.Text, 12).ZIndex = line.ZIndex
    table.insert(self.Toasts, {Frame = frame, Expires = os.clock() + 5})
end
function UI:Card(page, title, description, height)
    local frame = make("Frame", self.Pages[page], {Size = UDim2.new(1, -6, 0, height or 100), BackgroundColor3 = Palette.Panel, BorderSizePixel = 0, LayoutOrder = #self.Cards + 1})
    rounded(frame); stroke(frame)
    label(frame, title, UDim2.fromOffset(13, 11), UDim2.new(1, -26, 0, 22), Palette.Text, 14)
    if description ~= "" then label(frame, description, UDim2.fromOffset(13, 36), UDim2.new(1, -26, 0, 44), Palette.Muted, 12) end
    table.insert(self.Cards, {Frame = frame, Search = (title .. " " .. description):lower(), Page = page})
    return frame
end
function UI:Info(page, title, getter, height)
    local frame = self:Card(page, title, "", height or 110)
    local body = label(frame, "", UDim2.fromOffset(13, 38), UDim2.new(1, -26, 1, -45), Palette.Muted, 12)
    self:Bind(function() body.Text = tostring(getter()) end)
end
function UI:Action(page, title, description, caption, callback)
    local frame = self:Card(page, title, description, 142)
    return button(frame, caption, UDim2.new(0, 13, 1, -45), UDim2.new(1, -26, 0, 32), callback)
end
function UI:Toggle(page, title, description, getter, setter)
    local frame = self:Card(page, title, description, 106)
    frame:FindFirstChildOfClass("TextLabel").Size = UDim2.new(1, -86, 0, 22)
    local track = button(frame, "", UDim2.new(1, -65, 0, 11), UDim2.fromOffset(50, 24), function() setter(not getter()); Hub:RefreshUI() end, true)
    track.Name = "Toggle_" .. title
    rounded(track, 12)
    local knob = make("Frame", track, {Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = Palette.Text, BorderSizePixel = 0})
    rounded(knob, 9)
    local previous, tween
    local record = {Control = track, Knob = knob, Value = false}
    self.Toggles[title] = record
    self:Bind(function()
        local value = getter() == true
        record.Value = value
        track.BackgroundColor3 = value and Palette.Red or Palette.Border
        if value ~= previous then
            previous = value
            if tween then tween:Cancel() end
            tween = Services.TweenService:Create(knob, TweenInfo.new(0.15), {Position = UDim2.fromOffset(value and 29 or 3, 3)})
            tween:Play()
        end
    end)
end
function UI:Slider(page, title, key, low, high, step, description)
    local frame = self:Card(page, title, description, 116)
    local value = label(frame, "", UDim2.new(1, -84, 0, 11), UDim2.fromOffset(70, 20), Palette.Hover, 13)
    value.TextXAlignment = Enum.TextXAlignment.Right
    frame:FindFirstChildOfClass("TextLabel").Size = UDim2.new(1, -104, 0, 22)
    local hit = make("TextButton", frame, {Text = "", Position = UDim2.new(0, 14, 1, -39), Size = UDim2.new(1, -28, 0, 28), BackgroundTransparency = 1, BorderSizePixel = 0})
    local rail = make("Frame", hit, {Position = UDim2.fromOffset(0, 11), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Palette.Border, BorderSizePixel = 0})
    rounded(rail, 3)
    local fill = make("Frame", rail, {Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Palette.Red, BorderSizePixel = 0})
    rounded(fill, 3)
    local knob = make("Frame", rail, {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(13, 13), BackgroundColor3 = Palette.Text, BorderSizePixel = 0})
    rounded(knob, 7)
    local function update(x)
        local ratio = math.clamp((x - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1)
        Settings[key] = math.clamp(math.floor((low + (high - low) * ratio) / step + 0.5) * step, low, high)
    end
    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            UI.SliderDrag = {Input = input, Update = update}; update(input.Position.X)
        end
    end)
    self:Bind(function()
        local ratio = (Settings[key] - low) / (high - low)
        fill.Size, knob.Position = UDim2.new(ratio, 0, 1, 0), UDim2.new(ratio, 0, 0.5, 0)
        value.Text = string.format(step < 1 and "%.2f" or "%d", Settings[key])
    end)
end
function UI:Dropdown(page, title, description, key, provider, allowAuto)
    local frame = self:Card(page, title, description, 142)
    local record = {Frame = frame, Open = false, Items = {}, Revision = -1}
    self.Dropdowns[key] = record
    local control, list, search
    local function close()
        record.Open = false
        if list then list.Visible = false; search.Visible = false end
        frame.Size = UDim2.new(1, -6, 0, 142)
        control.Position = UDim2.new(0, 13, 1, -45)
    end
    record.Close = close
    local function refresh()
        -- Obtain options first: a provider failure leaves the previous usable menu intact.
        local options = provider()
        if type(options) ~= "table" then error("DROPDOWN_INVALID_OPTIONS: " .. key) end
        for _, item in ipairs(record.Items) do item:Destroy() end
        record.Items = {}
        local query, matches = search.Text:lower(), 0
        local function add(caption, value, informational)
            local item
            if informational then item = label(list, caption, UDim2.new(), UDim2.new(1, -10, 0, 36), Palette.Muted, 12)
            else
                item = button(list, caption, UDim2.new(), UDim2.new(1, -10, 0, 36), function()
                    Manager:StopAll("Selection changed"); Settings[key] = value; close(); Hub:RefreshUI()
                end, true)
                item.TextTruncate = Enum.TextTruncate.AtEnd
            end
            item.LayoutOrder = #record.Items + 1
            table.insert(record.Items, item)
        end
        if allowAuto then add("Auto / Equipped", "") end
        for _, option in ipairs(options) do
            local value, caption = option, option
            if type(option) == "table" then value, caption = option.Value, option.Label end
            caption = tostring(caption)
            if query == "" or caption:lower():find(query, 1, true) then matches = matches + 1; add(caption, value) end
        end
        if matches == 0 then
            add(key == "Weapon" and (#options == 0 and "No weapons found" or "No matching weapons") or "No loaded options", nil, true)
        end
        record.Revision = InventoryController.Revision
        self:UpdateCanvases()
    end
    record.Refresh = refresh
    control = button(frame, "", UDim2.new(0, 13, 1, -45), UDim2.new(1, -26, 0, 32), function()
        if record.Open then close(); return end
        if not list then
            search = make("TextBox", frame, {Name = key .. "Search", Position = UDim2.fromOffset(13, 138), Size = UDim2.new(1, -26, 0, 30), PlaceholderText = "Search...", Text = "", ClearTextOnFocus = false, BackgroundColor3 = Palette.Sidebar, TextColor3 = Palette.Text, PlaceholderColor3 = Palette.Muted, TextSize = 12, Font = Enum.Font.Gotham, BorderSizePixel = 0, Visible = false})
            list = make("ScrollingFrame", frame, {Name = key .. "Options", Position = UDim2.fromOffset(13, 174), Size = UDim2.new(1, -26, 0, 160), BackgroundColor3 = Palette.Sidebar, BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(), Visible = false})
            rounded(search, 6); rounded(list, 6)
            local layout = make("UIListLayout", list, {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
            self:TrackCanvas(list, layout, false, 4)
            record.List, record.Search = list, search
            search:GetPropertyChangedSignal("Text"):Connect(function()
                if record.Open then
                    local ok, err = pcall(refresh)
                    if not ok then Hub:Log("Dropdown search: " .. tostring(err), true) end
                end
            end)
        end
        refresh()
        record.Open = true
        control.Position = UDim2.fromOffset(13, 97)
        local height = math.clamp(self.Pages[page].AbsoluteSize.Y - 170, 96, 184)
        frame.Size, list.Size = UDim2.new(1, -6, 0, 186 + height), UDim2.new(1, -26, 0, height)
        search.Visible, list.Visible = true, true
        self:UpdateCanvases()
    end, true)
    record.Control = control
    control.TextTruncate = Enum.TextTruncate.AtEnd
    self:Bind(function()
        control.Text = (Settings[key] == "" and (allowAuto and "Auto / Equipped" or "Select loaded option") or tostring(Settings[key])) .. "  v"
        if record.Open and key == "Weapon" and record.Revision ~= InventoryController.Revision then refresh() end
        if not record.Open then control.Position = UDim2.new(0, 13, 1, -45) end
    end)
end
function UI:TaskToggle(page, title, description, name)
    self:Toggle(page, title, description, function() return Manager.Tasks[name]:IsRunning() end, function(value)
        if value then Manager:Start(name) elseif Manager.Active == Manager.Tasks[name] then Hub:StopAll() else Manager.Tasks[name]:Stop("Stopped by user") end
    end)
end
function Logic.ImageAsset(value)
    local id = tostring(value or ""):match("^%s*(.-)%s*$")
    if id == "" then return "" end
    id = id:match("^rbxassetid://(%d+)$") or id
    if not id:match("^%d+$") or not id:find("[1-9]") or #id > 20 then return nil end
    return "rbxassetid://" .. id
end
function UI:UpdateFloating()
    local hasImage = self.Reopen.Image ~= ""
    self.Floating.Visible = not self.Window.Visible or hasImage
    self.Floating.Size = UDim2.fromOffset(self.Window.Visible and 56 or 110, 56)
    self.FloatingStop.Visible = not self.Window.Visible
    if self.StatusLabel then self:Layout() end
end
function Hub:SetLuffyImageAssetId(value)
    if self.Destroyed then return false, "HUB_UNLOADED" end
    local imageId = Logic.ImageAsset(value)
    if imageId == nil then return false, "INVALID_IMAGE_ASSET_ID" end
    Config.LuffyImageAssetId = value
    if UI and UI.Reopen then
        UI.Reopen.Image = imageId
        UI.ReopenFallback.Visible = imageId == ""
        UI:UpdateFloating()
    end
    return true
end
function UI:Minimize() self.Window.Visible = false; self:UpdateFloating() end
function UI:Show() self.Window.Visible = true; self:UpdateFloating() end
function UI:ToggleWindow() if self.Window.Visible then self:Minimize() else self:Show() end end
function UI:Layout()
    if not self.Host then return end
    local size = self.Host.AbsoluteSize
    if size.X <= 0 or size.Y <= 0 then return end
    local w, h = math.min(size.X, math.max(240, math.min(820, size.X - 20))), math.min(size.Y, math.max(200, math.min(610, size.Y - 20)))
    local compact = w < 610
    self.Window.Size = UDim2.fromOffset(w, h)
    local old = self.Window.Position
    if not self.Dragged then self.Window.Position = UDim2.fromOffset(math.max(0, (size.X - w) / 2), math.max(0, (size.Y - h) / 2))
    else self.Window.Position = UDim2.fromOffset(math.clamp(old.X.Offset, 0, math.max(0, size.X - w)), math.clamp(old.Y.Offset, 0, math.max(0, size.Y - h))) end
    self.Nav.Position = UDim2.fromOffset(12, 64)
    self.Nav.Size = compact and UDim2.new(1, -24, 0, 40) or UDim2.new(0, 150, 1, -120)
    self.NavLayout.FillDirection = compact and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
    self.Compact = compact
    for _, tab in pairs(self.Tabs) do tab.Size = compact and UDim2.fromOffset(122, 34) or UDim2.new(1, -6, 0, 36) end
    for _, page in pairs(self.Pages) do
        page.Position = compact and UDim2.fromOffset(12, 114) or UDim2.fromOffset(174, 64)
        page.Size = compact and UDim2.new(1, -24, 1, -166) or UDim2.new(1, -186, 1, -116)
    end
    self.StatusLabel.Size = UDim2.new(1, -145, 0, 28)
    if not self.FloatingPlaced then
        self.FloatingPlaced = true
        self.Floating.Position = UDim2.fromOffset(math.max(0, size.X - 122), 76)
    end
    local floatingPos, floatingSize = self.Floating.Position, self.Floating.Size
    self.Floating.Position = UDim2.fromOffset(math.clamp(floatingPos.X.Offset, 0, math.max(0, size.X - floatingSize.X.Offset)), math.clamp(floatingPos.Y.Offset, 0, math.max(0, size.Y - floatingSize.Y.Offset)))
    self:UpdateCanvases()
end
function UI:Build()
    Screen = make("ScreenGui", PlayerGui, {Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 40, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
    Screen:SetAttribute("CrimsonOwner", OWNER)
    local shutdown = make("BindableEvent", Screen, {Name = "Shutdown"})
    Hub:Connect(shutdown.Event, function() Hub:Cleanup() end)
    Hub:Connect(Screen.Destroying, function() Hub:Cleanup() end)
    self.Host = make("Frame", Screen, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0})
    self.Window = make("Frame", self.Host, {Size = UDim2.fromOffset(820, 610), BackgroundColor3 = Palette.Background, BorderSizePixel = 0, ClipsDescendants = true})
    rounded(self.Window, 13); stroke(self.Window)
    local header = make("Frame", self.Window, {Size = UDim2.new(1, 0, 0, 53), BackgroundColor3 = Palette.Sidebar, BorderSizePixel = 0, Active = true})
    label(header, "CRIMSON HUB", UDim2.fromOffset(16, 9), UDim2.new(1, -112, 0, 22), Palette.Text, 18)
    label(header, "v1.1  |  live test pending", UDim2.fromOffset(17, 32), UDim2.new(1, -112, 0, 16), Palette.Muted, 10)
    button(header, "_", UDim2.new(1, -83, 0, 10), UDim2.fromOffset(30, 30), function() self:Minimize() end, true)
    button(header, "X", UDim2.new(1, -44, 0, 10), UDim2.fromOffset(30, 30), function() Hub:Cleanup() end)
    self.Nav = make("ScrollingFrame", self.Window, {BackgroundColor3 = Palette.Sidebar, BorderSizePixel = 0, CanvasSize = UDim2.new(), ScrollBarThickness = 2})
    rounded(self.Nav, 8)
    self.NavLayout = make("UIListLayout", self.Nav, {Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder})
    self:TrackCanvas(self.Nav, self.NavLayout, function() return self.Compact == true end, 8)
    local pages = {"Dashboard", "Auto Farm", "Mastery", "Boss", "Fruit & Chest", "Teleport", "Settings"}
    for index, name in ipairs(pages) do
        local page = make("ScrollingFrame", self.Window, {Name = name, Visible = name == "Dashboard", BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y})
        self.Pages[name] = page
        local layout = make("UIListLayout", page, {Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder})
        self:TrackCanvas(page, layout, false, 16)
        make("UIPadding", page, {PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), PaddingBottom = UDim.new(0, 12)})
        local search = make("TextBox", page, {LayoutOrder = -1, Size = UDim2.new(1, -6, 0, 36), PlaceholderText = "Search controls...", Text = "", ClearTextOnFocus = false, BackgroundColor3 = Palette.Sidebar, TextColor3 = Palette.Text, PlaceholderColor3 = Palette.Muted, TextSize = 12, Font = Enum.Font.Gotham, BorderSizePixel = 0})
        rounded(search, 7)
        search:GetPropertyChangedSignal("Text"):Connect(function()
            local query = search.Text:lower()
            for _, card in ipairs(self.Cards) do if card.Page == name then card.Frame.Visible = query == "" or card.Search:find(query, 1, true) ~= nil end end
        end)
        local tab = button(self.Nav, name, UDim2.new(), UDim2.fromOffset(144, 36), function()
            self.ActiveTab = name
            for n, content in pairs(self.Pages) do content.Visible = n == name end
            if name == "Auto Farm" and self.Dropdowns.Weapon and self.Dropdowns.Weapon.Open then self.Dropdowns.Weapon.Refresh() end
            Hub:RefreshUI()
        end, true)
        tab.LayoutOrder = index; self.Tabs[name] = tab
    end
    self.StatusLabel = label(self.Window, "IDLE", UDim2.new(0, 14, 1, -36), UDim2.new(1, -145, 0, 28), Palette.Muted, 11)
    button(self.Window, "STOP ALL", UDim2.new(1, -119, 1, -42), UDim2.fromOffset(105, 30), function() Hub:StopAll() end)
    self.Floating = make("Frame", self.Host, {Name = "CrimsonFloating", Position = UDim2.fromOffset(12, 110), Size = UDim2.fromOffset(110, 56), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, Active = true})
    local reopen = make("ImageButton", self.Floating, {Name = "LuffyToggle", Position = UDim2.fromOffset(1, 1), Size = UDim2.fromOffset(54, 54), Image = "", ScaleType = Enum.ScaleType.Fit, BackgroundColor3 = Palette.Sidebar, AutoButtonColor = true, BorderSizePixel = 0, ClipsDescendants = true})
    rounded(reopen, 12)
    make("UIStroke", reopen, {Color = Palette.Red, Thickness = 2})
    self.Reopen = reopen
    self.ReopenFallback = label(reopen, "CRIMSON", UDim2.fromOffset(2, 17), UDim2.new(1, -4, 0, 20), Palette.Text, 9)
    self.ReopenFallback.TextXAlignment = Enum.TextXAlignment.Center
    self.FloatingStop = button(self.Floating, "STOP", UDim2.fromOffset(61, 9), UDim2.fromOffset(46, 38), function() Hub:StopAll() end)
    reopen.Activated:Connect(function()
        if Hub:IsAlive() and not self.FloatingDragged then self:ToggleWindow() end
    end)
    Hub:SetLuffyImageAssetId(Config.LuffyImageAssetId)
    local function drag(handle, target, main)
        handle.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if not main then self.FloatingDragged = false end
                self.Drag = {Input = input, Origin = input.Position, Position = target.Position, Target = target, Main = main}
            end
        end)
    end
    drag(header, self.Window, true); drag(reopen, self.Floating, false)
    Hub:Connect(Services.UserInputService.InputChanged, function(input)
        local slide = self.SliderDrag
        if slide and (input == slide.Input or input.UserInputType == Enum.UserInputType.MouseMovement) then slide.Update(input.Position.X) end
        local d = self.Drag
        if d and (input == d.Input or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = input.Position - d.Origin
            local size, ts = self.Host.AbsoluteSize, d.Target.AbsoluteSize
            d.Target.Position = UDim2.fromOffset(math.clamp(d.Position.X.Offset + delta.X, 0, math.max(0, size.X - ts.X)), math.clamp(d.Position.Y.Offset + delta.Y, 0, math.max(0, size.Y - ts.Y)))
            if delta.Magnitude > 6 then
                if d.Main then self.Dragged = true else self.FloatingDragged = true end
            end
        end
    end)
    Hub:Connect(Services.UserInputService.InputEnded, function(input)
        if self.Drag and (input == self.Drag.Input or input.UserInputType == Enum.UserInputType.MouseButton1) then self.Drag = nil end
        if self.SliderDrag and (input == self.SliderDrag.Input or input.UserInputType == Enum.UserInputType.MouseButton1) then self.SliderDrag = nil end
    end)
    Hub:Connect(Services.UserInputService.InputBegan, function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.RightControl then if self.Window.Visible then self:Minimize() else self:Show() end end
    end)
    Hub:Connect(self.Host:GetPropertyChangedSignal("AbsoluteSize"), function() self:Layout() end)
    self:Layout()
end
function UI:Populate()
    self:Info("Dashboard", "Player", function()
        return Player.DisplayName .. "  (@" .. Player.Name .. ")\nLevel: " .. tostring(LevelDetector:Get() or "unreadable") .. "    Sea: " .. tostring(SeaDetector:Get() or "unknown")
    end)
    self:Info("Dashboard", "Task status", function()
        local s = Manager:Status()
        local active = Manager.Active
        return s.State .. "  |  " .. (Manager.Name or "none") .. "\n" .. s.Detail .. "\nRuntime: " .. tostring(active and active.Running and math.floor(os.clock() - active.Started) or 0) .. "s"
    end, 128)
    self:Info("Dashboard", "Current error", function() return Hub.LastError and Hub:Explain(Hub.LastError) or "None" end, 164)
    self:Info("Dashboard", "Validation scope", function()
        return "No live game/executor test performed. Data and progress are checked while running. A method call alone never proves quest, damage or pickup success."
    end, 146)
    self:TaskToggle("Auto Farm", "Auto Level", "Quest selection, NPC approach and monitored combat. Stops when required data or progress is missing.", "level")
    self:Dropdown("Auto Farm", "Weapon", "Live Tools in Character + Backpack. Auto attacks use Melee / Sword; manual combat switches stop the task.", "Weapon", function()
        local names = {}; for _, tool in ipairs(CombatController:Tools()) do table.insert(names, tool.Name) end; return names
    end, true)
    self:Toggle("Auto Farm", "Auto equip tool", "Uses Humanoid:EquipTool once per combat session.", function() return Settings.AutoEquip end, function(v) Settings.AutoEquip = v; Manager:StopAll("Equipment settings changed") end)
    self:Slider("Auto Farm", "Farm distance", "FarmDistance", 3, 10, 1, "Horizontal distance in studs. Excess range may prevent damage.")
    self:Slider("Auto Farm", "Attack interval", "AttackInterval", 0.2, 1.5, 0.05, "One attack scheduler; no simultaneous attack loops.")
    self:Dropdown("Auto Farm", "Target order", "Applies only to matching quest enemies in the Enemies folder.", "TargetOrder", function() return {"Nearest", "Lowest health"} end)
    self:Info("Auto Farm", "Quest", function()
        local job = Manager.Active
        return "Database: " .. QuestDatabase.Status .. " (" .. #QuestDatabase.Rows .. " rows)\n" .. (job and job.QuestText or "No quest observation")
    end, 142)
    self:Action("Auto Farm", "Quest data", "Reads Quests + GuideModule. Keeps valid quests and reports uncertain NPC bindings separately.", "Reload quest data", function()
        Manager:StopAll("Reloading quest data"); QuestDatabase:Load()
    end)
    self:TaskToggle("Mastery", "Melee mastery", "Runs the quest engine using a Tool whose ToolTip is Melee. Mastery credit remains server controlled.", "melee")
    self:TaskToggle("Mastery", "Sword mastery", "Runs the quest engine using a Tool whose ToolTip is Sword.", "sword")
    self:Info("Mastery", "Observed tool mastery", function()
        local tool, mastery = CombatController:Mastery()
        return tool .. "\nMastery: " .. tostring(mastery or "not exposed by this tool")
    end)
    self:Info("Mastery", "Fruit mastery unavailable", function()
        return "No general fruit-skill protocol was verified. There is no fruit mastery toggle or invented Z/X/C/V remote implementation."
    end, 132)
    self:Dropdown("Boss", "Live labelled bosses", "Only live Enemies carrying [Boss] or [Raid Boss] in their name are listed. No spawn coordinates are assumed.", "Boss", function() return TargetManager:Bosses() end)
    self:TaskToggle("Boss", "Auto Boss", "Approaches and attacks the selected live boss. No boss quest. Stops after 20 seconds without a target.", "boss")
    self:Info("Boss", "Boss detection limit", function() return "Games that omit boss labels will produce an empty list. This build does not guess identities or request boss spawns." end, 132)
    self:TaskToggle("Fruit & Chest", "Fruit approach / pickup", "Moves to a dropped fruit Tool and checks whether that same Tool enters your inventory.", "fruit")
    self:TaskToggle("Fruit & Chest", "Chest approach / pickup", "Uses loaded ChestModels. Requires disappearance plus increased Beli to report an observed pickup.", "chest")
    self:Toggle("Fruit & Chest", "Fruit notifications", "Monitors loaded dropped Tools. Scans are bounded; streaming can hide items.", function() return Observer.Manual end, function(v) if v then Observer:Start() else Observer:Stop() end end)
    self:Slider("Fruit & Chest", "Search radius", "ScanRadius", 100, 5000, 100, "Radius in studs for choosing loaded items and enemies.")
    self:Action("Fruit & Chest", "Inspect loaded world", "Incremental scan capped at 12000 nodes. This does not trigger collection.", "Scan once", function() Observer:ScanOnce() end)
    self:Info("Fruit & Chest", "Observed items", function()
        local fruit, chest = 0, 0
        for _, item in ipairs(Observer.Results) do if item.Object:IsDescendantOf(Services.Workspace) then if item.Kind == "Fruit" then fruit = fruit + 1 else chest = chest + 1 end end end
        return "Fruit: " .. fruit .. "    Chests: " .. chest .. "\n" .. Observer:GetStatus().Detail
    end)
    self:Dropdown("Teleport", "Loaded location", "Reads _WorldOrigin.Locations in this Sea. Movement keeps the game's collision settings.", "Destination", function()
        local list = {}; for _, node in ipairs(TravelController:Locations()) do table.insert(list, node.Name) end; return list
    end)
    self:TaskToggle("Teleport", "Move to location", "Walk or optional local Tween. Stops if blocked or corrected. No cross-Sea travel.", "travel")
    self:Dropdown("Settings", "Movement method", "Walk uses MoveTo. Tween writes only your root CFrame; server acceptance is unverified.", "Movement", function() return {"Walk", "Tween"} end)
    self:Slider("Settings", "Tween speed", "TweenSpeed", 30, 180, 10, "Used only by Tween movement; no collision or anti-cheat changes.")
    self:Dropdown("Settings", "Attack method", "Tool.Activate is the default. VirtualUser is optional and may be blocked by executor permissions.", "AttackMethod", function() return {"Tool.Activate", "VirtualUser (optional)"} end)
    self:Toggle("Settings", "Auto Haki", "Optional Buso request once per task/respawn. No success claim from the RPC return value.", function() return Settings.AutoHaki end, function(v) Settings.AutoHaki = v end)
    self:Toggle("Settings", "Minimize on Start", "The floating button can reopen the window or stop all work.", function() return Settings.MinimizeOnStart end, function(v) Settings.MinimizeOnStart = v end)
    self:Info("Settings", "Luffy image", function()
        return UI.Reopen.Image ~= "" and "Asset ID configured. Display still depends on Roblox asset access/moderation."
            or "Chưa có Roblox Image Asset ID. Ảnh đính kèm nằm trong assets/Luffy_Gear5.png; xem README để cấu hình."
    end, 126)
    self:Action("Settings", "Stop all tasks", "Cancels movement, combat, pending local jobs and item monitoring.", "STOP ALL", function() Hub:StopAll() end)
    self:Action("Settings", "Reset settings", "Stops all work and restores defaults for this session. No file APIs are used.", "Reset", function()
        Hub:StopAll(); for k, v in pairs(Defaults) do Settings[k] = v end; Hub.LastError = nil
    end)
    self:Info("Settings", "Recent messages", function()
        local lines = {}; for i = math.max(1, #Hub.Logs - 5), #Hub.Logs do table.insert(lines, Hub.Logs[i].Message) end
        return #lines > 0 and table.concat(lines, "\n") or "No messages"
    end, 200)
    self:Action("Settings", "Unload Hub", "Stops tasks, disconnects listeners and destroys the UI. Run the file again to reopen.", "Unload", function() Hub:Cleanup() end)
end
function UI:Update(now)
    InventoryController:Step(now)
    self.BindingErrors = self.BindingErrors or {}
    for index, binding in ipairs(self.Bindings) do
        local ok, err = pcall(binding)
        if not ok and self.BindingErrors[index] ~= tostring(err) then
            self.BindingErrors[index] = tostring(err)
            Hub:Log("UI_BINDING_ERROR[" .. index .. "]: " .. tostring(err):sub(1, 120), true)
        elseif ok then self.BindingErrors[index] = nil end
    end
    local status = Manager:Status()
    self.StatusLabel.Text = status.State .. "  |  " .. status.Detail
    self.StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
    for name, tab in pairs(self.Tabs) do tab.BackgroundColor3 = name == self.ActiveTab and Palette.Red or Palette.Sidebar end
    for i = #self.Toasts, 1, -1 do if now >= self.Toasts[i].Expires then self.Toasts[i].Frame:Destroy(); table.remove(self.Toasts, i) end end
    for index, toast in ipairs(self.Toasts) do toast.Frame.Position = UDim2.new(1, -292, 1, -62 - index * 74) end
    self:UpdateCanvases()
end

function Hub:Start(name) return Manager:Start(name or "level") end
function Hub:StopAll()
    Manager:StopAll("Stopped by user"); Observer:Cleanup(); Jobs:CancelAll()
    if QuestDatabase.Status == "LOADING" then QuestDatabase.Status, QuestDatabase.Error = "NOT_LOADED", nil end
    self:RefreshUI()
end
function Hub:GetStatus() return Manager:Status() end
function Hub:Cleanup()
    if self.Destroyed then return end
    self.Destroyed = true
    Manager:StopAll("Hub unloaded"); Observer:Cleanup(); Jobs:CancelAll(); InventoryController:Cleanup()
    for _, connection in ipairs(self.Connections) do pcall(function() connection:Disconnect() end) end
    self.Connections = {}
    if Screen and Screen.Parent then Screen:Destroy() end
    UI.Bindings, UI.Pages, UI.Tabs, UI.Cards, UI.Toasts, UI.Dropdowns, UI.Toggles, UI.Canvases = {}, {}, {}, {}, {}, {}, {}, {}
    UI.Drag, UI.SliderDrag, UI.Host = nil, nil, nil
end

local built, buildError = pcall(function() UI:Build(); UI:Populate(); UI:Update(os.clock()) end)
if not built then
    warn("CRIMSON UI initialization failed: " .. tostring(buildError))
    Hub:Cleanup(); return
end
Hub.UI = UI
InventoryController:Bind()
Hub:Connect(Player.ChildAdded, function(object) if object:IsA("Backpack") then InventoryController:Bind() end end)
Hub:Connect(Player.ChildRemoved, function(object) if object:IsA("Backpack") then InventoryController:Bind() end end)
Hub:Connect(Player.CharacterAdded, function()
    InventoryController:Bind()
    Jobs:Cancel("action"); MovementController:Stop(); CombatController:Stop()
    for _, job in pairs(Manager.Tasks) do if job:IsRunning() then job:Respawn() end end
end)
local lastTick, lastUI = 0, 0
Hub:Connect(Services.RunService.Heartbeat, function()
    if not Hub:IsAlive() then Hub:Cleanup(); return end
    local now = os.clock()
    if now - lastTick < 0.15 then return end
    lastTick = now
    local ok, err = pcall(function() Jobs:Step(now) end)
    if not ok then Hub:StopAll(); Hub:Log("ASYNC_SCHEDULER_ERROR: " .. tostring(err):sub(1, 140), true) end
    local demanded = Manager.Active and Manager.Active:IsRunning() and (Manager.Name == "fruit" or Manager.Name == "chest")
    local observerOK, observerError = pcall(function() Observer:Step(now, demanded == true) end)
    if not observerOK then
        Observer:Cleanup()
        if demanded then Manager.Active:Fail("OBSERVER_ERROR: " .. tostring(observerError))
        elseif not Observer.ReportedError then Observer.ReportedError = true; Hub:Log("OBSERVER_ERROR: " .. tostring(observerError), true) end
    end
    Manager:Step(now)
    -- UI exceptions are isolated from movement/combat and never stop Auto Level.
    if now - lastUI >= 0.3 then lastUI = now; Hub:RefreshUI() end
end)
Hub:Debug("Version", Hub.Version)
Hub:Log("Crimson Hub v1.1 ready. Select Melee / Sword; live game validation is pending.")
return Hub

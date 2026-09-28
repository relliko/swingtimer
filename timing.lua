--[[
* swingtimer - timing
* When your next melee round is due.
*
* The server swings one weapon delay after the last round, checking every 400 ms and carrying
* the leftover, and your first round comes 2 s after you engage (CAttackState, Phoenix/LSB).
* Weapon skills, spells and abilities pause its round timer. The delay starts from your weapons
* (dual wield and martial arts by job level) and is then learned from the rounds you actually
* swing, which picks up haste and gear by itself.
--]]

local timing = {
    learned = { },   -- [weapon set] = ms between rounds (the settings table, so it's saved)
    dirty   = false, -- learned changed since the last save
    last    = nil,   -- when the last round landed, or when you engaged
    first   = false, -- waiting for the first round of a fight
    clean   = false, -- nothing else of yours happened since `last`
    samples = { },   -- recent clean intervals (ms) for `set`
    set     = nil,
    long    = nil,   -- an interval too long to trust yet (a second like it confirms a slowdown)
};

local FIRST_MS = 2000; -- the round timer when you engage
local TICK_MS  = 400;  -- the server checks the round timer this often
local SAMPLES  = 6;

-- Traits by job and level (Phoenix sql/traits.sql, era rows): the highest the level reaches.
local NIN, MNK, PUP = 13, 2, 18;
local DUAL_WIELD = { { 65, 30 }, { 45, 25 }, { 25, 15 }, { 10, 10 } };  -- NIN: % less delay
local MARTIAL_ARTS = {                                                     -- delay taken off
    [MNK] = { { 75, 180 }, { 61, 160 }, { 46, 140 }, { 31, 120 }, { 16, 100 }, { 1, 80 } },
    [PUP] = { { 75, 120 }, { 50, 100 }, { 25, 80 } },
};

local function by_level(t, level)
    for _, row in ipairs(t) do
        if (level >= row[1]) then
            return row[2];
        end
    end
    return 0;
end

-- A trait's value from your main job or your sub job at its level, whichever is higher.
local function trait(fn)
    local p = AshitaCore:GetMemoryManager():GetPlayer();
    return math.max(fn(p:GetMainJob(), p:GetMainJobLevel()), fn(p:GetSubJob(), p:GetSubJobLevel()));
end

-- The item in an equipment slot (0 main, 1 sub): its id and resource, or nil.
local function equipped(slot)
    local inv = AshitaCore:GetMemoryManager():GetInventory();
    local e = inv:GetEquippedItem(slot);
    local index = e ~= nil and bit.band(e.Index or 0, 0xFF) or 0;
    if (index == 0) then
        return nil;
    end
    local item = inv:GetContainerItem(bit.rshift(bit.band(e.Index, 0xFF00), 8), index);
    if (item == nil or item.Count == 0 or item.Id == 0) then
        return nil;
    end
    return item.Id, AshitaCore:GetResourceManager():GetItemById(item.Id);
end

-- The weapon set: learned speeds are kept per main and sub item.
function timing.key()
    return ('%d:%d'):fmt(equipped(0) or 0, equipped(1) or 0);
end

--[[
* Your delay in ms before haste: the main weapon's (hand-to-hand less martial arts; empty hands
* 480), or with a weapon in the sub slot both weapons' less dual wield.
--]]
function timing.base_ms()
    local _, main = equipped(0);
    local _, sub = equipped(1);
    local delay, h2h = 480, true;
    if (main ~= nil) then
        delay, h2h = main.Delay or 0, main.Skill == 1;
        if (h2h and delay < 480) then
            delay = delay + 480; -- the server keeps hand-to-hand delay with 480 added
        end
    end
    if (h2h) then
        delay = delay - trait(function (job, level) return MARTIAL_ARTS[job] and by_level(MARTIAL_ARTS[job], level) or 0; end);
    elseif (sub ~= nil and (sub.Damage or 0) > 0 and (sub.Delay or 0) > 0 and (sub.Skill or 0) >= 1 and sub.Skill <= 12) then
        local dw = trait(function (job, level) return job == NIN and by_level(DUAL_WIELD, level) or 0; end);
        delay = (delay + sub.Delay) * (1 - dw / 100);
    end
    return delay * 1000 / 60;
end

-- The time between rounds for your weapons now: learned, or from the weapons.
function timing.estimate()
    return timing.learned[timing.key()] or timing.base_ms();
end

local function mean(s)
    local sum = 0;
    for _, v in ipairs(s) do
        sum = sum + v;
    end
    return sum / #s;
end

local function near(a, b)
    return math.abs(a - b) <= math.max(TICK_MS, b * 0.2);
end

local function remember(set, s)
    local v = math.floor(mean(s) + 0.5);
    if (timing.learned[set] ~= v) then
        timing.learned[set] = v;
        timing.dirty = true;
    end
end

--[[
* A clean interval between two rounds. One far from the recent ones means your speed changed
* (haste on or off) and starts over from it; one much longer than expected is left out (out of
* range, or a pause), unless the next one agrees with it.
--]]
local function learn(set, ms)
    local s = timing.samples;
    if (ms > timing.estimate() * 1.5 + TICK_MS) then
        if (timing.long ~= nil and near(ms, timing.long)) then
            timing.samples, timing.long = { timing.long, ms }, nil;
            remember(set, timing.samples);
        else
            timing.long = ms;
        end
        return;
    end
    timing.long = nil;
    if (#s > 0 and not near(ms, mean(s))) then
        s = { };
        timing.samples = s;
    end
    s[#s + 1] = ms;
    if (#s > SAMPLES) then
        table.remove(s, 1);
    end
    remember(set, s);
end

-- You engaged at time t (seconds): the first round is due 2 s later.
function timing.on_engage(t)
    timing.last, timing.first, timing.clean = t, true, false;
end

function timing.on_disengage()
    timing.last, timing.first = nil, false;
end

-- Something of yours that isn't a melee round (a weapon skill, spell, ability, item, shot).
function timing.on_action()
    timing.clean = false;
end

-- One of your melee rounds landed at time t.
function timing.on_round(t)
    local set = timing.key();
    if (timing.set ~= set) then
        -- New weapons: the interval since the last round was partly the old ones'.
        timing.set, timing.samples, timing.long, timing.clean = set, { }, nil, false;
    end
    if (timing.last ~= nil and not timing.first and timing.clean) then
        learn(set, (t - timing.last) * 1000);
    end
    timing.last, timing.first, timing.clean = t, false, true;
end

--[[
* The wait for the next round at time t: (ms left, ms in all), or nil when not timing.
--]]
function timing.due(t)
    if (timing.last == nil) then
        return nil;
    end
    local total = timing.first and FIRST_MS or timing.estimate();
    return math.max(0, total - (t - timing.last) * 1000), total;
end

return timing;

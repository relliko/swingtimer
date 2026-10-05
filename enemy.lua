--[[
* swingtimer - enemy
* When the mob you're fighting swings its next melee round.
*
* Mobs swing on the same round timer as you (CAttackState, Phoenix/LSB), one weapon delay apart;
* most mobs' delay is 240 (4 s, mob_pools.cmbDelay). The real time between its rounds is learned
* as it swings, the same way as yours, and remembered per mob name, so slow and haste are picked
* up by themselves. Its bar shows once it has swung at least once.
--]]

local timing = require('timing');

local enemy = {
    learned = { },   -- [mob name] = ms between rounds (the settings table, so it's saved)
    dirty   = false, -- learned changed since the last save
    id      = nil,   -- the mob's server id
    name    = nil,
    last    = nil,   -- when its last round landed
    clean   = false, -- it did nothing else since `last`
    samples = { },   -- recent clean intervals (ms)
    long    = nil,   -- an interval too long to trust yet
};

local DEFAULT_MS = 4000;

-- The mob's entity index, or nil when it isn't nearby.
local function index_of(id)
    local i = bit.band(id, 0xFFF);
    if (i < 0x900 and AshitaCore:GetMemoryManager():GetEntity():GetServerId(i) == id) then
        return i;
    end
    return nil;
end

-- True for a server id that is a mob (or a pet or NPC), not a player.
function enemy.is_mob(id)
    return id ~= nil and id >= 0x1000000;
end

-- The time between its rounds: learned, or the usual mob delay.
function enemy.estimate()
    return enemy.name ~= nil and enemy.learned[enemy.name] or DEFAULT_MS;
end

-- Fight this mob (a server id), or nobody (nil). The same mob keeps its timing.
function enemy.set(id)
    if (id == enemy.id) then
        return;
    end
    local i = id ~= nil and index_of(id) or nil;
    enemy.id, enemy.name = id, i ~= nil and AshitaCore:GetMemoryManager():GetEntity():GetName(i) or nil;
    enemy.last, enemy.clean, enemy.samples, enemy.long = nil, false, { }, nil;
end

-- True while the mob is nearby and alive.
function enemy.alive()
    local i = enemy.id ~= nil and index_of(enemy.id) or nil;
    if (i == nil) then
        return false;
    end
    local ent = AshitaCore:GetMemoryManager():GetEntity();
    local status = ent:GetStatus(i);
    return ent:GetHPPercent(i) > 0 and status ~= 2 and status ~= 3;
end

-- Something of the mob's that isn't a melee round (a TP move, a spell).
function enemy.on_action()
    enemy.clean = false;
end

-- One of the mob's melee rounds landed at time t.
function enemy.on_round(t)
    if (enemy.last ~= nil and enemy.clean) then
        local name = enemy.name;
        timing.learn(enemy, (t - enemy.last) * 1000, enemy.estimate(), function (v)
            v = math.floor(v + 0.5);
            if (name ~= nil and enemy.learned[name] ~= v) then
                enemy.learned[name] = v;
                enemy.dirty = true;
            end
        end);
    end
    enemy.last, enemy.clean = t, true;
end

--[[
* The wait for the mob's next round at time t: (ms left, ms in all), or nil before it has swung.
--]]
function enemy.due(t)
    if (enemy.last == nil) then
        return nil;
    end
    local total = enemy.estimate();
    return math.max(0, total - (t - enemy.last) * 1000), total;
end

return enemy;

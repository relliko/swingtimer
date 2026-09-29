--[[
* swingtimer
*
* A slim bar that fills up until your next melee round, with the seconds left beside it. It's
* only there while you're engaged, and it never takes a click from the game (/swing move to
* place it).
*
* The time between rounds starts from your weapons' delay and is learned from the rounds you
* actually swing, so haste and gear are picked up by themselves; it's remembered per weapon set.
*
* Nothing is ever sent to the server: swingtimer only reads client memory and incoming packets.
--]]

addon.name    = 'swingtimer';
addon.author  = 'Relli';
addon.version = '0.1.1';
addon.desc    = 'A slim bar that fills up until your next melee round.';
addon.link    = '';

require('common');
local chat     = require('chat');
local imgui    = require('imgui');
local settings = require('settings');
local timing   = require('timing');

local defaults = T{
    visible = true,
    x       = -1,     -- where the bar sits (-1: below the middle of the screen, set on first draw)
    y       = -1,
    width   = 140,
    height  = 3,
    text    = true,   -- the seconds left beside the bar
    learned = T{ },   -- [weapon set] = ms between rounds (timing.lua)
};

local st = {
    settings  = nil,
    engaged   = false,
    placing   = false, -- /swing move: shown and draggable
    moved     = false, -- dragged; save once the mouse is let go
    reset     = false, -- put the bar at its spot next frame
    fade_from = nil,   -- when you disengaged
    fill      = 0,     -- the bar's last fill, kept while it fades out
    last_save = 0,
    seen      = { },   -- packets already read (the same packet can arrive twice)
    order     = { },
};

local FADE       = 0.5;  -- seconds the bar takes to fade after you disengage
local SAVE_EVERY = 30;
local TRACK      = 0x59000000; -- ImGui colors, 0xAABBGGRR
local FILL       = 0xC8D2E8F0;
local OUTLINE    = 0x5AFFFFFF;
local TEXT       = 0xD9D9E6EB;
local TEXT_SCALE = 0.8;  -- the countdown, against the font size

local function msg(text)
    print(chat.header(addon.name):append(chat.message(text)));
end

local function err(text)
    print(chat.header(addon.name):append(chat.error(text)));
end

local function save()
    settings.save();
    timing.dirty, st.last_save = false, os.clock();
end

local function me()
    local party = AshitaCore:GetMemoryManager():GetParty();
    return party:GetMemberServerId(0), party:GetMemberTargetIndex(0);
end

local function engaged_now()
    local _, index = me();
    return index ~= nil and index ~= 0 and AshitaCore:GetMemoryManager():GetEntity():GetStatus(index) == 1;
end

--[[
* The bar, when there's something to show: filling toward your next round while you're engaged,
* fading after you disengage, and a sample while you place it.
--]]
local function draw(t)
    local s = st.settings;
    if (s == nil or not s.visible) then
        return;
    end
    local fill, left, alpha = nil, nil, 1;
    if (st.placing) then
        fill = 0.6;
    elseif (st.engaged) then
        local l, total = timing.due(t);
        if (l == nil) then
            return;
        end
        fill, left = 1 - l / total, l;
        st.fill = fill;
    elseif (st.fade_from ~= nil and t - st.fade_from < FADE) then
        fill, alpha = st.fill, 1 - (t - st.fade_from) / FADE;
    else
        return;
    end

    if (s.x < 0 or s.y < 0) then
        local size = imgui.GetIO().DisplaySize;
        s.x, s.y, st.reset = math.floor(size.x / 2 - s.width / 2), math.floor(size.y * 0.62), true;
    end
    imgui.SetNextWindowPos({ s.x, s.y }, st.reset and ImGuiCond_Always or ImGuiCond_FirstUseEver);
    st.reset = false;
    imgui.PushStyleVar(ImGuiStyleVar_Alpha, alpha);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 4, 4 });
    imgui.PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0);
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 6, 0 });
    local flags = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoBackground, ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoCollapse);
    if (not st.placing) then
        flags = bit.bor(flags, ImGuiWindowFlags_NoInputs); -- clicks go to the game
    end
    if (imgui.Begin('swingtimer', { true }, flags)) then
        local w, h = s.width, s.height;
        local row = s.text and math.max(h, imgui.GetFontSize() * TEXT_SCALE) or h;
        local x, y = imgui.GetCursorScreenPos();
        local top = y + (row - h) / 2;
        imgui.Dummy({ w, row });
        local dl = imgui.GetWindowDrawList();
        dl:AddRectFilled({ x, top }, { x + w, top + h }, TRACK);
        if (fill > 0) then
            dl:AddRectFilled({ x, top }, { x + w * math.min(1, fill), top + h }, FILL);
        end
        if (st.placing) then
            dl:AddRect({ x - 3, top - 3 }, { x + w + 3, top + h + 3 }, OUTLINE);
        end
        if (s.text and left ~= nil and left > 0) then
            -- Drawn at a size: Ashita's ImGui has no SetWindowFontScale.
            local text = ('%.1f'):fmt(left / 1000);
            local size = imgui.GetFontSize() * TEXT_SCALE;
            local tw = imgui.CalcTextSize(text) * TEXT_SCALE;
            imgui.SameLine();
            local tx, ty = imgui.GetCursorScreenPos();
            imgui.Dummy({ tw, row });
            dl:AddText(imgui.GetFont(), size, { tx, ty + (row - size) / 2 }, TEXT, text);
        end
        if (st.placing) then
            local wx, wy = imgui.GetWindowPos();
            if (math.abs(wx - s.x) > 0.5 or math.abs(wy - s.y) > 0.5) then
                s.x, s.y, st.moved = wx, wy, true;
            end
        end
    end
    imgui.End();
    imgui.PopStyleVar(4);

    -- Save a new spot once you let go of it.
    if (st.moved and not imgui.IsMouseDown(ImGuiMouseButton_Left)) then
        st.moved = false;
        save();
    end
end

local function help()
    msg('/swing (or /swingtimer) on|off   show the swing timer while you\'re engaged');
    msg('/swing move   show it so you can drag it into place; /swing move again when done');
    msg(('/swing size <width> <height>   in pixels (now %d x %d)'):fmt(st.settings.width, st.settings.height));
    msg('/swing text on|off   the seconds left beside the bar');
    msg('/swing reset   put it back below the middle of the screen');
    msg('/swing forget   forget the swing speeds it has learned');
    msg('/swing debug   your weapon set, its delay and what has been learned');
end

--[[
* True the second time the same packet is seen (the last 50 are kept).
--]]
local function repeated(data)
    if (st.seen[data]) then
        return true;
    end
    st.seen[data] = true;
    st.order[#st.order + 1] = data;
    if (#st.order > 50) then
        st.seen[table.remove(st.order, 1)] = nil;
    end
    return false;
end

ashita.events.register('load', 'swingtimer_load', function ()
    st.settings = settings.load(defaults);
    timing.learned = st.settings.learned;
end);

settings.register('settings', 'swingtimer_settings_update', function (s)
    if (s ~= nil) then
        st.settings, st.reset = s, true;
        timing.learned = s.learned;
    end
end);

ashita.events.register('unload', 'swingtimer_unload', function ()
    save();
end);

ashita.events.register('command', 'swingtimer_command', function (e)
    local args = e.command:args();
    if (#args == 0 or (args[1]:lower() ~= '/swing' and args[1]:lower() ~= '/swingtimer')) then
        return;
    end
    e.blocked = true;
    local s = st.settings;
    local what, a, b = (args[2] or ''):lower(), args[3], args[4];
    if (what == 'on' or what == 'off') then
        s.visible = what == 'on';
        save();
        msg(('Swing timer %s.'):fmt(s.visible and 'on' or 'off'));
    elseif (what == 'move') then
        st.placing = not st.placing;
        msg(st.placing and 'Drag the bar where you want it, then /swing move again.' or 'Placed.');
    elseif (what == 'size') then
        local w, h = tonumber(a), tonumber(b);
        if (w == nil or h == nil or w < 20 or w > 600 or h < 1 or h > 20) then
            err('Use /swing size <width 20-600> <height 1-20>.');
            return;
        end
        s.width, s.height = math.floor(w), math.floor(h);
        save();
        msg(('Size %d x %d.'):fmt(s.width, s.height));
    elseif (what == 'text') then
        local v = (a or ''):lower();
        if (v ~= 'on' and v ~= 'off') then
            err('Use /swing text on or off.');
            return;
        end
        s.text = v == 'on';
        save();
        msg(('Seconds left %s.'):fmt(s.text and 'shown' or 'hidden'));
    elseif (what == 'reset') then
        s.x, s.y = -1, -1;
        save();
        msg('Moved back below the middle of the screen.');
    elseif (what == 'forget') then
        for k in pairs(s.learned) do
            s.learned[k] = nil;
        end
        timing.samples = { };
        save();
        msg('Forgot the learned swing speeds.');
    elseif (what == 'debug') then
        local set = timing.key();
        local learned = s.learned[set];
        local recent = { };
        for _, v in ipairs(timing.samples) do
            recent[#recent + 1] = ('%d'):fmt(math.floor(v + 0.5));
        end
        msg(('weapon set %s: delay %.0f ms, learned %s, recent rounds %s'):fmt(set, timing.base_ms(),
            learned and ('%d ms'):fmt(learned) or 'nothing yet', #recent > 0 and table.concat(recent, ' ') or 'none'));
    else
        help();
    end
end);

-- Read only: never blocks or changes a packet.
ashita.events.register('packet_in', 'swingtimer_packet_in', function (e)
    if (e.id == 0x00A) then
        st.engaged = false;
        timing.on_disengage();
        if (timing.dirty) then
            save();
        end
        return;
    end
    if (e.id ~= 0x028 or repeated(e.data)) then
        return;
    end
    local id = me();
    if (id == nil or id == 0 or ashita.bits.unpack_be(e.data_raw, 0, 40, 32) ~= id) then
        return;
    end
    if (ashita.bits.unpack_be(e.data_raw, 0, 82, 4) == 1) then
        timing.on_round(os.clock());
    else
        timing.on_action();
    end
end);

ashita.events.register('d3d_present', 'swingtimer_present', function ()
    local t = os.clock();
    local now = engaged_now();
    if (now and not st.engaged) then
        timing.on_engage(t);
        st.fade_from = nil;
    elseif (not now and st.engaged) then
        timing.on_disengage();
        st.fade_from = t;
    end
    st.engaged = now;
    draw(t);
    if (timing.dirty and t - st.last_save > SAVE_EVERY) then
        save();
    end
end);

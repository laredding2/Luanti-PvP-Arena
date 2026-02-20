-- ============================================================================
-- PVP ARENA MOD for Minetest
-- Features: Arena zones, teams, guns, scoreboards, health display, respawning
-- ============================================================================

pvp_arena = {}

-- =========================
-- CONFIGURATION
-- =========================
pvp_arena.config = {
    -- Arena boundaries (set via in-game commands)
    arena_pos1 = nil,
    arena_pos2 = nil,

    -- Gameplay
    match_duration    = 300,   -- seconds (5 minutes)
    respawn_delay     = 3,     -- seconds
    max_score         = 25,    -- kills to win
    starting_hp       = 20,    -- default max HP
    friendly_fire     = false,

    -- Teams
    teams = {
        red  = { color = "#FF4444", name = "Red Team",  spawn = nil },
        blue = { color = "#4444FF", name = "Blue Team", spawn = nil },
    },
}

-- =========================
-- STATE
-- =========================
pvp_arena.state = {
    active        = false,
    players       = {},     -- { [name] = { team, kills, deaths, hud_ids } }
    scores        = { red = 0, blue = 0 },
    match_timer   = 0,
    scoreboard_hud = {},
}

local S = pvp_arena.state
local C = pvp_arena.config

-- =========================
-- STORAGE (persistent scores)
-- =========================
local storage = minetest.get_mod_storage()

local function save_arena()
    if C.arena_pos1 then
        storage:set_string("arena_pos1", minetest.pos_to_string(C.arena_pos1))
    end
    if C.arena_pos2 then
        storage:set_string("arena_pos2", minetest.pos_to_string(C.arena_pos2))
    end
    for team, data in pairs(C.teams) do
        if data.spawn then
            storage:set_string("spawn_" .. team, minetest.pos_to_string(data.spawn))
        end
    end
end

local function load_arena()
    local p1 = storage:get_string("arena_pos1")
    local p2 = storage:get_string("arena_pos2")
    if p1 ~= "" then C.arena_pos1 = minetest.string_to_pos(p1) end
    if p2 ~= "" then C.arena_pos2 = minetest.string_to_pos(p2) end
    for team, _ in pairs(C.teams) do
        local sp = storage:get_string("spawn_" .. team)
        if sp ~= "" then C.teams[team].spawn = minetest.string_to_pos(sp) end
    end
end

load_arena()

-- =========================
-- UTILITY FUNCTIONS
-- =========================

local function is_in_arena(pos)
    if not C.arena_pos1 or not C.arena_pos2 then return false end
    local p1, p2 = C.arena_pos1, C.arena_pos2
    return pos.x >= math.min(p1.x, p2.x) and pos.x <= math.max(p1.x, p2.x)
       and pos.y >= math.min(p1.y, p2.y) and pos.y <= math.max(p1.y, p2.y)
       and pos.z >= math.min(p1.z, p2.z) and pos.z <= math.max(p1.z, p2.z)
end

local function broadcast(msg)
    minetest.chat_send_all(minetest.colorize("#FFAA00", "[PvP Arena] ") .. msg)
end

local function team_msg(team, msg)
    for name, pdata in pairs(S.players) do
        if pdata.team == team then
            minetest.chat_send_player(name,
                minetest.colorize(C.teams[team].color, "[Team] ") .. msg)
        end
    end
end

local function get_team_color(team)
    return C.teams[team] and C.teams[team].color or "#FFFFFF"
end

-- =========================
-- HUD SYSTEM
-- =========================

local function remove_player_huds(player)
    local name = player:get_player_name()
    local pdata = S.players[name]
    if not pdata or not pdata.hud_ids then return end
    for _, hud_id in pairs(pdata.hud_ids) do
        player:hud_remove(hud_id)
    end
    pdata.hud_ids = {}
end

local function update_hud(player)
    local name = player:get_player_name()
    local pdata = S.players[name]
    if not pdata then return end

    -- Remove existing HUDs first
    remove_player_huds(player)
    pdata.hud_ids = {}

    if not S.active then return end

    -- === SCOREBOARD HEADER ===
    pdata.hud_ids.header = player:hud_add({
        hud_elem_type = "text",
        position  = { x = 1, y = 0 },
        offset    = { x = -10, y = 10 },
        text      = "=== PVP ARENA ===",
        alignment = { x = -1, y = 1 },
        scale     = { x = 100, y = 100 },
        number    = 0xFFAA00,
        size      = { x = 2 },
    })

    -- === TEAM SCORES ===
    local red_score  = S.scores.red  or 0
    local blue_score = S.scores.blue or 0

    pdata.hud_ids.red_score = player:hud_add({
        hud_elem_type = "text",
        position  = { x = 1, y = 0 },
        offset    = { x = -10, y = 35 },
        text      = "Red: " .. red_score,
        alignment = { x = -1, y = 1 },
        scale     = { x = 100, y = 100 },
        number    = 0xFF4444,
        size      = { x = 2 },
    })

    pdata.hud_ids.blue_score = player:hud_add({
        hud_elem_type = "text",
        position  = { x = 1, y = 0 },
        offset    = { x = -10, y = 55 },
        text      = "Blue: " .. blue_score,
        alignment = { x = -1, y = 1 },
        scale     = { x = 100, y = 100 },
        number    = 0x4444FF,
        size      = { x = 2 },
    })

    -- === TIMER ===
    local time_left = math.max(0, C.match_duration - S.match_timer)
    local mins = math.floor(time_left / 60)
    local secs = time_left % 60

    pdata.hud_ids.timer = player:hud_add({
        hud_elem_type = "text",
        position  = { x = 0.5, y = 0 },
        offset    = { x = 0, y = 10 },
        text      = string.format("Time: %d:%02d", mins, secs),
        alignment = { x = 0, y = 1 },
        scale     = { x = 100, y = 100 },
        number    = 0xFFFFFF,
        size      = { x = 2 },
    })

    -- === PERSONAL STATS ===
    pdata.hud_ids.stats = player:hud_add({
        hud_elem_type = "text",
        position  = { x = 1, y = 0 },
        offset    = { x = -10, y = 85 },
        text      = string.format("K: %d  D: %d  KDR: %.1f",
            pdata.kills, pdata.deaths,
            pdata.deaths > 0 and (pdata.kills / pdata.deaths) or pdata.kills),
        alignment = { x = -1, y = 1 },
        scale     = { x = 100, y = 100 },
        number    = 0xCCCCCC,
        size      = { x = 1 },
    })

    -- === TEAM INDICATOR ===
    local team_name = C.teams[pdata.team] and C.teams[pdata.team].name or "None"
    pdata.hud_ids.team_indicator = player:hud_add({
        hud_elem_type = "text",
        position  = { x = 0, y = 0 },
        offset    = { x = 10, y = 10 },
        text      = "Team: " .. team_name,
        alignment = { x = 1, y = 1 },
        scale     = { x = 100, y = 100 },
        number    = tonumber(get_team_color(pdata.team):sub(2), 16) or 0xFFFFFF,
        size      = { x = 2 },
    })

    -- === CROSSHAIR ===
    pdata.hud_ids.crosshair = player:hud_add({
        hud_elem_type = "text",
        position  = { x = 0.5, y = 0.5 },
        offset    = { x = 0, y = 0 },
        text      = "+",
        alignment = { x = 0, y = 0 },
        scale     = { x = 100, y = 100 },
        number    = 0x00FF00,
        size      = { x = 3 },
    })
end

local function update_all_huds()
    for name, _ in pairs(S.players) do
        local player = minetest.get_player_by_name(name)
        if player then
            update_hud(player)
        end
    end
end

-- =========================
-- WEAPONS / GUNS
-- =========================

-- Particle effect for bullet trail
local function bullet_trail(start_pos, end_pos)
    local dir = vector.direction(start_pos, end_pos)
    local dist = vector.distance(start_pos, end_pos)

    minetest.add_particlespawner({
        amount = math.floor(dist * 2),
        time = 0.1,
        minpos = start_pos,
        maxpos = end_pos,
        minvel = { x = 0, y = 0, z = 0 },
        maxvel = { x = 0, y = 0, z = 0 },
        minexptime = 0.3,
        maxexptime = 0.5,
        minsize = 1,
        maxsize = 1,
        texture = "pvp_arena_bullet_trail.png",
        glow = 14,
    })
end

-- Impact effect
local function impact_effect(pos)
    minetest.add_particlespawner({
        amount = 10,
        time = 0.1,
        minpos = vector.subtract(pos, 0.2),
        maxpos = vector.add(pos, 0.2),
        minvel = { x = -2, y = -2, z = -2 },
        maxvel = { x = 2, y = 2, z = 2 },
        minexptime = 0.2,
        maxexptime = 0.5,
        minsize = 1,
        maxsize = 2,
        texture = "pvp_arena_impact.png",
        glow = 10,
    })
end

-- Raycast-based shooting function
local function shoot_gun(player, damage, range, spread, sound_name)
    local name = player:get_player_name()
    local pdata = S.players[name]
    if not pdata then return end
    if not S.active then
        minetest.chat_send_player(name, "No active match!")
        return
    end

    local pos = vector.add(player:get_pos(), { x = 0, y = 1.5, z = 0 }) -- eye level
    local dir = player:get_look_dir()

    -- Apply spread
    if spread > 0 then
        dir.x = dir.x + (math.random() - 0.5) * spread
        dir.y = dir.y + (math.random() - 0.5) * spread
        dir.z = dir.z + (math.random() - 0.5) * spread
        dir = vector.normalize(dir)
    end

    local end_pos = vector.add(pos, vector.multiply(dir, range))

    -- Play sound
    minetest.sound_play(sound_name, {
        pos = pos,
        gain = 0.8,
        max_hear_distance = 50,
    }, true)

    -- Raycast
    local ray = minetest.raycast(pos, end_pos, true, false)
    for pointed_thing in ray do
        if pointed_thing.type == "object" then
            local obj = pointed_thing.ref
            if obj:is_player() then
                local target_name = obj:get_player_name()
                local target_data = S.players[target_name]

                -- Skip self
                if target_name == name then
                    goto continue
                end

                -- Skip friendly fire
                if not C.friendly_fire and target_data and target_data.team == pdata.team then
                    minetest.chat_send_player(name, minetest.colorize("#FFAA00", "Friendly fire is OFF!"))
                    goto continue
                end

                -- Apply damage
                local hp = obj:get_hp()
                obj:set_hp(hp - damage, { type = "punch", from = "pvp_arena" })

                -- Hit marker feedback
                minetest.chat_send_player(name, minetest.colorize("#FF0000", ">> HIT " .. target_name .. " <<"))

                -- Show damage numbers
                impact_effect(pointed_thing.intersection_point or obj:get_pos())
                bullet_trail(pos, pointed_thing.intersection_point or obj:get_pos())
                return
            elseif pointed_thing.type == "node" then
                -- Bullet hit a wall
                impact_effect(pointed_thing.intersection_point or pointed_thing.under)
                bullet_trail(pos, pointed_thing.intersection_point or minetest.int_to_pos(pointed_thing.under) or end_pos)
                return
            end
        end
        ::continue::
    end

    -- No hit - draw trail to max range
    bullet_trail(pos, end_pos)
end

-- =====================
-- WEAPON: Pistol
-- =====================
minetest.register_tool("pvp_arena:pistol", {
    description = "Pistol\nDamage: 3 | Range: 40 | Semi-auto",
    inventory_image = "pvp_arena_pistol.png",
    wield_scale = { x = 1.5, y = 1.5, z = 1 },
    on_use = function(itemstack, user, pointed_thing)
        shoot_gun(user, 3, 40, 0.02, "pvp_arena_pistol_shot")
        -- Cooldown via wear
        itemstack:add_wear(200)
        minetest.after(0.4, function()
            local player = minetest.get_player_by_name(user:get_player_name())
            if player then
                local inv = player:get_inventory()
                local list = inv:get_list("main")
                for i, stack in ipairs(list) do
                    if stack:get_name() == "pvp_arena:pistol" then
                        stack:set_wear(0)
                        inv:set_stack("main", i, stack)
                        break
                    end
                end
            end
        end)
        return itemstack
    end,
    on_secondary_use = function(itemstack, user, pointed_thing)
        -- Aim / zoom (toggle)
        local name = user:get_player_name()
        local fov = user:get_fov()
        if fov == 0 or fov == nil then
            user:set_fov(60, false, 0.2)
        else
            user:set_fov(0, false, 0.2)
        end
    end,
})

-- =====================
-- WEAPON: Rifle
-- =====================
minetest.register_tool("pvp_arena:rifle", {
    description = "Assault Rifle\nDamage: 4 | Range: 60 | Burst",
    inventory_image = "pvp_arena_rifle.png",
    wield_scale = { x = 2, y = 1.5, z = 1 },
    on_use = function(itemstack, user, pointed_thing)
        -- 3-round burst
        local name = user:get_player_name()
        for i = 0, 2 do
            minetest.after(i * 0.1, function()
                local player = minetest.get_player_by_name(name)
                if player then
                    shoot_gun(player, 4, 60, 0.03 + (i * 0.01), "pvp_arena_rifle_shot")
                end
            end)
        end
        itemstack:add_wear(400)
        minetest.after(0.6, function()
            local player = minetest.get_player_by_name(name)
            if player then
                local inv = player:get_inventory()
                local list = inv:get_list("main")
                for idx, stack in ipairs(list) do
                    if stack:get_name() == "pvp_arena:rifle" then
                        stack:set_wear(0)
                        inv:set_stack("main", idx, stack)
                        break
                    end
                end
            end
        end)
        return itemstack
    end,
    on_secondary_use = function(itemstack, user, pointed_thing)
        local fov = user:get_fov()
        if fov == 0 or fov == nil then
            user:set_fov(40, false, 0.2)
        else
            user:set_fov(0, false, 0.2)
        end
    end,
})

-- =====================
-- WEAPON: Shotgun
-- =====================
minetest.register_tool("pvp_arena:shotgun", {
    description = "Shotgun\nDamage: 2x8 pellets | Range: 15 | Pump",
    inventory_image = "pvp_arena_shotgun.png",
    wield_scale = { x = 2, y = 1.5, z = 1 },
    on_use = function(itemstack, user, pointed_thing)
        -- 8 pellets with high spread
        for i = 1, 8 do
            shoot_gun(user, 2, 15, 0.15, "pvp_arena_shotgun_shot")
        end
        itemstack:add_wear(600)
        minetest.after(1.0, function()
            local player = minetest.get_player_by_name(user:get_player_name())
            if player then
                local inv = player:get_inventory()
                local list = inv:get_list("main")
                for idx, stack in ipairs(list) do
                    if stack:get_name() == "pvp_arena:shotgun" then
                        stack:set_wear(0)
                        inv:set_stack("main", idx, stack)
                        break
                    end
                end
            end
        end)
        return itemstack
    end,
})

-- =====================
-- WEAPON: Sniper Rifle
-- =====================
minetest.register_tool("pvp_arena:sniper", {
    description = "Sniper Rifle\nDamage: 14 | Range: 100 | Bolt-action",
    inventory_image = "pvp_arena_sniper.png",
    wield_scale = { x = 2.5, y = 1.5, z = 1 },
    on_use = function(itemstack, user, pointed_thing)
        shoot_gun(user, 14, 100, 0.005, "pvp_arena_sniper_shot")
        itemstack:add_wear(800)
        minetest.after(2.0, function()
            local player = minetest.get_player_by_name(user:get_player_name())
            if player then
                local inv = player:get_inventory()
                local list = inv:get_list("main")
                for idx, stack in ipairs(list) do
                    if stack:get_name() == "pvp_arena:sniper" then
                        stack:set_wear(0)
                        inv:set_stack("main", idx, stack)
                        break
                    end
                end
            end
        end)
        return itemstack
    end,
    on_secondary_use = function(itemstack, user, pointed_thing)
        local fov = user:get_fov()
        if fov == 0 or fov == nil then
            user:set_fov(20, false, 0.2)
        else
            user:set_fov(0, false, 0.2)
        end
    end,
})

-- =====================
-- WEAPON: Rocket Launcher (area damage)
-- =====================
minetest.register_tool("pvp_arena:rocket_launcher", {
    description = "Rocket Launcher\nDamage: 10 (AoE) | Range: 50 | Slow",
    inventory_image = "pvp_arena_rocket.png",
    wield_scale = { x = 2.5, y = 2, z = 1 },
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        local pdata = S.players[name]
        if not pdata or not S.active then return end

        local pos = vector.add(user:get_pos(), { x = 0, y = 1.5, z = 0 })
        local dir = user:get_look_dir()
        local end_pos = vector.add(pos, vector.multiply(dir, 50))

        minetest.sound_play("pvp_arena_rocket_shot", {
            pos = pos, gain = 1.0, max_hear_distance = 60,
        }, true)

        -- Raycast to find impact point
        local impact_pos = end_pos
        local ray = minetest.raycast(pos, end_pos, true, false)
        for pointed in ray do
            if pointed.type == "object" then
                local obj = pointed.ref
                if obj:is_player() and obj:get_player_name() ~= name then
                    impact_pos = pointed.intersection_point or obj:get_pos()
                    break
                end
            elseif pointed.type == "node" then
                impact_pos = pointed.intersection_point or pointed.above
                break
            end
        end

        -- Explosion effect
        minetest.add_particlespawner({
            amount = 30,
            time = 0.2,
            minpos = vector.subtract(impact_pos, 1),
            maxpos = vector.add(impact_pos, 1),
            minvel = { x = -5, y = -5, z = -5 },
            maxvel = { x = 5, y = 5, z = 5 },
            minexptime = 0.5,
            maxexptime = 1.5,
            minsize = 3,
            maxsize = 6,
            texture = "pvp_arena_explosion.png",
            glow = 14,
        })

        minetest.sound_play("pvp_arena_explosion", {
            pos = impact_pos, gain = 1.2, max_hear_distance = 80,
        }, true)

        -- Area damage (radius 4)
        local nearby = minetest.get_objects_inside_radius(impact_pos, 4)
        for _, obj in ipairs(nearby) do
            if obj:is_player() then
                local tname = obj:get_player_name()
                local tdata = S.players[tname]
                if tname ~= name and (C.friendly_fire or not tdata or tdata.team ~= pdata.team) then
                    local dist = vector.distance(impact_pos, obj:get_pos())
                    local dmg = math.floor(10 * (1 - dist / 4))
                    if dmg > 0 then
                        obj:set_hp(obj:get_hp() - dmg, { type = "punch", from = "pvp_arena" })
                        minetest.chat_send_player(name,
                            minetest.colorize("#FF0000", ">> SPLASH HIT " .. tname .. " for " .. dmg .. " <<"))
                    end
                end
            end
        end

        bullet_trail(pos, impact_pos)

        itemstack:add_wear(1200)
        minetest.after(3.0, function()
            local player = minetest.get_player_by_name(name)
            if player then
                local inv = player:get_inventory()
                local list = inv:get_list("main")
                for idx, stack in ipairs(list) do
                    if stack:get_name() == "pvp_arena:rocket_launcher" then
                        stack:set_wear(0)
                        inv:set_stack("main", idx, stack)
                        break
                    end
                end
            end
        end)
        return itemstack
    end,
})

-- =====================
-- WEAPON: Grenade (throwable)
-- =====================
minetest.register_craftitem("pvp_arena:grenade", {
    description = "Frag Grenade\nThrow to deal AoE damage (3s fuse)",
    inventory_image = "pvp_arena_grenade.png",
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        local pdata = S.players[name]
        if not pdata or not S.active then return end

        local pos = vector.add(user:get_pos(), { x = 0, y = 1.5, z = 0 })
        local dir = user:get_look_dir()
        local vel = vector.multiply(dir, 15)
        vel.y = vel.y + 4

        -- Spawn grenade entity
        local obj = minetest.add_entity(pos, "pvp_arena:grenade_entity")
        if obj then
            obj:set_velocity(vel)
            obj:set_acceleration({ x = 0, y = -9.81, z = 0 })
            local ent = obj:get_luaentity()
            ent._thrower = name
            ent._team = pdata.team
            ent._timer = 0
        end

        itemstack:take_item()
        return itemstack
    end,
})

minetest.register_entity("pvp_arena:grenade_entity", {
    initial_properties = {
        physical = true,
        collide_with_objects = true,
        collisionbox = { -0.15, -0.15, -0.15, 0.15, 0.15, 0.15 },
        visual = "sprite",
        visual_size = { x = 0.5, y = 0.5 },
        textures = { "pvp_arena_grenade.png" },
        glow = 5,
    },
    _thrower = "",
    _team = "",
    _timer = 0,

    on_step = function(self, dtime)
        self._timer = self._timer + dtime
        if self._timer >= 3 then
            local pos = self.object:get_pos()

            -- Explosion
            minetest.add_particlespawner({
                amount = 25,
                time = 0.2,
                minpos = vector.subtract(pos, 1),
                maxpos = vector.add(pos, 1),
                minvel = { x = -4, y = -4, z = -4 },
                maxvel = { x = 4, y = 8, z = 4 },
                minexptime = 0.5,
                maxexptime = 1.5,
                minsize = 2,
                maxsize = 5,
                texture = "pvp_arena_explosion.png",
                glow = 14,
            })

            minetest.sound_play("pvp_arena_explosion", {
                pos = pos, gain = 1.0, max_hear_distance = 60,
            }, true)

            -- AoE damage
            local nearby = minetest.get_objects_inside_radius(pos, 5)
            for _, obj in ipairs(nearby) do
                if obj:is_player() then
                    local tname = obj:get_player_name()
                    local tdata = S.players[tname]
                    if tname ~= self._thrower and
                       (C.friendly_fire or not tdata or tdata.team ~= self._team) then
                        local dist = vector.distance(pos, obj:get_pos())
                        local dmg = math.floor(8 * (1 - dist / 5))
                        if dmg > 0 then
                            obj:set_hp(obj:get_hp() - dmg, { type = "punch", from = "pvp_arena" })
                        end
                    end
                end
            end

            self.object:remove()
        end
    end,
})

-- =========================
-- LOADOUT SYSTEM
-- =========================

local function give_loadout(player)
    local inv = player:get_inventory()
    inv:set_list("main", {})
    inv:add_item("main", "pvp_arena:rifle")
    inv:add_item("main", "pvp_arena:pistol")
    inv:add_item("main", "pvp_arena:grenade 3")
end

-- =========================
-- KILL / DEATH TRACKING
-- =========================

local last_damager = {}

minetest.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_caps, dir, damage)
    if not S.active then return end
    if hitter and hitter:is_player() then
        last_damager[player:get_player_name()] = hitter:get_player_name()
    end
end)

minetest.register_on_dieplayer(function(player, reason)
    if not S.active then return end

    local victim = player:get_player_name()
    local vdata = S.players[victim]
    if not vdata then return end

    vdata.deaths = vdata.deaths + 1

    -- Determine killer
    local killer_name = last_damager[victim]
    last_damager[victim] = nil

    if killer_name then
        local kdata = S.players[killer_name]
        if kdata then
            kdata.kills = kdata.kills + 1
            S.scores[kdata.team] = (S.scores[kdata.team] or 0) + 1

            -- Kill feed
            broadcast(
                minetest.colorize(get_team_color(kdata.team), killer_name) ..
                " killed " ..
                minetest.colorize(get_team_color(vdata.team), victim)
            )

            -- Check win condition
            if S.scores[kdata.team] >= C.max_score then
                pvp_arena.end_match(kdata.team)
                return
            end
        end
    else
        broadcast(minetest.colorize(get_team_color(vdata.team), victim) .. " died")
    end

    update_all_huds()

    -- Respawn after delay
    minetest.after(C.respawn_delay, function()
        local p = minetest.get_player_by_name(victim)
        if p and S.active and S.players[victim] then
            pvp_arena.respawn_player(p)
        end
    end)
end)

-- =========================
-- RESPAWN
-- =========================

function pvp_arena.respawn_player(player)
    local name = player:get_player_name()
    local pdata = S.players[name]
    if not pdata then return end

    local spawn = C.teams[pdata.team] and C.teams[pdata.team].spawn
    if spawn then
        player:set_pos(spawn)
    end

    player:set_hp(C.starting_hp)
    give_loadout(player)
    player:set_fov(0) -- reset zoom
end

minetest.register_on_respawnplayer(function(player)
    if S.active and S.players[player:get_player_name()] then
        pvp_arena.respawn_player(player)
        return true -- override default respawn
    end
end)

-- =========================
-- MATCH MANAGEMENT
-- =========================

function pvp_arena.start_match()
    if S.active then
        broadcast("A match is already in progress!")
        return
    end

    if not C.arena_pos1 or not C.arena_pos2 then
        broadcast("Arena boundaries not set! Use /arena_set pos1/pos2")
        return
    end

    S.active = true
    S.scores = { red = 0, blue = 0 }
    S.match_timer = 0

    -- Auto-assign connected arena players to teams
    local all_players = minetest.get_connected_players()
    local team_toggle = true
    for _, player in ipairs(all_players) do
        local name = player:get_player_name()
        local team = team_toggle and "red" or "blue"
        team_toggle = not team_toggle

        S.players[name] = {
            team   = team,
            kills  = 0,
            deaths = 0,
            hud_ids = {},
        }

        -- Set nametag color
        player:set_nametag_attributes({
            color = get_team_color(team),
        })

        -- Setup player
        player:set_hp(C.starting_hp)
        player:set_properties({ hp_max = C.starting_hp })
        give_loadout(player)

        -- Teleport to spawn
        local spawn = C.teams[team].spawn
        if spawn then
            player:set_pos(spawn)
        end

        minetest.chat_send_player(name,
            minetest.colorize("#FFAA00", "You are on ") ..
            minetest.colorize(get_team_color(team), C.teams[team].name))
    end

    broadcast("MATCH STARTED! First to " .. C.max_score .. " kills wins!")
    update_all_huds()
end

function pvp_arena.end_match(winning_team)
    if not S.active then return end

    S.active = false

    -- Announce winner
    if winning_team then
        broadcast(minetest.colorize(get_team_color(winning_team),
            C.teams[winning_team].name .. " WINS!"))
    else
        broadcast("Match ended - DRAW!")
    end

    -- Show final scoreboard
    broadcast("=== FINAL SCORES ===")
    broadcast(minetest.colorize("#FF4444", "Red: " .. S.scores.red) .. "  |  " ..
              minetest.colorize("#4444FF", "Blue: " .. S.scores.blue))

    -- Show top players
    local sorted = {}
    for name, pdata in pairs(S.players) do
        table.insert(sorted, { name = name, kills = pdata.kills, deaths = pdata.deaths, team = pdata.team })
    end
    table.sort(sorted, function(a, b) return a.kills > b.kills end)

    broadcast("--- Top Players ---")
    for i, p in ipairs(sorted) do
        if i <= 5 then
            broadcast(string.format("#%d %s - K:%d D:%d KDR:%.1f",
                i,
                minetest.colorize(get_team_color(p.team), p.name),
                p.kills, p.deaths,
                p.deaths > 0 and (p.kills / p.deaths) or p.kills))
        end
    end

    -- Cleanup
    for name, _ in pairs(S.players) do
        local player = minetest.get_player_by_name(name)
        if player then
            remove_player_huds(player)
            player:set_fov(0)
            player:set_nametag_attributes({ color = "#FFFFFF" })
            player:set_properties({ hp_max = 20 })
            player:set_hp(20)
        end
    end

    S.players = {}
end

-- =========================
-- MATCH TIMER (globalstep)
-- =========================

local hud_update_timer = 0

minetest.register_globalstep(function(dtime)
    if not S.active then return end

    S.match_timer = S.match_timer + dtime

    -- Check time limit
    if S.match_timer >= C.match_duration then
        local winner = nil
        if S.scores.red > S.scores.blue then
            winner = "red"
        elseif S.scores.blue > S.scores.red then
            winner = "blue"
        end
        pvp_arena.end_match(winner)
        return
    end

    -- Update HUDs every second
    hud_update_timer = hud_update_timer + dtime
    if hud_update_timer >= 1.0 then
        hud_update_timer = 0
        update_all_huds()
    end
end)

-- =========================
-- CHAT COMMANDS
-- =========================

-- Set arena boundaries
minetest.register_chatcommand("arena_set", {
    params = "<pos1|pos2|redspawn|bluespawn>",
    description = "Set arena boundaries and team spawns at your current position",
    privs = { server = true },
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found" end
        local pos = vector.round(player:get_pos())

        if param == "pos1" then
            C.arena_pos1 = pos
            save_arena()
            return true, "Arena pos1 set to " .. minetest.pos_to_string(pos)
        elseif param == "pos2" then
            C.arena_pos2 = pos
            save_arena()
            return true, "Arena pos2 set to " .. minetest.pos_to_string(pos)
        elseif param == "redspawn" then
            C.teams.red.spawn = pos
            save_arena()
            return true, "Red team spawn set to " .. minetest.pos_to_string(pos)
        elseif param == "bluespawn" then
            C.teams.blue.spawn = pos
            save_arena()
            return true, "Blue team spawn set to " .. minetest.pos_to_string(pos)
        else
            return false, "Usage: /arena_set <pos1|pos2|redspawn|bluespawn>"
        end
    end,
})

-- Start match
minetest.register_chatcommand("arena_start", {
    description = "Start a PvP arena match",
    privs = { server = true },
    func = function(name, param)
        pvp_arena.start_match()
        return true
    end,
})

-- End match
minetest.register_chatcommand("arena_stop", {
    description = "Force stop the current match",
    privs = { server = true },
    func = function(name, param)
        pvp_arena.end_match(nil)
        return true, "Match force-stopped."
    end,
})

-- Set match config
minetest.register_chatcommand("arena_config", {
    params = "<duration|maxscore|hp|friendlyfire> <value>",
    description = "Configure arena settings",
    privs = { server = true },
    func = function(name, param)
        local key, val = param:match("(%S+)%s+(%S+)")
        if not key then
            return false, "Usage: /arena_config <duration|maxscore|hp|friendlyfire> <value>"
        end

        if key == "duration" then
            C.match_duration = tonumber(val) or 300
            return true, "Match duration set to " .. C.match_duration .. "s"
        elseif key == "maxscore" then
            C.max_score = tonumber(val) or 25
            return true, "Max score set to " .. C.max_score
        elseif key == "hp" then
            C.starting_hp = tonumber(val) or 20
            return true, "Starting HP set to " .. C.starting_hp
        elseif key == "friendlyfire" then
            C.friendly_fire = val == "true" or val == "on" or val == "1"
            return true, "Friendly fire: " .. tostring(C.friendly_fire)
        else
            return false, "Unknown config key: " .. key
        end
    end,
})

-- Switch teams
minetest.register_chatcommand("arena_team", {
    params = "<red|blue>",
    description = "Switch your team (before match starts)",
    func = function(name, param)
        if S.active then
            return false, "Cannot switch teams during a match!"
        end
        if param ~= "red" and param ~= "blue" then
            return false, "Usage: /arena_team <red|blue>"
        end
        -- Will take effect on next match start
        return true, "You will join " .. C.teams[param].name .. " next match."
    end,
})

-- View scores
minetest.register_chatcommand("arena_scores", {
    description = "Show current match scores",
    func = function(name, param)
        if not S.active then
            return false, "No active match."
        end
        minetest.chat_send_player(name,
            minetest.colorize("#FFAA00", "=== SCORES ==="))
        minetest.chat_send_player(name,
            minetest.colorize("#FF4444", "Red: " .. S.scores.red) .. "  |  " ..
            minetest.colorize("#4444FF", "Blue: " .. S.scores.blue))

        for pname, pdata in pairs(S.players) do
            minetest.chat_send_player(name,
                string.format("  %s - K:%d D:%d",
                    minetest.colorize(get_team_color(pdata.team), pname),
                    pdata.kills, pdata.deaths))
        end
        return true
    end,
})

-- Give weapon command (for testing)
minetest.register_chatcommand("arena_give", {
    params = "<pistol|rifle|shotgun|sniper|rocket|grenade>",
    description = "Give yourself a weapon",
    privs = { server = true },
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false end

        local items = {
            pistol  = "pvp_arena:pistol",
            rifle   = "pvp_arena:rifle",
            shotgun = "pvp_arena:shotgun",
            sniper  = "pvp_arena:sniper",
            rocket  = "pvp_arena:rocket_launcher",
            grenade = "pvp_arena:grenade 3",
        }

        local item = items[param]
        if not item then
            return false, "Unknown weapon. Options: pistol, rifle, shotgun, sniper, rocket, grenade"
        end

        player:get_inventory():add_item("main", item)
        return true, "Gave " .. param
    end,
})

-- =========================
-- PLAYER JOIN/LEAVE
-- =========================

minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    if S.active and S.players[name] then
        -- Rejoin match
        update_hud(player)
        pvp_arena.respawn_player(player)
    end
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    if S.players[name] then
        remove_player_huds(player)
        last_damager[name] = nil
    end
end)

-- =========================
-- ARENA BARRIER (prevent leaving)
-- =========================
minetest.register_globalstep(function(dtime)
    if not S.active then return end
    if not C.arena_pos1 or not C.arena_pos2 then return end

    for name, pdata in pairs(S.players) do
        local player = minetest.get_player_by_name(name)
        if player then
            local pos = player:get_pos()
            if not is_in_arena(pos) then
                -- Push player back into arena
                local center = vector.divide(vector.add(C.arena_pos1, C.arena_pos2), 2)
                local dir = vector.direction(pos, center)
                player:add_velocity(vector.multiply(dir, 5))
                minetest.chat_send_player(name,
                    minetest.colorize("#FF0000", "Stay in the arena!"))
            end
        end
    end
end)

-- =========================
-- STARTUP
-- =========================
minetest.log("action", "[pvp_arena] PvP Arena mod loaded successfully!")
minetest.log("action", "[pvp_arena] Commands: /arena_set, /arena_start, /arena_stop, /arena_config, /arena_scores, /arena_give")

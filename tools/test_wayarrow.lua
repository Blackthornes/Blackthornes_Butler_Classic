-- Butler's arrow for Show the way: Farmer's, Equipment's and Pets' dial,
-- aimed at a place (a class trainer), and TomTom's arrow instead when it is
-- installed and "Use TomTom:" is ticked.
--
-- What matters: it shows only while a place is set; it measures in yards and
-- says "You're there" up close; opening the trainer there, or its close,
-- puts it away; inside a dungeon it hides; TomTom gets one waypoint at the
-- place and the dial hides; and only one Blackthornes arrow shows at a time.

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("wayarrow")

local ns = env.Load()
env.Enable(ns)
local Arrow, ArrowUI = ns.WayArrow, ns.WayArrowUI

local clock = 100
_G.GetTime = function() return clock end
local inside = false
_G.IsInInstance = function() return inside, inside and "party" or "none" end
_G.GetPlayerFacing = function() return 0 end

local MAPS = {
    [37] = { name = "Elwynn Forest", mapType = 3, parentMapID = 13, continent = 0,
        top = 0, left = 0, width = 3000, height = 2000 },
    [13] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 },
    [947] = { name = "Azeroth", mapType = 1 },
}
_G.CreateVector2D = function(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end
local where = { map = 37, x = 0.45, y = 0.50 }
_G.C_Map = {
    GetBestMapForUnit = function() return where.map end,
    GetPlayerMapPosition = function() return _G.CreateVector2D(where.x, where.y) end,
    GetMapInfo = function(mapID)
        local map = MAPS[mapID]
        if not map then return nil end
        return { name = map.name, mapType = map.mapType, parentMapID = map.parentMapID, mapID = mapID }
    end,
    GetMapChildrenInfo = function() return {} end,
    GetWorldPosFromMapPos = function(mapID, vector)
        local map = MAPS[mapID]
        if not (map and map.width) then return nil end
        return map.continent, { GetXY = function()
            return map.top - vector.y * map.height, map.left - vector.x * map.width end }
    end,
    GetMapWorldSize = function(mapID)
        local map = MAPS[mapID]
        if map and map.width then return map.width, map.height end
    end,
}

-- Nothing set: nothing shows.
Arrow:Clear()
suite.check("off with no place", Arrow:State(clock).mode == "off" and not Arrow.IsOn())
ArrowUI:Refresh()
suite.check("and the dial stays hidden", not (ArrowUI.frame and ArrowUI.frame:IsShown()))

-- Aimed at a trainer in this zone.
suite.check("a place without a spot is refused", Arrow:Aim({ name = "Nowhere" }) == false)
suite.check("aimed at the trainer", Arrow:Aim({ name = "Mage trainer: Jennea Cannon",
    zone = "Elwynn Forest", map = 37, x = 0.55, y = 0.50 }))
suite.check("kept for this character", ns.charDB.wayArrowPlace and ns.charDB.wayArrowPlace.map == 37)
clock = clock + 5
local state = Arrow:State(clock)
suite.check("it points", state.mode == "point", state.mode)
suite.check("in yards", state.yards and math.abs(state.yards - 300) < 1, state.yards)
suite.check("said in yards", state.distance == "300 yd", state.distance)
ArrowUI:Draw(true)
suite.check("the dial shows", ArrowUI.frame and ArrowUI.frame:IsShown())

-- Inside a dungeon it hides.
inside = true
clock = clock + 5
suite.check("inside a dungeon it hides", Arrow:State(clock).mode == "inside")
inside = false

-- TomTom: its arrow instead of the dial.
do
    local TomTom = ns.TomTom
    local points = {}
    _G.TomTom = {
        AddWaypoint = function(self, map, x, y, opts)
            local uid = { map, x, y, title = opts and opts.title }
            points[uid] = true
            return uid
        end,
        RemoveWaypoint = function(self, uid) points[uid] = nil end,
    }
    local function Count()
        local count = 0
        for _ in pairs(points) do count = count + 1 end
        return count
    end
    suite.check("the TomTom switch is on unless unticked", TomTom.IsOn())
    clock = clock + 5
    ArrowUI:Draw(true)
    local uid = TomTom.uid
    suite.check("with TomTom the dial hides", not ArrowUI.frame:IsShown())
    suite.check("and TomTom gets one waypoint at the place", Count() == 1 and uid
        and uid[1] == 37 and uid[2] == 0.55 and uid[3] == 0.50)
    local box = ns.SettingsUI and ns.SettingsUI.controls and ns.SettingsUI.controls.useTomTom
    if box then
        box:Click()
        suite.check("Settings unticks it: the dial again", ns.db.useTomTom == false
            and ArrowUI.frame:IsShown() and Count() == 0)
        box:Click()
        suite.check("and ticks it again", ns.db.useTomTom == true)
    else
        TomTom:SetOn(false)
        suite.check("turned off: the dial again", ArrowUI.frame:IsShown() and Count() == 0)
        TomTom:SetOn(true)
    end
    TomTom:SetOn(false)
    _G.TomTom = nil
    TomTom.refused = nil
    TomTom:SetOn(true)
end

-- One Blackthornes arrow at a time.
local shared = _G.BlackthornesArrows
suite.check("it shares its place in one table", type(shared) == "table" and shared.wants.Butler == true)
clock = clock + 5
shared.wants.Farmer = true
shared.claims.Farmer = clock
ArrowUI:Draw(true)
suite.check("another addon's arrow aimed later hides this one", not ArrowUI.frame:IsShown())
shared.wants.Farmer = nil
ArrowUI:Refresh()
suite.check("the other put away, this one shows", ArrowUI.frame:IsShown())

-- At the trainer: opening it puts the arrow away.
where.x = 0.551
clock = clock + 5
suite.check("up close it says you're there", Arrow:State(clock).mode == "arrived")
env.Fire("TRAINER_SHOW")
suite.check("opening the trainer there puts it away", not Arrow.IsOn())
env.Fire("TRAINER_CLOSED")

-- Far from it, opening another trainer leaves it.
where.x = 0.45
Arrow:Aim({ name = "Mage trainer", zone = "Elwynn Forest", map = 37, x = 0.55, y = 0.50 })
clock = clock + 5
env.Fire("MERCHANT_SHOW")
suite.check("a vendor far from it leaves the arrow", Arrow.IsOn())
env.Fire("MERCHANT_CLOSED")
Arrow:Clear()
suite.check("its close puts it away", not Arrow.IsOn() and shared.wants.Butler == nil)

-- Drawn smaller, and a spot saved before stays where it was: kept in
-- UIParent's units, the arrow's own (smaller) units are turned back.
do
    local frame = ArrowUI:Build()
    local scale = ArrowUI.SCALE
    suite.check("the arrow is drawn smaller", scale < 1)
    ns.db.wayArrowX, ns.db.wayArrowY = 650, 400
    ArrowUI:RestorePosition()
    local p = frame._point
    suite.check("a saved spot is placed in the arrow's own units",
        p and math.abs(p[4] - 650 / scale) < 0.01 and math.abs(p[5] - 400 / scale) < 0.01)
    frame._cx, frame._cy = 650 / scale, 400 / scale
    ArrowUI:SavePosition()
    suite.check("and saved back in UIParent's units, unmoved",
        math.abs(ns.db.wayArrowX - 650) < 0.01 and math.abs(ns.db.wayArrowY - 400) < 0.01)
    ns.db.wayArrowX, ns.db.wayArrowY = nil, nil
    ArrowUI:RestorePosition()
end

-- "Guide Me:" is on until the player unticks it (Logic/Travel.lua).
if ns.Travel and ns.Travel.IsOn then
    local kept = ns.db.arrowRoute
    ns.db.arrowRoute = nil
    suite.check("Guide Me is on when never set", ns.Travel.IsOn())
    ns.db.arrowRoute = false
    suite.check("and off once unticked", not ns.Travel.IsOn())
    ns.db.arrowRoute = kept
end

suite.done()

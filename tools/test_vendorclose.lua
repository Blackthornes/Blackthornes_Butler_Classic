-- Closing a vendor, mailbox or bank before Butler has read the bags must
-- not bring the window up afterwards (a player's report, 2026-11-01).

local env = dofile(lfs_cwd .. "/tools/testenv.lua")
local suite = env.NewSuite("vendorclose")

local ns = env.Load()
local items = {
    { bag = 0, slot = 1, id = 201, name = "Junk", quality = 0, price = 10 },
}
env.FakeBags(items)
env.Enable(ns)

local UI, Bags, Selling, Errands = ns.UI, ns.Bags, ns.Selling, ns.Errands

-- Hold timers back, as the game does: a bag read takes a few frames.
local queued = {}
local realAfter = C_Timer.After
C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
local function RunTimers()
    for _ = 1, 50 do
        if #queued == 0 then return end
        local run = queued
        queued = {}
        for _, fn in ipairs(run) do fn() end
    end
end
local function Stale()
    Bags.stale = true
    Bags.scanning = false
end

ns.db.openAtVendor = true
ns.db.openAtMailbox = true

-- A normal visit still brings the window up once the bags are read.
Stale()
env.Fire("MERCHANT_SHOW")
RunTimers()
suite.check("the window comes up at a vendor", UI:IsShown() and UI.openedByVendor)
env.Fire("MERCHANT_CLOSED")
RunTimers()
suite.check("and goes when the vendor closes", not UI:IsShown())

-- The vendor closes before the bags are read: the window stays shut.
Stale()
env.Fire("MERCHANT_SHOW")
env.Fire("MERCHANT_CLOSED")
RunTimers()
suite.check("a vendor closed before the read leaves Butler shut", not UI:IsShown())
suite.check("and not marked as opened by the vendor", not UI.openedByVendor)

-- Forever can end the vendor without MERCHANT_CLOSED.
Stale()
env.Fire("MERCHANT_SHOW")
RunTimers()
suite.check("up again at the next vendor", UI:IsShown())
env.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
suite.check("the interaction ending closes it too", not UI:IsShown() and not Selling.merchantOpen)
env.Fire("MERCHANT_CLOSED")
suite.check("a second close does nothing", not UI:IsShown())

-- Opened by the player before the vendor: it stays up after.
UI:Show("bags")
Stale()
env.Fire("MERCHANT_SHOW")
RunTimers()
env.Fire("MERCHANT_CLOSED")
RunTimers()
suite.check("a window the player opened stays up", UI:IsShown())
UI:Hide()

-- The mailbox the same way.
Stale()
env.Fire("MAIL_SHOW")
env.Fire("MAIL_CLOSED")
RunTimers()
suite.check("a mailbox closed before the read leaves Butler shut", not UI:IsShown())

C_Timer.After = realAfter
suite.done()

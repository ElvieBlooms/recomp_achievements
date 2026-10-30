-- rules/common.lua
-- ==================================================================
-- Bonus achievements that don't depend on the game: they reward using
-- this mod's own features.  Loaded for every generation, marked `extra`
-- (BONUS ACHIEVEMENTS option) like the other bonus rules, and never part
-- of the RetroAchievements list, so they never change leaderboard points.
--
-- "ui.*" events are sent by this mod's menus (engine:dispatch), not by
-- the game.
-- ==================================================================

return {
  {
    id = "show_and_tell", title = "Show and Tell", category = "EXTRAS", points = 1,
    description = "Open your leaderboard card. Sharing it is up to you!",
    kind = "event", on = "ui.card_opened",
    test = function() return true end,
  },
}

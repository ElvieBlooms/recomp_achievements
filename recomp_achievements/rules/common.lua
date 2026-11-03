-- rules/common.lua
-- Bonus achievements for using the mod itself, so they work in every generation.
-- They are marked `extra` like the other bonus rules, so the BONUS ACHIEVEMENTS
-- option hides them, and they never count toward RetroAchievements points.
-- The "ui.*" events come from this mod's own menus (engine:dispatch), not the game.
-- ------------------

return {
  {
    id = "show_and_tell", title = "Show and Tell", category = "EXTRAS", points = 1,
    description = "Open your leaderboard card. Sharing it is up to you!",
    kind = "event", on = "ui.card_opened",
    test = function() return true end,
  },
}

return function(mod)
    mod.events:on("game.ready",function(ev)
        mod.log:info("I'm alive!")
    end)
end


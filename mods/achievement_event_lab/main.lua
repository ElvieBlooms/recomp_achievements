return function(mod)
    mod.events:on("game.ready", function(ev)
        mod.log:info("I'm alive!")
            local datatype = type(ev)
            mod.log:info(datatype)
            local message = "Type: " .. datatype
            mod.log:info(message)
    end)
    mod.log:info("Observer Initialized")
end

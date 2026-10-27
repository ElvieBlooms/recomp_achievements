return function(mod)
    mod.events:on("game.ready", function(ev)
        mod.log:info("I'm alive!")

        local datatype = type(ev)
        mod.log:info(datatype)

        local message = "Type: " .. datatype
        mod.log:info(message)

        local gameType = type(ev.game)
        mod.log:info("Game field type: " .. gameType)

        for key, value in pairs(ev) do
            mod.log:info("Event field: " .. tostring(key))
            mod.log:info("Field type: " .. type(value))
        end
    end)

    mod.log:info("Observer Initialized")
end

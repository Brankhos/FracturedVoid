local Replica = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Replica"))

Replica.OnNew("GlobalData", function(replica: typeof(Replica.Replica))

    print(`Replica received client-side! Data:`, replica.Data)

    replica:OnSet({"Score"}, function(new_value, old_value)
        print(`Score has changed from {old_value} to {new_value}`)
    end)

end)

Replica.RequestData() -- Must be called once anywhere in game code client-side
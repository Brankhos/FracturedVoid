local Replica = require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("Replica"))
local ProfileStore = require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("ProfileStore"))

-- Replica Example
local replica = Replica.New({
	Token = Replica.Token("GlobalData"),
	Data = { -- Passed table reference will be used
		Score = 0,
		Nested = {
			Value = false,
		},
	},
})

replica:Replicate()

task.spawn(function()
	while true do
		replica:Set({"Score"}, replica.Data.Score + 100)
		task.wait(1)
	end
end)

replica:Set({"Nested", "Value"}, true)



-- Profile Store Example
-- The PROFILE_TEMPLATE table is what new profile "Profile.Data" will default to:
local PROFILE_TEMPLATE = {
	Cash = 0,
	Items = {},
}

local Players = game:GetService("Players")

local PlayerStore = ProfileStore.New("PlayerStore", PROFILE_TEMPLATE)
local Profiles: {[Player]: typeof(PlayerStore:StartSessionAsync())} = {}

local function PlayerAdded(player: Player)
   local loaded = false

	-- Start a profile session for this player's data:

	local profile = PlayerStore:StartSessionAsync(`{player.UserId}`, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})

	-- Handling new profile session or failure to start it:

	if profile ~= nil then

		profile:AddUserId(player.UserId) -- GDPR compliance
		profile:Reconcile() -- Fill in missing variables from PROFILE_TEMPLATE (optional)

		profile.OnSessionEnd:Connect(function()
			Profiles[player] = nil
			player:Kick(`Profile session end - Please rejoin`)
		end)

		local function newCharacter(character)
         if player.Parent == Players and not loaded then
            loaded = true
            print("character loaded!", character)
            -- YOUR CODE HERE
         end
		end

      if player.Character then
         task.defer(newCharacter, player.Character)
      end
      player.CharacterAdded:Connect(newCharacter)


		if player.Parent == Players then
			Profiles[player] = profile
			print(`Profile loaded for {player.DisplayName}!`)
			-- EXAMPLE: Grant the player 100 coins for joining:
			profile.Data.Cash += 100
			-- You should set "Cash" in PROFILE_TEMPLATE and use "Profile:Reconcile()",
			-- otherwise you'll have to check whether "Data.Cash" is not nil
		else
			-- The player has left before the profile session started
			profile:EndSession()
		end

	else
		-- This condition should only happen when the Roblox server is shutting down
		player:Kick(`Profile load fail - Please rejoin`)
	end

end

-- In case Players have joined the server earlier than this script ran:
for _, player in Players:GetPlayers() do
	task.defer(PlayerAdded, player)
end

Players.PlayerAdded:Connect(PlayerAdded)

Players.PlayerRemoving:Connect(function(player: Player)
	local profile = Profiles[player]
	if profile ~= nil then
		profile:EndSession()
	end
end)
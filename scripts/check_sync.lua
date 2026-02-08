-- scripts/check_sync.lua
-- Verifies that key mapped places exist in the built data model

print("Running sync checks (filesystem-only checks not available in this runner).\nThis script is meant to be executed inside Roblox Studio or adapted to your CI.")

-- Provide a simple check function for use inside Studio's command bar or a Studio script
return {
    Run = function()
        local ReplicatedStorage = game:FindFirstChild("ReplicatedStorage")
        if not ReplicatedStorage then
            warn("ReplicatedStorage not found in the place.")
            return false
        end
        local shared = ReplicatedStorage:FindFirstChild("Shared")
        if not shared then
            warn("ReplicatedStorage.Shared missing. Check Rojo mapping of src/shared -> ReplicatedStorage/Shared")
        else
            print("ReplicatedStorage.Shared exists")
        end
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if not remotes then
            warn("ReplicatedStorage.Remotes missing. Ensure RemotesInit.Init() ran on server startup.")
        else
            print("ReplicatedStorage.Remotes exists")
        end

        local ServerScriptService = game:FindFirstChild("ServerScriptService")
        if not ServerScriptService then
            warn("ServerScriptService missing")
            return false
        end
        local server = ServerScriptService:FindFirstChild("Server")
        if not server then warn("ServerScriptService.Server missing (check Rojo mapping for src/server)") end
        local services = server and server:FindFirstChild("services")
        if not services then warn("Server.services folder missing under ServerScriptService.Server.services") end
        local remotesInit = services and services:FindFirstChild("RemotesInit")
        if not remotesInit then
            warn("RemotesInit script missing under Server.services. Ensure only one RemotesInit exists and Rojo mapping is correct.")
        else
            print("Server.services.RemotesInit exists")
        end
        return true
    end
}

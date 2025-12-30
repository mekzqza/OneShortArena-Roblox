local RunService = game:GetService("RunService")

return {
    IS_PRODUCTION = not RunService:IsStudio(),
    IS_STUDIO = RunService:IsStudio(),
    IS_CLIENT = RunService:IsClient(),
    IS_SERVER = RunService:IsServer(),
}

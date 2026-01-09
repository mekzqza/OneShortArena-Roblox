return {
	Name = "teleportlobby",
	Aliases = {"tplobby", "lobby"},
	Description = "ส่งผู้เล่นไป Lobby",
	Group = "Admin",
	Args = {
		{
			Type = "players",  -- ✅ รองรับหลายคน
			Name = "ผู้เล่น",
			Description = "ผู้เล่นที่ต้องการส่งไป Lobby",
		},
	},
}

return {
	Name = "setstate",
	Aliases = {"state"},
	Description = "เปลี่ยนสถานะของผู้เล่น",
	Group = "Admin",
	Args = {
		{
			Type = "player",
			Name = "ผู้เล่น",
			Description = "ผู้เล่นที่ต้องการเปลี่ยนสถานะ",
		},
		{
			Type = "string",
			Name = "สถานะ",
			Description = "สถานะใหม่ (Lobby, Arena, Playing, Downed, Spectating, Died)",
		},
	},
}

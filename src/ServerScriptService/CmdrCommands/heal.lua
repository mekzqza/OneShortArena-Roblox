return {
	Name = "heal",
	Aliases = {"hp"},
	Description = "เติม HP ให้ผู้เล่น",
	Group = "Admin",
	Args = {
		{
			Type = "players",
			Name = "ผู้เล่น",
			Description = "ผู้เล่นที่ต้องการเติม HP",
		},
		{
			Type = "number",
			Name = "HP",
			Description = "จำนวน HP (ไม่ใส่ = เต็ม)",
			Optional = true,
			Default = 100,
		},
	},
}

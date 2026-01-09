return {
	Name = "givecoins",
	Aliases = {"coins", "money"},
	Description = "ให้เหรียญผู้เล่น",
	Group = "Admin",
	Args = {
		{
			Type = "player",
			Name = "ผู้เล่น",
			Description = "ผู้เล่นที่ต้องการให้เหรียญ",
		},
		{
			Type = "number",
			Name = "จำนวน",
			Description = "จำนวนเหรียญ",
		},
	},
}

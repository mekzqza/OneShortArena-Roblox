return {
	Name = "setstate",
	Aliases = {},
	Description = "เปลี่ยนสถานะผู้เล่น",
	Group = "DefaultAdmin",
	Args = {
		{
			Type = "player",
			Name = "target",
			Description = "ผู้เล่นที่จะเปลี่ยนสถานะ",
		},
		{
			Type = "string",
			Name = "state",
			Description = "สถานะใหม่ (Lobby/Arena/Playing/Downed)",
		},
	},
}

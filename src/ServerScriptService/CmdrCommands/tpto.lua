return {
	Name = "tpto",
	Aliases = {"teleportto"},
	Description = "วาร์ปผู้เล่นไปหาผู้เล่นอื่น",
	Group = "DefaultAdmin",
	Args = {
		{
			Type = "player",
			Name = "from",
			Description = "ผู้เล่นที่จะถูกวาร์ป",
		},
		{
			Type = "player",
			Name = "to",
			Description = "ผู้เล่นปลายทาง",
		},
	},
}

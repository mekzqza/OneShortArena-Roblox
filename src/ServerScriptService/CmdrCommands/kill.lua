return {
	Name = "kill",
	Aliases = {"slay"},
	Description = "ฆ่าผู้เล่น",
	Group = "DefaultAdmin",
	Args = {
		{
			Type = "players",  -- ✅ "players" = หลายคน, "player" = คนเดียว
			Name = "targets",
			Description = "ผู้เล่นที่จะฆ่า (ใส่ได้หลายคน)",
		},
	},
}

return {
	Name = "getdata",
	Aliases = {"data", "stats"},
	Description = "ดูข้อมูลผู้เล่น",
	Group = "Admin",
	Args = {
		{
			Type = "player",
			Name = "ผู้เล่น",
			Description = "ผู้เล่นที่ต้องการดูข้อมูล",
		},
	},
}

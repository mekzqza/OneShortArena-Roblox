return {
	Name = "getdata",
	Aliases = {"data", "stats"},
	Description = "ดูข้อมูลผู้เล่น",
	Group = "DefaultAdmin",
	Args = {
		{
			Type = "player",
			Name = "target",
			Description = "ผู้เล่นที่จะดูข้อมูล",
			Optional = true,  -- ✅ ไม่ใส่ = ดูข้อมูลตัวเอง
		},
	},
}

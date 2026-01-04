return {
	Name = "coins",
	Aliases = {"givemoney", "cash"},  -- คำสั่งอื่นที่เรียกได้
	Description = "ให้เหรียญกับผู้เล่น",
	Group = "DefaultAdmin",  -- ต้องเป็น Admin (จาก Hooks)
	Args = {
		{
			Type = "player",  -- ชนิดข้อมูล: ผู้เล่น
			Name = "target",
			Description = "ผู้เล่นที่จะให้เหรียญ",
		},
		{
			Type = "integer",  -- ชนิดข้อมูล: จำนวนเต็ม
			Name = "amount",
			Description = "จำนวนเหรียญ",
		},
	},
}

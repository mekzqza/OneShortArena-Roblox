# 📚 OneShortArena Documentation

Welcome to the OneShortArena documentation! This folder contains all guides and references for the project.

---

## 📖 Available Guides

### 🚀 [Quick Reference](quick-reference.md)
คู่มือย่อสำหรับงานทั่วไป - อ่านก่อนเสมอ!

**เหมาะสำหรับ:**
- เพิ่ม Event ใหม่
- สร้าง Service/Controller ใหม่
- Debug ปัญหาพื้นฐาน
- ทดสอบระบบ

---

### 📐 [Dependencies & Architecture](deps.md)
โครงสร้างระบบและความสัมพันธ์ระหว่างส่วนต่างๆ

**เหมาะสำหรับ:**
- ทำความเข้าใจภาพรวมโปรเจ็ค
- ดูว่าไฟล์ไหนขึ้นกับไฟล์ไหน
- เข้าใจ Client-Server architecture

---

### 🎮 [Input System Guide](input-system-guide.md)
คู่มือการใช้งานระบบ Input แบบละเอียด

**เหมาะสำหรับ:**
- เพิ่มปุ่มควบคุมใหม่
- ทำความเข้าใจ Input Flow
- แก้ปัญหาเกี่ยวกับ Input
- Mobile button configuration

**เนื้อหาประกอบด้วย:**
- ✅ Architecture & Data Flow
- ✅ การเพิ่ม Action ใหม่
- ✅ Mobile support
- ✅ Security considerations
- ✅ Common issues & solutions

---

### 🚀 [Production Features](production-features.md) **← ใหม่!**
ระบบ Production-Ready: Input, Cooldown, Validation

**เหมาะสำหรับ:**
- ทำความเข้าใจ Advanced Input System
- เรียนรู้ Cooldown System
- ดู Server Validation best practices
- เพิ่ม Attack types และ Combos

**เนื้อหาประกอบด้วย:**
- ✅ 5 Input Types (Tap, Hold, DoubleTap, Release, Combo)
- ✅ Server-side Cooldown System
- ✅ Action Queue & Lag Compensation
- ✅ Attack/Defense variations
- ✅ Complete examples & tutorials

---

## 🎯 Getting Started

### สำหรับนักพัฒนาใหม่:

1. **อ่าน [Quick Reference](quick-reference.md) ก่อน**
   - เรียนรู้ task พื้นฐาน
   - ทำความเข้าใจ event system

2. **ดู [Dependencies](deps.md)**
   - เข้าใจโครงสร้างโปรเจ็ค
   - รู้ว่าไฟล์ไหนอยู่ที่ไหน

3. **อ่าน [Input Guide](input-system-guide.md) (ถ้าทำเกี่ยวกับ Input)**
   - เรียนรู้วิธีเพิ่มปุ่มควบคุม
   - ทำความเข้าใจ input flow

4. **อ่าน [Production Features](production-features.md) (สำหรับ Advanced)**
   - เรียนรู้ Input types ทั้งหมด
   - ทำความเข้าใจ Cooldown System
   - ดู Production best practices

5. **ลองทำ Demo**
   - Run `_G.DemoController:RunTests()` ใน Command Bar
   - ดู Console output

---

## 🔍 Quick Navigation

| ต้องการทำอะไร | ดูเอกสารไหน | หน้าที่ |
|---------------|-------------|---------|
| เพิ่ม Event | Quick Reference | Task 1 |
| เพิ่ม Service | Quick Reference | Task 4 |
| เพิ่มปุ่มควบคุม | Input Guide | Use Case 1 |
| Debug Input | Input Guide | Common Issues |
| เข้าใจโครงสร้าง | Dependencies | Architecture |
| ทดสอบระบบ | Quick Reference | Testing Shortcuts |
| เพิ่ม Attack Type | Production Features | Attack System |
| ใช้ Cooldown | Production Features | Cooldown System |
| ทำ Combo | Production Features | Combo System |

---

## 📁 Document Structure

```
docs/
├── README.md                    ← You are here
├── quick-reference.md           ← คู่มือย่อ
├── deps.md                      ← โครงสร้างระบบ
├── input-system-guide.md        ← คู่มือ Input พื้นฐาน
└── production-features.md       ← Production Features (ใหม่!)
```

---

## 🛠️ Additional Resources

### Backend Development
- See: `.github/agents/gameplay-backend.md`
- Service template & security guidelines

### Code Style
- Follow: `.github/agents/gameplay-backend.md` → Coding Standards
- Use `--!strict` mode
- Export types properly

### Testing
- Demo files in `src/ServerScriptService/Services/DemoService.luau`
- Demo client in `src/StarterPlayerScripts/Controllers/DemoController.luau`

---

## 🆘 Need Help?

### Common Questions

**Q: ฉันจะเพิ่ม Event ใหม่ได้อย่างไร?**
A: ดู [Quick Reference → Task 1](quick-reference.md#task-1-add-new-event)

**Q: ต้องการเพิ่มปุ่มควบคุมใหม่**
A: ดู [Input Guide → Use Case 1](input-system-guide.md#use-case-1-เพิ่ม-action-ใหม่)

**Q: Event ไม่ fire**
A: ดู [Quick Reference → Debug Checklist](quick-reference.md#-debug-checklist)

**Q: Input ไม่ทำงาน**
A: ดู [Input Guide → Common Issues](input-system-guide.md#-common-issues--solutions)

---

## 📊 Documentation Version

| Document | Version | Last Updated | Status |
|----------|---------|--------------|--------|
| Quick Reference | 1.3 | 2024 | ✅ Hold Detection Fixed |
| Dependencies | 1.0 | 2024 | ✅ Up to date |
| Input Guide | 1.0 | 2024 | ✅ Up to date |
| Production Features | 1.1 | 2024 | ✅ **Hold Detection Fixed** |

### Recent Updates

**v1.1 (Latest):**
- ✅ **Fixed Hold detection** - เปลี่ยนจาก Change State เป็น Timer-based
- ✅ Added Release event handling
- ✅ Auto-cancel timers on Double Tap
- ✅ Proper timer cleanup on unbind

---

## 🤝 Contributing to Docs

เมื่อเพิ่มฟีเจอร์ใหม่:
1. อัพเดท `Events.luau` และ `quick-reference.md`
2. เพิ่ม example ใน relevant guide
3. อัพเดท version number
4. Test ตัวอย่างที่เขียนให้แน่ใจว่าทำงาน

---

*Happy Coding! 🚀*

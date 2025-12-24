# 📚 OneShortArena Documentation

Welcome to the OneShortArena documentation! This folder contains all guides and references for the project.

---

## 📖 Available Guides

### 🚀 [Quick Reference](quick-reference.md) **← เริ่มต้นที่นี่**
คู่มือย่อ Production - อ่านก่อนเสมอ!

**เหมาะสำหรับ:**
- เพิ่ม Event ใหม่
- สร้าง Service/Controller ใหม่
- Debug ปัญหาพื้นฐาน
- Production tasks

**⚠️ Production components เท่านั้น** - ไม่มี Demo

---

### 📐 [Dependencies & Architecture](deps.md)
โครงสร้างระบบและความสัมพันธ์ระหว่างส่วนต่างๆ

**เหมาะสำหรับ:**
- ทำความเข้าใจภาพรวมโปรเจ็ค
- ดูว่าไฟล์ไหนขึ้นกับไฟล์ไหน
- เข้าใจ Production vs Demo architecture

**Highlights:**
- ✅ Production components (InputController, CombatService, etc.)
- 🧪 Demo components (DemoController, DemoService - ลบได้)
- Clear separation of concerns

---

### 🎮 [Input System Guide](input-system-guide.md)
คู่มือการใช้งานระบบ Input Production

**เหมาะสำหรับ:**
- เพิ่มปุ่มควบคุมใหม่ (Production)
- ทำความเข้าใจ Input Flow
- แก้ปัญหาเกี่ยวกับ Input
- Mobile button configuration

**Components:**
- InputController ✅ - Hardware input
- InputHandler ✅ - Game actions
- ~~DemoController 🧪~~ - (ดู demo-testing.md)

---

### 🚀 [Production Features](production-features.md)
ระบบ Production-Ready: Input, Cooldown, Combat

**เหมาะสำหรับ:**
- ทำความเข้าใจ Advanced Input System
- เรียนรู้ Cooldown System
- ดู Server Validation best practices
- เพิ่ม Attack types และ Combos

**เนื้อหาประกอบด้วย:**
- ✅ 5 Input Types (Tap, Hold, DoubleTap, Release, Combo)
- ✅ Server-side Cooldown System
- ✅ Production architecture only
- ❌ ไม่มี Demo references

---

### 🧪 [Demo & Testing Guide](demo-testing.md) **← สำหรับ Testing เท่านั้น**
คู่มือ Demo components (ลบได้ในอนาคต)

**เหมาะสำหรับ:**
- ทดสอบ network communication
- Quick prototyping
- Verify RemoteEvent setup

**⚠️ Components ในนี้ลบได้:**
- DemoController 🧪
- DemoService 🧪
- DEMO_* events 🧪

**ไม่ควรใช้:**
- ❌ ใน Production
- ❌ เป็น architecture reference
- ❌ สำหรับ business logic

---

## 🎯 Getting Started

### สำหรับนักพัฒนาใหม่:

1. **อ่าน [Quick Reference](quick-reference.md) ก่อน** ✅
   - เรียนรู้ Production tasks
   - ทำความเข้าใจ event system

2. **ดู [Dependencies](deps.md)** ✅
   - เข้าใจโครงสร้างโปรเจ็ค
   - แยก Production vs Demo

3. **อ่าน [Production Features](production-features.md)** ✅
   - เรียนรู้ Production architecture
   - ทำความเข้าใจ Input/Cooldown systems

4. **(Optional) [Demo Testing](demo-testing.md)** 🧪
   - เฉพาะเมื่อต้องการทดสอบ network
   - **ไม่ใช่สำหรับ Production**

---

## 🔍 Quick Navigation

| ต้องการทำอะไร | ดูเอกสารไหน | หน้าที่ |
|---------------|-------------|---------|
| เพิ่ม Event | Quick Reference | Task 1 |
| เพิ่ม Service | Quick Reference | Task 4 |
| เพิ่มปุ่มควบคุม | Production Features | Input System |
| เพิ่ม Attack Type | Production Features | Combat System |
| ใช้ Cooldown | Production Features | Cooldown System |
| Debug Input | Production Features | Common Issues |
| เข้าใจโครงสร้าง | Dependencies | Architecture |
| **ทดสอบ Network** | **Demo Testing** | **Testing Guide** |
| ทดสอบระบบ | Quick Reference | Testing Shortcuts |

---

## 📁 Document Structure

```
docs/
├── README.md                    ← You are here
│
├── Production Docs (ใช้งานจริง) ✅
│   ├── quick-reference.md       ← คู่มือย่อ
│   ├── deps.md                  ← โครงสร้างระบบ
│   ├── input-system-guide.md    ← Input พื้นฐาน
│   └── production-features.md   ← Production features
│
└── Testing Docs (ทดสอบ) 🧪
    └── demo-testing.md          ← Demo components (ลบได้)
```

---

## 🚦 Component Status

### ✅ Production (Core - ห้ามลบ)

**Client:**
- InputController - Hardware input
- InputHandler - Game actions
- NetworkController - Network bridge

**Server:**
- NetworkHandler - Security layer
- CooldownService - Cooldown tracking
- CombatService - Combat logic
- GameService - Game state
- ArenaService - Arena management

**Shared:**
- EventBus - Event system
- Events - Event constants
- InputSettings - Key bindings

### 🧪 Demo (Testing - ลบได้)

**Client:**
- ~~DemoController~~ - Network testing

**Server:**
- ~~DemoService~~ - Test responses

**Events:**
- ~~DEMO_*~~ - Test events

### 🔨 TODO (กำลังทำ)

- UIController - UI management
- ProfileService - Data persistence
- GameConfigs - Configuration

---

## 📊 Documentation Version

| Document | Version | Type | Last Updated |
|----------|---------|------|--------------|
| Quick Reference | 2.0 | ✅ Production | 2024 |
| Dependencies | 2.0 | ✅ Production | 2024 |
| Input Guide | 1.0 | ✅ Production | 2024 |
| Production Features | 2.0 | ✅ Production | 2024 |
| Demo Testing | 1.0 | 🧪 Demo | 2024 |

### Recent Updates

**v2.0 (Latest):**
- ✅ **Separated Demo from Production**
- ✅ Created dedicated demo-testing.md
- ✅ Removed Demo references from Production docs
- ✅ Clear component categorization

**v1.1:**
- ✅ Fixed Hold detection (Timer-based)
- ✅ Added Release event handling

---

## 🛠️ Additional Resources

### Backend Development
- See: `.github/agents/gameplay-backend.md`
- Service template & security guidelines

### Code Style
- Follow: `.github/agents/gameplay-backend.md` → Coding Standards
- Use `--!strict` mode
- Export types properly

### Production Testing
- Use: InputController + InputHandler
- **Avoid:** DemoController (ดู demo-testing.md)

---

## 🤝 Contributing to Docs

เมื่อเพิ่มฟีเจอร์ใหม่:

1. **Production Features:**
   - อัพเดท `production-features.md`
   - อัพเดท `quick-reference.md`
   - เพิ่ม examples ที่ชัดเจน

2. **Demo/Testing:**
   - อัพเดท `demo-testing.md` เท่านั้น
   - **ห้ามเพิ่มใน Production docs**

3. **Version Control:**
   - อัพเดท version number
   - เพิ่ม changelog entry
   - Test ตัวอย่างที่เขียน

---

*Happy Coding! 🚀*
*Remember: Production ≠ Demo*

# 🛡️ x-ui RAM Watchdog (FINAL)

ระบบ **Watchdog สำหรับ x-ui / 3x-ui**  
ช่วยป้องกันปัญหา RAM เต็ม, Swap พุ่ง, ความเร็วตก  
โดย **รีสตาร์ท x-ui อัตโนมัติเมื่อ RAM ใช้งานสูงเกินกำหนด**

> ✅ ปลอดภัย  
> ✅ ไม่ยุ่ง / ไม่พังคำสั่ง `x-ui`  
> ✅ ใช้ systemd timer (ไม่ใช้ cron)  
> ✅ ใช้ได้กับ Ubuntu 20.04 / 22.04  

---

## ✨ Features

- 🔄 Restart x-ui อัตโนมัติเมื่อ RAM ≥ 80%
- ⏳ Cooldown ป้องกัน restart ถี่
- 🧹 ลบ watchdog รุ่นเก่าอัตโนมัติ
- 📉 คุม log ไม่ให้กิน storage
- 📋 มีเมนูดูสถานะและ log
- 🚫 ไม่ override คำสั่ง `x-ui`

---

## 📦 Requirements

- Ubuntu 20.04 / 22.04
- ติดตั้ง x-ui / 3x-ui แล้ว
- ต้องรันด้วย root

---

## 🚀 Installation

```bash
wget -O install-watchdog.sh https://raw.githubusercontent.com/TspKchn/3x-ui-ram-watchdog/main/install-xui-watchdog-final.sh \
&& chmod +x install-watchdog.sh \
&& bash install-watchdog.sh \
&& rm -f install-watchdog.sh

```

---

## 🧭 Usage

เปิดเมนู watchdog:
```bash
watchdog

```

---

## 📊 Log & Status

```bash
tail -f /var/log/xui-watchdog.log
systemctl status xui-watchdog.timer

```

---

## ⚙ Default Config

- RAM Threshold: 80%
- Duration: 120s
- Cooldown: 600s
- Action: restart x-ui

---

## 🧹 Uninstall

```bash
systemctl stop xui-watchdog.timer
systemctl disable xui-watchdog.timer
rm -f /usr/local/bin/xui-watchdog.sh
rm -f /usr/local/bin/x-ui-watchdog
rm -f /etc/systemd/system/xui-watchdog.*
rm -f /var/log/xui-watchdog.log
rm -rf /run/xui-watchdog
systemctl daemon-reload
```

---

## 👤 Author

**TspKchn**

⭐ Enjoy stable x-ui server

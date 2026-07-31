# 3ERoomElectrical v1.9.26 — Build 47.1-HF1

Hotfix لتخطيط iPhone وiPad: شريط `2D / 3D / الصور` أعلى العارض بالطول وشريط جانبي بالعرض، مع ضغط أدوات مخطط 2D وتوزيع الكهرباء والتصوير الفوتوغرافي عند انخفاض ارتفاع النافذة. لا يغيّر هذا الإصلاح بيانات المشروع أو صادرات PDF/DXF/GLB.

راجع `Docs/3E-v1.9.26-build47.1-HF1-adaptive-layout.md`.

## Build 47.2 — 3E suite integration

The current app can now use the user-selected shared `3E` folder through a persisted security-scoped bookmark. Its stable identity is `com.essam.3E.roomelectrical`, it registers `roomElectrical` in `System/registry.json`, stores app data under `Apps/RoomElectrical`, and accepts `electrical://open` links. App Group `group.com.essam.3e` is prepared as a future constant but is not present in the free-signing entitlements.


## Build 48 — registry compatibility

يقبل التطبيق الآن الحقل `apps` داخل `System/registry.json` بصيغة القائمة القديمة أو الكائن المفهرس الذي تستخدمه 3ELocal، ويحافظ على سجلات 3ELiDAR و3ELocal والحقول الإضافية قبل حفظ الصيغة الموحدة.

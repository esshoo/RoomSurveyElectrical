# 3ERoomElectrical v1.9.6.1 — Build 24

Build-only correction for Xcode 26:

- Replaces the rejected conditional `as? CTFont` bridge with a guarded attribute lookup followed by the required `as! CTFont` Core Foundation bridge.
- No DXF geometry, encoding, widget, or export behaviour was changed.

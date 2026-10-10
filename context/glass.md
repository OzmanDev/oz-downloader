# Glass

## 2026-10-10 — System material on the Mac window

Mac only. Buttons, cards, list panels, fields, the tab bar, the progress columns, and the What’s new sheet use Apple’s system material. Cards use the regular material. Buttons, fields, and the tab bar use the thin material. The toolchain SDK is macOS 15.2, so this is `regularMaterial` and `thinMaterial`, the system blur that ships with that SDK.

A glass button that is off is dimmer than one that is on. Every glass button uses the same accent border. The What failed popup uses the same regular material as other cards, thin material on each song row, and a glass Close button. Windows is unchanged. Row selection keeps its accent tint. Tiny icon buttons inside a row stay plain.

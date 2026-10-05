# Aether visual identity

## Browsing screens

The browsing interface uses a paper and ink palette rather than a luminous
radio gradient. It is deliberately quiet so station marks and album artwork
provide the changing color.

| Role | Color |
| --- | --- |
| Canvas | `#F5F3EC` |
| Surface | `#FFFEF9` |
| Navigation surface | `#EDF0E8` |
| Main text | `#222B25` |
| Supporting text | `#576359` |
| Inactive icons | `#5E705F` |
| Active controls and favorites | `#2B664C` |
| Soft active surface | `#D8E8DA` |
| Hairlines | `#D0D9CE` |
| Logo wells | `#1D3226` |

Large screen headings use the system serif face. Station names and controls
stay in the system sans face for fast scanning. Rows use a thin inset rule and
dark logo wells so transparent white station logos remain legible. The app
icon is an Æ lettermark rendered from `scripts/generate-aether-icon.py`.

## Player

The fullscreen vinyl player and its preview bar keep their original dark
palette, text colors, artwork treatment, layout, and controls. Their colors
live separately in `AetherTheme.Player` so future browsing changes cannot
silently recolor them.

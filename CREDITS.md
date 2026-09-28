# Credits / 致谢

- **DRIVER HUD 1.4.5** and **HUD 1.11.1**, by FireScallion, Copyright (c) 2026, MIT License
  https://github.com/FireScallion/DRIVER-HUD---HD2-Vehicle-HUD
  - `src/vendor/native_hud.lua`: HUD 1.11.1's `native.lua` (itself adapted from DRIVER HUD). It is used **unmodified**: the read-only native reader, code guards, Health record/config layout, and network entity round-trip checks.
  - `src/vendor/weapon_driverhud.lua`: the Magazine/Rounds weapon component layout and its code guards, from DRIVER HUD 1.4.5.
  - The vehicle/arm resource hashes in `src/body.lua` also come from these two mods.
  - The license text is included verbatim in `third_party/LICENSE-DRIVER-HUD.txt`.
- **Bingus Shared Loader v17**, by CowboyBingus. This is a required dependency and is **not** redistributed here. https://www.nexusmods.com/helldivers2/mods/16292
- Ammo capacities come from [helldivers.wiki.gg](https://helldivers.wiki.gg/) (checked 2026-09) and from in-game measurement.
- Helldivers 2 and its assets, names and identifiers belong to their respective owners. This project is not affiliated with or endorsed by Arrowhead, Sony, or the upstream authors.

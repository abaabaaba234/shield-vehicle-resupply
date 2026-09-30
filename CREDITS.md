# Credits / 致谢

- **DRIVER HUD 1.4.5** and **HUD 1.11.1**, by FireScallion, Copyright (c) 2026, MIT License
  https://github.com/FireScallion/DRIVER-HUD---HD2-Vehicle-HUD
  - `src/vendor/native_hud.lua`: HUD 1.11.1's `native.lua` (itself adapted from DRIVER HUD). It is used **unmodified**: the read-only native reader, code guards, Health record/config layout, and network entity round-trip checks.
  - `src/vendor/weapon_driverhud.lua`: the Magazine/Rounds weapon component layout and its code guards, from DRIVER HUD 1.4.5.
  - The vehicle/arm resource hashes in `src/body.lua` also come from these two mods.
  - The license text is included verbatim in `third_party/LICENSE-DRIVER-HUD.txt`.
- **Bingus Shared Loader v17**, by CowboyBingus. This is a required dependency and is **not** redistributed here. https://www.nexusmods.com/helldivers2/mods/16292
- Ammo capacities come from [helldivers.wiki.gg](https://helldivers.wiki.gg/) (checked 2026-09) and from in-game measurement.
- **filediver** by xypwn and contributors, BSD-3-Clause License — https://github.com/xypwn/filediver
  - The v0.13 healing uses the game's own regeneration; the `HealthComponent` field layout (offsets of
    `Health` / `HeathChangerate` / `HealthChangerateDisabled` / `HeathChangerateCooldown` /
    `RegenerationSegments` / `RegenerationChangerate`, and `DamageableZoneInfo.RegenerationEnabled`) comes from
    filediver's `datalibrary` package, which mirrors the game's plaintext data. No filediver code is redistributed here.
  - v0.15 corrects the per-zone offsets using the 64-bit metadata in
    [dl_library.dl_typelib.gz](https://github.com/xypwn/filediver/blob/master/datalibrary/dl_library.dl_typelib.gz),
    with a regression fixture extracted from its public generated_entities.dl_bin.gz.
    v0.14 incorrectly derived the offset from an incomplete hand-written Go structure.
    Its `OnHealScriptEvent` and `OnDeadDisableAllActors` fields are exposed as diagnostics; their presence
    is not treated as proof that detached models or physics actors can be restored.
- Helldivers 2 and its assets, names and identifiers belong to their respective owners. This project is not affiliated with or endorsed by Arrowhead, Sony, or the upstream authors.

- **Vehicle Supply Tower 1.0.1**, user-provided local reference (`mods/codex/vehicle_supply_tower`): its Lua implementation identifies the repair-drone wrapper, game repair ABI, VehicleApi getter/setter slots, four-wheel resource header and 48-byte intact tyre restoration. `src/repair_native.lua` implements these interfaces for the existing shield service, with its own ownership, configuration, selection, mapping and readback logic. The full supply-tower addon is not redistributed, and its Tesla, ammo and stat-modifier features are not included.

# Shield Vehicle Resupply

[中文](README.md)

This is a Helldivers 2 Lua mod. While an **FX-12 Shield Generator** bubble is up, vehicles inside it are continuously repaired and resupplied:

| Vehicle | Repair | Ammo |
|---|---|---|
| EXO mechs (all 4, including arms) | ✅ | ✅ |
| Tanks (TD-220 Bastion / TD-110 Maelstrom) | ✅ hull + zones | ✅ |
| FRV | ✅ hull + zones | — |

Repair and resupply stop when the bubble goes away. The generator entity disappears at that point, about 42 s in-game.

## Install
1. Install [Bingus Shared Loader v17](https://www.nexusmods.com/helldivers2/mods/16292).
2. Download `ShieldVehicleResupply_<version>.zip` from [Releases](../../releases) and import it with your mod manager.

The mod targets the same game build as DRIVER HUD 1.4.5 / HUD 1.11.1 (Steam build 25480438). On any other build, the code-guard check fails and the mod disables itself **without writing memory**.

## Settings and commands
All files are in `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\`:
- `shield_resupply_settings.txt`: settings. The mod creates it on first run. Send `reload` after you edit it.
- `shield_resupply_cmd.txt`: commands, one per line. Each runs within 0.5 s.
- `ShieldVehicleResupply.log`: log and command output.

Commands: `status`, `on`, `off`, `reload`, `test`, `vehicles`, `weapons`, `units`, `recent [n]`, `healcfg`, `hptrace [secs]`, `heal native|write|off`, `probe`, `netinfo`, `netset`. The Chinese README has the full settings table.

Key healing settings: `heal` (`native` by default: use the game's own regeneration; `write`: the old per-tick HP write, kept as a fallback; `off`), `native_zone` (byte offset of the per-zone `RegenerationEnabled` flag, `0` = off until confirmed in game), `native_segments`, `native_force`.

## How it works
- It reuses DRIVER HUD / HUD's read-only native reader: the Health and Magazine/Rounds component layouts plus their code guards.
- It finds the shield by looking for resource `ed13ddc480ec6910` (the FX-12 generator) in the network entity table. `73f8498bffdcf415` is the generic hellpod, not the shield.
- Healing (v0.13) turns on the **game's own regeneration** in the per-unit `HealthComponent` config
  (`HealthChangerateDisabled = 0`, `HeathChangerate` / `RegenerationChangerate` = HP per second,
  `HeathChangerateCooldown` = `cooldown`; field layout from filediver's datalibrary). The config header is
  sanity-checked before any write, and the original values are written back when no authoritative vehicle
  is inside the shield. This is what replaced the v0.12 memory scan (and its stutter).
- Writes:
  - Health damage zones and ammo components are written with in-process `WriteProcessMemory`. The mod only writes `PAGE_READWRITE` pages, compares the old value before writing, and reads the value back afterwards.
  - Tank/FRV hull HP is written with `GameSession.set_game_object_field`, and only for objects this machine owns.
- While no shield is up, the mod only runs a light scan every 3 s and restores the config values.

## Healing details and limits
The game subtracts damage from its own saved copy of the HP, not from the value this mod writes. v0.12 hunted for
that copy by scanning memory (spread across frames, no freeze, but 15-20 s per vehicle and a re-scan every match).
v0.13 instead enables the game's built-in regeneration, so the game keeps both copies in sync and no scan is needed.

- The config is shared per unit resource, so it is only enabled while an authoritative vehicle of that type is
  inside the shield, and restored right after. During that time, other vehicles of the same type regenerate too.
- The per-zone regeneration flag offset is not confirmed in game yet, so `native_zone` defaults to `0` (off).
  Run `healcfg` and check the candidate offsets it logs.
- Details, field table and how to verify in game: [docs/回血原理.md](docs/回血原理.md) (Chinese).

## Risk
This mod **writes game memory**, which is riskier than a read-only HUD. Use it in private missions only, at your own risk. Healing only takes effect where your machine has authority, so it does little when you are a client in someone else's game.

## Build from source
```
python tools/build.py          # -> dist/ShieldVehicleResupply_<version>.zip
pip install lupa
python tests/svr_test.py         # offline test, heal=write fallback (LuaJIT + mocked memory)
python tests/native_heal_test.py # native regen: enable config / no HP write / restore on exit
python tests/native_guard_test.py# refuses to write when the config header does not look right
```

## License
MIT, see [LICENSE](LICENSE). The native reader in `src/vendor/` is by FireScallion (MIT). See [CREDITS.md](CREDITS.md).

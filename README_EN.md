# Shield Vehicle Resupply

[中文](README.md)

This is a Helldivers 2 Lua mod. While an **FX-12 Shield Generator** bubble is up, vehicles inside it are continuously repaired and resupplied:

| Vehicle | Repair | Ammo |
|---|---|---|
| EXO mechs (all 4, including arms) | ✅ | ✅ |
| Tanks (TD-220 Bastion / TD-110 Maelstrom) | ✅ hull + zones | ✅ |
| FRV | ✅ hull + zones | — |

Repair and resupply stop when the bubble goes away. The generator entity disappears at that point, about 42 s in-game.

`exo_weapon_guard=1` protects non-shield mech weapons before damage. Reaching 1 HP latches failure and saves/empties ammunition; repair must raise HP **strictly above 5%** to restore it. A weapon below 5% that has never reached 1 HP remains usable. Protection runs outside the bubble; ordinary repair still requires the bubble. The user reports that v0.19 retains all tested non-shield mech weapons; the EXO-49 [live test record](docs/v0.19实测记录.md) documents the HP and ammunition behavior. Its first fatal-damage sample briefly reached -1 HP before recovering to 1 HP, so this is not a strict per-frame clamp. See [weapon failure notes](docs/武器故障保护.md).

FRV tyres retain their models through prevention configuration and receive the native physical puncture transformation at 1 HP; recovery requires more than 5% (18 HP for a 350-HP tyre). Intact components must be discovered before fatal damage; detached models are not rebuilt. The user confirmed the full v0.21 tyre failure and repair cycle.

**v0.22** separates EXO-55 shield bash from flak ammunition. Either the shoulder (800 HP) or shield plate (5000 HP) reaching 1 HP clears only that shield entity's skill-input bit; each failed pool must exceed 5% to restore it. The flak cannon uses its own HP latch only. Offline regression passes; actual bash suppression and recovery still require in-game verification. See [tyre and shield notes](docs/轮胎与大盾保护.md) and [implementation notes](docs/v0.22独立盾击控制.md).

v0.19 corrects attachment parsing using a read-only capture from a running mech. The Attachable parent field contains the mech's full Unit handle; previous versions treated it as an entity ID, so protection never armed. The full handle now matches a known mech with current network identity and living authoritative Health. Logs include `parent`, `parent_unit` and `chain`. Confirm `weapon guard armed` before testing fatal damage.

## Install
1. Install [Bingus Shared Loader v17](https://www.nexusmods.com/helldivers2/mods/16292).
2. Download `ShieldVehicleResupply_<version>.zip` from [Releases](../../releases) and import it with your mod manager.

The mod targets the same game build as DRIVER HUD 1.4.5 / HUD 1.11.1 (Steam build 25480438). On any other build, the code-guard check fails and the mod disables itself **without writing memory**.

## Settings and commands
All files are in `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\`:
- `shield_resupply_settings.txt`: settings. The mod creates it on first run. Send `reload` after you edit it.
- `shield_resupply_cmd.txt`: commands, one per line. Each runs within 0.5 s.
- `ShieldVehicleResupply.log`: log and command output.

Commands: `status`, `on`, `off`, `reload`, `test`, `vehicles`, `parts`, `weapons`, `units`, `recent [n]`, `healcfg`, `hptrace [secs]`, `heal native|write|off`, `probe`, `netinfo`, `netset`. The Chinese README has the full settings table.

Key healing settings: `heal` (`native` by default: use the game's own regeneration; `write`: the old per-tick HP write, kept as a fallback; `off`), `native_zone` (`0x141` by default, confirmed by filediver's binary type library and guarded per part; `0` uses the old part HP writes), `part_regen` (default `1`), `native_segments`, `native_force`.

Use `parts` to list resource/zone hashes. Independently choose a part with `part=<16-digit resource hash>:<8-digit zone hash>=0|1`; entries override `part_regen`. Disabled parts are also excluded from the old HP-write fallback. Existing settings with `native_zone=0` need updating to `0x141` to try this feature.

## How it works
- It reuses DRIVER HUD / HUD's read-only native reader: the Health and Magazine/Rounds component layouts plus their code guards.
- It finds the shield by looking for resource `ed13ddc480ec6910` (the FX-12 generator) in the network entity table. `73f8498bffdcf415` is the generic hellpod, not the shield.
- Healing (v0.13) turns on the **game's own regeneration** in the per-unit `HealthComponent` config
  (`HealthChangerateDisabled = 0`, `HeathChangerate` / `RegenerationChangerate` = HP per second,
  `HeathChangerateCooldown` = `cooldown`; field layout from filediver's datalibrary). The config header is
  sanity-checked before any write, and the original values are written back when no authoritative vehicle
  is inside the shield. This is what replaced the v0.12 memory scan (and its stutter).
- Writes:
  - v0.15 enables each selected damage zone's own regeneration using the corrected +0x141 flag, including zones with nonpositive HP. Original flags are restored on exit, off, and reload; failed restores are retained for retries. The separate game repair and tyre interfaces are described below; real engine/model behavior remains unverified.
  - The old HP-write fallback and ammo components use in-process `WriteProcessMemory` on `PAGE_READWRITE` pages, with compare-before-write and readback checks.
  - Tank/FRV hull HP is written with `GameSession.set_game_object_field`, and only for objects this machine owns.
- Without a shield, the entity roster refreshes every 3 s and continuous regeneration settings are restored. When `exo_weapon_guard` is enabled, known weapons are checked about every 0.05 s. Engine repair may maintain a 1 HP floor outside the bubble; there is no continuous weapon regeneration there.

## Healing details and limits
The game subtracts damage from its own saved copy of the HP, not from the value this mod writes. v0.12 hunted for
that copy by scanning memory (spread across frames, no freeze, but 15-20 s per vehicle and a re-scan every match).
v0.13 instead enables the game's built-in regeneration, so the game keeps both copies in sync and no scan is needed.

- The config is shared per unit resource, so it is only enabled while an authoritative vehicle of that type is
  inside the shield, and restored right after. During that time, other vehicles of the same type regenerate too.
- The per-zone offset is confirmed by the upstream binary type library and checked against zone names, HP limits, neighboring booleans, floats and child-zone references, including a real FRV regression fixture. This does not prove that the game will regrow detached models or restore disabled physics actors. Dead/removed independent entities such as arms are not respawned.
- `parts` reports the configuration flag and healing event; configuration `regen=1` alone is not proof of successful repair. See [docs/部位再生.md](docs/部位再生.md) for the in-game experiment (Chinese).
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
python tests/part_regen_test.py   # all 38 parts / individual selection / layout and restore guards
python tests/exo_repair_test.py   # mech speed / upgraded arms / native attachment / death guards
python tests/weapon_fault_test.py# real weapon configs / failure hysteresis / ammo escrow and retries
python tests/shield_fault_test.py # real pools / independent bash and flak / identity / restore retries
python tests/tyre_fault_test.py  # captured wheel centres / puncture dispatch / restore and generation guards
```

## License
MIT, see [LICENSE](LICENSE). The native reader in `src/vendor/` is by FireScallion (MIT). See [CREDITS.md](CREDITS.md).

In v0.15, `part_repair=1` calls the game repair routine for destroyed zones of a living vehicle; it is skipped if any zone is disabled because the routine affects the whole unit. `tires=1` restores FRV tyre parameters through VehicleApi, at most one tyre per vehicle every `wheel_interval=2` seconds. Intact samples are learned by vehicle type and API index, including outside the shield. Spawn an intact FRV of the same type if the necessary sample is missing. Tyre visuals are not rebuilt. Selective tyres require API/Health index mappings learned from isolated damage; ambiguous mappings are skipped. Restart the game after replacing the package. Offline tests do not establish real game/physics behavior. See [repair notes](docs/部位修复与爆胎.md).

v0.16 adds `exo_leg_fix=1`: after the mech hull and all its zones are fully repaired, the exact 0.75 movement penalty is restored to 1.0. Mechs and independent arms use the game repair routine until fully healed, without simultaneous config regeneration or direct HP writes. Upgraded arm resources are now recognized. Zero-HP arms may be repaired only when still present, not engine-dead, authoritative, and attached through the native Attachable chain to a living authoritative mech. Dead, detached or removed arms are not rebuilt. Automated logs record mech zones, death states and zero-HP arm parents. Offline regression tests pass; real movement, arm models and weapon operation require in-game verification. See [mech repair notes](docs/机甲部位修复.md).

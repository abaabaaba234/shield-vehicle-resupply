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
2. Download `ShieldVehicleResupply.zip` from [Releases](../../releases) and import it with your mod manager.

The mod targets the same game build as DRIVER HUD 1.4.5 / HUD 1.11.1 (Steam build 25480438). On any other build, the code-guard check fails and the mod disables itself **without writing memory**.

## Settings and commands
All files are in `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\`:
- `shield_resupply_settings.txt`: settings. The mod creates it on first run. Send `reload` after you edit it.
- `shield_resupply_cmd.txt`: commands, one per line. Each runs within 0.5 s.
- `ShieldVehicleResupply.log`: log and command output.

Commands: `status`, `on`, `off`, `reload`, `test`, `vehicles`, `weapons`, `units`, `recent [n]`, `probe`, `netinfo`, `netset`. The Chinese README has the full settings table.

## How it works
- It reuses DRIVER HUD / HUD's read-only native reader: the Health and Magazine/Rounds component layouts plus their code guards.
- It finds the shield by looking for resource `ed13ddc480ec6910` (the FX-12 generator) in the network entity table. `73f8498bffdcf415` is the generic hellpod, not the shield.
- Writes:
  - Health and ammo components are written with in-process `WriteProcessMemory`. The mod only writes `PAGE_READWRITE` pages, compares the old value before writing, and reads the value back afterwards.
  - Tank/FRV hull HP is written with `GameSession.set_game_object_field`, and only for objects this machine owns.
- While no shield is up, the mod only runs a light scan every 3 s.

## Risk
This mod **writes game memory**, which is riskier than a read-only HUD. Use it in private missions only, at your own risk. Healing only takes effect where your machine has authority, so it does little when you are a client in someone else's game.

## Build from source
```
python tools/build.py          # -> dist/ShieldVehicleResupply.zip
pip install lupa
python tests/svr_test.py       # offline test (LuaJIT + mocked memory)
```

## License
MIT, see [LICENSE](LICENSE). The native reader in `src/vendor/` is by FireScallion (MIT). See [CREDITS.md](CREDITS.md).

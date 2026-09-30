# FRV regression fixture

`frv_health_filediver.bin` is the 0x5650-byte `HealthComponent` record for resource
`9b2140378640432e`, extracted from xypwn/filediver's public
[`generated_entities.dl_bin.gz`](https://github.com/xypwn/filediver/blob/master/datalibrary/generated_entities.dl_bin.gz)
on 2026-09-30 using the 64-bit offsets in
[`dl_library.dl_typelib.gz`](https://github.com/xypwn/filediver/blob/master/datalibrary/dl_library.dl_typelib.gz).

It contains 35 zones, main maximum 2400, four wheel maxima 350, a float at +0xFC,
ChildZones at +0x100, regeneration at +0x141 and a nonzero uint32 enum at +0x158.
The hand-written Go structure omits fields and must not be used to recompute
these offsets. This fixture reproduces the v0.14 layout-check failure.

The data is for offline regression testing and is not included in the mod package.

`exo49_health_filediver.bin` is the same-size record for EXO-49 resource
`c2d449ecf7facab1` from the same public dataset, extracted on 2026-09-30.
It contains main maximum 1800 and eight zones, including right leg `87b05ff4`
and left leg `64a3fa1d`, both maximum 550. It verifies full-repair prerequisites
against a real mech configuration; engine/model behavior is still mocked.
Game assets and identifiers belong to their respective owners. filediver is
BSD-3-Clause licensed; no upstream implementation code is included in this fixture.

`arm_health_e5f64dcc3bfe9dd1.bin` (EXO-49 left autocannon, zone `372f0418`)
and `arm_health_0736bee2d6328726.bin` (EXO-51 flamethrower, zone `aa1db0b0`)
are 0x5650-byte Health records from the same public dataset, extracted on
2026-09-30. Each has main maximum 800 and one independent 800-HP zone;
the zone has `AffectsMainHealth=0` and `CausesDeathOnDeath=1` before modification.
They exercise both known non-shield weapon zone layouts. The tests simulate
engine repair and weapon firing; they do not prove the game's exact immortal
clamp, model retention or suppression of continuous fire.

`attachable_live_v0.18.json` was captured read-only from the user's running
v0.18 game on 2026-10-01 using VM_READ and guarded component/network tables.
It contains six descriptors (one authoritative EXO-49 and its two arms,
plus three non-authoritative equivalents), Health summaries and each
Attachable row's first 12 bytes. World transforms and process addresses are
excluded. The row stride is 0xAC and the manager's row-pointer offset is +0x38.
Arms 551/552 contain parent 4194742, the full UnitReference of mech entity 550;
it is neither the parent's entity ID nor either child's UnitReference.
The regression replays these exact handles and row prefixes in the mock
component tables, with distinct entity IDs. It rejects generation changes,
stale/ambiguous candidates and changes during sampling. It verifies parent
association, not the engine's damage or firing behavior.

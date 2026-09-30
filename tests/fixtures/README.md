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
Game assets and identifiers belong to their respective owners. filediver is
BSD-3-Clause licensed; no upstream implementation code is included in this fixture.

"""Captured EXO-55 config, float32 integer heal and guarded StopEffect regressions.

Native calls are mocked; live visual confirmation requires installing v0.23.
"""
from pathlib import Path
import json
import struct

ROOT = Path(__file__).resolve().parents[1]
ns = {'__file__': str(ROOT / 'tests/exo_repair_test.py')}
source = (ROOT / 'tests/exo_repair_test.py').read_text()
exec(compile(source.split('\nmem, lua, cfg, rec, logs = fixture()', 1)[0], 'exo-harness', 'exec'), ns)
fixture, run, maps, Q, U, I, F, BASE, ROWS = (ns[k] for k in ('fixture', 'run', 'maps', 'Q', 'U', 'I', 'F', 'BASE', 'ROWS'))
EXO55 = '35dbf54f016f3624'
FXROOT, FX, FENTRIES, FOWNERS, FROWS, SETTINGS = BASE + 0x3326570, 0x58000000, 0x58001000, 0x58002000, 0x58003000, 0x59000000
LOOKUP = json.loads((ROOT / 'tests/fixtures/exo55_effect_lookup_live_v0.24.json').read_text())
assert LOOKUP['count'] == 0x560 == 1376 and LOOKUP['hits'][0]['slot'] == 676
ECFG = SETTINGS + 0x5600 + LOOKUP['hits'][0]['index'] * 0xf48
DESC = 0x20000000 + 0xf32f18
CODE = json.loads((ROOT / 'tests/fixtures/exo_leg_effect_native_v0.23.json').read_text())['spans']


def hp(mem, at):
    return struct.unpack('<i', mem.r(at, 4))[0]


def f32(value):
    return struct.unpack('<f', F(value))[0]


def make():
    mem, lua, cfg, rec, logs = fixture(EXO55, 'exo55_health_live_v0.23.bin')
    for span in CODE:
        mem.w(BASE + span['rva'], bytes.fromhex(span['hex']))
    mem.w(FXROOT, Q(FX)); maps(mem, FX + 0x20, FENTRIES, [(100, 0), (101, 1)])
    mem.w(FX + 0x38, Q(FOWNERS)); mem.w(FOWNERS, Q(DESC) + Q(DESC + 24))
    mem.w(DESC + 24, Q(int(EXO55, 16)) + U(101) + U(8) + U(51) + U(1))
    mem.w(FX + 0x48, Q(FROWS)); mem.w(FROWS, bytes(0x218 * 2))
    # Captured left leg fire handle; preserve other particle slots and another mech.
    mem.w(FROWS + 4 * 4, U(18347)); mem.w(FROWS + 0x218 + 4 * 4, U(22222))
    mem.w(FROWS + 3 * 4, U(33333))
    mem.w(0x20000000 + 0xf127b8, Q(SETTINGS))
    # Replay the actual runtime table and its native index, rather than
    # constructing a table using the same arithmetic as the implementation.
    mem.w(SETTINGS, (ROOT / 'tests/fixtures/exo55_effect_table_live_v0.24.bin').read_bytes())
    mem.w(ECFG, (ROOT / 'tests/fixtures/exo55_effect_live_v0.24.bin').read_bytes())
    r = lua.eval(b'SVR.R'); r.next_check = 0
    assert r.ensure(3) and r.effects is not None, r.effects_status
    lua.execute(b'''
      sim_effect_calls=0
      local original=SVR.R.invoke
      SVR.R.invoke=function(name,address,manager,entity,effect,node,replicate,queued)
        if name~='effect_stop' then return original(name,address,manager,entity,effect) end
        assert(address==0x1408abb20 and tonumber(require('ffi').cast('uintptr_t',manager))==0x58000000)
        assert(entity==100 and (effect==0xa1d3345e or effect==0x4a3fa896))
        assert(node==0 and replicate==1 and queued==false)
        sim_effect_calls=sim_effect_calls+1; pystop(effect,sim_fail_effect==true)
      end
    ''')

    def stop(name, failed):
        if not failed:
            slot = 4 if name == 0xa1d3345e else 5
            mem.w(FROWS + slot * 4, U(0))

    def game_heal(fraction):
        # Native cvttss2si truncates float32(current HP + max HP * fraction).
        fraction = f32(fraction)
        for i in range(8):
            maximum = hp(mem, cfg + 0x208 + i * 0x228 + 0xe8)
            at = rec + 0xf8 + i * 4
            mem.w(at, I(min(maximum, int(f32(hp(mem, at) + f32(maximum * fraction))))))
        mem.w(rec + 0x20, U(0))

    lua.globals()[b'pystop'] = stop
    lua.globals()[b'pyheal'] = game_heal
    return mem, lua, cfg, rec, logs


mem, lua, cfg, rec, logs = make()
other = mem.r(FROWS + 0x218, 0x218)
run(lua)
assert mem.r(ROWS, 4) == F(1) and hp(mem, FROWS + 16) == 0
assert hp(mem, FROWS + 12) == 33333 and mem.r(FROWS + 0x218, 0x218) == other
assert lua.eval(b'sim_effect_calls') == lua.eval(b'SVR.R.leg_fires_stopped') == 1
run(lua); assert lua.eval(b'sim_effect_calls') == 1
assert 'exo leg fire stopped' in (logs / 'ShieldVehicleResupply.log').read_text(encoding='utf-8')
print('PASS: captured left leg fire is stopped once; hull effect and second mech are preserved')

mem, lua, cfg, rec, logs = make()
mem.w(ROWS, F(1)); mem.w(FROWS + 20, U(44444))
run(lua)
assert hp(mem, FROWS + 16) == hp(mem, FROWS + 20) == 0
assert lua.eval(b'sim_speed_writes') == 0 and lua.eval(b'sim_effect_calls') == 2
print('PASS: both leg fires are stopped when speed is already normal')

for why in ('damaged leg', 'damaged small zone', 'damaged hull', 'destroyed state', 'disabled part',
            'disabled fix', 'non-authority', 'dead', 'no shield', 'cooldown', 'wrong owner',
            'wrong resource', 'wrong node', 'wrong strategy', 'duplicate name', 'missing settings', 'missing row'):
    mem, lua, cfg, rec, logs = make()
    if why == 'damaged leg': mem.w(rec + 0xf8 + 5*4, I(549))
    elif why == 'damaged small zone': mem.w(rec + 0xf8 + 6*4, I(0))
    elif why == 'damaged hull': mem.w(rec + 0x14, I(1799))
    elif why == 'destroyed state': mem.w(rec + 0x20, U(2 * 4**6))
    elif why == 'disabled part': lua.execute(b"SVR.C.part['35dbf54f016f3624:64a3fa1d']=false")
    elif why == 'disabled fix': lua.execute(b'SVR.C.exo_leg_fix=false')
    elif why == 'non-authority': mem.w(DESC + 20, U(0))
    elif why == 'dead': mem.w(rec + 0x19c, U(1))
    elif why == 'no shield': lua.execute(b'SVR.C.test=false')
    elif why == 'cooldown':
        lua.execute(b'SVR.C.exo_leg_fix=false'); run(lua, 10)
        lua.execute(b"SVR.C.exo_leg_fix=true; SVR.C.cooldown=100; SVR.S.last_hit['100:50']=SVR.S.clock")
    elif why == 'wrong owner': mem.w(FOWNERS, Q(DESC + 24))
    elif why == 'wrong resource': mem.w(ECFG + 8 + 4*80, Q(42))
    elif why == 'wrong node': mem.w(ECFG + 8 + 4*80 + 32, U(42))
    elif why == 'wrong strategy': mem.w(ECFG + 8 + 4*80 + 68, U(1))
    elif why == 'duplicate name': mem.w(ECFG + 8 + 5*80 + 48, U(0xa1d3345e))
    elif why == 'missing settings': mem.w(SETTINGS + LOOKUP['hits'][0]['slot'] * 16, bytes(16))
    elif why == 'missing row': maps(mem, FX + 0x20, FENTRIES, [])
    run(lua)
    assert lua.eval(b'sim_effect_calls') == 0 and hp(mem, FROWS + 16) == 18347, why
print('PASS: health, selection, authority, identity, range, cooldown and particle configuration gate native cleanup')

for why in ('rows moved', 'owner moved', 'effect config moved', 'new damage', 'authority changed'):
    mem, lua, cfg, rec, logs = make()
    original, injected = mem.r, [False]

    def changing_read(a, n):
        if a == FROWS + 16 and n == 4 and not injected[0]:
            injected[0] = True
            if why == 'rows moved': mem.w(FX + 0x48, Q(FROWS + 0x1000))
            elif why == 'owner moved': mem.w(FOWNERS, Q(DESC + 24))
            elif why == 'effect config moved': mem.w(SETTINGS + LOOKUP['hits'][0]['slot'] * 16 + 8, U(3))
            elif why == 'new damage': mem.w(rec + 0xf8 + 5*4, I(100))
            elif why == 'authority changed': mem.w(DESC + 20, U(0))
        return original(int(a), int(n))

    lua.globals()[b'pyread'] = changing_read
    run(lua, 6)
    assert lua.eval(b'sim_effect_calls') == 0, why
print('PASS: identity/configuration/health changes during sampling prevent native effect calls')

mem, lua, cfg, rec, logs = make()
lua.execute(b'sim_fail_effect=true'); run(lua)
assert lua.eval(b'SVR.R.leg_fires_stopped') == 0 and hp(mem, FROWS + 16) == 18347
lua.execute(b'sim_fail_effect=false'); run(lua)
assert lua.eval(b'SVR.R.leg_fires_stopped') == 1 and hp(mem, FROWS + 16) == 0
print('PASS: failed native stop is not counted and is retried with fresh ownership')

for span in CODE:
    mem, lua, cfg, rec, logs = make()
    r = lua.eval(b'SVR.R'); mem.w(BASE + span['rva'], b'\x90'); r.next_check = 0
    assert r.ensure(4) and r.effects is None and r.health is not None and r.stats is not None
    run(lua)
    assert lua.eval(b'sim_effect_calls') == 0 and mem.r(ROWS, 4) == F(1)
print('PASS: each reviewed StopEffect code guard fails independently; health/speed interfaces remain available')

mem, lua, cfg, rec, logs = make()
lua.execute(b'SVR.C.part_repair=true; SVR.C.exo_heal=0.04')
mem.w(rec + 0xf8 + 6*4, I(0)); mem.w(rec + 0xf8 + 7*4, I(0)); mem.w(rec + 0x20, U(0xa000))
run(lua, 20)
assert hp(mem, rec + 0xf8 + 6*4) == 0 and lua.eval(b'sim_calls.heal') == 0
run(lua, 5)
assert hp(mem, rec + 0xf8 + 6*4) == hp(mem, rec + 0xf8 + 7*4) == 1
assert mem.r(ROWS, 4) == F(.75) and lua.eval(b'sim_effect_calls') == 0
run(lua, 225)
assert hp(mem, rec + 0xf8 + 6*4) == hp(mem, rec + 0xf8 + 7*4) == 10
assert lua.eval(b'sim_calls.heal') == 10, 'integer pools healed faster/slower than 4% per second'
run(lua, 5)
assert mem.r(ROWS,4) == F(1) and hp(mem,FROWS+16) == 0
print('PASS: default 4%/s repairs 10-HP pools in 25 seconds; movement/fire cleanup follows full recovery')

for why in ('left shield', 'reload', 'repair disabled', 'part disabled', 'rate changed', 'cooldown gap', 'Unit generation changed'):
    mem, lua, cfg, rec, logs = make()
    lua.execute(b'SVR.C.part_repair=true; SVR.C.exo_heal=0.04')
    mem.w(rec + 0xf8 + 6*4, I(0)); run(lua, 20)
    if why == 'left shield':
        lua.execute(b'SVR.C.test=false'); run(lua, 5); lua.execute(b'SVR.C.test=true')
    elif why == 'reload':
        (logs/'shield_resupply_cmd.txt').write_text('reload\n'); run(lua, 5)
        lua.execute(b'SVR.C.part_repair=true; SVR.C.exo_heal=0.04; SVR.C.test=true; SVR.C.cooldown=0')
    elif why == 'repair disabled':
        lua.execute(b'SVR.C.part_repair=false'); run(lua, 5); lua.execute(b'SVR.C.part_repair=true')
    elif why == 'part disabled':
        lua.execute(b"SVR.C.part['35dbf54f016f3624:2be9516e']=false"); run(lua,5)
        lua.execute(b"SVR.C.part['35dbf54f016f3624:2be9516e']=nil")
    elif why == 'rate changed': lua.execute(b'SVR.C.exo_heal=0.02')
    elif why == 'cooldown gap':
        lua.execute(b"SVR.C.cooldown=100; SVR.S.last_hit['100:50']=SVR.S.clock"); run(lua,5)
        lua.execute(b'SVR.C.cooldown=0')
    elif why == 'Unit generation changed': mem.w(DESC+12,U(7+0x400000)); lua.execute(b'SVR.S.next_roster=0')
    run(lua, 5)
    assert hp(mem, rec + 0xf8 + 6*4) == 0, why
    credit = lua.eval(b'SVR.S.vehicles[1].repair_credit.fraction')
    assert 0 < credit < .025, (why, credit)
print('PASS: fractional credit is discarded across range/reload/settings/cooldown/Unit identity boundaries')

"""Part regeneration integration tests: real LuaJIT addon, mocked process memory.

These verify ownership of configuration writes, NOT the game's model/physics repair.
Run after python tools/build.py: python tests/part_regen_test.py
"""
import os
from pathlib import Path
import struct
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
setup = (ROOT / 'tests/svr_test.py').read_text(encoding='utf-8').split("L.execute(b'for i=1,40", 1)[0]
setup = setup.replace('_G.SVR={N=N,W=W,S=S,C=C}', """
  C.heal='native'
  C.native_force=false
  W.raw=function(p,n,oldraw,newraw)
    if fail_at == p or N.win.read(p,n)~=oldraw then return false end
    pywrite(p,newraw); W.writes=W.writes+1; return true
  end
  W.raw4=function(p,o,n) return W.raw(p,4,o,n) end
  W.raw1=function(p,o,n) return W.raw(p,1,o,n) end
  W.prot=function() return 4 end
  _G.SVR={N=N,W=W,S=S,C=C}
""")


def scenario(name, zones=2):
    tmp = tempfile.mkdtemp(prefix='.run-parts-', dir=ROOT / 'tests')
    os.environ['LOCALAPPDATA'] = tmp
    logs = Path(tmp) / 'CowboyBingus/Helldivers2/Logs'
    logs.mkdir(parents=True)
    env = {'__file__': str(ROOT / 'tests/svr_test.py')}
    exec(compile(setup, 'part-regen-harness', 'exec'), env)
    mem, lua, cfg, rec = (env[k] for k in ('M', 'L', 'cfg', 'rec'))
    # Use the full 38-part configuration, including parts beyond the old 16-bit pairs.
    for i in range(zones):
        base = cfg + 0x208 + i * 0x228
        mem.w(base, bytes(0x228))
        mem.w(base + 0x60, struct.pack('<I', 0xA0000000 + i))
        mem.w(base + 0xE8, struct.pack('<i', 400))
        mem.w(rec + 0xF8 + 4 * i, struct.pack('<i', -40 if i % 2 else 100))
        # Valid but nonzero neighbors catch accidental writes to the bool-run start.
        mem.w(base + 0x13C, b'\1\0\1\1')
    return mem, lua, cfg, rec, logs


def run(lua, n=40):
    lua.execute(('for i=1,%d do update(0.1) end' % n).encode())
    assert lua.eval(b'SVR.S.errors') is None, 'tick error'


def flag(cfg, i):
    return cfg + 0x208 + i * 0x228 + 0x13D


def command(lua, logs, text):
    (logs / 'shield_resupply_cmd.txt').write_text(text, encoding='utf-8')
    run(lua, 10)


mem, lua, cfg, rec, logs = scenario('38 parts', 38)
before = mem.r(rec, 0x1B8)
run(lua)
assert mem.r(rec, 0x1B8) == before, 'native path wrote health/state directly'
for i in range(38):
    assert mem.r(flag(cfg, i) - 1, 4) == b'\1\1\1\1', i
command(lua, logs, 'parts\n')
log = (logs / 'ShieldVehicleResupply.log').read_text(encoding='utf-8')
assert 'i=37' in log and 'regen=1' in log
lua.execute(b'SVR.C.test=false')
run(lua, 10)
for i in range(38):
    assert mem.r(flag(cfg, i) - 1, 4) == b'\1\0\1\1', i
print('PASS: all 38 parts, destroyed HP preserved, neighbors and originals restored')

mem, lua, cfg, rec, logs = scenario('unresolved shield position')
run(lua, 10)
lua.execute(b'SVR.C.test=false; SVR.S.next_roster=1000; SVR.S.shields={SVR.S.vehicles[1].d}')
run(lua, 10)
assert mem.r(flag(cfg, 0), 1) == mem.r(flag(cfg, 1), 1) == b'\0'
print('PASS: unresolved shield position closes previously used configuration')

mem, lua, cfg, rec, logs = scenario('shared maximum')
mem.w(cfg + 0x208 + 0xE8, struct.pack('<i', -1))
run(lua, 10)
assert mem.r(flag(cfg, 0), 1) == b'\1'
print('PASS: zones with maximum -1 use the main health maximum')

mem, lua, cfg, rec, logs = scenario('individual control')
mem.w(flag(cfg, 0), b'\1')  # Original engine behavior must be restored too.
(logs / 'shield_resupply_settings.txt').write_text(
    'test=1\nheal=native\nnative_zone=0x13d\npart_regen=0\n'
    'part=35dbf54f016f3624:a0000001=1\n'
    'part=35dbf54f016f3624:a0000000=0\n'
    'part=79e4b3d2da5e45e3:a0000001=0\n', encoding='utf-8')
before = mem.r(rec, 0x1B8)
command(lua, logs, 'reload\n')
assert mem.r(flag(cfg, 0), 1) == b'\0'
assert mem.r(flag(cfg, 1), 1) == b'\1'
assert mem.r(rec, 0x1B8) == before, 'disabled part bypassed via HP writes'
# Changing the setting must restore at the ORIGINAL address, then use the new setting.
(logs / 'shield_resupply_settings.txt').write_text('test=1\nheal=native\nnative_zone=0\n', encoding='utf-8')
command(lua, logs, 'reload\n')
assert mem.r(flag(cfg, 0), 1) == b'\1'
assert mem.r(flag(cfg, 1), 1) == b'\0'
assert mem.r(flag(cfg, 1) - 0x13D, 1) == b'\0', 'restored to the new offset'
assert lua.eval(b'next(SVR.C.part)') is None, 'removed per-part settings persisted'
print('PASS: independent policies scoped by vehicle hash, reload/removal/offset changes')

for field, raw in ((0xF0, b'\2'), (0xF8, struct.pack('<f', float('nan'))),
                   (0xFC, struct.pack('<I', 0xDEADBEEF)), (0x13D, b'\2')):
    mem, lua, cfg, rec, logs = scenario('bad zone')
    p = cfg + 0x208 + field
    mem.w(p, raw)
    original = mem.r(flag(cfg, 0), 1)
    run(lua)
    assert mem.r(flag(cfg, 0), 1) == original, hex(field)
    assert mem.r(p, len(raw)) == raw
    assert mem.r(flag(cfg, 1), 1) == b'\1', 'unrelated valid part blocked'
print('PASS: invalid bool, NaN, child hash and regeneration flag rejected per part')

for why in ('not authoritative', 'dead'):
    mem, lua, cfg, rec, logs = scenario(why)
    if why == 'dead':
        mem.w(rec + 0x14, struct.pack('<i', 0))
    else:
        mem.w(0x20000000 + 0xF32F18 + 20, struct.pack('<I', 0))
    original = mem.r(cfg, 0x5650)
    run(lua)
    assert mem.r(cfg, 0x5650) == original
print('PASS: dead vehicles and non-authoritative components do not open regeneration')

mem, lua, cfg, rec, logs = scenario('write retry')
lua.globals()[b'fail_at'] = flag(cfg, 1)
run(lua, 10)
assert mem.r(flag(cfg, 1), 1) == b'\0'
lua.globals()[b'fail_at'] = None
run(lua, 10)
assert mem.r(flag(cfg, 1), 1) == b'\1'
command(lua, logs, 'off\n')
assert mem.r(flag(cfg, 0), 1) == mem.r(flag(cfg, 1), 1) == b'\0'
print('PASS: failed flag write retried, off restores successful writes')

mem, lua, cfg, rec, logs = scenario('restore retry')
run(lua, 10)
lua.globals()[b'fail_at'] = flag(cfg, 1)
command(lua, logs, 'off\n')
assert mem.r(flag(cfg, 1), 1) == b'\1'
lua.globals()[b'fail_at'] = None
run(lua, 20)
assert mem.r(flag(cfg, 1), 1) == b'\0', 'failed restoration was forgotten'
print('PASS: failed restoration retained and retried while mod is off')

mem, lua, cfg, rec, logs = scenario('header write failure')
lua.globals()[b'fail_at'] = cfg + 0x14
run(lua, 10)
assert mem.r(flag(cfg, 0), 1) == mem.r(flag(cfg, 1), 1) == b'\0'
lua.globals()[b'fail_at'] = None
run(lua, 10)
assert mem.r(flag(cfg, 0), 1) == mem.r(flag(cfg, 1), 1) == b'\1'
print('PASS: part flags wait for successful component regeneration setup')

mem, lua, cfg, rec, logs = scenario('external changes')
run(lua, 10)
mem.w(flag(cfg, 0), b'\2')  # Engine/another addon changed this field.
mem.w(cfg + 0x208 + 0x228 + 0x60, struct.pack('<I', 0xB0000001))
command(lua, logs, 'off\n')
assert mem.r(flag(cfg, 0), 1) == b'\2'
assert mem.r(flag(cfg, 1), 1) == b'\1', 'restored a different zone identity'
print('PASS: restore preserves external changes and checks zone identity')

mem, lua, cfg, rec, logs = scenario('unsupported offset')
lua.execute(b'SVR.C.native_zone=0x13c')
original = mem.r(flag(cfg, 0) - 1, 4)
run(lua, 10)
assert mem.r(flag(cfg, 0) - 1, 4) == original
assert 'unsupported offset' in (logs / 'ShieldVehicleResupply.log').read_text(encoding='utf-8')
print('PASS: unsupported offset does not modify neighboring flags')

mem, lua, cfg, rec, logs = scenario('write fallback policy')
lua.execute(b"SVR.C.heal='write'; SVR.C.part['35dbf54f016f3624:a0000000']=false")
run(lua)
assert struct.unpack('<i', mem.r(rec + 0x14, 4))[0] == 1800
assert struct.unpack('<i', mem.r(rec + 0xF8, 4))[0] == 100
assert struct.unpack('<i', mem.r(rec + 0xFC, 4))[0] == -40
print('PASS: write fallback still heals the vehicle and honors disabled parts')

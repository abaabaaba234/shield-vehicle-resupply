"""Execute the actual addon with guarded native interfaces and mocked engine calls.

Validates dispatch, handles, selection, cooldown and tyre restoration. This does
not emulate or establish real engine/model behavior. Build before running.
"""
from pathlib import Path
import math
import os
import struct
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
BASE = 0x140000000
FRV = '9b2140378640432e'
Q = lambda n: struct.pack('<Q', n)
U = lambda n: struct.pack('<I', n)
I = lambda n: struct.pack('<i', n)
SETUP = (ROOT / 'tests/svr_test.py').read_text(encoding='utf-8').split("L.execute(b'for i=1,40", 1)[0]
SETUP = SETUP.replace('__SVR_TEST=function(N,W,S,C)', '__SVR_TEST=function(N,W,S,C,R,F)')
SETUP = SETUP.replace('_G.SVR={N=N,W=W,S=S,C=C}', '''
  C.heal='native'; C.part_repair=false; C.tires=false; C.exo_weapon_guard=false
  W.raw=function(p,n,o,v) if N.win.read(p,n)~=o then return false end; pywrite(p,v); return true end
  W.raw4=function(p,o,v) return W.raw(p,4,o,v) end
  W.raw1=function(p,o,v) return W.raw(p,1,o,v) end
  W.prot=function() return 4 end
  _G.SVR={N=N,W=W,S=S,C=C,R=R,F=F}
''')


def make():
    tmp = tempfile.mkdtemp(prefix='.run-repair-', dir=ROOT / 'tests')
    os.environ['LOCALAPPDATA'] = tmp
    logs = Path(tmp) / 'CowboyBingus/Helldivers2/Logs'
    logs.mkdir(parents=True)
    old = sys.argv
    sys.argv = [__file__, FRV]
    env = {'__file__': str(ROOT / 'tests/svr_test.py')}
    try:
        exec(compile(SETUP, 'repair-native-harness', 'exec'), env)
    finally:
        sys.argv = old
    mem, lua, cfg, rec = (env[k] for k in ('M', 'L', 'cfg', 'rec'))
    mem.w(cfg, (ROOT / 'tests/fixtures/frv_health_filediver.bin').read_bytes())
    for i in range(35):
        zmax = struct.unpack('<i', mem.r(cfg + 0x208 + i * 0x228 + 0xE8, 4))[0]
        mem.w(rec + 0xF8 + i * 4, I(2400 if zmax == -1 else zmax))
    lua.execute(b'SVR.N.ensure(); svr_d={resource="9b2140378640432e",entity=100,unit=7,goid=50,flags=1}')
    r = lua.eval(b'SVR.R')
    assert not r.ensure(0), 'missing code guards accepted'

    for name in (b'heal', b'wheel'):
        sig = r.signatures[name]
        raw = bytes(0 if t == '??' else int(t, 16) for t in sig[2].decode().split())
        mem.w(BASE + sig[1], raw)

    def rel(at, target, displacement=3, length=7):
        mem.w(at + displacement, I(target - at - length))

    hp, wh, hf = BASE + 0x4B9B50, BASE + 0x11A8490, BASE + 0x91E920
    rel(hp + 9, BASE + 0x3326688)
    mem.w(hp + 0xA1, b'\xe9')
    rel(hp + 0xA1, hf, 1, 5)
    mem.w(hf, bytes.fromhex('488bc448895810'))
    mem.w(hf + 0xBB, bytes.fromhex('498bcc'))
    mem.w(hf + 0xC2, b'\xe8' + bytes(4))
    mem.w(hf + 0xCB, bytes.fromhex('4d69edb8010000'))
    mem.w(wh + 0xB3, bytes.fromhex('4c8b0d') + bytes(4))
    rel(wh + 0xB3, BASE + 0x3326310)
    mem.w(wh + 0xBA, bytes.fromhex('4c8d4424508b4b0cba10000000'))
    mem.w(wh + 0xCD, bytes.fromhex('488b4c2470'))
    mem.w(wh + 0xEB, bytes.fromhex('488b05') + bytes(4))
    rel(wh + 0xEB, BASE + 0x3326320)
    mem.w(wh + 0x114, bytes.fromhex('488b05') + bytes(4))
    rel(wh + 0x114, BASE + 0x3326320)
    mem.w(wh + 0xFC, bytes.fromhex('ff5040'))
    mem.w(wh + 0x173, bytes.fromhex('ff5048'))
    query, get, setter = BASE + 0x100000, BASE + 0x200000, BASE + 0x200200
    mem.w(query, b'\xc3'); mem.w(setter, b'\xc3')
    mem.w(BASE + 0x3326310, Q(0x51000000)); mem.w(0x51000000, Q(query))
    mem.w(BASE + 0x3326320, Q(0x51001000))
    mem.w(0x51001040, Q(get)); mem.w(0x51001048, Q(setter))
    mem.w(get, bytes.fromhex('48895c2408574883ec308bc14c8d0d') + bytes(4))
    rel(get + 0xC, BASE + 0x3330000)
    mem.w(BASE + 0x3330008, Q(0x52000000))
    mem.w(0x52000000, bytes(0x38)); mem.w(0x52000000, Q(0x52001000))
    mem.w(0x5200001C, U(0x10000080))
    mem.w(0x52000024, U(2)); mem.w(0x52000028, U(0x3FFFFFFF)); mem.w(0x52000034, U(0x40000000))
    mem.w(0x52001080, U(0x40000001)); mem.w(0x520010B0, Q(0x52002000))
    mem.w(0x5200200C, U(0x100)); mem.w(0x52002100, U(0x20575256) + U(4))
    mem.w(0x53000000, U(0x40000001))
    r.next_check = 0
    assert r.ensure(1) and r.health is not None and r.wheels is not None
    samples = [struct.pack('<10f', *([0.4 + 0.05 * i] * 10)) + bytes(8) for i in range(4)]
    wheels = lua.table_from({i: sample for i, sample in enumerate(samples)})
    lua.globals()[b'sim_wheels'] = wheels
    lua.globals()[b'sim_handle_ptr'] = Q(0x53000000)

    def heal(frac):
        for i in range(35):
            at = rec + 0xF8 + i * 4
            hpv = struct.unpack('<i', mem.r(at, 4))[0]
            zm = struct.unpack('<i', mem.r(cfg + 0x208 + i * 0x228 + 0xE8, 4))[0]
            zm = 2400 if zm == -1 else zm
            if zm > 0:
                mem.w(at, I(min(zm, max(0, hpv) + math.ceil(zm * frac))))
        mem.w(rec + 0x20, U(0))

    lua.globals()[b'pyheal'] = heal
    lua.execute(b'''
    sim_calls={heal=0,query=0,get=0,set=0}
    SVR.R.invoke=function(name,address,a,b,buffer)
      local ffi=require('ffi')
      sim_calls[name]=sim_calls[name]+1
      if name=='query' then
        assert(a==7 and b==16)
        ffi.copy(ffi.cast('uint8_t *',buffer)+0x20,sim_handle_ptr,8)
        return 1
      elseif name=='get' then
        assert(a==0x40000001 and b>=0 and b<4)
        ffi.copy(buffer,sim_wheels[b],48); return 1
      elseif name=='set' then
        assert(a==0x40000001)
        if not sim_fail_set then sim_wheels[b]=ffi.string(buffer,48) end
        return 1
      elseif name=='heal' then
        assert(b==100 and buffer>0 and buffer<=1)
        pyheal(buffer)
      else error('unexpected native call') end
    end
    ''')
    return mem, lua, cfg, rec, logs, samples


def blow(lua, index):
    s = lua.globals()[b'sim_wheels'][index]
    lua.globals()[b'sim_wheels'][index] = struct.pack('<10f', *([0.1] * 10)) + b'\1' + s[41:]


def run(lua, n=30):
    lua.execute(('for i=1,%d do update(0.1) end' % n).encode())
    assert lua.eval(b'SVR.S.errors') is None


mem, lua, cfg, rec, logs, samples = make()
r, d = lua.eval(b'SVR.R'), lua.globals()[b'svr_d']
assert r.learn(d)
assert r.cache[FRV.encode()].complete
blow(lua, 0); blow(lua, 1)
assert r.repair_wheel(d, lua.table_from({0: False, 1: True, 2: True, 3: True}))
assert lua.globals()[b'sim_wheels'][0][40] == 1, 'disabled wheel repaired'
assert lua.globals()[b'sim_wheels'][1] == samples[1]
assert lua.eval(b'sim_calls.set') == 1
assert r.repair_wheel(d, lua.table_from({0: True}))
assert lua.globals()[b'sim_wheels'][0] == samples[0]
print('PASS: validated interfaces, per-position intact parameters restored, disabled wheel preserved')

blow(lua, 2)
lua.execute(b'sim_fail_set=true')
fixed = r.fixed
done, reason = r.repair_wheel(d, lua.table_from({2: True}))
assert done is False and reason == b'tyre setter readback failed' and r.fixed == fixed
lua.execute(b'sim_fail_set=false')
assert r.repair_wheel(d, lua.table_from({2: True}))
print('PASS: setter result verified by getter; failed restoration is not reported as success')

mem, lua, cfg, rec, logs, samples = make()
r, d = lua.eval(b'SVR.R'), lua.globals()[b'svr_d']
# The wheel getter and its handle table can belong to the engine executable.
exe, getter, setter = 0x180000000, 0x180200000, 0x180200200
r.exe = lua.table_from({b'base': exe, b'size': 0x4000000})
mem.w(0x51001040, Q(getter)); mem.w(0x51001048, Q(setter))
mem.w(getter, bytes.fromhex('48895c2408574883ec308bc14c8d0d') + I(exe + 0x3330000 - getter - 0x13))
mem.w(setter, b'\xc3'); mem.w(exe + 0x3330008, Q(0x52000000))
assert r.learn(d)
blow(lua, 0)
assert r.repair_wheel(d, lua.table_from({0: True}))
assert lua.globals()[b'sim_wheels'][0] == samples[0]
print('PASS: engine-executable getter and relative handle table supported within validated module bounds')

for why in ('not authoritative', 'dead vehicle', 'stale handle', 'wrong wheel count', 'outside function', 'getter guard'):
    mem, lua, cfg, rec, logs, samples = make()
    r, d = lua.eval(b'SVR.R'), lua.globals()[b'svr_d']
    assert r.learn(d)
    blow(lua, 0)
    if why == 'not authoritative': mem.w(0x20000000 + 0xF32F18 + 20, U(0))
    elif why == 'dead vehicle': mem.w(rec + 0x19C, U(1))
    elif why == 'stale handle': mem.w(0x52001080, U(0x40000002))
    elif why == 'wrong wheel count': mem.w(0x52002104, U(5))
    elif why == 'outside function': mem.w(0x51001048, Q(0x51004000))
    elif why == 'getter guard': mem.w(BASE + 0x200000, b'\x90')
    lua.execute(b"sim_ok,sim_error=pcall(SVR.R.repair_wheel,svr_d,{[0]=true})")
    assert lua.globals()[b'sim_ok'] is False, why
    assert lua.eval(b'sim_calls.set') == 0, why
print('PASS: authority, death, handle generation, wheel count and function guards prevent setters')

mem, lua, cfg, rec, logs, samples = make()
r, d = lua.eval(b'SVR.R'), lua.globals()[b'svr_d']
blow(lua, 0)
assert r.learn(d)
done, reason = r.repair_wheel(d, lua.table_from({0: True}))
assert done is False and b'missing intact sample' in reason
assert lua.eval(b'sim_calls.set') == 0
lua.globals()[b'sim_wheels'][0] = samples[0]
assert r.learn(d)
blow(lua, 0)
assert r.repair_wheel(d, lua.table_from({0: True}))
r.reset()
assert r.cache[FRV.encode()] is None
print('PASS: missing samples skipped, late intact sample learned, session reset clears sample cache')

mem, lua, cfg, rec, logs, samples = make()
lua.execute(b'SVR.C.part_repair=true; SVR.C.tires=true; SVR.C.frv_heal=0.05')
run(lua, 10)  # Learn intact tyres before damage.
blow(lua, 0); blow(lua, 1)
mem.w(rec + 0xF8, I(-20)); mem.w(rec + 0x20, U(2))
run(lua, 10)
assert lua.eval(b'sim_calls.heal') > 0
assert struct.unpack('<i', mem.r(rec + 0xF8, 4))[0] > 0
assert lua.eval(b'sim_calls.set') <= 1, 'multiple tyres repaired in one interval'
run(lua, 45)
assert lua.globals()[b'sim_wheels'][0] == samples[0] and lua.globals()[b'sim_wheels'][1] == samples[1]
print('PASS: addon integration dispatches game repair and restores tyres one per interval')

mem, lua, cfg, rec, logs, samples = make()
lua.execute(b'SVR.C.part_repair=true; SVR.C.tires=true')
run(lua, 10)
lua.execute(b"SVR.C.part['9b2140378640432e:fed0a478']=false")
blow(lua, 2)  # Deliberately different API/health indices: health front-left 0 -> API 2.
mem.w(rec + 0xF8, I(-20)); mem.w(rec + 0x20, U(2))
run(lua, 10)
blow(lua, 3)
mem.w(rec + 0xFC, I(-20)); mem.w(rec + 0x20, U(10))
run(lua, 35)
assert lua.eval(b'sim_calls.heal') == 0, 'whole-unit call bypassed disabled part'
assert lua.globals()[b'sim_wheels'][2][40] == 1 and lua.globals()[b'sim_wheels'][3][40] == 0
assert lua.eval(b"SVR.R.maps['9b2140378640432e'][2]") == b'fed0a478'
assert lua.eval(b"SVR.R.maps['9b2140378640432e'][3]") == b'f3cb00ad'
print('PASS: differing API/health indices learned, disabled parts preserved, selected tyres restored')

mem, lua, cfg, rec, logs, samples = make()
lua.execute(b'SVR.C.part_repair=true; SVR.C.tires=true')
run(lua, 10)
lua.execute(b"SVR.C.part['9b2140378640432e:fed0a478']=false")
blow(lua, 2); blow(lua, 3)
mem.w(rec + 0xF8, I(-20)); mem.w(rec + 0xFC, I(-20)); mem.w(rec + 0x20, U(10))
run(lua, 35)
assert lua.eval(b'sim_calls.set') == 0 and lua.eval(b'sim_calls.heal') == 0
assert lua.eval(b"SVR.R.maps['9b2140378640432e']") is None
print('PASS: ambiguous multi-wheel damage never guesses a mapping for selective repair')

mem, lua, cfg, rec, logs, samples = make()
lua.execute(b'SVR.C.part_repair=true; SVR.C.tires=true')
run(lua, 10)
blow(lua, 0); mem.w(rec + 0xF8, I(-20))
lua.execute(b'SVR.C.cooldown=10')
run(lua, 10)
assert lua.eval(b'sim_calls.heal') == lua.eval(b'sim_calls.set') == 0
lua.execute(b'SVR.C.cooldown=0; SVR.C.test=false')
run(lua, 30)
assert lua.eval(b'sim_calls.heal') == lua.eval(b'sim_calls.set') == 0
print('PASS: cooldown and absence of shields prevent repair mutations')

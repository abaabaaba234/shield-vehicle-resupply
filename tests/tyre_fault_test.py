"""Real FRV health and captured VRW centres; native puncture calls are mocked."""
from pathlib import Path
import json
import struct

ROOT=Path(__file__).resolve().parents[1]
env={'__file__':str(ROOT/'tests/repair_native_test.py')}
source=(ROOT/'tests/repair_native_test.py').read_text(encoding='utf-8')
exec(compile(source.split('\nmem, lua, cfg, rec, logs, samples = make()',1)[0],'wheel-harness','exec'),env)
make,run,Q,U,I,BASE=(env[k] for k in ('make','run','Q','U','I','BASE'))
VM,VMROOT=0x5a000000,BASE+0x3332000
DESC=0x20000000+0xF32F18
F=lambda x:struct.pack('<f',x)
CENTRES=json.loads((ROOT/'tests/fixtures/frv_wheel_centres_live.json').read_text())['wheel_centres']


def fixture():
    mem,lua,cfg,rec,logs,samples=make()
    mem.w(rec+0x14,I(2400))
    r=lua.eval(b'SVR.R');p=BASE+r.signatures[b'wheel'][1]
    guard=r.wheels.damage_guard.decode()
    mem.w(p+0xff,bytes(0 if x=='??' else int(x,16) for x in guard.split()))
    # Preserve the VehicleApi RIP displacement covered by the new tail guard.
    mem.w(p+0x117,I(BASE+0x3326320-p-0x11b))
    mem.w(p+0xa3,bytes.fromhex('488b4358488b1cc8488bcbe8'))
    mem.w(p+0x32,I(VMROOT-p-0x36));mem.w(VMROOT,Q(VM))
    # Reuse the harness's guarded table layout helper.
    mem.w(VM+0x40,Q(0x5a001000)+U(16)+U(0xffffffff)+U(1))
    mem.w(0x5a001000,(U(0xffffffff)*2)*16)
    mem.w(0x5a001000+(100%16)*8,U(100)+U(0))
    mem.w(VM+0x58,Q(0x5a002000));mem.w(0x5a002000,Q(DESC))
    header=0x52002100
    mem.w(header,U(0x20575256)+U(4)+b''.join(U(0x20+i*0x70) for i in range(4)))
    for row in CENTRES:
        i=row['api_index']
        mem.w(header+0x20+i*0x70,U(row['axle'])+U(row['steered'])+U(0)+F(row['x'])+F(row['y'])+F(row['z']))
    r.next_check=0;assert r.ensure(3) and r.wheels.damage is not None
    lua.execute(b'''
      sim_calls.damage=0
      local old=SVR.R.invoke
      SVR.R.invoke=function(name,address,a,b,buffer)
        if name~='damage' then return old(name,address,a,b,buffer) end
        local ffi=require('ffi');assert(tonumber(ffi.cast('uintptr_t',a))==0x20000000+0xF32F18)
        sim_calls.damage=sim_calls.damage+1
        local raw=sim_wheels[b]
        sim_wheels[b]=sim_broken_radius..raw:sub(5,40)..'\1'..raw:sub(42)
      end
      SVR.C.frv_tire_guard=true;SVR.C.test=false;SVR.C.tires=true
    ''')
    lua.globals()[b'sim_broken_radius']=F(.2)
    return mem,lua,cfg,rec,logs,samples


def physical(lua,i):return lua.globals()[b'sim_wheels'][i]


mem,lua,cfg,rec,logs,samples=fixture();original=mem.r(cfg,0x5650)
run(lua,3)
assert all(mem.r(cfg+0x208+i*0x228+0xf0,1)==b'\1' for i in range(4))
assert mem.r(cfg+0x40+0xf0,1)==original[0x40+0xf0:0x40+0xf1], 'hull protected from death'
map_=lua.eval(b'SVR.R.tyre_snapshot(svr_d).map')
assert [map_[i] for i in range(4)]==[b'c6bf05a9',b'f12186b7',b'fed0a478',b'f3cb00ad']
mem.w(rec+0xf8,I(2));run(lua,1)
assert lua.eval(b'sim_calls.damage')==0
mem.w(rec+0xf8,I(-1));run(lua,1)
assert mem.r(rec+0xf8,4)==I(1) and mem.r(rec+0x14,4)==I(2400), (logs/'ShieldVehicleResupply.log').read_text(encoding='utf-8')
assert physical(lua,2)[40]==1 and physical(lua,0)[40]==physical(lua,1)[40]==physical(lua,3)[40]==0
assert physical(lua,2)[:4]==F(.2) and lua.eval(b'sim_calls.damage')==1
run(lua,10)
assert lua.eval(b'sim_calls.damage')==1 and mem.r(rec+0xf8,4)==I(1), 'repeated puncture or outside regeneration'
mem.w(rec+0xf8,I(17));run(lua,1);assert physical(lua,2)[40]==1
mem.w(rec+0xf8,I(18));run(lua,1);assert physical(lua,2)==samples[2]
mem.w(rec+0xf8,I(2));run(lua,1);assert physical(lua,2)==samples[2]
print('PASS: captured centres map FL to API 2; 1 HP keeps hull/other tyres unchanged; puncture latches until >5%')

for zone,api in ((0,2),(1,3),(2,0),(3,1)):
    mem,lua,cfg,rec,logs,samples=fixture();run(lua,3)
    mem.w(rec+0xf8+zone*4,I(1));run(lua,1)
    assert physical(lua,api)[40]==1 and sum(physical(lua,i)[40] for i in range(4))==1
    lua.execute(b'SVR.C.test=true;SVR.S.next_fault=SVR.S.clock+100;SVR.S.acc=0.49')
    run(lua,1)
    assert physical(lua,api)[40]==1,'normal tyre repair bypassed failed latch'
    mem.w(rec+0xf8+zone*4,I(18));run(lua,2)
    assert physical(lua,api)==samples[api]
print('PASS: each wheel maps independently; normal repair cannot restore physics below the recovery threshold')

mem,lua,cfg,rec,logs,samples=fixture();original=mem.r(cfg,0x5650);run(lua,3)
mem.w(rec+0xf8,I(1));run(lua,1)
(logs/'shield_resupply_cmd.txt').write_text('reload\n');run(lua,1)
assert physical(lua,2)[40]==1
(logs/'shield_resupply_cmd.txt').write_text('off\n');run(lua,1)
assert mem.r(cfg,0x5650)==original and physical(lua,2)==samples[2]
print('PASS: reload preserves failure; off restores original wheel configurations and physical parameters')

for why in ('hull dead','non-authority','bad maximum','bad wheel schema','unknown centre','missing damage guard','stale vehicle owner'):
    mem,lua,cfg,rec,logs,samples=fixture()
    if why=='hull dead':mem.w(rec+0x19c,U(2))
    elif why=='non-authority':mem.w(DESC+20,U(0))
    elif why=='bad maximum':mem.w(cfg+0x208+0xe8,I(351))
    elif why=='bad wheel schema':mem.w(cfg+0x208+0x60,U(1))
    elif why=='unknown centre':mem.w(0x52002100+0x20+12,F(0))
    elif why=='missing damage guard':lua.eval(b'SVR.R').wheels.damage=None
    elif why=='stale vehicle owner':mem.w(0x5a002000,Q(DESC+24));mem.w(DESC+24,bytes(24))
    before=mem.r(cfg,0x5650);mem.w(rec+0xf8,I(1));run(lua,3)
    assert lua.eval(b'sim_calls.damage')==0,why
    if why!='stale vehicle owner':assert mem.r(cfg,0x5650)==before,why
print('PASS: death, authority, schema, centres, missing guards and stale damage owners prevent native puncture calls')

# A failed restore must retain the latch and retry; external physics edits win.
mem,lua,cfg,rec,logs,samples=fixture();run(lua,3)
mem.w(rec+0xf8,I(1));run(lua,1)
lua.execute(b'sim_fail_set=true');mem.w(rec+0xf8,I(18));run(lua,1)
assert physical(lua,2)[40]==1 and lua.eval(b'SVR.T.states["100:50:7:9b2140378640432e"].parts[1].broken')
lua.execute(b'sim_fail_set=false');run(lua,1);assert physical(lua,2)==samples[2]
mem.w(rec+0xf8,I(1));run(lua,1)
changed=F(.123)+physical(lua,2)[4:];lua.globals()[b'sim_wheels'][2]=changed
mem.w(rec+0xf8,I(18));run(lua,1);assert physical(lua,2)==changed
(logs/'shield_resupply_cmd.txt').write_text('off\n');run(lua,1);assert physical(lua,2)==changed
print('PASS: restore failures retain the latch and retry; external physical parameter edits are preserved')

# New handle generations cannot receive the old wheel's cached physical data.
mem,lua,cfg,rec,logs,samples=fixture();run(lua,3)
mem.w(rec+0xf8,I(1));run(lua,1);before=physical(lua,2)
mem.w(0x52001080,U(0x40000002));mem.w(rec+0xf8,I(18));run(lua,1)
assert physical(lua,2)==before
(logs/'shield_resupply_cmd.txt').write_text('off\n');run(lua,1);assert physical(lua,2)==before
print('PASS: wheel handle generation changes prevent restoration to replacement physics')

# Layout changes in resource ordering must not change anatomical selection.
mem,lua,cfg,rec,logs,samples=fixture()
mem.w(0x52002100+8,b''.join(U(0x20+i*0x70) for i in (2,0,3,1)))
run(lua,3);mem.w(rec+0xf8,I(1));run(lua,1)
assert physical(lua,0)[40]==1 and sum(physical(lua,i)[40] for i in range(4))==1
print('PASS: reordered VRW entries still select the wheel by geometry, independently of API or Health order')

# The second known FRV configuration has the same guarded four-wheel schema.
mem,lua,cfg,rec,logs,samples=fixture()
other='cc21c7ffd3ebefb9'
mem.w(DESC,Q(int(other,16)))
mem.w(0x40000000+int('9b2140378640432e',16)%1002*16,bytes(16))
mem.w(0x40000000+int(other,16)%1002*16,Q(int(other,16))+U(3)+U(0))
mem.w(cfg,(ROOT/'tests/fixtures/health_cc21c7ffd3ebefb9_filediver.bin').read_bytes())
run(lua,3);mem.w(rec+0xf8,I(1));run(lua,1)
assert physical(lua,2)[40]==1
print('PASS: the second real FRV configuration supports the same guarded model protection and physical puncture')

# An incomplete model-protection write must not apply a physical puncture.
mem,lua,cfg,rec,logs,samples=fixture()
lua.execute(b'SVR.W.raw=function() return false end')
mem.w(rec+0xf8,I(1));run(lua,3)
assert lua.eval(b'sim_calls.damage')==0
print('PASS: protection-write failures defer physical puncture until protection is armed')

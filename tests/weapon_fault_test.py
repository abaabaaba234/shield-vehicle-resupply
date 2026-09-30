"""Real packaged Lua: prevention config, failure hysteresis and ammo escrow.

The game's Immortal clamp and shot dispatch are simulated. Live-game floor,
damage routing and suppression of ongoing fire still require verification.
"""
from pathlib import Path
import math
import struct

ROOT=Path(__file__).resolve().parents[1]
env={'__file__':str(ROOT/'tests/exo_repair_test.py')}
source=(ROOT/'tests/exo_repair_test.py').read_text()
prefix=source.split('\nmem, lua, cfg, rec, logs = fixture()',1)[0]
tail=source.split('\ndef arm_fixture():',1)[1].split('\nmem, lua, cfg, rec, logs = arm_fixture()',1)[0]
exec(compile(prefix+'\ndef arm_fixture():'+tail,'exo-harness','exec'),env)
arm_fixture,run,maps,Q,U,I,BASE=(env[k] for k in ('arm_fixture','run','maps','Q','U','I','BASE'))
MAG,ENTRIES,OWNERS,ROWS=0x58000000,0x58001000,0x58002000,0x58003000
ARM='32c7063b4bcc4208'


def integer(mem,p):return struct.unpack('<i',mem.r(p,4))[0]


def fixture(resource=ARM,kind='turret'):
    mem,lua,cfg,rec,logs=arm_fixture()
    if resource!=ARM:
        mem.w(0x20000000+0xF32F18,Q(int(resource,16)))
        mem.w(0x40000000+int(ARM,16)%1002*16,bytes(16))
        mem.w(0x40000000+int(resource,16)%1002*16,Q(int(resource,16))+U(3)+U(0))
    blob=(ROOT/'tests/fixtures'/('arm_health_e5f64dcc3bfe9dd1.bin' if kind=='turret' else 'arm_health_0736bee2d6328726.bin')).read_bytes()
    mem.w(cfg,blob);mem.w(rec+0x14,I(800));mem.w(rec+0xf8,I(800));mem.w(rec+0x20,U(0))
    mem.w(BASE+0x3326648,Q(MAG))
    maps(mem,MAG+0x20,ENTRIES,[(100,0)])
    mem.w(MAG+0x38,Q(OWNERS));mem.w(OWNERS,Q(0x20000000+0xF32F18))
    mem.w(MAG+0x50,Q(ROWS));mem.w(ROWS,I(55)+I(6)+I(1234))
    lua.execute(b'SVR.C.test=false; SVR.C.exo_weapon_guard=true; SVR.C.ammo=true')

    def native_heal(frac):
        for offset in (0x14,0xf8):
            mem.w(rec+offset,I(min(800,max(0,integer(mem,rec+offset))+math.ceil(800*frac))))
        mem.w(rec+0x20,U(0))
    lua.globals()[b'pyheal']=native_heal
    return mem,lua,cfg,rec,logs,blob


def ammo(mem):return mem.r(ROWS,8)
def failed(lua):return lua.eval(b"SVR.F.states['100:50:7:32c7063b4bcc4208'].broken")==True


mem,lua,cfg,rec,logs,original=fixture()
run(lua,3)
assert mem.r(cfg+0x208+0xf0,1)==b'\1' and mem.r(cfg+0x208+0xf4,1)==b'\0'
assert mem.r(cfg+0x40+0xf0,1)==b'\1' and mem.r(cfg+0x40+0xf8,4)==bytes(4)
assert ammo(mem)==I(55)+I(6) and mem.r(ROWS+8,4)==I(1234)
assert not failed(lua)
for value in (40,39,2):
    mem.w(rec+0xf8,I(value));run(lua,1)
    assert not failed(lua) and ammo(mem)==I(55)+I(6), value
mem.w(rec+0xf8,I(1));run(lua,1)
assert failed(lua) and ammo(mem)==bytes(8)
mem.w(rec+0xf8,I(39));run(lua,1)
assert failed(lua) and ammo(mem)==bytes(8)
mem.w(rec+0xf8,I(40));run(lua,1)
assert failed(lua) and ammo(mem)==bytes(8), 'exactly 5% unlocked'
mem.w(rec+0xf8,I(41));run(lua,1)
assert not failed(lua) and ammo(mem)==I(55)+I(6)
mem.w(rec+0xf8,I(39));run(lua,1)
assert not failed(lua) and ammo(mem)==I(55)+I(6), 'low HP without hitting 1 disabled weapon'
mem.w(rec+0xf8,I(1));run(lua,1)
assert failed(lua) and ammo(mem)==bytes(8)
print('PASS: 1 HP latches failure; 2..5% stays usable when healthy; failed weapon unlocks strictly above 5%')

mem,lua,cfg,rec,logs,original=fixture()
run(lua,2)
mem.w(rec+0xf8,I(0));run(lua,1)
assert integer(mem,rec+0xf8)==1 and failed(lua) and ammo(mem)==bytes(8)
assert lua.eval(b'sim_calls.heal')==1
run(lua,20)
assert integer(mem,rec+0xf8)==1 and lua.eval(b'sim_calls.heal')==1, 'regenerated outside shield'
lua.execute(b'SVR.C.test=true; SVR.C.exo_heal=0.04')
run(lua,3)
assert integer(mem,rec+0xf8)<=40 and ammo(mem)==bytes(8), 'refill bypassed the failure latch'
run(lua,25)
assert integer(mem,rec+0xf8)>40 and not failed(lua) and integer(mem,ROWS+4)>=6
print('PASS: zero-HP floor uses one engine HP outside shield; shield repairs/re-enables; refill cannot bypass latch')

mem,lua,cfg,rec,logs,original=fixture()
run(lua,2)
lua.execute(b'SVR.C.test=true; SVR.C.exo_heal=0.04; SVR.S.next_fault=SVR.S.clock+100; SVR.S.acc=0.49')
mem.w(rec+0xf8,I(1));run(lua,1)
assert integer(mem,rec+0xf8)>1 and failed(lua) and ammo(mem)==bytes(8)
print('PASS: guard always samples before healing even when its normal polling interval is not due')

for res,kind in (('08f6089289c83d22','turret'),('824b7e0c4c879eb5','body'),
                 ('821d035aa47e3e75','body'),('e5f64dcc3bfe9dd1','turret'),
                 ('ff9878576a4c543b','turret'),('32c7063b4bcc4208','turret'),
                 ('8ca4dfa795a473c8','turret'),('0a03761d50ba5121','turret'),
                 ('3e3a31261a124454','turret'),('0736bee2d6328726','body'),
                 ('17c5d12d8d5dee2c','turret'),('df51fe8d62f294be','turret')):
    mem,lua,cfg,rec,logs,original=fixture(res,kind)
    run(lua,2);mem.w(rec+0xf8,I(1));run(lua,1)
    assert ammo(mem)==bytes(8),res
    mem.w(rec+0xf8,I(41));run(lua,1)
    assert ammo(mem)==I(55)+I(6),res
print('PASS: all four mech families and known upgraded guns recognized; turret/body zone variants supported')

for why in ('shield arm','no ammo','non-authority','dead','detached','dead parent',
            'schema mismatch','bad ammo','bad default contribution','weapon guard missing','heal guard missing','attach guard missing'):
    mem,lua,cfg,rec,logs,original=fixture('65489809a8181b96' if why=='shield arm' else ARM)
    if why=='no ammo':mem.w(BASE+0x3326648,Q(0))
    elif why=='non-authority':mem.w(0x20000000+0xF32F18+20,U(0))
    elif why=='dead':mem.w(rec+0x19c,U(1))
    elif why=='detached':mem.w(env['AROWS'],U(0))
    elif why=='dead parent':mem.w(rec+0x1b8+0x14,I(0))
    elif why=='schema mismatch':mem.w(cfg+0x208+0x60,U(0xdeadbeef))
    elif why=='bad ammo':mem.w(ROWS,I(-10))
    elif why=='bad default contribution':mem.w(cfg+0x40+0xf8,struct.pack('<f',float('nan')))
    elif why=='weapon guard missing':
        lua.execute(b'SVR.N.weapon_base=SVR.N.base; SVR.N.weapon_ready=false')
    elif why in ('heal guard missing','attach guard missing'):
        lua.execute(b'SVR.R.next_check=1000')
        r=lua.eval(b'SVR.R');r[b'health' if why.startswith('heal') else b'attach']=None
    before=mem.r(cfg,0x5650);before_ammo=ammo(mem)
    mem.w(rec+0xf8,I(1));run(lua,2)
    assert mem.r(cfg,0x5650)==before and ammo(mem)==before_ammo,why
print('PASS: shield excluded; missing ammo/guards, bad layouts, death, authority and detached parents prevent arming')

mem,lua,cfg,rec,logs,original=fixture()
run(lua,2);mem.w(rec+0xf8,I(1));run(lua,1)
mem.w(rec+0xf8,I(30))
(logs/'shield_resupply_cmd.txt').write_text('reload\n')
run(lua,8)
assert failed(lua) and ammo(mem)==bytes(8), 'reload erased history at low HP'
(logs/'shield_resupply_cmd.txt').write_text('off\n')
run(lua,8)
assert mem.r(cfg,0x5650)==original and ammo(mem)==I(55)+I(6)
(logs/'shield_resupply_cmd.txt').write_text('on\n')
run(lua,8)
assert failed(lua) and ammo(mem)==bytes(8), 'reenable erased history'
mem.w(rec+0xf8,I(41));run(lua,1)
assert not failed(lua) and ammo(mem)==I(55)+I(6)
print('PASS: reload/off/on preserve failure history; off restores exact original config and escrowed ammo')

mem,lua,cfg,rec,logs,original=fixture()
run(lua,2);mem.w(rec+0xf8,I(1));run(lua,1)
mem.w(ROWS,I(70)) # another addon refills during failure
run(lua,1)
assert ammo(mem)==bytes(8)
mem.w(rec+0xf8,I(41));run(lua,1)
assert ammo(mem)==I(70)+I(6), 'external refill lost'
print('PASS: later external refill is saved while failed and restored on recovery')

mem,lua,cfg,rec,logs,original=fixture()
run(lua,2);mem.w(rec+0xf8,I(1));run(lua,1)
mem.w(0x20000000+0xF32F18+12,U(99)) # reused entity identity
mem.w(ROWS,I(11)+I(2))
run(lua,2)
assert ammo(mem)==I(11)+I(2), 'escrow restored to a different owner'
print('PASS: changed network/weapon identity never receives saved ammo')

mem,lua,cfg,rec,logs,original=fixture()
run(lua,2)
lua.globals()[b'fail_address']=ROWS+4
lua.execute(b'''
  old_i32=SVR.W.i32
  SVR.W.i32=function(p,o,n) if p==fail_address then return false end; return old_i32(p,o,n) end
''')
mem.w(rec+0xf8,I(1));run(lua,1)
assert failed(lua) and integer(mem,ROWS)==0 and integer(mem,ROWS+4)==6
lua.execute(b'fail_address=nil');run(lua,1)
assert ammo(mem)==bytes(8)
mem.w(rec+0xf8,I(41));lua.globals()[b'fail_address']=ROWS+4;run(lua,1)
assert failed(lua) and ammo(mem)==bytes(8), 'partial recovery exposed ammunition before transaction completed'
lua.execute(b'fail_address=nil');run(lua,1)
assert not failed(lua) and ammo(mem)==I(55)+I(6)
print('PASS: partial hold/release write failures retain escrow and retry without dropping the latch')

mem,lua,cfg,rec,logs,original=fixture()
run(lua,2)
lua.globals()[b'fail_address']=cfg+0x208+0xf0
lua.execute(b'''
  old_raw=SVR.W.raw
  SVR.W.raw=function(p,n,o,v) if p==fail_address then return false end; return old_raw(p,n,o,v) end
''')
lua.execute(b'SVR.C.exo_weapon_guard=false');run(lua,1)
assert lua.eval(b'next(SVR.F.configs)') is not None
lua.execute(b'fail_address=nil');run(lua,1)
assert mem.r(cfg,0x5650)==original and lua.eval(b'next(SVR.F.configs)') is None
print('PASS: failed protection restoration remains tracked and retries with guard disabled')

mem,lua,cfg,rec,logs,original=fixture()
lua.globals()[b'fail_address']=cfg+0x208+0xf0
lua.execute(b'''
  old_raw=SVR.W.raw
  SVR.W.raw=function(p,n,o,v) if p==fail_address then return false end; return old_raw(p,n,o,v) end
''')
mem.w(rec+0xf8,I(1));run(lua,1)
assert failed(lua) and ammo(mem)==bytes(8), 'protection write failure bypassed firing latch'
lua.execute(b'fail_address=nil');run(lua,1)
assert mem.r(cfg+0x208+0xf0,1)==b'\1'
print('PASS: failure latch still blocks at 1 HP while a protection write is being retried')

for nodes in ((202,), (202,203), (202,203,204)):
    mem,lua,cfg,rec,logs,original=fixture()
    env['bridge_chain'](mem,nodes)
    run(lua,2)
    assert mem.r(cfg+0x208+0xf0,1)==b'\1' and ammo(mem)==I(55)+I(6), nodes
    chain='->'.join(str(i) for i in (100,*nodes,101))
    log=(logs/'ShieldVehicleResupply.log').read_text(encoding='utf-8',errors='replace')
    assert f'parent=101 chain={chain}' in log, log
    mem.w(rec+0xf8,I(1));run(lua,1)
    assert failed(lua) and ammo(mem)==bytes(8), nodes
    mem.w(rec+0xf8,I(41));run(lua,1)
    assert not failed(lua) and ammo(mem)==I(55)+I(6), nodes
print('PASS: native-only attachment bridges arm protection and preserve 1 HP/5% weapon behavior; success logs include chain')

for why in ('missing bridge row','cycle','too deep','dead mech','non-authoritative mech'):
    mem,lua,cfg,rec,logs,original=fixture()
    env['bridge_chain'](mem,(202,))
    if why=='missing bridge row':mem.w(env['AROWS']+0x30,U(9999))
    elif why=='cycle':mem.w(env['AROWS']+0x30,U(100))
    elif why=='too deep':env['bridge_chain'](mem,(202,203,204,205))
    elif why=='dead mech':mem.w(rec+0x1b8+0x19c,U(2))
    elif why=='non-authoritative mech':mem.w(0x20000000+0xF32F18+24+20,U(0))
    mem.w(rec+0xf8,I(1));run(lua,2)
    assert mem.r(cfg,0x5650)==original and ammo(mem)==I(55)+I(6),why
    if why=='missing bridge row':
        log=(logs/'ShieldVehicleResupply.log').read_text(encoding='utf-8',errors='replace')
        assert 'chain=100->202->9999' in log,log
print('PASS: broken native-only chains cannot arm protection or clear ammo; failed chain IDs are logged')

mem,lua,cfg,rec,logs,original=fixture()
env['bridge_chain'](mem,(202,))
original_read,injected=mem.r,[False]
def changing_bridge(a,n):
    data=original_read(int(a),int(n))
    if a==env['AROWS']+0x30 and n==4 and not injected[0]:
        injected[0]=True
        mem.w(env['AROWS'],U(222))
    return data
lua.globals()[b'pyread']=changing_bridge
mem.w(rec+0xf8,I(1));run(lua,2)
assert injected[0] and mem.r(cfg,0x5650)==original and ammo(mem)==I(55)+I(6)
log=(logs/'ShieldVehicleResupply.log').read_text(encoding='utf-8',errors='replace')
assert 'identity changed during sample' in log,log
print('PASS: attachment bridge changes during sampling prevent all weapon writes')

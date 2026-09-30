"""Two real shield pools and exact-parent attack suppression in the packaged Lua.

Model retention, shield collision and firing are not emulated by this harness.
"""
from pathlib import Path
import struct

ROOT=Path(__file__).resolve().parents[1]
env={'__file__':str(ROOT/'tests/weapon_fault_test.py')}
source=(ROOT/'tests/weapon_fault_test.py').read_text(encoding='utf-8')
exec(compile(source.split('\nmem,lua,cfg,rec,logs,original=fixture()',1)[0],'weapon-harness','exec'),env)
fixture0,run,maps,Q,U,I=(env[k] for k in ('fixture','run','maps','Q','U','I'))
MECH_UNIT,ARM_UNIT=env['env']['MECH_UNIT'],env['env']['ARM_UNIT']
AROWS,AM,AENTRIES=(env['env'][k] for k in ('AROWS','AM','AENTRIES'))
ATT_STRIDE=env['env']['ATT_STRIDE']
GUN,SHIELD,MECH='df51fe8d62f294be','65489809a8181b96','35dbf54f016f3624'
MAG,OWNERS,ROWS=(env[k] for k in ('MAG','OWNERS','ROWS'))
NET,HM,DESC=0x20000000,0x30000000,0x20000000+0xF32F18


def fixture():
    mem,lua,cfg,rec,logs,original=fixture0(GUN)
    mem.w(DESC+24,Q(int(MECH,16)))
    oldparent=int('c2d449ecf7facab1',16)
    mem.w(0x40000000+oldparent%1002*16,bytes(16))
    # EXO-55 and its gun hash to the same slot; preserve the gun at 198.
    mem.w(0x40000000+(int(MECH,16)%1002+1)*16,Q(int(MECH,16))+U(4)+U(0))
    mem.w(DESC+48,Q(int(SHIELD,16))+U(102)+U(ARM_UNIT+10)+U(52)+U(1))
    maps(mem,NET+0xF1AEB0,0x21000000,[(100,0),(101,1),(102,2)])
    maps(mem,NET+0xF22EC8,0x21001000,[(50,0),(51,1),(52,2)])
    maps(mem,HM+0x1030,0x31000000,[(100,0),(101,1),(102,2)])
    mem.w(0x31002010,Q(DESC+48))
    shield_cfg=0x40000000+0x3ea0+5*0x5650
    mem.w(0x40000000+int(SHIELD,16)%1002*16,Q(int(SHIELD,16))+U(5)+U(0))
    blob=(ROOT/'tests/fixtures/health_65489809a8181b96_filediver.bin').read_bytes()
    mem.w(shield_cfg,blob)
    shield_rec=rec+2*0x1b8
    mem.w(shield_rec,bytes(0x1b8));mem.w(shield_rec+0x14,I(800))
    mem.w(shield_rec+0xf8,I(800)+I(5000))
    maps(mem,AM+0x18,AENTRIES,[(100,0),(102,1)])
    mem.w(AROWS+ATT_STRIDE,bytes(ATT_STRIDE))
    mem.w(AROWS+ATT_STRIDE,U(MECH_UNIT)+U(83)+U(0xffffffff))
    lua.execute(b'SVR.C.exo_shield_guard=true')
    return mem,lua,cfg,rec,shield_cfg,shield_rec,logs,original,blob


def blocked(lua):
    return lua.eval(f"SVR.F.blocked({{resource='{GUN}',entity=100,unit={ARM_UNIT},goid=50}})".encode())


def ammo(mem):return mem.r(ROWS,8)


mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
run(lua,3)
assert mem.r(sc+0x40+0xf0,1)==mem.r(sc+0x208+0xf0,1)==mem.r(sc+0x430+0xf0,1)==b'\1'
assert mem.r(sc+0x208+0xf4,1)==b'\0' and mem.r(sc+0x208+0xf8,4)==bytes(4)
assert not blocked(lua) and ammo(mem)==I(55)+I(6)
mem.w(sr+0xf8,I(39));mem.w(sr+0xfc,I(249));run(lua,1)
assert not blocked(lua), 'below 5% without reaching 1 HP disabled attacks'
mem.w(sr+0xfc,I(1));run(lua,1)
assert blocked(lua) and ammo(mem)==bytes(8)
mem.w(sr+0xfc,I(250));run(lua,1)
assert blocked(lua), 'shield at exactly 5% released the gun'
mem.w(sr+0xfc,I(251));run(lua,1)
assert not blocked(lua) and ammo(mem)==I(55)+I(6), 'healthy low-HP arm incorrectly required >5%'
mem.w(sr+0xf8,I(1));run(lua,1)
assert blocked(lua) and ammo(mem)==bytes(8)
mem.w(sr+0xf8,I(40));run(lua,1);assert blocked(lua)
mem.w(sr+0xf8,I(41));run(lua,1)
assert not blocked(lua) and ammo(mem)==I(55)+I(6)
print('PASS: real 800/5000 shield pools are protected; either failure disables the paired gun; individual >5% hysteresis')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
run(lua,3)
mem.w(sr+0xf8,I(1)+I(1));mem.w(rec+0xf8,I(1));run(lua,1)
assert blocked(lua) and ammo(mem)==bytes(8)
mem.w(rec+0xf8,I(41));mem.w(sr+0xf8,I(41));run(lua,1)
assert blocked(lua), 'one unrepaired shield pool released the gun'
mem.w(sr+0xfc,I(251));run(lua,1)
assert not blocked(lua) and ammo(mem)==I(55)+I(6)
print('PASS: gun, shield arm and plate failures must each recover before ammunition returns')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
run(lua,3);mem.w(sr+0xfc,I(-1));run(lua,1)
assert mem.r(sr+0xfc,4)==I(1) and mem.r(sr+0xf8,4)==I(800) and mem.r(sr+0x14,4)==I(800)
assert lua.eval(b'sim_calls.heal')==0, 'shield floor regenerated other pools outside the bubble'
assert blocked(lua) and ammo(mem)==bytes(8)
(logs/'shield_resupply_cmd.txt').write_text('reload\n',encoding='utf-8');run(lua,1)
assert blocked(lua) and ammo(mem)==bytes(8)
(logs/'shield_resupply_cmd.txt').write_text('off\n',encoding='utf-8');run(lua,1)
assert mem.r(sc,0x5650)==blob and mem.r(cfg,0x5650)==original and ammo(mem)==I(55)+I(6)
print('PASS: shield floor changes only the depleted pool; reload preserves failure; off restores configurations and ammo')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture();run(lua,3)
mem.w(sr+0x14,I(0));run(lua,1)
assert mem.r(sr+0x14,4)==I(1) and mem.r(sr+0xf8,8)==I(800)+I(5000)
assert blocked(lua) and lua.eval(b'sim_calls.heal')==0
print('PASS: a live depleted shield main pool is floored separately without healing either named pool')

for why in ('dead shield','detached shield','wrong parent','non-authoritative shield','unexpected third zone','bad shield maximum'):
    mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
    if why=='dead shield':mem.w(sr+0x19c,U(2))
    elif why=='detached shield':mem.w(AROWS+ATT_STRIDE,U(0))
    elif why=='wrong parent':mem.w(AROWS+ATT_STRIDE,U(MECH_UNIT+0x400000))
    elif why=='non-authoritative shield':mem.w(DESC+48+20,U(0))
    elif why=='unexpected third zone':mem.w(sc+0x658+0x60,U(1))
    elif why=='bad shield maximum':mem.w(sc+0x430+0xe8,I(4999))
    before=mem.r(sc,0x5650)
    run(lua,3)
    assert mem.r(sc,0x5650)==before,why
    assert blocked(lua) and ammo(mem)==bytes(8), why+' let a mech with no verified shield companion attack'
print('PASS: invalid/dead/missing shield companion cannot arm or permit attacks; parent generation is preserved')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
lua.execute(b'SVR.C.exo_shield_guard=false');run(lua,3)
mem.w(sr+0xfc,I(1));run(lua,1)
assert mem.r(sc,0x5650)==blob and not blocked(lua) and ammo(mem)==I(55)+I(6)
print('PASS: shield guard can be disabled independently; original gun protection remains available')

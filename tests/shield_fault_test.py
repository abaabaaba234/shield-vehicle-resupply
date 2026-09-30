"""Real shield pools and per-entity skill gating in the packaged Lua.

Model retention, collision and actual shield-bash dispatch require live testing.
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
BASE=env['BASE']
WM,WENTRIES,WOWNERS,WROWS=0x59000000,0x59001000,0x59002000,0x59003000


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
    r=lua.eval(b'SVR.R')
    for name in (b'bash',b'bash_table',b'bash_branch',b'bash_root'):
        sig=r.signatures[name]
        mem.w(BASE+sig[1],bytes(0 if t=='??' else int(t,16) for t in sig[2].decode().split()))
    p=BASE+r.signatures[b'bash_root'][1]
    mem.w(p+3,I(BASE+0x3326660-p-7))
    mem.w(p+10,I(BASE+0x744AD0-p-14))
    mem.w(BASE+0x3326660,Q(WM))
    maps(mem,WM+0x28,WENTRIES,[(102,0),(100,1)])
    mem.w(WM+0x40,Q(WOWNERS));mem.w(WOWNERS,Q(DESC+48)+Q(DESC))
    mem.w(WM+0x50,Q(WROWS))
    mem.w(WROWS,U(0x2808)+bytes(36)+U(0x2141)+bytes(36))
    r.next_check=0;r.ensure(3)
    assert r.bash is not None
    lua.execute(b'SVR.C.exo_shield_guard=true')
    return mem,lua,cfg,rec,shield_cfg,shield_rec,logs,original,blob


def blocked(lua):
    return lua.eval(f"SVR.F.blocked({{resource='{GUN}',entity=100,unit={ARM_UNIT},goid=50}})".encode())


def ammo(mem):return mem.r(ROWS,8)


def bash(mem,row=0):return struct.unpack('<I',mem.r(WROWS+row*40,4))[0]


def shield_blocked(lua):
    return lua.eval(f"SVR.F.blocked({{resource='{SHIELD}',entity=102,unit={ARM_UNIT+10},goid=52}})".encode())


def fail_flag_writes(lua):
    lua.globals()[b'flag_address']=WROWS
    lua.execute(b'''
      old_u32=SVR.W.u32
      SVR.W.u32=function(p,o,n) if fail_flag and p==flag_address then return false end; return old_u32(p,o,n) end
      fail_flag=true
    ''')


mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
run(lua,3)
assert mem.r(sc+0x40+0xf0,1)==mem.r(sc+0x208+0xf0,1)==mem.r(sc+0x430+0xf0,1)==b'\1'
assert mem.r(sc+0x208+0xf4,1)==b'\0' and mem.r(sc+0x208+0xf8,4)==bytes(4)
assert not blocked(lua) and ammo(mem)==I(55)+I(6)
assert bash(mem)==0x2808 and bash(mem,1)==0x2141
mem.w(sr+0xf8,I(39));mem.w(sr+0xfc,I(249));run(lua,1)
assert not blocked(lua), 'below 5% without reaching 1 HP disabled attacks'
mem.w(sr+0xfc,I(1));run(lua,1)
assert shield_blocked(lua) and bash(mem)==0x2800
assert not blocked(lua) and ammo(mem)==I(55)+I(6)
mem.w(sr+0xfc,I(250));run(lua,1)
assert shield_blocked(lua) and bash(mem)==0x2800, 'shield at exactly 5% enabled bash'
mem.w(sr+0xfc,I(251));run(lua,1)
assert not shield_blocked(lua) and bash(mem)==0x2808, 'healthy low-HP arm incorrectly required >5%'
mem.w(sr+0xf8,I(1));run(lua,1)
assert shield_blocked(lua) and bash(mem)==0x2800
mem.w(sr+0xf8,I(40));run(lua,1);assert shield_blocked(lua)
mem.w(sr+0xf8,I(41));run(lua,1)
assert not shield_blocked(lua) and bash(mem)==0x2808
assert ammo(mem)==I(55)+I(6) and bash(mem,1)==0x2141
print('PASS: either 800/5000 shield pool gates only its skill bit; strict independent >5% recovery; flak stores untouched')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
run(lua,3)
mem.w(sr+0xf8,I(1)+I(1));mem.w(rec+0xf8,I(1));run(lua,1)
assert blocked(lua) and ammo(mem)==bytes(8)
mem.w(rec+0xf8,I(41));mem.w(sr+0xf8,I(41));run(lua,1)
assert not blocked(lua) and ammo(mem)==I(55)+I(6), 'shield failure kept recovered flak disabled'
assert shield_blocked(lua) and bash(mem)==0x2800
mem.w(sr+0xfc,I(251));run(lua,1)
assert not blocked(lua) and ammo(mem)==I(55)+I(6)
assert not shield_blocked(lua) and bash(mem)==0x2808
mem.w(rec+0xf8,I(1));run(lua,1)
assert blocked(lua) and ammo(mem)==bytes(8) and bash(mem)==0x2808
print('PASS: flak failure/recovery is independent of both shield latches; gun damage never gates a healthy shield')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
run(lua,3);mem.w(sr+0xfc,I(-1));run(lua,1)
assert mem.r(sr+0xfc,4)==I(1) and mem.r(sr+0xf8,4)==I(800) and mem.r(sr+0x14,4)==I(800)
assert lua.eval(b'sim_calls.heal')==0, 'shield floor regenerated other pools outside the bubble'
assert shield_blocked(lua) and bash(mem)==0x2800 and ammo(mem)==I(55)+I(6)
(logs/'shield_resupply_cmd.txt').write_text('reload\n',encoding='utf-8');run(lua,1)
assert shield_blocked(lua) and bash(mem)==0x2800 and ammo(mem)==I(55)+I(6)
(logs/'shield_resupply_cmd.txt').write_text('off\n',encoding='utf-8');run(lua,1)
assert mem.r(sc,0x5650)==blob and mem.r(cfg,0x5650)==original and ammo(mem)==I(55)+I(6)
assert bash(mem)==0x2808
print('PASS: shield floor changes only depleted pool; reload preserves failure; off restores configs and owned input bit')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture();run(lua,3)
mem.w(sr+0x14,I(0));run(lua,1)
assert mem.r(sr+0x14,4)==I(1) and mem.r(sr+0xf8,8)==I(800)+I(5000)
assert shield_blocked(lua) and bash(mem)==0x2800 and lua.eval(b'sim_calls.heal')==0
print('PASS: a live depleted shield main pool is floored separately without healing either named pool')

for why in ('dead shield','detached shield','wrong parent','non-authoritative shield','unexpected third zone','bad shield maximum',
            'missing weapon row','wrong weapon owner','wrong weapon kind','missing bash guard','wrong root','wrong query'):
    mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
    if why=='dead shield':mem.w(sr+0x19c,U(2))
    elif why=='detached shield':mem.w(AROWS+ATT_STRIDE,U(0))
    elif why=='wrong parent':mem.w(AROWS+ATT_STRIDE,U(MECH_UNIT+0x400000))
    elif why=='non-authoritative shield':mem.w(DESC+48+20,U(0))
    elif why=='unexpected third zone':mem.w(sc+0x658+0x60,U(1))
    elif why=='bad shield maximum':mem.w(sc+0x430+0xe8,I(4999))
    elif why=='missing weapon row':maps(mem,WM+0x28,WENTRIES,[(100,1)])
    elif why=='wrong weapon owner':mem.w(WOWNERS,Q(DESC))
    elif why=='wrong weapon kind':mem.w(WROWS,U(0x2141))
    elif why in ('missing bash guard','wrong root','wrong query'):
        r=lua.eval(b'SVR.R');p=BASE+r.signatures[b'bash_root'][1]
        if why=='missing bash guard':mem.w(BASE+r.signatures[b'bash_branch'][1],b'\x90')
        elif why=='wrong root':mem.w(p+3,I(BASE+0x3326648-p-7))
        else:mem.w(p+10,I(BASE+0x744AE0-p-14))
        r.next_check=0;r.ensure(4)
        assert r.bash is None and r.health is not None and r.attach is not None
    before=mem.r(sc,0x5650)
    run(lua,3)
    assert mem.r(sc,0x5650)==before,why
    assert not blocked(lua) and ammo(mem)==I(55)+I(6), why+' affected independent flak'
    assert bash(mem)==(0x2141 if why=='wrong weapon kind' else 0x2808),why
print('PASS: death, attachment, authority, owners, schema and semantic code guards reject shield writes without blocking flak')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
lua.execute(b'SVR.C.exo_shield_guard=false');run(lua,3)
mem.w(sr+0xfc,I(1));run(lua,1)
assert mem.r(sc,0x5650)==blob and not blocked(lua) and ammo(mem)==I(55)+I(6)
assert bash(mem)==0x2808
print('PASS: shield guard can be disabled independently; original gun protection remains available')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
lua.execute(b'SVR.C.exo_weapon_guard=false');run(lua,3)
mem.w(rec+0xf8,I(1));mem.w(sr+0xfc,I(1));run(lua,1)
assert bash(mem)==0x2800 and ammo(mem)==I(55)+I(6) and mem.r(cfg,0x5650)==original
print('PASS: shield guard does not implicitly enable flak protection or ammunition escrow')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture();run(lua,3)
mem.w(sr+0xfc,I(1));fail_flag_writes(lua);run(lua,1)
assert bash(mem)==0x2808 and shield_blocked(lua)
lua.execute(b'fail_flag=false');run(lua,1);assert bash(mem)==0x2800
mem.w(WROWS,U(0x12808));run(lua,1)
assert bash(mem)==0x12800, 'engine rewrite was not gated or unrelated flags lost'
mem.w(sr+0xfc,I(251));lua.execute(b'fail_flag=true');run(lua,1)
assert bash(mem)==0x12800 and shield_blocked(lua), 'failed restore dropped pending input ownership'
lua.execute(b'fail_flag=false');run(lua,1)
assert bash(mem)==0x12808 and not shield_blocked(lua)
assert ammo(mem)==I(55)+I(6)
print('PASS: failed disable/restore retries; engine rewrites re-gated and counted; unrelated flag bits preserved')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
mem.w(WROWS,U(0x2800));run(lua,3)
mem.w(sr+0xfc,I(1));run(lua,1);mem.w(sr+0xfc,I(251));run(lua,1)
(logs/'shield_resupply_cmd.txt').write_text('off\n');run(lua,1)
assert bash(mem)==0x2800, 'external disabled input was enabled without owning that bit'
print('PASS: an externally disabled skill bit is never adopted or enabled by recovery/off')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture();run(lua,3)
mem.w(sr+0xfc,I(1));run(lua,1);fail_flag_writes(lua)
(logs/'shield_resupply_cmd.txt').write_text('off\n');run(lua,1)
assert bash(mem)==0x2800
lua.execute(b'SVR.F.reset()')
assert lua.eval(b'next(SVR.F.states)') is not None
lua.execute(b'fail_flag=false');run(lua,1)
assert bash(mem)==0x2808
print('PASS: off and reset preserve failed input restores for retry')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture();run(lua,3)
mem.w(sr+0xfc,I(1));run(lua,1)
old=mem.r(WROWS,40);moved=WROWS+5*40
mem.w(moved,old);mem.w(WROWS,U(0x2141)+bytes(36))
maps(mem,WM+0x28,WENTRIES,[(102,5),(100,1)])
mem.w(WOWNERS+5*8,Q(DESC+48))
mem.w(sr+0xfc,I(251));run(lua,1)
assert mem.r(moved,4)==U(0x2808) and bash(mem)==0x2141, 'restore used saved row address'
print('PASS: relocated dense row restores current owner and leaves replaced old slot untouched')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture();run(lua,3)
mem.w(sr+0xfc,I(1));run(lua,1)
mem.w(DESC+48+12,U(ARM_UNIT+20));mem.w(WROWS,U(0x2800))
(logs/'shield_resupply_cmd.txt').write_text('off\n');run(lua,1)
assert bash(mem)==0x2800, 'old input restore reached reused entity identity'
print('PASS: reused network identity never receives an old input restoration')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture();run(lua,3)
raw,injected=mem.r,[False]
def changing_owner(a,n):
    data=raw(int(a),int(n))
    if a==WROWS and n==4 and not injected[0]:
        injected[0]=True;mem.w(WOWNERS,Q(DESC))
    return data
lua.globals()[b'pyread']=changing_owner
mem.w(sr+0xfc,I(1));run(lua,2)
assert injected[0] and bash(mem)==0x2808 and ammo(mem)==I(55)+I(6)
print('PASS: changed component ownership during sampling prevents input writes')

mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
# A second intact mech shares Health configuration, but has its own input row.
desc2,desc3=DESC+72,DESC+96
mem.w(desc2,Q(int(MECH,16))+U(103)+U(MECH_UNIT+30)+U(53)+U(1))
mem.w(desc3,Q(int(SHIELD,16))+U(104)+U(ARM_UNIT+30)+U(54)+U(1))
maps(mem,NET+0xF1AEB0,0x21000000,[(100,0),(101,1),(102,2),(103,3),(104,4)])
maps(mem,NET+0xF22EC8,0x21001000,[(50,0),(51,1),(52,2),(53,3),(54,4)])
maps(mem,HM+0x1030,0x31000000,[(100,0),(101,1),(102,2),(103,3),(104,4)])
mem.w(0x31002018,Q(desc2)+Q(desc3))
mem.w(rec+3*0x1b8,mem.r(rec+0x1b8,0x1b8));mem.w(rec+4*0x1b8,mem.r(sr,0x1b8))
maps(mem,AM+0x18,AENTRIES,[(100,0),(102,1),(104,2)])
mem.w(AROWS+2*ATT_STRIDE,U(MECH_UNIT+30)+U(83)+U(0xffffffff)+bytes(ATT_STRIDE-12))
maps(mem,WM+0x28,WENTRIES,[(102,0),(100,1),(104,2)])
mem.w(WOWNERS+16,Q(desc3));mem.w(WROWS+80,U(0x2808)+bytes(36))
run(lua,8);mem.w(sr+0xfc,I(1));run(lua,2)
assert bash(mem)==0x2800 and bash(mem,2)==0x2808 and ammo(mem)==I(55)+I(6)
mem.w(sr+0xfc,I(251));run(lua,1)
assert bash(mem)==bash(mem,2)==0x2808
print('PASS: one failed shield gates only its entity; another intact EXO-55 stays enabled despite shared Health config')
mem.w(sr+0xfc,I(1));run(lua,1);assert bash(mem)==0x2800
mem.w(AROWS+ATT_STRIDE,U(MECH_UNIT+30));mem.w(sr+0xfc,I(251));run(lua,2)
assert bash(mem)==0x2800 and bash(mem,2)==0x2808, 'parent change adopted old input ownership'
(logs/'shield_resupply_cmd.txt').write_text('off\n');run(lua,1)
assert bash(mem)==0x2800, 'off restored input into a different parent mech'
print('PASS: a shield reattached to a different live parent does not receive stale input restoration')

for name in (b'bash',b'bash_table',b'bash_branch',b'bash_root'):
    mem,lua,cfg,rec,sc,sr,logs,original,blob=fixture()
    r=lua.eval(b'SVR.R');mem.w(BASE+r.signatures[name][1],b'\x90')
    r.next_check=0;r.ensure(4)
    assert r.bash is None and r.health is not None and r.wheels is not None and r.attach is not None
    mem.w(sr+0xfc,I(1));run(lua,3)
    assert mem.r(sc,0x5650)==blob and bash(mem)==0x2808 and ammo(mem)==I(55)+I(6)
print('PASS: drift in any reviewed input/layout signature disables only the new shield interface')

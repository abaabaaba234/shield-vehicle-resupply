"""Replay actual EXO-55 animation definition and mock asynchronous engine events.

Proves detection and dispatch gates; visible gait requires in-game confirmation.
"""
from pathlib import Path
import json, struct
ROOT = Path(__file__).resolve().parents[1]
ns = {'__file__':str(ROOT/'tests/exo_repair_test.py')}
exec(compile((ROOT/'tests/exo_repair_test.py').read_text().split('\nmem, lua, cfg, rec, logs = fixture()',1)[0], 'exo-harness','exec'),ns)
fixture,run,maps,Q,U,I,F,BASE,ROWS = (ns[k] for k in ('fixture','run','maps','Q','U','I','F','BASE','ROWS'))
CODE=json.loads((ROOT/'tests/fixtures/exo_animation_native_v0.25.json').read_text())
BLOB=(ROOT/'tests/fixtures/exo55_animation_live_v0.25.bin').read_bytes()
PROFILES=json.loads((ROOT/'tests/fixtures/exo55_animation_states_live_v0.25.json').read_text())['profiles']
EXE=0x180000000
MANAGER,ENTRIES,OWNERS,APIROOT,API=0x60000000,0x60001000,0x60002000,0x60003000,0x60004000
UM,GEN,OBJECTS,OBJ,VT,CTRL,DEF,STATES=0x61000000,0x61001000,0x61002000,0x61003000,0x61004000,0x61005000,0x62000000,0x61006000
DESC=0x20000000+0xf32f18
FINE,LEFT,RIGHT=0xbdf3a6a1,0xb8349337,0x50781aab
u=lambda p:struct.unpack_from('<I',BLOB,p)[0]
NODES=[0x50+u(0x54+i*4) for i in range(u(4))]
ALL_STATES=[[node+u(node+12+j*4) for j in range(u(node+8))] for node in NODES]


def make():
    mem,lua,cfg,rec,logs=fixture('35dbf54f016f3624','exo55_health_live_v0.23.bin')
    for span in CODE['spans']:
        mem.w((BASE if span['module']=='game.dll' else EXE)+span['rva'],bytes.fromhex(span['hex']))
    mem.w(BASE+0x3326de8,Q(MANAGER));maps(mem,MANAGER+0x48,ENTRIES,[(100,0)])
    mem.w(MANAGER+0x60,Q(OWNERS));mem.w(OWNERS,Q(DESC))
    mem.w(BASE+0x3326308,Q(APIROOT));mem.w(APIROOT+0x18,Q(API))
    for slot,rva in CODE['slots'].items():mem.w(API+int(slot,16),Q(EXE+rva))
    mem.w(EXE+0x1a100f0,Q(UM));mem.w(UM+0x98,U(8));mem.w(UM+0xa0,Q(GEN));mem.w(GEN,bytes(8))
    mem.w(UM+0x88,Q(OBJECTS));mem.w(OBJECTS+7*8,Q(OBJ));mem.w(OBJ,Q(VT))
    mem.w(VT+0x1b0,Q(EXE+0x2bd9c0));mem.w(OBJ+0x178,Q(CTRL));mem.w(CTRL,Q(OBJ))
    mem.w(CTRL+0x28,Q(DEF));mem.w(CTRL+0x48,U(len(NODES))*2);mem.w(CTRL+0x50,Q(STATES))
    mem.w(DEF,BLOB)
    for i,offset in enumerate(PROFILES[0]['state_offsets']):mem.w(STATES+i*8,Q(DEF+offset))
    r=lua.eval(b'SVR.R');r.exe=lua.table_from({b'base':EXE,b'size':0x4000000})
    r.animations=r.resolve_animation();r.animations_status=b'ok';r.next_check=1000000
    lua.execute(b'''
      sim_gait_calls=0
      local original=SVR.R.invoke
      SVR.R.invoke=function(name,address,manager,entity,event,behavior,replicate)
        if name~='animation_event' then return original(name,address,manager,entity,event) end
        assert(address==0x140808810 and tonumber(require('ffi').cast('uintptr_t',manager))==0x60000000)
        assert(entity==100 and event==0xbdf3a6a1 and behavior==false and replicate==1)
        sim_gait_calls=sim_gait_calls+1
      end
    ''')
    return mem,lua,cfg,rec,logs


mem,lua,cfg,rec,logs=make();mem.w(ROWS,F(1));run(lua,5)
assert lua.eval(b'sim_gait_calls')==1 and lua.eval(b'sim_speed_writes')==0
run(lua,5);assert lua.eval(b'sim_gait_calls')==1,'asynchronous event dispatched every tick'
for i in range(3):mem.w(STATES+i*8,Q(DEF+ALL_STATES[i][0]))
run(lua,20);assert lua.eval(b'sim_gait_calls')==1
log=(logs/'ShieldVehicleResupply.log').read_text(encoding='utf-8')
assert 'exo gait event sent' in log and 'exo gait state normal' in log
print('PASS: residual left limp sends one fine event at normal speed; asynchronous normal state is read back')

mem,lua,cfg,rec,logs=make()
for i in range(3):mem.w(STATES+i*8,Q(DEF+ALL_STATES[i][6 if i else 7]))
run(lua,5);assert lua.eval(b'sim_gait_calls')==1
run(lua,20);assert lua.eval(b'sim_gait_calls')==2,'remaining limp should retry after 2 seconds'
print('PASS: right-leg states use the same verified inverse event; unchanged state retries with a delay')

mem,lua,cfg,rec,logs=make()
for i,offset in enumerate(PROFILES[1]['state_offsets']):mem.w(STATES+i*8,Q(DEF+offset))
run(lua);assert lua.eval(b'sim_gait_calls')==0
print('PASS: intact mech animations are never reset')

mem,lua,cfg,rec,logs=make()
for i in range(3):mem.w(STATES+i*8,Q(DEF+ALL_STATES[i][5]))
run(lua,5);assert lua.eval(b'sim_gait_calls')==1
for i in range(3):mem.w(STATES+i*8,Q(DEF+ALL_STATES[i][2]))
run(lua,25);assert lua.eval(b'sim_gait_calls')==1
lua.eval(b'SVR.R.reset')();assert lua.eval(b'next(SVR.R.gait_pending)') is None
print('PASS: repaired walk state remains walking; reset clears only pending dispatch records')

for why in ('leg damaged','small pool damaged','hull damaged','destroyed','dead','non-authority','disabled fix',
            'disabled part','no shield','cooldown','wrong owner','wrong generation','wrong object','wrong getter',
            'wrong API','wrong controller','wrong version','wrong count','invalid state','invalid fine destination','unrelated fine'):
    mem,lua,cfg,rec,logs=make()
    if why=='leg damaged':mem.w(rec+0xf8+5*4,I(549))
    elif why=='small pool damaged':mem.w(rec+0xf8+6*4,I(0))
    elif why=='hull damaged':mem.w(rec+0x14,I(1799))
    elif why=='destroyed':mem.w(rec+0x20,U(2*4**5))
    elif why=='dead':mem.w(rec+0x19c,U(1))
    elif why=='non-authority':mem.w(DESC+20,U(0))
    elif why=='disabled fix':lua.execute(b'SVR.C.exo_leg_fix=false')
    elif why=='disabled part':lua.execute(b"SVR.C.part['35dbf54f016f3624:64a3fa1d']=false")
    elif why=='no shield':lua.execute(b'SVR.C.test=false')
    elif why=='cooldown':
        lua.execute(b'SVR.C.exo_leg_fix=false');run(lua,10)
        lua.execute(b"SVR.C.exo_leg_fix=true; SVR.C.cooldown=100; SVR.S.last_hit['100:50']=SVR.S.clock")
    elif why=='wrong owner':mem.w(OWNERS,Q(DESC+24));mem.w(DESC+24,mem.r(DESC,24));mem.w(DESC+24+8,U(101))
    elif why=='wrong generation':mem.w(GEN+7,b'\1')
    elif why=='wrong object':mem.w(OBJECTS+7*8,Q(0))
    elif why=='wrong getter':mem.w(VT+0x1b0,Q(EXE+0x2bd9c8))
    elif why=='wrong API':mem.w(API+0x370,Q(EXE+0x201930))
    elif why=='wrong controller':mem.w(CTRL,Q(OBJ+8))
    elif why=='wrong version':mem.w(DEF,U(0x1c))
    elif why=='wrong count':mem.w(CTRL+0x48,U(33))
    elif why=='invalid state':mem.w(STATES,Q(DEF+0x690+4))
    elif why=='invalid fine destination':mem.w(DEF+0x690+u(0x690+0x34)+3*16,U(99))
    elif why=='unrelated fine':
        for i in range(3):
            p=ALL_STATES[i][0];eo=p+u(p+0x2c);ec=u(p+0x28)
            for j in range(ec):
                if u(eo+j*8) in (LEFT,RIGHT):mem.w(DEF+eo+j*8,U(42+j))
    run(lua,5);assert lua.eval(b'sim_gait_calls')==0,why
print('PASS: full repair, selection, authority, range, cooldown, Unit identity and reciprocal transitions gate dispatch')

for why in ('new damage','owner moved','controller moved','state moved','API moved'):
    mem,lua,cfg,rec,logs=make();original=mem.r;injected=[False]
    def changing(a,n):
        result=original(int(a),int(n))
        if a==STATES and n==len(NODES)*8 and not injected[0]:
            injected[0]=True
            if why=='new damage':mem.w(rec+0xf8+5*4,I(100))
            elif why=='owner moved':mem.w(OWNERS,Q(0))
            elif why=='controller moved':mem.w(OBJ+0x178,Q(CTRL+8))
            elif why=='state moved':mem.w(STATES,Q(DEF+ALL_STATES[0][0]))
            elif why=='API moved':mem.w(API+0x370,Q(0))
        return result
    lua.globals()[b'pyread']=changing
    run(lua,5);assert lua.eval(b'sim_gait_calls')==0,why
print('PASS: changes during sampling reject the pending native event')

for span in CODE['spans']:
    mem,lua,cfg,rec,logs=make()
    mem.w((BASE if span['module']=='game.dll' else EXE)+span['rva'],b'\x90')
    try:lua.eval(b'SVR.R.resolve_animation')()
    except Exception:pass
    else:raise AssertionError('animation code guard accepted '+hex(span['rva']))
    assert lua.eval(b'SVR.R.health') is not None and lua.eval(b'SVR.R.stats') is not None
print('PASS: all captured animation/engine code guards reject changes independently of health and speed')

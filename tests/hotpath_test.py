"""Cache invalidation, completed-work polling, restore throttling and FFI reuse."""
from collections import Counter
from pathlib import Path
import tempfile

from lupa import luajit21

ROOT = Path(__file__).resolve().parents[1]


def harness(name, marker):
    path = ROOT / 'tests' / name
    env = {'__file__': str(path)}
    exec(compile(path.read_text(encoding='utf-8').split(marker, 1)[0], name, 'exec'), env)
    return env


lua = luajit21.LuaRuntime(encoding=None)
lua.globals()[b'N'] = lua.execute((ROOT / 'src/vendor/native_hud.lua').read_bytes())
lua.execute(b'''
    raw='abcdefghijklmnop'
    local g=N.graph(function(p,n)return raw:sub(p-0x100000+1,p-0x100000+n)end,0)
    assert(g:read_fields(0x100000,16,{{0,4},{12,4}})==raw and #g.watches==2)
    raw='abcdXXXXXXXXmnop';g:validate()
    raw='ZbcdXXXXXXXXmnop'
    local ok,why=pcall(function()g:read_fields(0x100000,16,{{0,4},{12,4}})end)
    assert(not ok and why=='identity changed during sample')
    ok,why=pcall(function()g:validate()end)
    assert(not ok and why=='identity changed during sample')
    ok,why=pcall(function()g:read_fields(0x100000,16,{{15,2}})end)
    assert(not ok and why=='watched field bounds')
''')
print('PASS: batched reads validate identity fields, allow mutable fields and reject invalid ranges')


fx = harness('exo_leg_effect_test.py', '\nmem, lua, cfg, rec, logs = make()')
mem, lua, cfg, rec, logs = fx['make']()
fx['run'](lua, 5)
lua.execute(b'''
    function stop_fire()
        local v=SVR.S.vehicles[1]
        return SVR.R.stop_leg_fire(v.d,v.zcache.cfg,v.zcache.zones,SVR.F.config_address)
    end
''')
reads = Counter()


def counted(a, n):
    reads[(int(a), int(n))] += 1
    return mem.r(int(a), int(n))


lua.globals()[b'pyread'] = counted
scans = lua.eval(b'SVR.R.effect_scans')
assert lua.eval(b'stop_fire')() == (False, b'no active leg fire')
assert lua.eval(b'SVR.R.effect_scans') == scans
assert reads[(fx['ECFG'] + 8, 2560)] == 1
assert not any(fx['ECFG'] + 8 <= a < fx['ECFG'] + 8 + 2560 and n == 80 for a, n in reads)
mem.w(fx['ECFG'] + 8 + 10 * 80 + 48, fx['U'](0xa1d3345e))
ok, why = lua.eval(b'function()return pcall(stop_fire)end')()
assert not ok and b'duplicate' in why
print('PASS: effect configuration parsed once and read in one block; warmed duplicate names rejected')

gait = harness('exo_gait_test.py', '\nmem,lua,cfg,rec,logs=make();')
mem, lua, cfg, rec, logs = gait['make']()
for i, offset in enumerate(gait['PROFILES'][1]['state_offsets']):
    mem.w(gait['STATES'] + i * 8, gait['Q'](gait['DEF'] + offset))
lua.execute(b'''
    leg_checks=0
    local original=SVR.R.fix_leg
    SVR.R.fix_leg=function(...)leg_checks=leg_checks+1;return original(...)end
    SVR.R.stop_leg_fire=function()return false,'no active leg fire'end
''')
gait['run'](lua, 10)
assert lua.eval(b'leg_checks') == 1
mem.w(rec + 0xf8 + 5 * 4, gait['I'](549))
gait['run'](lua, 5)
mem.w(rec + 0xf8 + 5 * 4, gait['I'](550))
gait['run'](lua, 5)
assert lua.eval(b'leg_checks') == 2, 'damage did not reset the quiet polling interval'
gait['run'](lua, 10)
assert lua.eval(b'leg_checks') == 2
lua.execute(b'''
    local v=SVR.S.vehicles[1]
    proof=SVR.R.leg_proof(v.d,v.zcache.cfg,v.zcache.zones,SVR.F.config_address)
''')
mem.w(gait['ROWS'], gait['F'](.75))
mem.w(rec + 0xf8 + 5 * 4, gait['I'](100))
ok, why = lua.eval(b'''function()
    local v=SVR.S.vehicles[1]
    return pcall(SVR.R.fix_leg,v.d,v.zcache.cfg,v.zcache.zones,SVR.W.f32,SVR.F.config_address,proof)
end''')()
assert not ok and why == b'identity changed during sample'
assert mem.r(gait['ROWS'], 4) == gait['F'](.75)
print('PASS: normal legs checked every 2 seconds; damage resets polling and shared proof rejects new damage')

tyre = harness('tyre_fault_test.py', '\nmem,lua,cfg,rec,logs,samples=fixture();')
mem, lua, cfg, rec, logs, samples = tyre['fixture']()
tyre['run'](lua, 3)
scans = lua.eval(b'SVR.R.wheel_layout_scans')
lua.execute(b'for i=1,5 do SVR.R.tyre_snapshot(svr_d) end')
assert lua.eval(b'SVR.R.wheel_layout_scans') == scans
mem.w(0x52002100 + 0x20 + 12, tyre['F'](99))
ok, why = lua.eval(b'function()return pcall(SVR.R.tyre_snapshot,svr_d)end')()
assert not ok and b'centre' in why
print('PASS: wheel geometry mapping cached; changed centres revalidated before reuse')

mem, lua, cfg, rec, logs, samples = tyre['fixture']()
tyre['run'](lua, 3)
mem.w(rec + 0xf8, tyre['I'](1))
tyre['run'](lua, 1)
lua.execute(b'SVR.C.enabled=false;sim_fail_set=true;update(0.1)')
sets = lua.eval(b'sim_calls.set')
assert lua.eval(b'SVR.T.close_clean') is False
lua.execute(b'for i=1,20 do update(0.01)end')
assert lua.eval(b'sim_calls.set') == sets, 'pending restore retried on every frame'
lua.execute(b'sim_fail_set=false;update(0.5)')
assert lua.eval(b'SVR.T.close_clean') is True
assert lua.globals()[b'sim_wheels'][2] == samples[2]
reads.clear()
lua.globals()[b'pyread'] = counted
lua.execute(b'for i=1,20 do update(0.01)end')
assert not reads, 'disabled, restored guard still reads process memory'
lua.execute(b'SVR.C.enabled=true;update(0.1)')
assert lua.globals()[b'sim_wheels'][2][40] == 1, 'off/on discarded the failure latch'
print('PASS: failed restores throttled to 0.5 seconds, completed work stays idle and off/on keeps latches')

# Run the actual write helpers against mocked Win32 calls, not the harness's W replacements.
lua = luajit21.LuaRuntime(encoding=None)
with tempfile.TemporaryDirectory(prefix='.run-buffers-', dir=ROOT / 'tests') as temp:
    logdir = Path(temp) / 'CowboyBingus/Helldivers2/Logs'
    logdir.mkdir(parents=True)
    lua.globals()[b'localpath'] = str(Path(temp)).encode()
    lua.execute(b'''
        local real=require('ffi');local original=require;local proxy={}
        for k,v in pairs(real)do proxy[k]=v end
        allocations=0
        proxy.new=function(...)allocations=allocations+1;return real.new(...)end
        memory={};page_protection=4;protect_calls=0
        local kernel={}
        kernel.GetCurrentProcess=function()return real.cast('void *',1)end
        kernel.GetModuleHandleA=function()return nil end
        kernel.VirtualQuery=function(p,mbi)
            local addr=tonumber(real.cast('uintptr_t',p))
            assert(addr>=0x100000 and addr<0x101000)
            real.fill(mbi,48);local q=real.cast('uint64_t *',mbi);q[0]=0x100000;q[3]=4096
            local u=real.cast('uint32_t *',mbi);u[8]=0x1000;u[9]=page_protection;u[10]=0x20000
            return 48
        end
        kernel.VirtualProtect=function(p,n,new,old)
            old[0]=page_protection;page_protection=new;protect_calls=protect_calls+1;return 1
        end
        kernel.WriteProcessMemory=function(h,p,b,n,got)
            memory[tonumber(real.cast('uintptr_t',p))]=real.string(b,n);got[0]=n;return 1
        end
        proxy.load=function()return kernel end;proxy.C=kernel
        require=function(name)if name=='ffi'then return proxy end;return original(name)end
        local getenv=os.getenv
        os.getenv=function(name)if name=='LOCALAPPDATA'then return localpath end;return getenv(name)end
        stingray={}
        __SVR_TEST=function(N,W,S,C)
            N.win={read=function(p,n)local s=memory[p];return s and s:sub(1,n)end}
            SVR={N=N,W=W,S=S,C=C}
        end
    ''')
    lua.execute((ROOT / 'dist/shield_vehicle_resupply.lua').read_bytes())
    lua.execute(b'''
        local ffi=require('ffi');local w=SVR.W
        memory[0x100000]='\0\0\0\0';memory[0x100004]='\0\0\0\0'
        memory[0x100008]='\0';memory[0x10000C]='\0\0\0\0'
        local before=allocations
        for i=1,100 do assert(w.i32(0x100000,i-1,i))end
        assert(w.f32(0x100004,memory[0x100004],0.5))
        assert(w.raw1(0x100008,'\0','\1'))
        page_protection=2
        assert(w.raw4(0x10000C,'\0\0\0\0','\1\2\3\4'))
        assert(page_protection==2 and protect_calls==2)
        assert(allocations==before,'per-write FFI allocations remain')
        assert(w.writes==103 and w.fails==0)
        assert(not w.i32(0x100000,99,101) and w.fails==1)
    ''')
print('PASS: actual integer/float/raw writers reuse buffers and restore page protection; old-value checks retained')

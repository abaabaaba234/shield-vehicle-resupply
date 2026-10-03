"""Address-cache invalidation, read counts and entity-state lifetime regression."""
from collections import Counter
import os
from pathlib import Path
import struct
import sys
import tempfile

from lupa import luajit21

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)

# Exercise the real module polling policy separately from the addon harness.
lua = luajit21.LuaRuntime(encoding=None)
lua.globals()[b'N'] = lua.execute((ROOT / 'src/vendor/native_hud.lua').read_bytes())
lua.execute(b'''
    current_base=0x140000000; checks=0; valid=true
    N.win={base=function() return current_base end,begin_sample=function() end,read=function() end}
    N.check_module=function() checks=checks+1; return valid,'test guard' end
    assert(N.ensure(0)); assert(N.ensure(11)); assert(N.ensure(22)); assert(checks==1)
    current_base=0x150000000; assert(N.ensure(33)); assert(checks==2)
    current_base=nil; assert(not N.ensure(44))
    current_base=0x150000000; valid=false; assert(not N.ensure(46)); assert(checks==3)
    valid=true; assert(N.ensure(57)); assert(checks==4)
''')
print('PASS: static module guards cached; relocation, unload and failed initialization rechecked')

setup = (ROOT / 'tests/svr_test.py').read_text(encoding='utf-8').split("L.execute(b'for i=1,40", 1)[0]
setup = setup.replace('__SVR_TEST=function(N,W,S,C)', '__SVR_TEST=function(N,W,S,C,R,F,T)')
setup = setup.replace('_G.SVR={N=N,W=W,S=S,C=C}', '''
    C.enabled=false; C.tires=false; C.part_repair=false; C.exo_leg_fix=false
    C.exo_weapon_guard=false; C.exo_shield_guard=false; C.frv_tire_guard=false
    _G.SVR={N=N,W=W,S=S,C=C,R=R,F=F,T=T}
''')
os.environ['LOCALAPPDATA'] = tempfile.mkdtemp(prefix='.run-cache-', dir=ROOT / 'tests')
old_args = sys.argv
sys.argv = [__file__]
env = {'__file__': str(ROOT / 'tests/svr_test.py')}
try:
    exec(compile(setup, 'cache-harness', 'exec'), env)
finally:
    sys.argv = old_args
mem, lua = env['M'], env['L']
Q, U = env['Q'], env['U']
table = env['table']
reads = Counter()


def read(address, size):
    reads[int(address)] += 1
    return mem.r(int(address), int(size))


lua.globals()[b'pyread'] = read
lua.execute(b'SVR.N.ensure()')
table(0x70000000, 0x70001000, [(100, 0), (116, 1), (132, 2)])
lua.execute(b'''
    function lookup()
        local g=SVR.N.sample_graph()
        local j=g:lookup(g:table(0x70000000),132)
        g:validate(); return j,g.calls
    end
''')
first = lua.eval(b'lookup')()
second = lua.eval(b'lookup')()
assert first[0] == second[0] == 2 and second[1] < first[1], (first, second)
mem.w(0x70001000 + 6 * 8 + 4, U(9))
assert lua.eval(b'lookup')()[0] == 9, 'cached contents reused after dense-index change'
mem.w(0x70001000 + 6 * 8, U(148) + U(3))
mem.w(0x70001000 + 7 * 8, U(132) + U(4))
assert lua.eval(b'lookup')()[0] == 4, 'moved hash entry not rediscovered'
table(0x70000000, 0x70002000, [(132, 7)], cap=32)
assert lua.eval(b'lookup')()[0] == 7, 'reallocated hash table used stale slot'
lua.globals()[b'mutate'] = lambda: mem.w(0x70002000 + 4 * 8 + 4, U(8))
lua.execute(b'''
    local g=SVR.N.sample_graph()
    assert(g:lookup(g:table(0x70000000),132)==7)
    mutate(); local ok,why=pcall(function()g:validate()end)
    assert(not ok and why=='identity changed during sample')
''')
print(f'PASS: cached hash slot reads {first[1]} -> {second[1]}; dense moves, reallocations and races validated')

st, res, cfg = env['st'], env['res'], env['cfg']
slot = res % 1002
mem.w(st + slot * 16, Q(1) + U(0) + U(0))
row = st + ((slot + 1) % 1002) * 16
mem.w(row, Q(res) + U(3) + U(0))
lua.globals()[b'resource'] = f'{res:016x}'.encode()
lua.execute(b'''
    function config()
        local g=SVR.N.sample_graph()
        local cfg=SVR.F.config_address(g,0x20000000,0x30000000,{entity=100,resource=resource})
        g:validate(); return cfg
    end
''')
assert lua.eval(b'config')() == cfg
reads.clear()
assert lua.eval(b'config')() == cfg
assert reads[st + slot * 16] == 0, 'cached config still traverses collision chain'
mem.w(row + 8, U(4))
assert lua.eval(b'config')() == st + 0x3EA0 + 4 * 0x5650
mem.w(row, Q(2))
newrow = st + ((slot + 2) % 1002) * 16
mem.w(newrow, Q(res) + U(3) + U(0))
assert lua.eval(b'config')() == cfg
newst = 0x71000000
mem.w(newst, bytes(1002 * 16))
mem.w(newst + slot * 16, Q(res) + U(2) + U(0))
mem.w(env['net'] + 0xF12B78, Q(newst))
assert lua.eval(b'config')() == newst + 0x3EA0 + 2 * 0x5650
table(env['hm'] + 0x1070, 0x72000000, [(100, 1)])
mem.w(env['hm'] + 0x10B0, Q(0x73000000))
assert lua.eval(b'config')() == 0x73000000 + 0x5650, 'cached shared config hid per-entity override'
print('PASS: config collision chain scanned once; row moves, roots and entity overrides stay live')

reads.clear()
lua.execute(b'''
    local r=SVR.R
    r.base=SVR.N.base; r.next_check=10
    for _,name in ipairs({'health','wheels','stats','attach','bash','effects','animations'}) do r[name]={} end
    assert(r.ensure(11)); assert(r.ensure(22))
    r.reset(); assert(r.health~=nil and r.animations~=nil)
''')
assert not reads, 'successful static repair interfaces resolved again'
lua.execute(b'SVR.R.next_check=0; assert(not SVR.R.ensure(23))')
assert reads, 'explicit interface recheck ignored missing guards'
print('PASS: validated repair interfaces retained across polling/reset; explicit guard rechecks supported')

lua.execute(b'update(0.1)')
scans = lua.eval(b'SVR.S.index_scans')
lua.execute(b'for i=1,31 do update(0.1) end')
assert lua.eval(b'SVR.S.index_scans') == scans
assert lua.eval(b'SVR.S.index_hits') >= 2
table(env['hm'] + 0x1030, 0x31000000, [])
lua.execute(b'''
    SVR.S.last_total['100:50']=100
    SVR.S.last_hit['100:50:net']=1
    SVR.S.frac['100:50:h']=0.5
    SVR.S.ammo_max['100:50:magcurrent']=6
    SVR.S.ammo_max[resource..':magcurrent']=6
    SVR.R.observations['100:50:7:'..resource]={}
    SVR.R.gait_pending['100:7:50:'..resource]={}
    SVR.F.reports['100:50:7:'..resource..':test']=true
    SVR.T.reports['100:50:7:'..resource..':test']=true
    SVR.S.next_roster=0; update(0.1)
    assert(#SVR.S.vehicles==0)
    assert(next(SVR.S.last_total)==nil and next(SVR.S.last_hit)==nil and next(SVR.S.frac)==nil)
    assert(SVR.S.ammo_max['100:50:magcurrent']==nil and SVR.S.ammo_max[resource..':magcurrent']==6)
    assert(next(SVR.R.observations)==nil and next(SVR.R.gait_pending)==nil)
    assert(next(SVR.F.reports)==nil and next(SVR.T.reports)==nil)
''')
print('PASS: unchanged indices reused; removed entity counters/reports released, model ammo caps retained')

# Cache storage remains bounded as object identities and tables accumulate.
table(0x75000000, 0x75001000, [(i, i) for i in range(512)], cap=1024)
lua.execute(b'''
    for i=0,511 do
        local g=SVR.N.sample_graph()
        assert(g:lookup(g:table(0x75000000),i)==i)
    end
    local n=0; for _ in pairs(SVR.N.lookup_cache[0x75000000].slots) do n=n+1 end
    assert(n==256)
''')
for i in range(20):
    table(0x74000000 + i * 0x2000, 0x74001000 + i * 0x2000, [(100, 0)])
lua.execute(b'''
    for i=0,19 do
        local g=SVR.N.sample_graph()
        assert(g:lookup(g:table(0x74000000+i*0x2000),100)==0)
    end
    assert(SVR.N.lookup_tables<=16)
    for _,t in pairs(SVR.N.lookup_cache) do
        local n=0;for _ in pairs(t.slots) do n=n+1 end;assert(n<=256)
    end
    stingray.Application.main_world=function()return nil end
    update(0.1)
    assert(next(SVR.S.index_cache)==nil and next(SVR.S.config_cache)==nil)
    assert(SVR.N.lookup_cache==nil and SVR.S.watch==nil and SVR.S.prev_counts==nil)
    assert(not SVR.S.errors)
''')
print('PASS: address caches bounded and cleared on session loss; no addon update errors')

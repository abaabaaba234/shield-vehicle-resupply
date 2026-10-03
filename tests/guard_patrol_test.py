"""Fresh-identity patrols, critical-state fallback and guard read counts."""
from collections import Counter
from pathlib import Path

from lupa import luajit21

ROOT = Path(__file__).resolve().parents[1]


def harness(name, marker):
    path = ROOT / 'tests' / name
    env = {'__file__': str(path)}
    exec(compile(path.read_text(encoding='utf-8').split(marker, 1)[0], name, 'exec'), env)
    return env


weapon = harness('weapon_fault_test.py', '\nmem,lua,cfg,rec,logs,original=fixture()')
tyre = harness('tyre_fault_test.py', '\nmem,lua,cfg,rec,logs,samples=fixture();')


def measured(env, module, full):
    mem, lua, *_ = env['fixture']()
    env['run'](lua, 3)
    reads = Counter()

    def read(p, n):
        reads['calls'] += 1
        reads['bytes'] += int(n)
        return mem.r(int(p), int(n))

    lua.globals()[b'pyread'] = read
    lua.execute(b'''
        guard_native_calls=0
        local original=SVR.R.invoke
        SVR.R.invoke=function(...)
            guard_native_calls=guard_native_calls+1;return original(...)
        end
    ''')
    clear = f'for _,st in pairs(SVR.{module}.states)do st.poll=nil end;' if full else ''
    lua.execute(f'for i=1,20 do {clear}SVR.{module}.step(SVR.S.vehicles,0.3+i*0.05)end'.encode())
    return reads, lua.eval(b'guard_native_calls')


for env, module, baseline in ((weapon, 'F', 2960), (tyre, 'T', 2720)):
    patrol, calls = measured(env, module, False)
    full, full_calls = measured(env, module, True)
    assert patrol['calls'] < full['calls'] * .55, (module, patrol, full)
    assert patrol['calls'] < baseline * .35, (module, patrol)
    if module == 'T':
        assert calls <= 5 and calls <= full_calls * .25, (calls, full_calls)
    print(f'PASS: {module} 20 healthy polls: perf2 {baseline} -> {patrol["calls"]} reads; '
          f'forced full {full["calls"]}; native calls {calls} vs {full_calls}')


for change in ('owner', 'authority', 'parent', 'parent dead', 'zone', 'ammo root'):
    mem, lua, cfg, rec, logs, original = weapon['fixture']()
    weapon['run'](lua, 3)
    assert lua.eval(b'SVR.F.patrols') >= 1
    if change == 'owner':
        mem.w(0x20000000 + 0xF32F18 + 12, weapon['U'](99))
    elif change == 'authority':
        mem.w(0x20000000 + 0xF32F18 + 20, weapon['U'](0))
    elif change == 'parent':
        mem.w(weapon['env']['AROWS'], weapon['U'](0))
    elif change == 'parent dead':
        mem.w(rec + 0x1B8 + 0x14, weapon['I'](0))
    elif change == 'zone':
        mem.w(cfg + 0x208 + 0x60, weapon['U'](1))
    else:
        mem.w(weapon['BASE'] + 0x3326648, weapon['Q'](0))
    mem.w(rec + 0xF8, weapon['I'](1))
    weapon['run'](lua, 1)
    assert weapon['ammo'](mem) == weapon['I'](55) + weapon['I'](6), change
print('PASS: warmed weapon patrol rejects changed owner, authority, parent, zone and ammunition root')

mem, lua, cfg, rec, logs, original = weapon['fixture']()
weapon['run'](lua, 3)
full = lua.eval(b'SVR.F.full_samples')
mem.w(cfg + 0x208 + 0xF0, b'\0')
weapon['run'](lua, 1)
assert lua.eval(b'SVR.F.full_samples') > full
assert all(state[b'poll'] is None for _, state in lua.eval(b'SVR.F.states').items())
print('PASS: externally modified protection bytes invalidate patrol without claiming protection is armed')

mem, lua, cfg, rec, logs, original = weapon['fixture']()
changed = False


def race(p, n):
    global changed
    if not changed and int(p) == rec + 0x1B8 + 0x14:
        changed = True
        mem.w(0x20000000 + 0xF32F18 + 12, weapon['U'](99))
    return mem.r(int(p), int(n))


lua.globals()[b'pyread'] = race
weapon['run'](lua, 1)
assert changed
assert mem.r(cfg, 0x5650) == original
assert weapon['ammo'](mem) == weapon['I'](55) + weapon['I'](6)
print('PASS: deferred combined proof still rejects identity changes before the first protection write')

mem, lua, cfg, rec, logs, samples = tyre['fixture']()
tyre['run'](lua, 3)
assert lua.eval(b'SVR.T.patrols') >= 1
mem.w(0x52001080, tyre['U'](0x40000002))
mem.w(rec + 0xF8, tyre['I'](1))
tyre['run'](lua, 1)
assert lua.eval(b'sim_calls.damage') == 0
print('PASS: critical tyre HP immediately reacquires physics and rejects a replaced handle generation')

mem, lua, cfg, rec, logs, samples = tyre['fixture']()
tyre['run'](lua, 3)
mem.w(rec + 0xF8, tyre['I'](1))
lua.execute(b'SVR.T.step(SVR.S.vehicles,0.4)')
lua.execute(b'''
    wheel_reads={[0]=0,[1]=0,[2]=0,[3]=0}
    local original=SVR.R.invoke
    SVR.R.invoke=function(name,address,a,b,...)
        if name=='get' then wheel_reads[b]=wheel_reads[b]+1 end
        return original(name,address,a,b,...)
    end
    for i=1,20 do SVR.T.step(SVR.S.vehicles,0.4+i*0.05)end
''')
assert [lua.globals()[b'wheel_reads'][i] for i in range(4)] == [1, 1, 20, 1]
lua.globals()[b'sim_wheels'][2] = samples[2]
lua.execute(b'SVR.T.step(SVR.S.vehicles,1.45)')
assert tyre['physical'](lua, 2)[40] == 1 and lua.eval(b'sim_calls.damage') == 2
print('PASS: one failed wheel uses 23 getters/second instead of 80; healthy wheels checked once, external repair re-punctured')


for env, module in ((weapon, 'F'), (tyre, 'T')):
    mem, lua, cfg, rec, *_ = env['fixture']()
    env['run'](lua, 3)
    lua.execute(f'for _,st in pairs(SVR.{module}.states)do st.poll.next_full=1000 end'.encode())
    lua.execute(f'for i=1,1000 do SVR.{module}.step(SVR.S.vehicles,0.3+i*0.05)end'.encode())
    assert lua.eval(f'SVR.{module}.patrols'.encode()) >= 1000
    mem.w(rec + 0xF8, env['I'](1))
    lua.execute(f'SVR.{module}.step(SVR.S.vehicles,51)'.encode())
    if module == 'F':
        assert weapon['failed'](lua) and weapon['ammo'](mem) == bytes(8)
    else:
        assert lua.eval(b'sim_calls.damage') == 1 and tyre['physical'](lua, 2)[40] == 1
print('PASS: 1000 fresh patrols stay within per-sample budgets; 1 HP latches in the same poll')

lua = luajit21.LuaRuntime(encoding=None)
lua.globals()[b'N'] = lua.execute((ROOT / 'src/vendor/native_hud.lua').read_bytes())
lua.execute(b'''
    raw='abcdefgh'
    local g=N.graph(function(p,n)return raw:sub(p-0x100000+1,p-0x100000+n)end,0)
    g:watch(0x100000,4);g:validate();local first=g.validation
    g:validate();assert(g.validation==first)
    g:watch(0x100004,4);g:validate();assert(g.validation~=first)
    raw='abcdEfgh'
    local ok,why=pcall(function()g:poll(0x100000,8)end)
    assert(not ok and why=='identity changed during sample')
''')
print('PASS: validation plans reuse only ranges, rebuild for new fields and reject newly watched changes')

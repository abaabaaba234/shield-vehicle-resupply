"""Real ModOptionsMenu registration/apply API, plus native restore fixtures.

No game UI hook or real process memory is called. Override
HD2_MOD_OPTIONS_MENU_SOURCE to point to the installed provider's Lua source.
"""
import os
from pathlib import Path
import struct
import tempfile
import zipfile
from lupa import luajit21

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT/'dist/shield_vehicle_resupply.lua').read_bytes()
PROVIDER = Path(os.environ.get('HD2_MOD_OPTIONS_MENU_SOURCE', ROOT.parent/
    'eruptor-original-shrapnel/research/references/mod_options_menu_9ba626afa44a3aa3.patch_15.lua'))
PREFIX = b'shield_vehicle_resupply_'


def real_menu(lua):
    source = PROVIDER.read_bytes().split(b'_G.ModOptionsMenu = api', 1)[0]
    assert len(source) > 50000
    return lua.execute(source+b'''\n_G.ModOptionsMenu=api
      return {api=api,state=state,translation=translation,
              set_pending=set_pending,apply_pending=apply_pending}''')


class Scenario:
    def __init__(self, settings=None):
        self.temp = tempfile.TemporaryDirectory(prefix='.run-menu-',dir=ROOT/'tests')
        self.logs = Path(self.temp.name)/'CowboyBingus/Helldivers2/Logs'
        self.logs.mkdir(parents=True)
        self.settings = self.logs/'shield_resupply_settings.txt'
        if settings is not None:
            self.settings.write_text(settings,encoding='utf-8')
        self.lua = luajit21.LuaRuntime(encoding=None)
        self.lua.globals()[b'localpath'] = str(Path(self.temp.name)).encode()
        self.lua.execute(b'''
          local original=require; local real=original('ffi');local ffi={}
          for k,v in pairs(real)do ffi[k]=v end
          ffi.load=function()return setmetatable({
            GetCurrentProcess=function()return real.cast('void *',1)end
          },{__index=function(_,key)return function()error('Unexpected native call: '..key)end end})end
          require=function(name)if name=='ffi' then return ffi end;return original(name)end
          local getenv=os.getenv
          os.getenv=function(k)if k=='LOCALAPPDATA' then return localpath end;return getenv(k)end
          stingray={Application={main_world=function()end},Network={game_session=function()end}}
          update=function(dt,extra)return dt,extra,42 end
          __SVR_TEST=function(N,W,S,C)W.fast=false;SVR={N=N,W=W,S=S,C=C}end
        ''')
        self.lua.eval(b'function(s)return assert(loadstring(s,"@addon"))()end')(SOURCE)

    def tick(self,n=10):
        self.lua.execute(('for i=1,%d do update(0.1) end'%n).encode())

    def close(self):
        self.temp.cleanup()


legacy = ('\ufeff# keep comment\nexo_heal=0.035 # custom rate\nenabled=0\n'
          'radius=17.5\npart=35dbf54f016f3624:ca47a7a9=0\n'
          'part=35dbf54f016f3624:64a3fa1d=1\n'
          'shield=1111111111111111\nweapon=2222222222222222\n'
          'ammo_max=df51fe8d62f294be:roundsreserve=60\nfuture_setting=abc\n')
s=Scenario(legacy)
try:
    # Register with stale provider cache. Configuration wins without changing it.
    menu=real_menu(s.lua)
    s.lua.globals()[b'menu_state']=menu[b'state']
    s.lua.execute(b"menu_state.saved={shield_vehicle_resupply_language='2',shield_vehicle_resupply_enabled='true',shield_vehicle_resupply_radius='1'}")
    s.tick()
    api, state = menu[b'api'],menu[b'state']
    options=state[b'options']; language=options[PREFIX+b'language']
    mod=state[b'mods'][language[b'mod']]
    assert state[b'option_count']==27 and mod[b'order'][1][b'id']==PREFIX+b'language'
    assert language[b'label']==b'Language' and language[b'choices'][1]=='简体汉字'.encode()
    assert language[b'choices'][2]==b'ENGLISH'
    assert api[b'get'](PREFIX+b'enabled') is False
    assert api[b'get'](PREFIX+b'radius')==17.5 and api[b'get'](PREFIX+b'exo_heal')==3.5
    assert s.lua.eval(b'SVR.C.language')==b'zh' and s.lua.eval(b'SVR.C.exo_heal')==0.035
    assert s.settings.read_text(encoding='utf-8')==legacy
    assert s.lua.eval(b'update')(0.1,b'chain')==(0.1,b'chain',42)
    # Pending values survive repeated sync and cancel without applying.
    menu[b'set_pending'](PREFIX+b'radius',20)
    s.tick(40)
    assert state[b'pending'][PREFIX+b'radius']==20
    assert s.lua.eval(b'SVR.C.radius')==17.5
    # Apply language and radius together; dynamic text refresh is explicit.
    menu[b'set_pending'](PREFIX+b'language',2)
    assert menu[b'apply_pending']()==2
    assert options[PREFIX+b'enabled'][b'label']=='启用模组'.encode()
    menu[b'translation'][b'refresh']()
    assert options[PREFIX+b'enabled'][b'label']==b'Enable Mod'
    assert options[PREFIX+b'heal'][b'choices'][1]==b'NATIVE'
    assert mod[b'title']==b'SHIELD VEHICLE RESUPPLY'
    saved=s.settings.read_text(encoding='utf-8')
    assert 'radius=20' in saved and 'language=en' in saved
    for line in legacy.lstrip('\ufeff').splitlines():
        if not line.startswith('radius='): assert line in saved,line
    assert s.lua.eval(b'SVR.C.exo_heal')==0.035 and s.lua.eval(b'SVR.C.enabled') is False
    # Switching language alone has no effect on any business config.
    before=s.lua.eval(b'SVR.W.writes')
    menu[b'set_pending'](PREFIX+b'language',1);menu[b'apply_pending']()
    menu[b'translation'][b'refresh']()
    assert s.lua.eval(b'SVR.W.writes')==before
    assert mod[b'title']=='护盾载具回血补弹'.encode()
    for _,callbacks in state[b'callbacks'].items(): assert len(callbacks)==1
    # Out-of-range / off-step file values are displayed as bounded snapshots.
    # Sync must not repeatedly erase an unapplied edit or alter file values.
    s.lua.execute(b'SVR.C.radius=200;SVR.C.exo_heal=0.0355')
    s.tick();assert api[b'get'](PREFIX+b'radius')==100
    menu[b'set_pending'](PREFIX+b'radius',25);s.tick(30)
    assert state[b'pending'][PREFIX+b'radius']==25
    assert s.lua.eval(b'SVR.C.radius')==200 and s.lua.eval(b'SVR.C.exo_heal')==0.0355
    # Invalid callback values and write failures leave runtime configuration.
    callback=state[b'callbacks'][PREFIX+b'radius'][1]
    for invalid in (-1,101,17.25,float('nan'),float('inf'),b'20'):
        callback(invalid);assert s.lua.eval(b'SVR.C.radius')==200
    enabled_callback=state[b'callbacks'][PREFIX+b'enabled'][1]
    enabled_callback(0);assert s.lua.eval(b'SVR.C.enabled') is False
    s.lua.execute(b"local open=io.open;io.open=function(path,mode)if path:match('shield_resupply_settings.txt$') and mode=='wb' then return nil,'mock write failure' end;return open(path,mode)end")
    callback(30);s.tick()
    assert s.lua.eval(b'SVR.C.radius')==200
    assert 'save failed' in (s.logs/'ShieldVehicleResupply.log').read_text(encoding='utf-8')
finally:s.close()
print('PASS: real provider ordering, stale cache, pending edits, language, percent mapping, config preservation, validation and save failure')

s=Scenario(saved)
try:
    menu=real_menu(s.lua);s.tick()
    assert menu[b'api'][b'get'](PREFIX+b'language')==2
    assert menu[b'api'][b'get'](PREFIX+b'radius')==20
    assert menu[b'api'][b'get'](PREFIX+b'enabled') is False
finally:s.close()

for failure in ('absent','old','register','callback','set'):
    s=Scenario('enabled=0\nradius=22\nlanguage=bad\n')
    try:
        s.tick()
        if failure=='old':s.lua.execute(b'ModOptionsMenu={api=1,version=1}')
        elif failure!='absent':
            menu=real_menu(s.lua)
            method={'register':'register_option','callback':'on_change','set':'set'}[failure]
            menu[b'api'][method.encode()]=s.lua.eval(b"function()return false,'mock unavailable'end")
            if failure=='set':menu[b'state'][b'saved']=s.lua.table_from({PREFIX+b'radius':b'1'})
        s.tick(30)
        assert s.lua.eval(b'SVR.C.enabled') is False and s.lua.eval(b'SVR.C.radius')==22
        assert s.lua.eval(b'SVR.C.language')==b'zh'
        assert s.lua.eval(b'SVR.S.errors') is None
        log=(s.logs/'ShieldVehicleResupply.log').read_text(encoding='utf-8')
        assert log.count('Optional MODS menu unavailable')==(0 if failure=='absent' else 1)
        if failure=='absent':
            menu=real_menu(s.lua);s.tick()
            assert menu[b'state'][b'option_count']==27
            # Singleton reload keeps the original update chain and callbacks.
            result=s.lua.eval(b'function(s)return assert(loadstring(s))()end')(SOURCE)
            assert result[b'duplicate'] is True
            s.tick();assert menu[b'state'][b'option_count']==27
    finally:s.close()
print('PASS: restart, late loading, duplicate addon, missing/old/failing optional provider; core config stays usable')

# Replay the packaged addon with fake native memory and actual configuration
# opening/restoring. This proves callbacks reach the existing business paths.
ns={'__file__':str(ROOT/'tests/repair_native_test.py')}
harness=(ROOT/'tests/repair_native_test.py').read_text(encoding='utf-8')
exec(compile(harness.split('\nmem, lua, cfg, rec, logs, samples = make()',1)[0],'restore-harness','exec'),ns)
mem,lua,cfg,rec,logs,samples=ns['make']()
menu=real_menu(lua);ns['run'](lua,10)
api,state=menu[b'api'],menu[b'state']
assert api[b'get'](PREFIX+b'enabled') is True
menu[b'set_pending'](PREFIX+b'tank_heal',7.5);menu[b'set_pending'](PREFIX+b'ammo',False)
menu[b'apply_pending']();assert abs(lua.eval(b'SVR.C.tank_heal')-0.075)<1e-9
assert lua.eval(b'SVR.C.ammo') is False
lua.execute(b"SVR.C.heal='native';SVR.C.part_repair=false;SVR.C.test=true")
ns['run'](lua,10)
assert struct.unpack('<f',mem.r(cfg+4,4))[0]>0
menu[b'set_pending'](PREFIX+b'enabled',False);menu[b'apply_pending']()
assert lua.eval(b'SVR.C.enabled') is False
assert mem.r(cfg+4,4)==struct.pack('<f',0)
# External file reload still runs the normal command and syncs to the menu.
path=logs/'shield_resupply_settings.txt'
path.write_text('enabled=1\nheal=off\nradius=18\nlanguage=en\n',encoding='utf-8')
(logs/'shield_resupply_cmd.txt').write_text('reload\n',encoding='utf-8')
ns['run'](lua,20)
assert api[b'get'](PREFIX+b'enabled') is True
assert api[b'get'](PREFIX+b'heal')==3 and api[b'get'](PREFIX+b'radius')==18
assert api[b'get'](PREFIX+b'language')==2
print('PASS: packaged addon applies numeric/toggle settings, restores native regen on disable and synchronizes command reload')

ns={'__file__':str(ROOT/'tests/weapon_fault_test.py')}
harness=(ROOT/'tests/weapon_fault_test.py').read_text(encoding='utf-8')
exec(compile(harness.split('\nmem,lua,cfg,rec,logs,original=fixture()',1)[0],'weapon-menu-harness','exec'),ns)
mem,lua,cfg,rec,logs,original=ns['fixture']()
menu=real_menu(lua);ns['run'](lua,5)
mem.w(rec+0xf8,struct.pack('<i',1));ns['run'](lua,2)
assert ns['ammo'](mem)==bytes(8)
menu[b'set_pending'](PREFIX+b'enabled',False);menu[b'apply_pending']()
assert mem.r(cfg,0x5650)==original and ns['ammo'](mem)==struct.pack('<ii',55,6)
print('PASS: menu disable restores weapon protection and escrowed ammo through the original close path')

ns={'__file__':str(ROOT/'tests/tyre_fault_test.py')}
harness=(ROOT/'tests/tyre_fault_test.py').read_text(encoding='utf-8')
exec(compile(harness.split('\nmem,lua,cfg,rec,logs,samples=fixture();original=',1)[0],'tyre-menu-harness','exec'),ns)
mem,lua,cfg,rec,logs,samples=ns['fixture']();original=mem.r(cfg,0x5650)
menu=real_menu(lua);ns['run'](lua,5)
mem.w(rec+0xf8,struct.pack('<i',1));ns['run'](lua,2)
assert ns['physical'](lua,2)[40]==1
menu[b'set_pending'](PREFIX+b'enabled',False);menu[b'apply_pending']()
assert mem.r(cfg,0x5650)==original and ns['physical'](lua,2)==samples[2]
print('PASS: menu disable restores tyre protection and native physical parameters')

with zipfile.ZipFile(ROOT/'dist/ShieldVehicleResupply_v0.25-menu-perf3.zip') as archive:
    patch=archive.read('data/9ba626afa44a3aa3.patch_0')
    row=struct.unpack_from('<7Q6I',patch,104)
    size,encoding=struct.unpack_from('<II',patch,row[2])
    assert encoding==2 and patch[row[2]+8:row[2]+8+size]==SOURCE
    assert SOURCE.startswith(b'-- HD2-Addon: mods/shieldresupply/shield_vehicle_resupply\n')
    assert b'ModBindings.new' not in SOURCE
print('PASS: archive payload equals assembled v0.25-menu-perf3 source and preserves addon declaration')

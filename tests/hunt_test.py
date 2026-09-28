# v0.12b hunt 离线测试：游戏在记录之外另存一份血量（0x50000100），扣血时用它算完盖回记录
#   py tests/hunt_test.py
import os, struct, sys, tempfile
tmp = tempfile.mkdtemp()
os.environ['LOCALAPPDATA'] = tmp
logs = os.path.join(tmp, 'CowboyBingus', 'Helldivers2', 'Logs')
os.makedirs(logs)
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'svr_test.py'), encoding='utf-8').read()
setup, _ = src.split("L.execute(b'for i=1,40", 1)
HID = 0x50000100
setup = setup.replace("M.w(rec,bytes(data))", "M.w(rec,bytes(data)); M.w(0x50000000,b'\\0'*0x1000); M.w(%d,I(1000))" % HID)
setup = setup.replace("_G.SVR={N=N,W=W,S=S,C=C}",
    "W.f32=function(p,oldraw,new) local ffi=require('ffi'); local nb=ffi.new('float[1]',new)\n"
    "    if N.win.read(p,4)~=oldraw then return false end; pywrite(p,ffi.string(nb,4)); W.writes=W.writes+1; return true end\n"
    "  W.rw_regions=function() return {{0x31003000,0x1000},{0x50000000,0x1000}} end\n"
    "  W.rpm=function(p,buf,n) local s=pyread(p,n); if not s then return false end; require('ffi').copy(buf,s,n); return true end\n"
    "  _G.SVR={N=N,W=W,S=S,C=C}")
os.chdir(os.path.join(here, '..'))
exec(setup)
Hd = lambda: struct.unpack('<i', M.r(HID, 4))[0]
Hp = lambda: struct.unpack('<i', M.r(rec + 0x14, 4))[0]
def hit(dmg):  # 游戏的做法：新血量 = 另存的血量 - 伤害，两处都写
    nv = Hd() - dmg
    M.w(HID, I(nv)); M.w(rec + 0x14, I(nv))
run = lambda n: L.execute(('for i=1,%d do update(0.1) end' % n).encode())
run(40)
print('healed', Hp(), 'hidden', Hd())
open(os.path.join(logs, 'shield_resupply_cmd.txt'), 'w').write('hunt\n')
run(10)
hit(50)
run(10)
print('after 1st hit', Hp(), '(bug: 950)')
run(40)
print('healed', Hp(), 'hidden', Hd())
hit(50)
print('after 2nd hit', Hp(), '(fixed: 1750)')
for line in open(os.path.join(logs, 'ShieldVehicleResupply.log'), encoding='utf-8'):
    if 'hunt' in line or 'error' in line: print(' ', line.rstrip()[:300])
ok = Hp() == 1750
print('PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)

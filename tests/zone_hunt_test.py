# v0.12d 部位血量离线测试：游戏在记录之外另存一个结构（主血量 @0x50000100，部位0 @0x50000140），
# 扣血时用它算完盖回记录（自动 hunt）
#   py tests/zone_hunt_test.py
import os, struct, sys, tempfile
tmp = tempfile.mkdtemp()
os.environ['LOCALAPPDATA'] = tmp
logs = os.path.join(tmp, 'CowboyBingus', 'Helldivers2', 'Logs')
os.makedirs(logs)
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'svr_test.py'), encoding='utf-8').read()
setup, _ = src.split("L.execute(b'for i=1,40", 1)
HID, HZ = 0x50000100, 0x50000140
setup = setup.replace("M.w(rec,bytes(data))",
    "M.w(rec,bytes(data)); M.w(0x50000000,b'\\0'*0x1000); M.w(%d,I(1000)+U(0xffffff6f)); M.w(%d,I(100)+I(-40)); M.w(0x50000800,I(100)+I(-40))" % (HID, HZ))
setup = setup.replace("_G.SVR={N=N,W=W,S=S,C=C}",
    "W.f32=function(p,oldraw,new) local ffi=require('ffi'); local nb=ffi.new('float[1]',new)\n"
    "    if N.win.read(p,4)~=oldraw then return false end; pywrite(p,ffi.string(nb,4)); W.writes=W.writes+1; return true end\n"
    "  W.rw_regions=function() return {{0x31003000,0x1000},{0x50000000,0x1000}} end\n"
    "  W.rpm=function(p,buf,n) local s=pyread(p,n); if not s then return false end; require('ffi').copy(buf,s,n); return true end\n"
    "  _G.SVR={N=N,W=W,S=S,C=C}")
os.chdir(os.path.join(here, '..'))
exec(setup)
g = lambda a: struct.unpack('<i', M.r(a, 4))[0]
def hit(dmg, zd):  # 新血量 = 另存的值 - 伤害，两处都写
    h = g(HID) - dmg; z = g(HZ) - zd
    M.w(HID, I(h)); M.w(rec + 0x14, I(h))
    M.w(HZ, I(z)); M.w(rec + 0xF8, I(z))
run = lambda n: L.execute(('for i=1,%d do update(0.1) end' % n).encode())
st = lambda tag: print(tag, 'hp', g(rec + 0x14), 'zone0', g(rec + 0xF8), '| hidden', g(HID), g(HZ))
run(10); st('healing')
hit(50, 20); run(5); st('hit1 (hunt 过滤主血量)')
run(10)
hit(50, 20); run(5); st('hit2 (主血量 fix 已生效；部位附近找到)')
run(40); st('healed')
hit(50, 20); st('hit3')
for line in open(os.path.join(logs, 'ShieldVehicleResupply.log'), encoding='utf-8'):
    if 'hunt' in line or 'error' in line: print(' ', line.rstrip()[:200])
ok = g(rec + 0x14) == 1750 and g(rec + 0xF8) == 380
print('PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)

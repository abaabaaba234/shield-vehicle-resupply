# v0.12g 分帧扫描离线测试：hunt_ms=hunt_ms_max=-1 时每块内存扫完就让出这一帧（共 ~32 帧）；
# 扫描途中挨打 -> 这次作废，下次回血重扫，之后照样能修好
#   py tests/scan_frames_test.py
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
    "  C.hunt_ms=-1; C.hunt_ms_max=-1; W.rw_regions=function() local r={{0x31003000,0x1000},{0x50000000,0x1000}}; for i=1,30 do r[#r+1]={0x60000000+i*0x1000,0x1000} end; return r end\n"
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
run(11); st('scan 进行中')
hit(50, 20); run(2); st('扫描中挨打（应作废）')
run(60); st('重扫完、修满')
hit(50, 20); run(5); st('hit (过滤)')
run(60); st('healed')
hit(50, 20); st('hit (应不掉回去)')
for line in open(os.path.join(logs, 'ShieldVehicleResupply.log'), encoding='utf-8'):
    if 'hunt' in line or 'error' in line: print(' ', line.rstrip()[:200])
log = open(os.path.join(logs, 'ShieldVehicleResupply.log'), encoding='utf-8').read()
ok = g(rec + 0x14) == 1750 and g(rec + 0xF8) == 380 and '作废' in log and '分 3' in log and '分 1 帧' not in log
print('PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)

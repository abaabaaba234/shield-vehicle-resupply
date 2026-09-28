# v0.12f 两辆载具的 hunt 离线测试：每辆载具都有自己另存的主血量/部位拷贝，都要各自找到并同步
# （v0.12e 只有一份全局 hunt，机甲占了以后坦克/小车从没扫过）
#   py tests/multi_hunt_test.py
import os, struct, sys, tempfile
tmp = tempfile.mkdtemp()
os.environ['LOCALAPPDATA'] = tmp
logs = os.path.join(tmp, 'CowboyBingus', 'Helldivers2', 'Logs')
os.makedirs(logs)
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'svr_test.py'), encoding='utf-8').read()
setup, _ = src.split("L.execute(b'for i=1,40", 1)
# 第二辆：entity 200 / goid 60 / 记录下标 1，血量 900、部位0 90
setup = setup.replace("table(hm+0x1030,0x31000000,[(ent,0)])",
    "table(hm+0x1030,0x31000000,[(ent,0),(200,1)])")
setup = setup.replace("table(net+0xF1AEB0,0x21000000,[(ent,0)]); table(net+0xF22EC8,0x21001000,[(goid,0)])",
    "table(net+0xF1AEB0,0x21000000,[(ent,0),(200,1)]); table(net+0xF22EC8,0x21001000,[(goid,0),(60,1)])")
setup = setup.replace("M.w(0x31002000,Q(desc))",
    "M.w(0x31002000,Q(desc)+Q(desc+24)); M.w(desc+24,Q(res)+U(200)+U(8)+U(60)+U(1))")
V = [(0x50000100, 0x50000140), (0x50000200, 0x50000240)]
setup = setup.replace("M.w(rec,bytes(data))",
    "M.w(rec,bytes(data)); d2=bytearray(data); d2[0x14:0x18]=I(900); d2[0xF8:0xFC]=I(90); M.w(rec+0x1B8,bytes(d2))\n"
    "M.w(0x50000000,b'\\0'*0x1000)\n"
    "M.w(%d,I(1000)+U(0xffffff6f)); M.w(%d,I(100)+I(-40))\n"
    "M.w(%d,I(900)+U(0xffffff6f)); M.w(%d,I(90)+I(-40))\n"
    "M.w(0x50000800,I(100)+I(-40)); M.w(0x50000900,I(90)+I(-40))" % (V[0] + V[1]))
setup = setup.replace("_G.SVR={N=N,W=W,S=S,C=C}",
    "W.f32=function(p,oldraw,new) local ffi=require('ffi'); local nb=ffi.new('float[1]',new)\n"
    "    if N.win.read(p,4)~=oldraw then return false end; pywrite(p,ffi.string(nb,4)); W.writes=W.writes+1; return true end\n"
    "  W.rw_regions=function() return {{0x31003000,0x1000},{0x50000000,0x1000}} end\n"
    "  W.rpm=function(p,buf,n) local s=pyread(p,n); if not s then return false end; require('ffi').copy(buf,s,n); return true end\n"
    "  _G.SVR={N=N,W=W,S=S,C=C}")
os.chdir(os.path.join(here, '..'))
exec(setup)
g = lambda a: struct.unpack('<i', M.r(a, 4))[0]
R = [rec, rec + 0x1B8]
def hit(dmg, zd):  # 新血量 = 另存的值 - 伤害，两处都写
    for r, (hid, hz) in zip(R, V):
        h = g(hid) - dmg; z = g(hz) - zd
        M.w(hid, I(h)); M.w(r + 0x14, I(h))
        M.w(hz, I(z)); M.w(r + 0xF8, I(z))
run = lambda n: L.execute(('for i=1,%d do update(0.1) end' % n).encode())
def st(tag):
    print(tag, ' | '.join('hp %d zone0 %d (hidden %d %d)' % (g(r + 0x14), g(r + 0xF8), g(h), g(z)) for r, (h, z) in zip(R, V)))
print('vehicles', L.eval(b'#SVR.S.vehicles'))
run(10); st('healing')
hit(50, 20); run(5); st('hit1')
run(10)
hit(50, 20); run(5); st('hit2')
run(60); st('healed')
hit(50, 20); st('hit3')
for line in open(os.path.join(logs, 'ShieldVehicleResupply.log'), encoding='utf-8'):
    if 'ent=200' in line or 'entity=200' in line or ' 200:' in line or ('hunt' in line and 'dump' not in line and '    ' not in line[:14]) or 'error' in line: print(' ', line.rstrip()[:160])
ok = all(g(r + 0x14) == 1750 and g(r + 0xF8) == 380 for r in R)
print('PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)

# v0.12 影子字段离线测试：模拟游戏受伤时用 +0x30 的 float 镜像重新算血量
#   py tests/shadow_test.py
import os, struct, sys, tempfile
tmp = tempfile.mkdtemp()
os.environ['LOCALAPPDATA'] = tmp
os.makedirs(os.path.join(tmp, 'CowboyBingus', 'Helldivers2', 'Logs'))
here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'svr_test.py'), encoding='utf-8').read()
setup, _ = src.split("L.execute(b'for i=1,40", 1)
# 记录里加一个 float 镜像（初值 = 主血量 1000），W.f32 也用假内存
setup = setup.replace("M.w(rec,bytes(data))", "data[0x30:0x34]=struct.pack('<f',1000.0)\nM.w(rec,bytes(data))")
setup = setup.replace("_G.SVR={N=N,W=W,S=S,C=C}",
    "W.f32=function(p,oldraw,new) local ffi=require('ffi'); local nb=ffi.new('float[1]',new)\n"
    "    if N.win.read(p,4)~=oldraw then return false end; pywrite(p,ffi.string(nb,4)); W.writes=W.writes+1; return true end\n"
    "  _G.SVR={N=N,W=W,S=S,C=C}")
os.chdir(os.path.join(here, '..'))
exec(setup)
F = lambda: struct.unpack('<f', M.r(rec + 0x30, 4))[0]
H = lambda: struct.unpack('<i', M.r(rec + 0x14, 4))[0]
def hit(dmg):  # 游戏的做法：血量 = 镜像 - 伤害，镜像同步
    nv = F() - dmg
    M.w(rec + 0x30, struct.pack('<f', nv)); M.w(rec + 0x14, I(int(nv)))
run = lambda n: L.execute(('for i=1,%d do update(0.1) end' % n).encode())
run(40)
print('healed', H(), 'mirror', F())
hit(50)
print('after 1st hit', H(), '(bug: 950)')
run(40)
print('healed', H(), 'mirror', F())
hit(50)
print('after 2nd hit', H(), '(fixed: 1750)')
logs = os.path.join(tmp, 'CowboyBingus', 'Helldivers2', 'Logs')
for n in ('ShieldVehicleResupply.log', 'shield_resupply_learned.txt'):
    p = os.path.join(logs, n)
    if os.path.exists(p):
        for line in open(p, encoding='utf-8'):
            if 'shadow' in line or 'heal lost' in line or 'tick error' in line: print(' ', line.rstrip())
ok = H() == 1750 and abs(F() - 1750) < 1
print('PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)

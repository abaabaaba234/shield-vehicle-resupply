# v0.13 离线测试：游戏自带的回血
#   * 打开载具 HealthComponent 配置里的回血开关/速率（+0x04 / +0x08 / +0x0C / +0x10 / +0x14）
#   * 主血量交给游戏，mod 不再逐帧写 +0x14，也不扫内存
#   * 没有载具在罩子里（也没有 test 模式）时，把配置写回原值
#   py tests/native_heal_test.py
import os, struct, sys
here = os.path.dirname(os.path.abspath(__file__))
tmp = os.path.join(here, '.run-%d' % os.getpid())  # 跑完可以删；.gitignore 里已忽略
os.makedirs(tmp, exist_ok=True)
os.environ['LOCALAPPDATA'] = tmp
logs = os.path.join(tmp, 'CowboyBingus', 'Helldivers2', 'Logs')
os.makedirs(logs, exist_ok=True)
src = open(os.path.join(here, 'svr_test.py'), encoding='utf-8').read()
setup, _ = src.split("L.execute(b'for i=1,40", 1)
# 配置记录里那 5 个回血字段原本全是 0，正好用来检查“写进去”和“写回来”
setup = setup.replace("_G.SVR={N=N,W=W,S=S,C=C}",
    "C.heal='native'\n"
    "  W.raw=function(p,n,oldraw,newraw)\n"
    "    if N.win.read(p,n)~=oldraw then return false end\n"
    "    pywrite(p,newraw); W.writes=W.writes+1; return true end\n"
    "  W.raw4=function(p,o,n) return W.raw(p,4,o,n) end\n"
    "  W.raw1=function(p,o,n) return W.raw(p,1,o,n) end\n"
    "  W.writable=function() return true end\n"
    "  W.prot=function() return 4 end\n"
    "  _G.SVR={N=N,W=W,S=S,C=C}")
os.chdir(os.path.join(here, '..'))
exec(setup)
L.execute(b'SVR.C.cooldown=2')
run = lambda n: L.execute(('for i=1,%d do update(0.1) end' % n).encode())
f32 = lambda o: struct.unpack('<f', M.r(cfg + o, 4))[0]
u32 = lambda o: struct.unpack('<I', M.r(cfg + o, 4))[0]
i32 = lambda a: struct.unpack('<i', M.r(a, 4))[0]

run(40)
hp, z0 = i32(rec + 0x14), i32(rec + 0xF8)
print('配置: rate=%.1f dis=%d cooldown=%.1f segments=%d regen=%.1f' % (f32(4), M.r(cfg + 8, 1)[0], f32(0x0C), u32(0x10), f32(0x14)))
print('主血量=%d(应保持 1000，mod 不写) 部位0=%d(应保持 100，交给游戏再生)' % (hp, z0))
print('writes=%s open=%s' % (L.eval(b'SVR.W.writes'), L.eval(b'SVR.C.heal')))
good = (f32(4) == 900.0 and M.r(cfg + 8, 1)[0] == 0 and f32(0x0C) == 2.0
        and u32(0x10) == 1 and f32(0x14) == 900.0 and hp == 1000 and z0 == 100
        and M.r(cfg + 0x208 + 0x141, 1) == b'\1'
        and M.r(cfg + 0x208 + 0x228 + 0x141, 1) == b'\1'
        and i32(rec + 0xFC) == -40)
log = open(os.path.join(logs, 'ShieldVehicleResupply.log'), encoding='utf-8').read()
good = good and 'native on' in log and 'hunt' not in log and 'shadow' not in log

# 载具离开罩子（这里用关掉 test 模式模拟）：配置写回原值
L.execute(b'SVR.C.test=false')
run(10)
print('离开后: rate=%.1f dis=%d cooldown=%.1f segments=%d regen=%.1f' % (f32(4), M.r(cfg + 8, 1)[0], f32(0x0C), u32(0x10), f32(0x14)))
good = good and f32(4) == 0.0 and f32(0x0C) == 0.0 and u32(0x10) == 0 and f32(0x14) == 0.0
good = good and M.r(cfg + 0x208 + 0x141, 1) == b'\0' and M.r(cfg + 0x208 + 0x228 + 0x141, 1) == b'\0'
log = open(os.path.join(logs, 'ShieldVehicleResupply.log'), encoding='utf-8').read()
good = good and 'native close' in log and 'tick error' not in log
for line in log.splitlines():
    if 'native' in line or 'error' in line:
        print(' ', line[:240])
print('PASS' if good else 'FAIL')
sys.exit(0 if good else 1)

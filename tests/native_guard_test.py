# v0.13 离线测试：配置头不像 HealthComponent 时，一个字节都不写（fail-closed）
#   py tests/native_guard_test.py
import os, struct, sys
here = os.path.dirname(os.path.abspath(__file__))
tmp = os.path.join(here, '.run-%d' % os.getpid())
os.makedirs(tmp, exist_ok=True)
os.environ['LOCALAPPDATA'] = tmp
logs = os.path.join(tmp, 'CowboyBingus', 'Helldivers2', 'Logs')
os.makedirs(logs, exist_ok=True)
src = open(os.path.join(here, 'svr_test.py'), encoding='utf-8').read()
setup, _ = src.split("L.execute(b'for i=1,40", 1)
setup = setup.replace("_G.SVR={N=N,W=W,S=S,C=C}",
    "C.heal='native'\n"
    "  W.raw=function(p,n,oldraw,newraw) pywrite(p,newraw); W.writes=W.writes+1; return true end\n"
    "  W.raw4=function(p,o,n) return W.raw(p,4,o,n) end\n"
    "  W.raw1=function(p,o,n) return W.raw(p,1,o,n) end\n"
    "  W.writable=function() return true end\n"
    "  W.prot=function() return 4 end\n"
    "  _G.SVR={N=N,W=W,S=S,C=C}")
os.chdir(os.path.join(here, '..'))
exec(setup)
# 上限保持正常（读记录那一关要过），但 0x04 起全部填成 0xAA：
# rate/cooldown 不是合法的正数、disabled 字节 = 0xAA，配置头检查应该拒绝
M.w(cfg, I(1800) + b'\xaa' * 0x1C)
run = lambda n: L.execute(('for i=1,%d do update(0.1) end' % n).encode())
run(30)
raw = M.r(cfg, 0x20)
log = open(os.path.join(logs, 'ShieldVehicleResupply.log'), encoding='utf-8').read()
print('cfg +00..+1c', raw.hex())
print('hp', struct.unpack('<i', M.r(rec + 0x14, 4))[0])
good = raw[4:0x20] == b'\xaa' * 0x1C and 'HealthComponent' in log and 'tick error' not in log
for line in log.splitlines():
    if 'native' in line or 'error' in line:
        print(' ', line[:240])
print('PASS' if good else 'FAIL')
sys.exit(0 if good else 1)

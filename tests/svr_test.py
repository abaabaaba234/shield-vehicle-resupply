import struct, os, sys, tempfile
from pathlib import Path
from lupa import luajit21 as lj
# Keep standalone and embedded harnesses away from the user's game files.
test_root=Path(__file__).resolve().parent
if not Path(os.environ.get('LOCALAPPDATA','')).resolve().is_relative_to(test_root):
    os.environ['LOCALAPPDATA']=tempfile.mkdtemp(prefix='.run-svr-',dir=test_root)
class Mem:
    def __init__(s): s.pages={}
    def w(s,a,b):
        for i,c in enumerate(b):
            pg=(a+i)>>12; s.pages.setdefault(pg,bytearray(4096))[(a+i)&4095]=c
    def r(s,a,n):
        out=bytearray()
        for i in range(n):
            pg=s.pages.get((a+i)>>12)
            if pg is None: return None
            out.append(pg[(a+i)&4095])
        return bytes(out)
M=Mem(); Q=lambda v:struct.pack('<Q',v); I=lambda v:struct.pack('<i',v); U=lambda v:struct.pack('<I',v)
base=0x140000000; net=0x20000000; hm=0x30000000; st=0x40000000
M.w(base,b'\0'*16)
M.w(base+0x346BF98,Q(net)); M.w(base+0x3326688,Q(hm))
EMPTY=0xFFFFFFFF
def table(at,entries,pairs,cap=16):
    M.w(at,Q(entries)+U(cap)+U(EMPTY)+U(1))
    M.w(entries,b''.join(U(EMPTY)+U(EMPTY) for _ in range(cap)))
    for k,j in pairs:
        slot=k%cap
        while M.r(entries+slot*8,4)!=U(EMPTY): slot=(slot+1)%cap
        M.w(entries+slot*8,U(k)+U(j))
res=int(sys.argv[1],16) if len(sys.argv)>1 else 0x35dbf54f016f3624
ent,unit,goid=100,7,50
desc=net+0xF32F18
M.w(desc,Q(res)+U(ent)+U(unit)+U(goid)+U(1))
table(net+0xF1AEB0,0x21000000,[(ent,0)]); table(net+0xF22EC8,0x21001000,[(goid,0)])
table(hm+0x1030,0x31000000,[(ent,0)])
M.w(hm+0x1048,Q(0x31002000)); M.w(0x31002000,Q(desc))
M.w(hm+0x1058,Q(0x31003000)); rec=0x31003000
data=bytearray(0x1B8); data[0x14:0x18]=I(1000); data[0x20:0x24]=U(0)
data[0xF8:0xFC]=I(100); data[0xFC:0x100]=I(-40)
M.w(rec,bytes(data))
M.w(hm+0x1070,Q(0)+U(0)+U(EMPTY)+U(1))
M.w(net+0xF12B78,Q(st))
k=3; slot=res%1002
M.w(st,b'\0'*(1002*16)); M.w(st+slot*16,Q(res)+U(k)+U(0))
cfg=st+0x3EA0+k*0x5650
M.w(cfg,b'\0'*0x5650); M.w(cfg,I(1800))
for i,(h,mx) in enumerate([(0xca47a7a9,400),(0x64a3fa1d,550)]):
    z=cfg+0x208+i*0x228; M.w(z+0x60,U(h)); M.w(z+0xE8,I(mx))
L=lj.LuaRuntime(encoding=None)
L.globals()[b'pyread']=lambda a,n: M.r(int(a),int(n))
L.globals()[b'pywrite']=lambda a,b: M.w(int(a),bytes(b,'latin-1') if isinstance(b,str) else bytes(b))
L.execute(b'''
stingray={Application={main_world=function() return 'W' end},Network={game_session=function() return 'S' end},
 GameSession={},UnitSynchronizer={},Unit={},Vector3={},World={units=function() return {} end},IdString64={}}
update=function() end
__SVR_TEST=function(N,W,S,C)
  N.win={begin_sample=function() end, read=function(p,n) local b=pyread(p,n); if b==nil then return nil end; return b end, base=function() return 0x140000000 end}
  N.ensure=function() N.ready=true; N.base=0x140000000; N.reason='mock'; return true end
  N.check_weapon_module=function() return true end
  W.fast=false; C.test=(os.getenv('SVR_NOTEST')==nil); C.cooldown=0; C.exo_heal=0.5; C.tank_heal=0.5
  C.heal='write'  -- this test exercises the old per-tick HP write path; native regen: native_heal_test.py
  W.i32=function(p,old,new) local ffi=require('ffi'); local ob=ffi.new('int32_t[1]',old); local nb=ffi.new('int32_t[1]',new)
    if N.win.read(p,4)~=ffi.string(ob,4) then return false end; pywrite(p,ffi.string(nb,4)); W.writes=W.writes+1; return true end
  _G.SVR={N=N,W=W,S=S,C=C}
end
''')
src=open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','dist','shield_vehicle_resupply.lua'),encoding='utf-8').read()
L.eval(b'function(s) return loadstring(s,"@svr")() end')(src.encode('utf-8'))
L.execute(b'for i=1,40 do update(0.1) end')
d=M.r(rec,0x1B8)
print('hull',struct.unpack('<i',d[0x14:0x18])[0],'z0',struct.unpack('<i',d[0xF8:0xFC])[0],'z1',struct.unpack('<i',d[0xFC:0x100])[0])
print('writes',L.eval(b'SVR.W.writes'),'vehicles',L.eval(b'#SVR.S.vehicles'),'errors',L.eval(b'SVR.S.errors'))

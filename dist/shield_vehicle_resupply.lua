-- HD2-Addon: mods/shieldresupply/shield_vehicle_resupply
-- Shield Vehicle Resupply v0.23
-- Native read layer: DRIVER HUD 1.4.5 / HUD 1.11.1, Copyright (c) 2026 FireScallion, MIT License
-- (see third_party/LICENSE-DRIVER-HUD.txt). Writes are added by this mod.
local N=(function()
-- Adapted from DRIVER HUD 1.3.5, Copyright (c) 2026 FireScallion, MIT.
-- Module compatibility check follows DRIVER HUD 1.4.5 (layout-v2): PE structure plus the
-- unchanged reviewed code guards authorize the RVAs; PE timestamp/size/checksum are diagnostic only.
-- Read-only reader retained unchanged in behaviour; this HUD uses relation/component/validate paths only.
return (function()
 local N={version='r4-layout-v2',ready=false,next_check=0}
 -- Read layout reviewed upstream on the 2026-09-22 and 2026-09-24 loaded images.
 -- Build metadata is diagnostic; exact semantic guards authorize these RVAs.
 N.roots={network=0x346BF98,health=0x3326688,synced=0x3326C98,seater=0x3326D78}
 -- Known images (diagnostic only, never an authorization by themselves):
 --   25327279: 6AA96B14 / 04770000 / 00F05B12
 --   25480438: 6AB3B43F / 04744000 / 00ECDA6F
 N.pe={machine=0x8664,sections=16,timestamp=0x6AB3B43F,size=0x4744000,checksum=0xECDA6F}
 local function u32(s,o)
  local a,b,c,d=s:byte(o+1,o+4)
  if not d then error('short uint32',0) end
  return a+b*256+c*65536+d*16777216
 end
 local function i32(s,o) local v=u32(s,o);return v>=2147483648 and v-4294967296 or v end
 local function hex64(s,o) return string.format('%08x%08x',u32(s,o+4),u32(s,o)) end
 local function ptr(s,o)
  local lo,hi=u32(s,o),u32(s,o+4)
  if hi>=32768 then error('noncanonical pointer',0) end
  return hi*4294967296+lo
 end
 local function addr(p,n)
  if type(p)~='number' or p~=math.floor(p) or p<65536 or p>=140737488355328
   or type(n)~='number' or n<1 or n>4096 or n~=math.floor(n) or p+n>140737488355328 then error('read bounds',0) end
 end
 local function mul32(a,b)
  local al,ah=a%65536,math.floor(a/65536)
  local bl,bh=b%65536,math.floor(b/65536)
  return (al*bl+((ah*bl+al*bh)%65536)*65536)%4294967296
 end
 local function mod64hex(h,n)
  local hi,lo=tonumber(h:sub(1,8),16),tonumber(h:sub(9,16),16)
  return ((hi%n)*(4294967296%n)+lo%n)%n
 end
 N.u32=u32;N.i32=i32;N.hex64=hex64;N.ptr=ptr;N.mul32=mul32;N.mod64hex=mod64hex
 function N.q4(word)
  local out={};for i=0,3 do out[i+1]=math.floor(word/4^i)%4 end;return out
 end
 local G={};G.__index=G
 function N.graph(read,base)
  return setmetatable({raw=read,base=base,calls=0,bytes=0,watches={},seen={}},G)
 end
 function G:read(p,n)
  addr(p,n)
  if self.calls>=960 or self.bytes+n>65536 then error('native sample budget',0) end
  self.calls=self.calls+1;self.bytes=self.bytes+n
  local b=self.raw(p,n)
  if type(b)~='string' or #b~=n then error('incomplete native read',0) end
  return b
 end
 function G:watch(p,n)
  local key=string.format('%.0f:%d',p,n);local old=self.seen[key]
  if old then return old end
  local b=self:read(p,n);self.seen[key]=b;self.watches[#self.watches+1]={p,n,b};return b
 end
 function G:validate()
  -- Adjacent/overlapping watched ranges share one fresh read. Compare only the
  -- original bytes; never validate against cached first-pass data or padding.
  local ordered={};for i,w in ipairs(self.watches) do ordered[i]=w end
  table.sort(ordered,function(a,b)return a[1]<b[1]end)
  local i=1
  while i<=#ordered do
   local first=ordered[i][1];local finish=first+ordered[i][2];local j=i+1
   while j<=#ordered and ordered[j][1]<=finish and math.max(finish,ordered[j][1]+ordered[j][2])-first<=4096 do
    finish=math.max(finish,ordered[j][1]+ordered[j][2]);j=j+1
   end
   local fresh=self:read(first,finish-first)
   for k=i,j-1 do
    local w=ordered[k];local offset=w[1]-first
    if fresh:sub(offset+1,offset+w[2])~=w[3] then error('identity changed during sample',0) end
   end
   i=j
  end
 end
 function G:root(name)
  local p=ptr(self:watch(self.base+N.roots[name],8),0)
  if p==0 then error(name..' manager not ready',0) end
  addr(p,1);return p
 end
 function G:table(p)
  local b=self:watch(p,20);local cap=u32(b,8)
  if cap>1048576 or (cap>0 and 2^math.floor(math.log(cap)/math.log(2)+0.5)~=cap) then error('invalid table capacity',0) end
  local t={p=p,entries=ptr(b,0),capacity=cap,empty=u32(b,12),multiplier=u32(b,16)}
  if cap>0 then addr(t.entries,1) end;return t
 end
 function G:lookup(t,key)
  if type(key)~='number' or key<0 or key>4294967295 or key~=math.floor(key) then error('invalid identity key',0) end
  if key==t.empty or t.capacity==0 then return nil end
  local first=mul32(key,t.multiplier)%t.capacity
  for step=0,math.min(t.capacity,64)-1 do
   local b=self:watch(t.entries+((first+step)%t.capacity)*8,8)
   local k,j=u32(b,0),u32(b,4)
   if k==key then
    if j==4294967295 then return nil end
    if j>=1048576 then error('invalid dense index',0) end
    return j
   end
   if k==t.empty then return nil end
  end
  error('identity lookup probe limit',0)
 end
 function G:descriptor(p)
  local b=self:watch(p,24)
  return {address=p,resource=hex64(b,0),entity=u32(b,8),unit=u32(b,12),goid=u32(b,16),flags=u32(b,20)}
 end
 local function same(a,b)
  return a and b and a.entity==b.entity and a.goid==b.goid and a.resource==b.resource and a.unit==b.unit
 end
 N.same=same
 function G:net(root,key,by_entity)
  if key==4294967295 or (not by_entity and key==32767) then return nil end
  local j=self:lookup(self:table(root+(by_entity and 0xF1AEB0 or 0xF22EC8)),key)
  if j==nil then return nil end
  local d=self:descriptor(root+0xF32F18+j*24)
  if (by_entity and d.entity or d.goid)~=key then error('network key mismatch',0) end
  return d
 end
 function G:roundtrip(root,d)
  local f=self:net(root,d.entity,true);local b=f and self:net(root,f.goid,false)
  if not same(d,f) or not same(d,b) then error('network roundtrip mismatch',0) end
 end
 function G:component(manager,entity,to,dp)
  local j=self:lookup(self:table(manager+to),entity)
  if j==nil then return nil end
  local array=ptr(self:watch(manager+dp,8),0)
  local d=self:descriptor(ptr(self:watch(array+j*8,8),0))
  if d.entity~=entity then error('component owner mismatch',0) end
  return j,d
 end
 function G:relation(avatar_goid)
  local net,seater=self:root('network'),self:root('seater')
  local av=self:net(net,avatar_goid,false)
  if not av then error('avatar not in native network table',0) end
  self.relation_avatar=av -- Observations also invalidate stale-display grace on a later short read.
  self:roundtrip(net,av)
  local j,ad=self:component(seater,av.entity,0x20,0x38)
  if j==nil then self.relation_absent=true;self:validate();return {status='NO_SEATER'} end
  if not same(av,ad) then error('Seater avatar mismatch',0) end
  local base=ptr(self:watch(seater+0x48,8),0)
  local e=u32(self:watch(base+j*0x40,4),0)
  self.relation_collection=e
  if e==0 or e==4294967295 then self:validate();return {status='EMPTY'} end
  local d=self:net(net,e,true)
  if not d or d.goid<=0 or d.goid>=32767 then error('collection not network-linked',0) end
  self.relation_vehicle=d
  self:roundtrip(net,d)
  local role=i32(self:read(base+j*0x40+0x1C,4),0)
  self:validate()
  return {status='VEHICLE',vehicle=d,avatar=av,role=role}
 end
 -- Resolve a SeatCollection/proxy descriptor to a FRV Hull without spatial or GOID heuristics.
 -- The only accepted edge is an exact shared native unit key, a known FRV resource,
 -- a Health component and a unique candidate. Table enumeration is limited to the
 -- typed Health entity index; this is not a process/address-space scan.
 function G:frv_hull_for_proxy(collection,known_resources)
  if not collection or type(collection.unit)~='number' or collection.unit<=0 or collection.unit==4294967295 then
   return nil,{reason='proxy has no usable unit key'}
  end
  local net,hm=self:root('network'),self:root('health')
  local live=self:net(net,collection.entity,true)
  if not same(live,collection) then error('proxy identity changed before resolve',0) end
  self:roundtrip(net,live)
  local t=self:table(hm+0x1030)
  if t.capacity==0 then return nil,{reason='Health table empty',capacity=0,entries=0,candidates=0} end
  if t.capacity>4096 then error('Health table too large for proxy resolver',0) end
  local bytes=t.capacity*8;local raw={};local off=0
  while off<bytes do
   local n=math.min(4096,bytes-off)
   raw[#raw+1]=self:watch(t.entries+off,n);off=off+n
  end
  raw=table.concat(raw)
  local descs=ptr(self:watch(hm+0x1048,8),0)
  local entries,candidates=0,{}
  for pos=0,#raw-8,8 do
   local entity,j=u32(raw,pos),u32(raw,pos+4)
   if entity~=t.empty and j~=4294967295 then
    entries=entries+1
    if j>=1048576 then error('Health dense index outside safety bound',0) end
    local dp=ptr(self:watch(descs+j*8,8),0)
    local d=self:descriptor(dp)
    if d.entity~=entity then error('Health table/descriptor owner mismatch',0) end
    if d.unit==collection.unit and d.entity~=collection.entity and known_resources[d.resource] then
     self:roundtrip(net,d);candidates[#candidates+1]=d
    end
   end
  end
  local meta={reason='no exact same-unit FRV Health owner',unit=collection.unit,capacity=t.capacity,entries=entries,candidates=#candidates}
  if #candidates==1 then meta.reason='unique_same_unit_health';return candidates[1],meta end
  if #candidates>1 then meta.reason='ambiguous same-unit FRV Health owners' end
  self:validate();return nil,meta
 end
 function G:configuration(net,hm,d,expected_zones)
  local j=self:lookup(self:table(hm+0x1070),d.entity);local cfg
  if j~=nil then cfg=ptr(self:watch(hm+0x10B0,8),0)+j*0x5650
  else
   local t=ptr(self:watch(net+0xF12B78,8),0)
   local start=mod64hex(d.resource,1002)
   for step=0,63 do
    local b=self:watch(t+((start+step)%1002)*16,16);local key=hex64(b,0)
    if key==d.resource then
     local k=u32(b,8);if k>=1002 then error('Health settings index',0) end
     cfg=t+0x3EA0+k*0x5650;break
    elseif key=='0000000000000000' then break end
   end
  end
  if not cfg then error('no identity-linked Health configuration',0) end
  local max={}
  for i=0,3 do
   local zone=cfg+0x208+i*0x228
   -- Read zone identity and maximum together, but watch only the identity.
   -- The intervening config bytes are not identity guards.
   local block=self:read(zone+96,140)
   local key=string.format('%.0f:%d',zone+96,4)
   local name_bytes=self.seen[key]
   if not name_bytes then
    name_bytes=block:sub(1,4);self.seen[key]=name_bytes
    self.watches[#self.watches+1]={zone+96,4,name_bytes}
   end
   local name=string.format('%08x',u32(name_bytes,0))
   if name~=expected_zones[i+1] then error('wheel zone identity mismatch',0) end
   local mx=i32(block,136)
   if mx<=0 or mx>1000000 then error('invalid wheel maximum',0) end
   max[i+1]=mx
  end
  return max
 end
 function G:health(d,expected_zones)
  local net,hm=self:root('network'),self:root('health')
  self:roundtrip(net,d)
  local hi,hd=self:component(hm,d.entity,0x1030,0x1048)
  if hi==nil or not same(hd,d) then error('no matching Health component',0) end
  local hpbase=ptr(self:watch(hm+0x1058,8),0)
  local record=hpbase+hi*0x1B8
  local data=self:read(record,0x1B8)
  local max=self:configuration(net,hm,hd,expected_zones)
  local hp,hp_valid={},{}
  for i=0,3 do
   local v=i32(data,0xF8+4*i);hp[i+1]=v
   -- Runtime HP can briefly leave [0,max] around a damage transition.  This is
   -- a per-zone data-quality issue, not grounds to discard the other wheels.
   -- Keep the raw value for diagnostics and let the UI fall back to q2 for
   -- this wheel only.  Destroyed state still wins independently in wheel_model.
   hp_valid[i+1]=(v>=0 and v<=max[i+1])
  end
  local out={hp=hp,hp_valid=hp_valid,max=max,body=i32(data,0x14),damage=N.q4(u32(data,0x20)),
   state_low=u32(data,0x20),health_index=hi,health_record=record,flags=hd.flags,precision='UNKNOWN'}
  -- Isolate ancillary watches as well as exceptions. Reserve the unchanged
  -- core validation cost so sync trouble cannot exhaust the core's budget.
  local reserve_calls,reserve_bytes=#self.watches,0
  for _,w in ipairs(self.watches) do reserve_bytes=reserve_bytes+w[2] end
  local sync=N.graph(function(p,n)
   if self.calls+1+reserve_calls>960 or self.bytes+n+reserve_bytes>65536 then
    error('ancillary sample budget',0)
   end
   return self:read(p,n)
  end,self.base)
  local ok,extra=pcall(function()return sync:synced_health(hd)end)
  out.sync_valid=ok and extra~=nil
  if out.sync_valid then
   out.q=extra.q;out.cache=extra.cache;out.synced_flags=extra.flags
   if hd.flags%2==1 and extra.flags%2==1 then out.precision='LOCAL_RUNTIME'
   else out.precision='QUANTIZED_OR_UNKNOWN' end
  else out.sync_error=ok and 'SyncedHealth absent' or tostring(extra) end
  -- Always recheck core owner/configuration AFTER ancillary reads, even when
  -- they failed. No failed sync watch or partial result is merged into core.
  self:validate();out.bytes=self.bytes;out.calls=self.calls
  return out
 end
 function G:synced_health(d)
  local sm=ptr(self:watch(self.base+N.roots.synced,8),0)
  if sm==0 then return nil end
  local si,sd=self:component(sm,d.entity,0x20,0x38)
  if si==nil then return nil end
  if not same(d,sd) then error('SyncedHealth owner mismatch',0) end
  local array=ptr(self:watch(sm+0x40,8),0);local rep=ptr(self:watch(sm+0x50,8),0)
  local cache=self:read(array+si*0xC0,16);local word=u32(self:read(rep+si*16+4,4),0)
  local out={q=N.q4(word),cache={},flags=sd.flags}
  for i=0,3 do out.cache[i+1]=i32(cache,4*i) end
  self:validate();return out
 end
 N.guards={
  {0xfd9ba4,"4c8b1ded234902448bc24c8bc981faff7f000075108b05ada94a028901488bc14883c408c3458b93d02ef20033d248895c2410418b9bd82ef20048896c2418410fafd8418d6aff488974242048893c244585d27436498bbbc82ef200418bb3d42ef200"}, -- network_reverse_root_and_table
  {0xfd9a70,"458b8ab8aef100458b9ac0aef100440fafd9418d71ff4585c97435498b9ab0aef100418bbabcaef100"}, -- network_forward_table
  {0xfd9d15,"8b4004488d0440488d80e3651e00498d04c2"}, -- network_descriptor_array
  {0x4a8a0a,"4c8b1567e3e7027512b8ffffffff48c1e006490342484883c408c3458b4a284533c048895c2410418b5a30"}, -- seater_manager_root_stride
  {0x63a8db,"45896f1041c7471cffffffff41893f"}, -- seater_collection_assignment
  {0x92161f,"488b2d6250a0027507b8ffffffffeb58448b8d381000008bcf448b9540100000440fafd24c89742440458d71ff4585c9742c4c8b9d30100000"}, -- health_manager_root_and_table
  {0x921687,"488b8d481000008bd8488b0cd9e88762beff4869cbb8010000488b5c243048038d58100000488b6c243848056802000039307426ffc748052802000083ff2672ef"}, -- health_descriptor_runtime_zone_layout
  {0x507435,"488b055c4bf602448bc14c8b90782bf10048b83366582707ea9e0548f7e1488bc1482bc248d1e84803c248c1e80969c0ea030000442bc0"}, -- health_settings_table_modulus
  {0x5074ae,"8b48084869c1505600004805a03e00004903c2"}, -- health_settings_record_base
  {0x5079d2,"4869c050560000490383b0100000"}, -- health_override_array
  {0x6b1dbe,"488b3dd34ec7027457448b5f28458bc88b5f300fafd8458d73ff4585db7441488b77208b6f2c"}, -- synced_manager_root_and_table
  {0x6b1ead,"4869c8b801000048038e581000008b81f80000004189028b81fc000000418942048b8100010000418942088b81040100004189420c"}, -- health_to_synced_copy
  {0x6b2957,"8bd58bf548c1e60449037650"}, -- synced_replicated_stride
  {0x6b26e5,"448b178d4bfe418bc10f57c9d3e883e003f3480f2ac8f30f5eca4183faff7504448b5614418d5001418bc8c1ea058bc2c1e0052bc8498b54d5208d0c4d0200000048d3eaf6c203751866410f6ec20f5bc0f30f59c1f30f2cc0"}, -- q2_and_damage_independent
 }
 function N.check_module(read,base)
  N.image_size=nil
  local b=read(base,512)
  if not b or #b~=512 or b:sub(1,2)~='MZ' then return false,'module header unreadable' end
  local off=u32(b,0x3C)
  if off<64 or off>4096 then return false,'module PE offset' end
  local p=read(base+off,112)
  if not p or #p~=112 or p:sub(1,4)~='PE\0\0' then return false,'module PE signature' end
  local machine=p:byte(5)+256*p:byte(6);local sections=p:byte(7)+256*p:byte(8)
  local optional_size=p:byte(21)+256*p:byte(22)
  local magic=p:byte(25)+256*p:byte(26)
  local size=u32(p,80)
  if machine~=0x8664 or magic~=0x20B or optional_size<112 or sections<1 or sections>96
   or size<4096 or size>134217728 then return false,'unsupported game.dll PE structure' end
  -- Timestamp/checksum/image size can change while the read contract stays intact.
  -- Never infer compatibility from PE metadata alone, including known builds.
  for _,rva in pairs(N.roots) do
   if rva+8>size then return false,'native root outside module' end
  end
  for _,v in ipairs(N.guards) do
   local want=v[2]:gsub('..',function(h)return string.char(tonumber(h,16))end)
   if v[1]+#want>size or read(base+v[1],#want)~=want then
    return false,string.format('native code guard 0x%X',v[1])
   end
  end
  N.image_size=size
  return true,string.format('layout=%s PE=%08X/%08X/%08X guards=%d',
   N.version,u32(p,8),size,u32(p,88),#N.guards)
 end
 function N.open_win32()
  local ok,ffi=pcall(require,'ffi')
  if not ok or not ffi or ffi.os~='Windows' or not ffi.abi('64bit') then return nil,'LuaJIT FFI / Windows x64 unavailable' end
  -- No game native calls; all pointed-to bytes go through RPM into owned buffers.
  local declarations={
   'void * __stdcall GetCurrentProcess(void);',
   'void * __stdcall GetModuleHandleA(const char *);',
   'int __stdcall ReadProcessMemory(void *, const void *, void *, size_t, size_t *);',
   'size_t __stdcall VirtualQuery(const void *, void *, size_t);'}
  for _,s in ipairs(declarations) do pcall(ffi.cdef,s) end
  local loaded,k=pcall(ffi.load,'kernel32');if not loaded then return nil,'kernel32 unavailable' end
  local h=k.GetCurrentProcess();local buffer=ffi.new('uint8_t[4096]')
  local got=ffi.new('size_t[1]');local mbi=ffi.new('uint8_t[48]')
  local w={stats={reads=0,queries=0,bytes=0}};local regions={}
  -- Protection metadata lives for one synchronous native sample only. RPM still
  -- checks every copy, including validation reads, if a region changes meanwhile.
  function w.begin_sample() regions={} end
  function w.base()
   local p=k.GetModuleHandleA('game.dll')
   if p==nil then return nil end
   return tonumber(ffi.cast('uintptr_t',p))
  end
  function w.read(p,n)
   addr(p,n)
   if N.perf then w.stats.reads=w.stats.reads+1;w.stats.bytes=w.stats.bytes+n end
   local at,finish=p,p+n
   for _=1,4 do
    if at>=finish then break end
    local region_end
    for _,r in ipairs(regions) do
     if at>=r[1] and at<r[2] then region_end=r[2];break end
    end
    if not region_end then
     if N.perf then w.stats.queries=w.stats.queries+1 end
     local z=tonumber(k.VirtualQuery(ffi.cast('const void *',at),ffi.cast('void *',mbi),48))
     if z~=48 then return nil end
     local b=ffi.string(mbi,48);local start=ptr(b,0);local extent=ptr(b,24)
     local state,protection=u32(b,32),u32(b,36);local kind=protection%256
     if state~=4096 or math.floor(protection/256)%2==1
      or not (kind==2 or kind==4 or kind==8 or kind==32 or kind==64 or kind==128)
      or start>at or extent==0 or start+extent<=at then return nil end
     region_end=start+extent
     regions[#regions+1]={start,region_end}
    end
    at=math.min(finish,region_end)
   end
   if at<finish then return nil end
   got[0]=0
   local success=k.ReadProcessMemory(h,ffi.cast('const void *',p),buffer,n,got)
   if success==0 or tonumber(got[0])~=n then return nil end
   return ffi.string(buffer,n)
  end
  return w
 end
 function N.ensure(now)
  if N.disabled then return false,N.reason end
  if now<N.next_check then return N.ready,N.reason end
  N.next_check=now+10
  if not N.win then
   local ok,w,why=pcall(N.open_win32)
   if not ok or not w then N.disabled=true;N.reason=why or tostring(w);return false,N.reason end
   N.win=w
  end
  local base=N.win.base()
  if not base then N.ready=false;N.next_check=now+1;N.reason='game.dll not yet loaded';return false,N.reason end
  N.win.begin_sample()
  local ok,valid,why=pcall(N.check_module,N.win.read,base)
  if not ok or not valid then
   N.ready=false;N.reason=why or tostring(valid)
   -- Retry loaded-code checks slowly (initialization), never use failed offsets.
   N.next_check=now+10;return false,N.reason
  end
  N.ready=true;N.base=base;N.reason=why;return true
 end
 function N.sample_graph()
  N.win.begin_sample()
  return N.graph(N.win.read,N.base)
 end
 function N.relation(avatar,now,previous)
  local valid,why=N.ensure(now)
  if not valid then return nil,why,'UNAVAILABLE' end
  local g=N.sample_graph()
  local ok,result=pcall(function()return g:relation(avatar)end)
  if ok then return result end
  local changed=g.relation_absent or (previous and (
   (g.relation_avatar and not same(g.relation_avatar,previous.avatar)) or
   (g.relation_collection and g.relation_collection~=previous.vehicle.entity) or
   (g.relation_vehicle and not same(g.relation_vehicle,previous.vehicle))))
  -- Only a proven short read may retain a display. Owner mismatches, changed
  -- watches, version failures and unclassified errors remain fail-closed.
  local kind=not changed and result=='incomplete native read' and 'TRANSIENT_READ' or 'INVALID'
  return nil,tostring(result),kind
 end
 function N.resolve_proxy(collection,known_resources)
  if not N.ready then return nil,'native version not validated' end
  local ok,result,meta=pcall(function()
   local g=N.sample_graph()
   local d,m=g:frv_hull_for_proxy(collection,known_resources)
   g:validate();return d,m
  end)
  if ok then return result,meta end
  return nil,tostring(result)
 end
 function N.health(vehicle,zones)
  if not N.ready then return nil,'native version not validated' end
  local ok,result=pcall(function()return N.sample_graph():health(vehicle,zones)end)
  if ok then return result end;return nil,tostring(result)
 end
 return N
end)()


end)()
do
 local ptr,u32,i32,same=N.ptr,N.u32,N.i32,N.same
 local G=getmetatable(N.graph(function() end,0)).__index
N.weapon_guards={
 {0x76e1da,"4c8b156784bb02"},
 {0x76e1ea,"458b4a284533c048895c2430418b5a3048896c24"},
 {0x76e259,"8bd0488d0452488d0c8500000000498b4250c7040100000000498b42384d8b42504c03c1488b0cd0ba8b9164ec8b49104883c428"},
 {0x76e339,"8bd0488d0452488d0c8500000000498b425044897401044d8b4250498b42384983c0044c03c1488b0cd0ba3ed6a5d78b49104883c420415ee9"},
 {0x76fece,"0f57c0418bc048c1e004480343480f1100488b433848893cc8488d4b208b5708e8cdf7fb00ff430c",32},
 {0x77760f,"4c8b155af4ba02"},
 {0x77769a,"8bc84584ff498b42504c8b7c2420488d14888b0488740e0bc3eb0e"},
 {0x7776c3,"8902babc9d88cd498b42504c8d0488498b4238488b0cc88b4910"},
 {0x77a11a,"488b3dcfcbba02"},
 {0x77a04b,"448b49304533c048895c24308b5938"},
 {0x77a0b9,"8bd0488d0492488d0c8500000000498b425844897401044d8b4258498b42404983c0044c03c1488b0cd0bad5f04ea78b49104883c42041"},
 {0x77a203,"4c8b47584983c0084d8d0490ba955bec048bf0488b47402bf14a8b0cf08b4910e8b8f58500"},
 {0x77a1cd,"4c8b47584983c00c4d8d0490ba9cfa25e5"},
}
-- The Magazine insertion helper moved by 0xD0 in the September 24 update.
-- Decode only this reviewed E8 rel32 operand and verify the entire unchanged
-- helper at its destination. No wildcard roots, field offsets or runtime scan.
N.weapon_insert_guard="48895c2408488974241048897c2418448b510833c0448b5910418bf0440fafda448bca418d7aff4585d274274c8b018b590c8bcf428d14184823d1498d0cd0418b14d03bd3740e413bd17409ffc0413bc272df33c9488b5c2408488bc1488b7c2418897104488b742410448909c3"
function N.check_weapon_module(read,base)
 local size=N.image_size
 if not size then return false,'native module not validated' end
 for _,rva in ipairs({0x3326648,0x3326CF0,0x3326A70}) do
  if rva+8>size then return false,'weapon root outside module' end
 end
 for _,v in ipairs(N.weapon_guards) do
  local want=v[2]:gsub('..',function(h)return string.char(tonumber(h,16))end)
  if v[1]+#want>size then return false,'weapon guard outside module' end
  local got=read(base+v[1],#want)
  if not got or #got~=#want then return false,string.format('weapon code guard 0x%X short read',v[1]) end
  if v[3] then
   local off=v[3]
   if got:sub(1,off+1)~=want:sub(1,off+1) or got:sub(off+6)~=want:sub(off+6) then
    return false,string.format('weapon code guard 0x%X',v[1])
   end
   local target=v[1]+off+5+i32(got,off+1)
   local body=N.weapon_insert_guard:gsub('..',function(h)return string.char(tonumber(h,16))end)
   if target<4096 or target+#body>size or read(base+target,#body)~=body then
    return false,'weapon insertion helper guard'
   end
  elseif got~=want then return false,string.format('weapon code guard 0x%X',v[1]) end
 end
 return true
end
function G:weapon_component(d,root_rva,to,dp,array_offset,stride,n)
 local manager=ptr(self:watch(self.base+root_rva,8),0)
 if manager==0 then return nil end
 local j,owner=self:component(manager,d.entity,to,dp)
 if j==nil then return nil end
 if not same(owner,d) then error('weapon component owner mismatch',0) end
 local array=ptr(self:watch(manager+array_offset,8),0)
 -- Values copied once; validate identity/table/array pointers after the copy.
 return self:read(array+j*stride,n)
end

end
local RepairNative=(function()
-- Native repair interfaces identified in the user-provided Vehicle Supply Tower 1.0.1.
-- This module uses fixed, guarded call sites on the already validated HUD build.
-- It never scans or patches executable pages. All calls run in the game's Lua update.
return function(N, log)
    local ffi = require('ffi')
    local R = { cache = {}, maps = {}, observations = {}, calls = 0, fixed = 0, legs_fixed = 0, leg_fires_stopped = 0, next_check = 0 }
    local exo_types = {['79e4b3d2da5e45e3']=true, ['c2d449ecf7facab1']=true,
        ['7b2326f6fd9c8069']=true, ['35dbf54f016f3624']=true}
    -- Vehicle Supply Tower's known arm resources; upgrades use observed ammo caps.
    R.arm_types = {['08f6089289c83d22']=true, ['824b7e0c4c879eb5']=true, ['821d035aa47e3e75']=true,
        ['bf4167fd26917ab1']=true, ['e5f64dcc3bfe9dd1']=true, ['32c7063b4bcc4208']=true,
        ['8ca4dfa795a473c8']=true, ['ff9878576a4c543b']=true, ['0a03761d50ba5121']=true,
        ['3e3a31261a124454']=true, ['0736bee2d6328726']=true, ['17c5d12d8d5dee2c']=true,
        ['65489809a8181b96']=true, ['df51fe8d62f294be']=true}
    local wheel_names = {'fed0a478', 'f3cb00ad', 'c6bf05a9', 'f12186b7'}
    local U32 = 4294967296
    local signatures = {
        -- Script StopEffect wrapper: entity, name, node=0, replicate=1, queued=false.
        effect_stop = {0x4DDE80, '48 83 EC 38 48 8B 01 44 8B C2 48 8B 0D ?? ?? ?? ?? 45 33 C9 C6 44 24 28 00 C7 44 24 20 01 00 00 00 8B 50 08 E8 ?? ?? ?? ?? 48 83 C4 38 C3'},
        effect_config = {0x4FC3A0, '48 85 C9 74 71 48 8B 05 ?? ?? ?? ?? 44 8B C1 4C 8B 90 B8 27 F1 00 48 B8 BF A0 2F E8 0B FA 82 BE 48 F7 E1 48 C1 EA 0A 69 C2 60 05 00 00 44 2B C0'},
        -- Reviewed input dispatcher and per-entity Weapon table on the captured build.
        bash = {0x7406F0, '48 8B 46 40 48 8B 4E 58 45 8B F1 48 89 4C 24 58 4E 8B 2C F0 4F 8D 3C B6 48 8B 46 50 48 89 44 24 60 4C 89 6C 24 70 4C 89 7C 24 68 42 8B 04 F8 0F BA E0 0D'},
        bash_table = {0x744AF7, '44 8B 49 30 45 33 C0 44 8B 59 38 41 8B D0 44 0F AF DB 45 8D 71 FF 45 85 C9 74 2E 48 8B 71 28 8B 69 34'},
        bash_branch = {0x7407C0, 'A8 08 0F 84 1D 01 00 00 41 8B 5D 08 3B 1D ?? ?? ?? ?? 45 0F B6 3C 0E 4C 8B 35 ?? ?? ?? ??'},
        bash_root = {0x74084C, '48 8B 0D ?? ?? ?? ?? 8B D3 E8 ?? ?? ?? ?? 84 C0 74 05'},
        heal = {0x4B9B50, '40 57 48 83 EC 20 48 8B 39 4C 8B 1D ?? ?? ?? ?? 8B 47 08 3B 05 ?? ?? ?? ?? 74 ?? 45 8B 93 ?? ?? ?? ?? 45 33 C0 48 89 5C 24 30 41 8B 9B ?? ?? ?? ?? 0F AF D8 4C 89 74 24 48 45 8D 72 FF 45 85 D2 74 ?? 48 89 6C 24 38 41 8B AB ?? ?? ?? ?? 48 89 74 24 40 49 8B B3 ?? ?? ?? ?? 66 0F 1F 44 00 00 41 8D 14 18 41 8B CE 48 23 D1 44 8B 0C D6 44 3B CD 74 ?? 44 3B C8 74 ?? 41 FF C0 45 3B C2 72 ?? 48 8B 74 24 40 48 8B 6C 24 38 48 8B 5C 24 30 4C 8B 74 24 48 0F 28 D1 8B D0 49 8B CB 48 83 C4 20 5F E9 ?? ?? ?? ??'},
        wheel = {0x11A8490, '48 89 5C 24 18 48 89 6C 24 20 57 48 81 EC C0 00 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 84 24 B0 00 00 00 8B 41 08 8B EA 3B 05 ?? ?? ?? ?? 48 8B 1D ?? ?? ?? ?? 75 ?? B8 FF FF FF FF EB ?? 44 8B 4B 48 33 D2 44 8B 53 50 44 0F AF D0'},
        stat = {0x9CCAE0, '40 55 3B 15 ?? ?? ?? ?? 4C 8B 15 ?? ?? ?? ?? 49 63 E8 75 ?? B8 FF FF FF FF EB ?? 45 8B 4A 28 33 C9 45 8B 5A 30 48 89 5C 24 10 48 89 74 24 18 44 0F AF DA 41 8D 71 FF 48 89 7C 24 20 45 85 C9 74 ?? 49 8B 5A 20 41 8B 7A 2C 0F 1F 80 00 00 00 00 8B C6 46 8D 04 19 4C 23 C0 42 8B 04 C3 3B C7 74 ?? 3B C2 74 ?? FF C1 41 3B C9 72 ?? B8 FF FF FF FF 48 8B 74 24 18 48 8B 5C 24 10 48 8B 7C 24 20 8B C8 49 8B 42 48 48 6B D1 0D 48 03 D5 F3 0F 11 1C 90 5D C3'},
        attach = {0x4A52B0, '48 89 5C 24 08 48 89 6C 24 10 48 89 74 24 18 48 89 7C 24 20 3B 15 ?? ?? ?? ?? 4C 8B 15 ?? ?? ?? ?? 74 ?? 45 8B 4A 20 45 33 C0 41 8B 5A 28 0F AF DA 41 8D 69 FF 45 85 C9 74 ?? 49 8B 7A 18 41 8B 72 24 0F 1F 40 00 66 66 0F 1F 84 00 00 00 00 00 8B C5 41 8D 0C 18 48 23 C8 8B 04 CF 4C 8D 1C CF 3B C6 74 ?? 3B C2 74 ?? 41 FF C0 45 3B C1 72 ?? 32 C0 48 8B 5C 24 08 48 8B 6C 24 10 48 8B 74 24 18 48 8B 7C 24 20 C3 3B C2 75 ?? 41 8B 43 04 83 F8 FF 74 ?? 48 69 C8 ?? ?? ?? ?? 49 8B 42 ?? 83 3C 01 00 0F 95 C0 EB ??'},
    }
    local ctypes = {
        effect_stop = 'void (*)(void *, uint32_t, uint32_t, uint32_t, uint32_t, bool)',
        heal = 'void (*)(void *, uint32_t, float)',
        query = 'uint64_t (*)(uint32_t, uint32_t, void *)',
        get = 'uint64_t (*)(uint32_t, uint32_t, void *)',
        set = 'uint64_t (*)(uint32_t, uint32_t, void *)',
        damage = 'void (*)(void *, uint32_t)',
    }
    local functions = {}
    pcall(ffi.cdef, 'size_t __stdcall VirtualQuery(const void *, void *, size_t);')
    pcall(ffi.cdef, 'void * __stdcall GetModuleHandleA(const char *);')
    local kernel_ok, kernel = pcall(ffi.load, 'kernel32')
    local region = ffi.new('uint8_t[48]')
    local function pointer(n) return ffi.cast('void *', ffi.cast('uintptr_t', n)) end
    local function read(p, n) return N.win.read(p, n) end
    local function rq(p)
        local b = read(p, 8)
        if not b then return nil end
        local v = N.ptr(b, 0)
        return v >= 65536 and v or nil
    end
    local function r32(p) local b = read(p, 4); return b and N.u32(b, 0) end
    local function rb(p) local b = read(p, 1); return b and b:byte(1) end
    local function in_module(p)
        return type(p) == 'number' and p >= N.base and p < N.base + N.pe.size
    end
    local function in_engine(p)
        return in_module(p) or (R.exe ~= nil and type(p) == 'number' and p >= R.exe.base and p < R.exe.base + R.exe.size)
    end
    local function resolve_exe()
        if not kernel_ok then return nil end
        local handle = kernel.GetModuleHandleA('helldivers2.exe')
        if handle == nil then return nil end
        local base = tonumber(ffi.cast('uintptr_t', handle))
        local dos = read(base, 0x40)
        if not dos or dos:sub(1, 2) ~= 'MZ' then return nil end
        local offset = N.u32(dos, 0x3C)
        if offset < 0x40 or offset > 0x1000 then return nil end
        local pe = read(base + offset, 0x100)
        if not pe or pe:sub(1, 4) ~= 'PE\0\0' or N.u32(pe, 4) % 65536 ~= 0x8664 or N.u32(pe, 24) % 65536 ~= 0x20B then return nil end
        local size = N.u32(pe, 80)
        if size < 4096 or size > 0x40000000 then return nil end
        return {base = base, size = size}
    end
    local function matches(p, pattern)
        local tokens = {}
        for t in pattern:gmatch('%S+') do tokens[#tokens + 1] = t end
        local b = read(p, #tokens)
        if not b or #b ~= #tokens then return false end
        for i, t in ipairs(tokens) do
            if t ~= '??' and b:byte(i) ~= tonumber(t, 16) then return false end
        end
        return true
    end
    local function rel(p, displacement, length)
        local b = read(p + displacement, 4)
        if not b then error('unreadable relative address', 0) end
        local target = p + length + N.i32(b, 0)
        if not in_engine(target) then error('relative target outside game modules', 0) end
        return target
    end
    local function need(ok, why) if not ok then error(why, 0) end end
    local function resolve_heal()
        local p = N.base + signatures.heal[1]
        need(matches(p, signatures.heal[2]), 'repair-drone wrapper guard')
        local root = rel(p + 9, 3, 7)
        need(root == N.base + N.roots.health, 'repair health manager differs')
        need(matches(p + 0xA1, 'E9 ?? ?? ?? ??'), 'repair tail jump')
        local fn = rel(p + 0xA1, 1, 5)
        need(matches(fn, '48 8B C4 48 89 58 10'), 'repair function prologue')
        need(matches(fn + 0xBB, '49 8B CC') and matches(fn + 0xC2, 'E8 ?? ?? ?? ??'), 'repair config call')
        need(matches(fn + 0xCB, '4D 69 ED B8 01 00 00'), 'repair Health record stride')
        return {root = root, fn = fn}
    end
    local function resolve_wheel()
        local p = N.base + signatures.wheel[1]
        need(matches(p, signatures.wheel[2]), 'wheel damage function guard')
        need(matches(p + 0xB3, '4C 8B 0D ?? ?? ?? ??'), 'wheel component query root')
        need(matches(p + 0xBA, '4C 8D 44 24 50 8B 4B 0C BA 10 00 00 00'), 'wheel component mask 16')
        need(matches(p + 0xCD, '48 8B 4C 24 70'), 'wheel component handle offset')
        need(matches(p + 0xEB, '48 8B 05 ?? ?? ?? ??'), 'VehicleApi root')
        need(matches(p + 0xFC, 'FF 50') and matches(p + 0x173, 'FF 50'), 'wheel getter/setter calls')
        local get, set = rb(p + 0xFE), rb(p + 0x175)
        need(get and set and get ~= set and get <= 0xF8 and set <= 0xF8 and get % 8 == 0 and set % 8 == 0, 'wheel API slots')
        local api = rel(p + 0xEB, 3, 7)
        need(api == rel(p + 0x114, 3, 7), 'VehicleApi roots differ')
        local damage_guard = 'F3 0F 10 87 64 01 00 00 4C 8D 44 24 20 F3 0F 10 4C 24 2C 8B D5 48 8B 05 ?? ?? ?? ?? 8B CB F3 0F 11 44 24 20 F3 0F 59 8F 68 01 00 00 C6 44 24 48 01 F3 0F 10 44 24 34 0F 5A C0 F3 0F 11 4C 24 2C F2 0F 59 05 ?? ?? ?? ?? F3 0F 10 4C 24 30 F3 0F 59 0D ?? ?? ?? ?? 66 0F 5A C0 F3 0F 11 4C 24 30 F3 0F 11 44 24 34 F3 0F 10 05 ?? ?? ?? ?? F3 0F 11 44 24 38 FF 50 48'
        local damage = get==0x40 and set==0x48 and matches(p+0xFF,damage_guard)
            and matches(p+0xA3,'48 8B 43 58 48 8B 1C C8 48 8B CB E8')
        return {query = rel(p + 0xB3, 3, 7), api = api, get = get, set = set,
            damage=damage and p or nil, vehicle_root=rel(p+0x2F,3,7),damage_guard=damage_guard}
    end
    local function resolve_stat()
        local p = N.base + signatures.stat[1]
        need(matches(p, signatures.stat[2]), 'stat modifier guard')
        local tbl = rb(p + 0x44)
        need(tbl == 0x20 and rb(p + 0x1E) == tbl + 8 and rb(p + 0x48) == tbl + 12
            and rb(p + 0x24) == tbl + 16 and rb(p + 0x85) == 0x48
            and matches(p + 0x86, '48 6B D1 0D'), 'stat modifier table/13-float stride')
        return {root = rel(p + 8, 3, 7), tbl = tbl, rows = 0x48}
    end
    local function resolve_attach()
        local p = N.base + signatures.attach[1]
        need(matches(p, signatures.attach[2]), 'attachable parent guard')
        local tbl, stride, rows = rb(p + 0x3D), r32(p + 0x97), rb(p + 0x9E)
        need(tbl == 0x18 and rb(p + 0x26) == tbl + 8 and rb(p + 0x41) == tbl + 12
            and rb(p + 0x2D) == tbl + 16, 'attachable table layout')
        need(stride and stride >= 4 and stride < 0x1000 and stride % 4 == 0
            and rows and rows >= tbl + 24 and rows < 0x100 and rows % 8 == 0, 'attachable rows/stride')
        return {root = rel(p + 0x1A, 3, 7), tbl = tbl, rows = rows, stride = stride}
    end
    local function resolve_bash()
        for _, name in ipairs({'bash','bash_table','bash_branch','bash_root'}) do
            need(matches(N.base+signatures[name][1],signatures[name][2]), 'shield bash '..name..' guard')
        end
        local p=N.base+signatures.bash_root[1]
        local root=rel(p,3,7)
        need(root==N.base+0x3326660 and rel(p+9,1,5)==N.base+0x744AD0,
            'shield bash Weapon root/query differs')
        return {root=root,tbl=0x28,owners=0x40,rows=0x50,stride=0x28,bit=8}
    end
    local function resolve_effects()
        local p = N.base + signatures.effect_stop[1]
        need(matches(p, signatures.effect_stop[2]), 'StopEffect wrapper guard')
        local root, fn = rel(p + 0xA, 3, 7), rel(p + 0x24, 1, 5)
        need(root == N.base + 0x3326570 and fn == N.base + 0x8ABB20, 'StopEffect root/function differs')
        need(matches(fn, '48 89 5C 24 18 48 89 6C 24 20 56 57 41 54 41 56 41 57 48 83 EC 40'), 'StopEffect prologue')
        need(matches(fn + 0x42, '4C 8B 59 20 44 8B 71 2C')
            and matches(fn + 0x82, '49 8B 47 38 4E 8B 24 F0'), 'StopEffect table/owner layout')
        need(matches(fn + 0xBC, 'E8 ?? ?? ?? ?? 4D 69 F6 18 02 00 00 44 8B ED 4D 03 77 48 4C 8D 78 28'), 'StopEffect config/row layout')
        local cp = rel(fn + 0xBC, 1, 5)
        need(cp == N.base + signatures.effect_config[1] and matches(cp, signatures.effect_config[2])
            and rel(cp + 5, 3, 7) == N.base + N.roots.network
            and matches(cp + 0x7E, '8B 48 08 48 69 C1 48 0F 00 00 48 05 00 56 00 00 49 03 C2 C3'), 'EffectReference configuration guard')
        need(matches(fn + 0xD6, '41 39 7F 10') and matches(fn + 0xF5, '41 8B 4F 24 83 E9 01 74 31 83 F9 01 75 49'), 'StopEffect name/strategy layout')
        need(matches(fn + 0x115, '41 FF 90 B0 02 00 00') and matches(fn + 0x141, '41 FF 90 A0 02 00 00')
            and matches(fn + 0x148, '41 89 2C 24'), 'StopEffect particle cleanup')
        need(matches(fn + 0x193, 'B9 00 73 6B 13')
            and matches(fn + 0x1AD, '41 FF C5 49 83 C7 50 49 83 C4 04 41 83 FD 20'), 'StopEffect replication/32-slot layout')
        return {root=root, fn=fn, tbl=0x20, owners=0x38, rows=0x48, stride=0x218}
    end
    function R.ensure(now)
        if not N.ready then return false end
        if R.base == N.base and now < R.next_check then return R.health ~= nil or R.wheels ~= nil or R.stats ~= nil end
        R.base, R.next_check = N.base, now + 10
        N.win.begin_sample()
        local exe_ok, exe = pcall(resolve_exe)
        R.exe = exe_ok and exe or nil
        for name, resolve in pairs({health = resolve_heal, wheels = resolve_wheel, stats = resolve_stat, attach = resolve_attach, bash = resolve_bash, effects = resolve_effects}) do
            local ok, value = pcall(resolve)
            R[name] = ok and value or nil
            local status = ok and 'ok' or tostring(value)
            if R[name .. '_status'] ~= status then
                R[name .. '_status'] = status
                log('repair native %s: %s', name, status)
            end
        end
        return R.health ~= nil or R.wheels ~= nil or R.stats ~= nil
    end
    function R.invoke(name, p, ...)
        need(in_engine(p) and read(p, 1), 'native function outside readable game modules')
        need(kernel_ok and tonumber(kernel.VirtualQuery(pointer(p), region, 48)) == 48, 'native executable-page query failed')
        local b = ffi.string(region, 48)
        local protection = N.u32(b, 36)
        local page = protection % 256
        need(N.u32(b, 32) == 0x1000 and math.floor(protection / 256) % 2 == 0
            and (page == 0x20 or page == 0x40 or page == 0x80), 'native target is not an executable page')
        local key = name .. ':' .. tostring(p)
        local fn = functions[key]
        if not fn then fn = ffi.cast(ctypes[name], pointer(p)); functions[key] = fn end
        R.calls = R.calls + 1
        return fn(...)
    end
    local function owner_graph(d)
        local g = N.sample_graph()
        local net, hm = g:root('network'), g:root('health')
        g:roundtrip(net, d)
        local i, hd = g:component(hm, d.entity, 0x1030, 0x1048)
        need(i ~= nil and N.same(hd, d) and hd.flags % 2 == 1, 'repair requires current authoritative owner')
        local rec = N.ptr(g:watch(hm + 0x1058, 8), 0) + i * 0x1B8
        return g, hm, rec
    end
    local function mounted_parent(g, d)
        need(R.attach ~= nil, R.attach_status or 'attachable interface unavailable')
        local am = N.ptr(g:watch(R.attach.root, 8), 0)
        local t = g:table(am + R.attach.tbl)
        local rows = N.ptr(g:watch(am + R.attach.rows, 8), 0)
        local net, hm = g:root('network'), g:root('health')
        local row = g:lookup(t, d.entity)
        if row == nil then return nil, 'arm has no attachment row (entity='..d.entity..')' end
        -- Live v0.18 capture: this field is the parent's full UnitReference,
        -- not its entity ID (arm 551 -> unit 4194742 -> mech entity 550).
        local parent_unit = N.u32(g:watch(rows + row * R.attach.stride, 4), 0)
        local context = string.format('arm=%d parent_unit=%d/%08x',d.entity,parent_unit,parent_unit)
        if parent_unit == 0 or parent_unit == 0xFFFFFFFF then return nil, 'arm is detached ('..context..')' end
        need(type(R.vehicle_roster)=='function', 'vehicle roster unavailable ('..context..')')
        local roster = R.vehicle_roster()
        need(type(roster)=='table' and #roster<=4096, 'vehicle roster bound ('..context..')')
        local matches, visited = {}, {}
        for _, v in ipairs(roster) do
            local candidate = v.d
            if candidate and exo_types[candidate.resource] and candidate.unit==parent_unit then
                local pd = g:net(net,candidate.entity,true)
                if pd and N.same(pd,candidate) and not visited[pd.entity] then
                    g:roundtrip(net,pd)
                    visited[pd.entity]=true; matches[#matches+1]=pd
                end
            end
        end
        if #matches~=1 then return nil, 'parent UnitReference must match exactly one known mech ('..context..' matches='..#matches..')' end
        local pd = matches[1]
        local i, hd = g:component(hm,pd.entity,0x1030,0x1048)
        need(i~=nil and N.same(hd,pd) and pd.flags%2==1 and hd.flags%2==1, 'arm parent is not authoritative ('..context..')')
        local rec = N.ptr(g:watch(hm+0x1058,8),0)+i*0x1B8
        need(N.i32(g:watch(rec+0x14,4),0)>0 and N.u32(g:watch(rec+0x19C,4),0)==0, 'arm parent is dead ('..context..')')
        return pd, nil, string.format('%d->unit:%08x->%d',d.entity,parent_unit,pd.entity)
    end
    local function owner(d, empty_arm)
        local g, hm, rec = owner_graph(d)
        local hp = N.i32(g:watch(rec + 0x14, 4), 0)
        need(N.u32(g:watch(rec + 0x19C, 4), 0) == 0, 'repair does not revive dead vehicles')
        if hp <= 0 then
            need(empty_arm and R.arm_types[d.resource] and hp > -1000000, 'repair does not revive dead vehicles')
            local parent, why = mounted_parent(g, d)
            need(parent ~= nil, why)
        end
        g:validate()
        return hm
    end
    function R.heal(d, fraction, empty_arm)
        if not R.health then return false, R.health_status end
        if type(fraction) ~= 'number' or fraction ~= fraction or fraction <= 0 or fraction > 1 then return false, 'invalid repair fraction' end
        local hm = owner(d, empty_arm)
        need(rq(R.health.root) == hm, 'repair manager changed')
        R.invoke('heal', R.health.fn, pointer(hm), d.entity, fraction)
        return true
    end
    function R.arm_parent(d, graph)
        need(R.arm_types[d.resource], 'unsupported arm resource')
        local g = graph or owner_graph(d)
        local pd, why, chain = mounted_parent(g, d)
        g:validate()
        return pd, why, chain
    end
    -- Shared fresh proof for movement and particle repairs; never trust a cached full snapshot.
    local function fully_repaired(d, cfg, zones, config_address)
        if not exo_types[d.resource] then return nil, 'not an exosuit' end
        local g, hm, rec = owner_graph(d)
        need(config_address(g, g:root('network'), hm, d) == cfg, 'leg Health config owner changed')
        need(N.u32(g:watch(rec + 0x19C, 4), 0) == 0, 'exosuit is dead')
        local mx = N.i32(g:watch(cfg, 4), 0)
        need(mx > 0 and mx <= 10000000, 'invalid exosuit maximum')
        if N.i32(g:watch(rec + 0x14, 4), 0) < mx then return nil, 'exosuit is not fully repaired' end
        local has_leg, count = false, 0
        local state = N.u32(g:watch(rec + 0x20, 4), 0)
        for _, z in ipairs(zones) do
            need(z.i == count and count < 38, 'incomplete leg zone list'); count = count + 1
            local p = cfg + 0x208 + z.i * 0x228
            need(string.format('%08x', N.u32(g:watch(p + 0x60, 4), 0)) == z.hash, 'leg zone identity changed')
            local zm = N.i32(g:watch(p + 0xE8, 4), 0)
            if zm == -1 then zm = mx end
            need(zm == z.max, 'leg zone maximum changed')
            if z.hash == '87b05ff4' or z.hash == '64a3fa1d' then has_leg = true end
            if zm > 0 and (N.i32(g:watch(rec + 0xF8 + z.i * 4, 4), 0) < zm
                or (z.i < 16 and math.floor(state / 4 ^ z.i) % 4 == 2)) then
                return nil, 'exosuit is not fully repaired'
            end
        end
        need(has_leg, 'no known exosuit leg zone')
        if count < 38 then need(N.u32(g:watch(cfg + 0x208 + count * 0x228 + 0x60, 4), 0) == 0, 'incomplete leg zone list') end
        return g
    end
    -- The first float in the guarded 13-float StatModifier row is movement speed.
    function R.fix_leg(d, cfg, zones, write_float, config_address)
        if not R.stats then return false, R.stats_status end
        local g, why = fully_repaired(d, cfg, zones, config_address)
        if not g then return false, why end
        local sm = N.ptr(g:watch(R.stats.root, 8), 0)
        local row = g:lookup(g:table(sm + R.stats.tbl), d.entity)
        if row == nil then return false, 'no stat modifier row' end
        local a = N.ptr(g:watch(sm + R.stats.rows, 8), 0) + row * 52
        local raw = g:watch(a, 4)
        if raw ~= '\0\0\64\63' then return false, 'no 0.75 leg penalty' end
        g:validate()
        if not write_float(a, raw, 1.0) or read(a, 4) ~= '\0\0\128\63' then return false, 'leg speed write/readback failed' end
        R.legs_fixed = R.legs_fixed + 1
        log('exo leg repaired %s ent=%d speed=0.75->1.0 (fully repaired)', d.resource, d.entity)
        return true
    end
    local leg_fire = {['a1d3345e']='2b57c939', ['4a3fa896']='a5bfa032'}
    local function effect_access(d, cfg, zones, config_address)
        local g, why = fully_repaired(d, cfg, zones, config_address)
        if not g then return nil, why end
        local fx = R.effects
        local manager = N.ptr(g:watch(fx.root, 8), 0)
        local row, fd = g:component(manager, d.entity, fx.tbl, fx.owners)
        if row == nil then return nil, 'no effect reference row' end
        need(N.same(fd, d) and fd.flags % 2 == 1, 'leg effect owner changed')
        local rows = N.ptr(g:watch(manager + fx.rows, 8), 0) + row * fx.stride
        local net = g:root('network')
        local settings = N.ptr(g:watch(net + 0xF127B8, 8), 0)
        local start, ecfg = N.mod64hex(d.resource, 1360), nil
        for step = 0, 63 do
            local entry = g:watch(settings + ((start + step) % 1360) * 16, 16)
            local resource = N.hex64(entry, 0)
            if resource == d.resource then
                local index = N.u32(entry, 8)
                need(index < 1360, 'EffectReference settings index')
                ecfg = settings + 0x5600 + index * 0xF48; break
            elseif resource == '0000000000000000' then break end
        end
        need(ecfg ~= nil, 'no EffectReference configuration')
        local particles, found = {}, {}
        for i = 0, 31 do
            local setting = g:watch(ecfg + 8 + i * 80, 80)
            local name = string.format('%08x', N.u32(setting, 48))
            if leg_fire[name] then
                need(not found[name], 'duplicate leg fire name'); found[name] = true
                need(N.hex64(setting, 0) == '1b9236a0c8137ed1'
                    and string.format('%08x', N.u32(setting, 32)) == leg_fire[name]
                    and N.u32(setting, 68) == 2, 'leg fire configuration differs')
                particles[#particles + 1] = {name=N.u32(setting,48), at=rows + i*4}
            end
        end
        if #particles ~= 2 then return nil, 'no recognized leg fire pair' end
        return {g=g, manager=manager, cfg=ecfg, particles=particles}
    end
    function R.stop_leg_fire(d, cfg, zones, config_address)
        if not R.effects then return false, R.effects_status end
        -- Stop one active leg effect per service. Reacquire ownership/health on
        -- the next service, including when movement speed is already normal.
        local a, why = effect_access(d, cfg, zones, config_address)
        if not a then return false, why end
        for _, particle in ipairs(a.particles) do
            if N.u32(a.g:watch(particle.at, 4), 0) ~= 0 then
                a.g:validate()
                need(rq(R.effects.root) == a.manager, 'leg effect manager changed')
                R.invoke('effect_stop', R.effects.fn, pointer(a.manager), d.entity, particle.name, 0, 1, false)
                local back, reason = effect_access(d, cfg, zones, config_address)
                if not back then return false, reason end
                need(back.manager == a.manager and back.cfg == a.cfg, 'leg effect owner changed after stop')
                for _, current in ipairs(back.particles) do
                    if current.name == particle.name then
                        if N.u32(back.g:watch(current.at, 4), 0) ~= 0 then return false, 'leg effect stop readback failed' end
                        back.g:validate()
                        R.leg_fires_stopped = R.leg_fires_stopped + 1
                        log('exo leg fire stopped %s ent=%d effect=%08x (native StopEffect)', d.resource, d.entity, particle.name)
                        return true
                    end
                end
                error('leg effect configuration changed after stop', 0)
            end
        end
        return false, 'no active leg fire'
    end
    local function wheel_access(d)
        need(R.wheels ~= nil, R.wheels_status or 'wheel interface unavailable')
        owner(d)
        local query_table = rq(R.wheels.query)
        local query = query_table and rq(query_table)
        need(query and in_engine(query), 'wheel query function unavailable')
        local buffer = ffi.new('uint8_t[128]')
        R.invoke('query', query, d.unit, 16, buffer)
        local handle_ptr = N.ptr(ffi.string(buffer, 128), 0x20)
        need(handle_ptr >= 65536, 'vehicle handle unavailable')
        local h = r32(handle_ptr)
        need(h and h ~= 0xFFFFFFFF, 'invalid vehicle handle')
        local api = rq(R.wheels.api)
        local get = api and rq(api + R.wheels.get)
        local set = api and rq(api + R.wheels.set)
        need(get and set and in_engine(get) and in_engine(set), 'wheel API functions unavailable')
        need(matches(get, '48 89 5C 24 08 57 48 83 EC 30 8B C1 4C 8D 0D'), 'wheel getter guard')
        local table_root = rel(get + 0x0C, 3, 7)
        local table_ptr = rq(table_root + math.floor(h / 0x40000000) * 8)
        local b = table_ptr and read(table_ptr, 0x38)
        need(b, 'wheel handle table unreadable')
        local base, desc = N.ptr(b, 0), N.u32(b, 0x1C)
        local limit, mask, check = N.u32(b, 0x24), N.u32(b, 0x28), N.u32(b, 0x34)
        local bit = require('bit')
        local index = bit.band(h, mask) % U32
        need(base >= 65536 and index < limit and bit.band(h, check) ~= 0, 'stale wheel handle')
        local stride = desc % 65536
        need(stride >= 0x28 and stride < 0x10000, 'wheel handle stride')
        local entry = base + index * stride
        need(r32(entry + math.floor(desc / 65536) % 256) == h, 'wheel handle generation changed')
        local resource = rq(entry + math.floor(desc / 16777216) + 0x20)
        local offset = resource and r32(resource + 0x0C)
        need(offset and offset < 0x1000000, 'wheel resource header offset')
        local header = resource + offset
        need(r32(header) == 0x20575256 and r32(header + 4) == 4, 'FRV wheel resource must contain four wheels')
        return {h = h, get = get, set = set,header=header}
    end
    local function get_wheel(a, index)
        local b = ffi.new('uint8_t[48]')
        if tonumber(R.invoke('get', a.get, a.h, index, b)) == 0 then return nil end
        local s = ffi.string(b, 48)
        return s:byte(0x29) <= 1 and s or nil
    end
    -- Runtime VRW centres identify physical wheels independently of Health order.
    -- Only the two known FRV resources and the captured axle/centre schema qualify.
    function R.tyre_snapshot(d)
        need(d.resource=='9b2140378640432e' or d.resource=='cc21c7ffd3ebefb9','unsupported tyre resource')
        local a=wheel_access(d); local map,seen,values={},{},{}
        for i=0,3 do
            local off=r32(a.header+8+i*4)
            need(off and off>=24 and off<=0x10000,'wheel resource offset')
            local raw=read(a.header+off,24);need(raw,'wheel centre unreadable')
            local f=ffi.new('float[3]');ffi.copy(f,raw:sub(13,24),12)
            local x,y,z=tonumber(f[0]),tonumber(f[1]),tonumber(f[2])
            local axle,steered=N.u32(raw,0),N.u32(raw,4)
            need(x==x and y==y and z==z and math.abs(x)>=0.5 and math.abs(x)<=3
                and math.abs(y)>=0.5 and math.abs(y)<=4 and math.abs(z)<=1,'unknown FRV wheel centre')
            need((axle==1 and steered==0 and y>0) or (axle==2 and steered==1 and y<0),'unknown FRV axle layout')
            local hash=y>0 and (x<0 and 'fed0a478' or 'f3cb00ad') or (x<0 and 'c6bf05a9' or 'f12186b7')
            need(not seen[hash],'duplicate FRV wheel location');seen[hash]=true;map[i]=hash
            values[i]=get_wheel(a,i);need(values[i],'wheel parameters unavailable')
        end
        return {h=a.h,map=map,values=values}
    end
    function R.damage_wheel(d,index,hash)
        need(R.wheels and R.wheels.damage,'wheel damage transformation guard unavailable')
        need(type(index)=='number' and index>=0 and index<=3 and index%1==0,'wheel index')
        local before=R.tyre_snapshot(d)
        need(before.map[index]==hash,'wheel location changed')
        if before.values[index]:byte(0x29)==1 then return before.values[index],before.h end
        local g=N.sample_graph();local vm=N.ptr(g:watch(R.wheels.vehicle_root,8),0)
        local j,vd=g:component(vm,d.entity,0x40,0x58)
        need(j~=nil and N.same(vd,d) and vd.flags%2==1,'vehicle damage owner changed')
        g:roundtrip(g:root('network'),vd);g:validate()
        local fresh=wheel_access(d);need(fresh.h==before.h,'wheel handle changed before damage')
        R.invoke('damage',R.wheels.damage,pointer(vd.address),index)
        local back=R.tyre_snapshot(d)
        need(back.h==before.h and back.map[index]==hash and back.values[index]:byte(0x29)==1,'wheel damage readback failed')
        return back.values[index],back.h
    end
    function R.restore_guard_wheel(d,index,hash,expected,intact,handle)
        local current=R.tyre_snapshot(d)
        need(current.h==handle and current.map[index]==hash,'guarded wheel identity changed')
        if current.values[index]:byte(0x29)==0 then return true end
        need(current.values[index]==expected,'guarded wheel parameters changed externally')
        need(type(intact)=='string' and #intact==48 and intact:byte(0x29)==0,'intact wheel snapshot')
        local a=wheel_access(d);need(a.h==handle,'wheel handle changed before restore')
        local buffer=ffi.new('uint8_t[48]');ffi.copy(buffer,intact,48)
        R.invoke('set',a.set,a.h,index,buffer)
        return get_wheel(a,index)==intact
    end
    -- Health zone indices and VehicleApi wheel indices are different namespaces.
    -- Learn only unambiguous simultaneous damage, never infer an index from its name/order.
    function R.observe_damage(d, zones, data)
        if not R.wheels then return end
        local key = d.entity .. ':' .. d.goid .. ':' .. d.unit .. ':' .. d.resource
        local a, broken, flags = wheel_access(d), {}, {}
        for i = 0, 3 do
            local z = zones[i + 1]
            if not z or z.i ~= i or z.hash ~= wheel_names[i + 1] then return end
            local hp = N.i32(data, 0xF8 + i * 4)
            local bits = math.floor(N.u32(data, 0x20) / 4 ^ i) % 4
            broken[i] = (hp <= 0 and hp > -1000000) or bits == 2
            local s = get_wheel(a, i)
            if not s then return end
            flags[i] = s:byte(0x29) == 1
        end
        local old = R.observations[key]
        R.observations[key] = {broken = broken, flags = flags}
        local function unique(values, previous)
            local found
            for i = 0, 3 do
                if values[i] and (not previous or not previous[i]) then
                    if found ~= nil then return nil end
                    found = i
                end
            end
            return found
        end
        local zone, index = unique(broken, old and old.broken), unique(flags, old and old.flags)
        if zone == nil or index == nil then return end
        local map = R.maps[d.resource] or {}
        local hash = wheel_names[zone + 1]
        local conflict = map[index] and map[index] ~= hash
        for i, name in pairs(map) do if i ~= index and name == hash then conflict = true end end
        if conflict then
            R.maps[d.resource] = nil
            log('wheel mapping reset %s: contradictory damage observations', d.resource)
            return
        end
        if not map[index] then
            map[index] = hash; R.maps[d.resource] = map
            log('wheel mapping learned %s api_index=%d zone=%s (isolated damage)', d.resource, index, hash)
        end
    end
    function R.allowed(d, selected)
        local all, none = true, true
        for _, hash in ipairs(wheel_names) do
            if selected[hash] then none = false else all = false end
        end
        local allowed, map = {}, R.maps[d.resource] or {}
        for i = 0, 3 do allowed[i] = all or (not none and map[i] ~= nil and selected[map[i]] == true) end
        return allowed, not all and not none
    end
    function R.learn(d)
        if not R.wheels then return false, R.wheels_status end
        local c = R.cache[d.resource]
        if c and c.complete then return true end
        local a = wheel_access(d)
        c = c or {}; R.cache[d.resource] = c
        local count = 0
        for i = 0, 3 do
            if not c[i] then
                local sample = get_wheel(a, i)
                if sample and sample:byte(0x29) == 0 then
                    c[i] = sample
                    log('wheel learned %s index=%d (VehicleApi, 48 bytes)', d.resource, i)
                end
            end
            if c[i] then count = count + 1 end
        end
        c.complete = count == 4
        return true
    end
    function R.repair_wheel(d, allowed)
        if not R.wheels then return false, R.wheels_status end
        local c = R.cache[d.resource]
        if not c then return false, 'no intact tyre sample; spawn an intact FRV of the same type' end
        local a = wheel_access(d)
        local missing = false
        for i = 0, 3 do
            if allowed[i] then
                local current = get_wheel(a, i)
                if current and current:byte(0x29) == 1 then
                    if c[i] then
                        local buffer = ffi.new('uint8_t[48]')
                        ffi.copy(buffer, c[i], 48)
                        buffer[0x28] = 0
                        -- Revalidate ownership and query again immediately before mutation.
                        local fresh = wheel_access(d)
                        need(fresh.h == a.h and fresh.set == a.set, 'wheel interface changed before repair')
                        R.invoke('set', fresh.set, fresh.h, i, buffer)
                        local back = get_wheel(fresh, i)
                        if not back or back:byte(0x29) ~= 0 then return false, 'tyre setter readback failed' end
                        R.fixed = R.fixed + 1
                        log('wheel repaired %s ent=%d index=%d flag=1->0 (mobility; model not rebuilt)', d.resource, d.entity, i)
                        return true
                    end
                    missing = true
                end
            end
        end
        return false, missing and 'missing intact sample for damaged wheel' or 'no selected blown tyre'
    end
    function R.reset() R.cache, R.maps, R.observations = {}, {}, {}; functions = {} end
    R.signatures = signatures -- read-only metadata used by offline guard tests
    return R
end

end)()
local WeaponFault=(function()
-- Weapon failure is latched at 1 HP; only repair above 5% releases the latch.
-- Protect known independent arm Health zones before damage. No executable patch.
-- Guns escrow ammunition; EXO-55 shields clear only their skill-input bit.
-- Restoration is
-- tied to the original network/Health/weapon owners, never just an entity ID.
return function(N, W, R, C, log, ammo_components)
    local ffi = require('ffi')
    local bit = require('bit')
    local F = {states = {}, configs = {}, reports = {}}
    F.models = {
        ['08f6089289c83d22']={name='EXO-45 minigun',zone='372f0418'},
        ['824b7e0c4c879eb5']={name='EXO-45 rockets',zone='aa1db0b0'},
        ['821d035aa47e3e75']={name='EXO-45 rockets MK2',zone='aa1db0b0'},
        ['bf4167fd26917ab1']={name='EXO-49 arm',zone='372f0418'},
        ['e5f64dcc3bfe9dd1']={name='EXO-49 autocannon L',zone='372f0418'},
        ['ff9878576a4c543b']={name='EXO-49 autocannon R',zone='372f0418'},
        ['32c7063b4bcc4208']={name='EXO-49 autocannon L MK2',zone='372f0418'},
        ['8ca4dfa795a473c8']={name='EXO-49 autocannon L MK3',zone='372f0418'},
        ['0a03761d50ba5121']={name='EXO-49 autocannon R MK2',zone='372f0418'},
        ['3e3a31261a124454']={name='EXO-49 autocannon R MK3',zone='372f0418'},
        ['0736bee2d6328726']={name='EXO-51 flamethrower',zone='aa1db0b0'},
        ['17c5d12d8d5dee2c']={name='EXO-51 AT cannon',zone='372f0418'},
        ['df51fe8d62f294be']={name='EXO-55 flak cannon',zone='372f0418'},
        ['65489809a8181b96']={name='EXO-55 shield arm',zone='fd7c9885',shield=true,
            zones={{hash='fd7c9885',max=-1},{hash='b0ef49f8',max=5000}}},
    }
    local function key(d) return d.entity..':'..d.goid..':'..d.unit..':'..d.resource end
    local function need(v, s) if not v then error(s, 0) end end
    local function report(d, why)
        local k = key(d)..':'..why
        if not F.reports[k] then F.reports[k]=true; log('weapon guard skip %s ent=%d: %s', d.resource, d.entity, why) end
    end
    local function snapshot(d, allow_dead)
        local g = N.sample_graph()
        local net, hm = g:root('network'), g:root('health')
        g:roundtrip(net, d)
        local j, hd = g:component(hm, d.entity, 0x1030, 0x1048)
        need(j ~= nil and N.same(hd,d) and hd.flags % 2 == 1, 'weapon Health owner/authority changed')
        local rec = N.ptr(g:watch(hm+0x1058,8),0)+j*0x1B8
        local data = g:read(rec,0x1B8)
        g:watch(rec+0x19C,4)
        need(allow_dead or N.u32(data,0x19C)==0, 'already engine-dead; spawn a new mech')
        local cfg = F.config_address(g,net,hm,d)
        local mx = N.i32(g:watch(cfg,4),0)
        need(mx >= 20 and mx <= 1000000, 'invalid weapon maximum')
        local model = F.models[d.resource]
        need(model ~= nil, 'unsupported weapon resource')
        need(N.i32(g:watch(cfg+0x40+0xE8,4),0)==-1, 'default zone maximum changed')
        local parts, bases = {}, {cfg+0x40}
        for i, expected in ipairs(model.zones or {{hash=model.zone,max=mx}}) do
            local z=cfg+0x208+(i-1)*0x228
            need(string.format('%08x',N.u32(g:watch(z+0x60,4),0))==expected.hash,
                'weapon damage zone identity changed')
            local rawmax=N.i32(g:watch(z+0xE8,4),0)
            local zm=rawmax==-1 and mx or rawmax
            need(zm==(expected.max==-1 and mx or expected.max), 'weapon zone maximum changed')
            local contribution=g:read(z+0xF8,4)
            if model.shield and i==1 then
                need(contribution=='\0\0\128\63' or contribution=='\0\0\0\0', 'unexpected shield-arm damage contribution')
            else need(contribution=='\0\0\0\0', 'unexpected weapon-to-main damage contribution') end
            local hp=N.i32(data,0xF8+(i-1)*4)
            if i==1 then hp=math.min(hp,N.i32(data,0x14)) end
            need(hp>-1000000 and hp<=zm, 'invalid effective weapon HP')
            parts[#parts+1]={hash=expected.hash,mx=zm,hp=hp,index=i-1,rawmax=rawmax}
            bases[#bases+1]=z
        end
        need(N.u32(g:watch(cfg+0x208+#parts*0x228+0x60,4),0)==0, 'unexpected additional weapon damage zone')
        for _, base in ipairs(bases) do
            for o=0xF0,0xF4 do need(g:read(base+o,1):byte(1)<=1, 'invalid death flags') end
            need(N.i32(g:read(base+0xEC,4),0)==0 and g:read(base+0xF1,3)=='\0\0\0', 'unexpected constitution/death propagation')
        end
        local contribution=g:read(cfg+0x40+0xF8,4)
        local f=ffi.new('float[1]'); ffi.copy(f,contribution,4)
        need(f[0]==f[0] and f[0]>=0 and f[0]<=1, 'invalid default-to-main damage contribution')
        local bash
        if model.shield then
            need(R.bash~=nil, R.bash_status or 'shield bash interface unavailable; protection not armed')
            local b=R.bash
            local m=N.ptr(g:watch(b.root,8),0)
            local n,owner=g:component(m,d.entity,b.tbl,b.owners)
            need(n~=nil and N.same(owner,d) and owner.flags%2==1, 'shield Weapon owner/authority changed')
            local p=N.ptr(g:watch(m+b.rows,8),0)+n*b.stride
            local flags=N.u32(g:read(p,4),0)
            need(bit.band(flags,0x2800)==0x2800 and bit.band(flags,0x37)==0,
                'shield Weapon kind flags changed')
            bash={p=p,flags=flags}
        end
        local slots = {}
        for _, comp in ipairs(model.shield and {} or ammo_components) do
            local m = N.ptr(g:watch(N.base+comp.root,8),0)
            if m ~= 0 then
                local n, owner = g:component(m,d.entity,comp.to,comp.dp)
                if n ~= nil then
                    need(N.same(owner,d) and owner.flags%2==1, 'ammunition owner changed')
                    local arr = N.ptr(g:watch(m+comp.arr,8),0)+n*comp.stride
                    for _, field in ipairs(comp.fields) do
                        local p = arr+field[2]
                        local value = N.i32(g:read(p,4),0)
                        need(value>=0 and value<=100000, 'invalid ammunition value')
                        slots[#slots+1]={id=comp.name..':'..field[1],p=p,value=value}
                    end
                end
            end
        end
        need(model.shield or #slots > 0, 'no verified ammunition stores; protection not armed')
        g:validate()
        return {g=g,d=d,cfg=cfg,rec=rec,mx=mx,hp=parts[1].hp,main_hp=N.i32(data,0x14),parts=parts,
            slots=slots,bash=bash,life=N.u32(data,0x19C),zone=model.zone,model=model}
    end
    local function put(e, offset, value)
        local p, n = e.cfg+offset, #value
        local old = N.win.read(p,n)
        if not old then return false end
        if e.orig[offset]==nil then e.orig[offset]=old end
        if old == value then e.wrote[offset]=value; return true end
        if e.wrote[offset] and old ~= e.wrote[offset] then return false end
        if W.raw(p,n,old,value) then e.wrote[offset]=value; return true end
        return false
    end
    local function config_identity(e)
        local b = N.win.read(e.cfg,4)
        if not b then return nil end
        if N.i32(b,0)~=e.mx then return false end
        for i,part in ipairs(e.parts) do
            local z=N.win.read(e.cfg+0x208+(i-1)*0x228+0x60,4)
            local mx=N.win.read(e.cfg+0x208+(i-1)*0x228+0xE8,4)
            if not z or not mx then return nil end
            if string.format('%08x',N.u32(z,0))~=part.hash or N.i32(mx,0)~=part.rawmax then return false end
        end
        return true
    end
    local function close_config(e)
        local identity=config_identity(e)
        if identity==nil then return false end
        if not identity then
            log('weapon guard config abandoned cfg=%x: identity changed; original bytes not written',e.cfg)
            return true
        end
        local done = true
        for off, original in pairs(e.orig) do
            local cur = N.win.read(e.cfg+off,#original)
            if not cur then done=false
            elseif cur==e.wrote[off] and cur~=original then
                if not W.raw(e.cfg+off,#cur,cur,original) then done=false end
            end
        end
        return done
    end
    local function arm_config(s)
        local e=F.configs[s.cfg]
        if not e then e={cfg=s.cfg,mx=s.mx,zone=s.zone,parts=s.parts,orig={},wrote={},users=0}; F.configs[s.cfg]=e end
        need(e.mx==s.mx and e.zone==s.zone and config_identity(e), 'protected config identity changed')
        e.users=e.users+1
        s.g:validate()
        -- Stop the named zone from killing its independent arm; Immortal lets the
        -- engine keep the zone alive. Default hits must not kill the separate main pool.
        local ready=true
        local edits={{0x40+0xF4,'\0'}, {0x40+0xF0,'\1'}, {0x40+0xF8,'\0\0\0\0'}}
        for i in ipairs(s.parts) do
            local z=0x208+(i-1)*0x228
            edits[#edits+1]={z+0xF4,'\0'}; edits[#edits+1]={z+0xF0,'\1'}
            if s.model.shield and i==1 then edits[#edits+1]={z+0xF8,'\0\0\0\0'} end
        end
        for _, p in ipairs(edits) do
            if not put(e,p[1],p[2]) then ready=false end
        end
        if not ready then return false end
        if not e.logged then
            e.logged=true; log('weapon guard armed %s ent=%d zone=%s max=%d parent=%d parent_unit=%d/%08x chain=%s (Immortal; zones=%d)',s.d.resource,s.d.entity,s.zone,s.mx,s.parent.entity,s.parent.unit,s.parent.unit,s.chain,#s.parts)
        end
        return true
    end
    local function hold_ammo(st,s)
        st.ammo=st.ammo or {}
        local complete=true
        for _, slot in ipairs(s.slots) do
            local saved=st.ammo[slot.id]
            if not saved then saved={value=slot.value}; st.ammo[slot.id]=saved end
            if slot.value~=0 then saved.value=slot.value end -- preserve a later external refill
            if slot.value~=0 then
                s.g:validate()
                if not W.i32(slot.p,slot.value,0) then complete=false end
            end
        end
        return complete
    end
    local function release_ammo(st,s)
        if not st.ammo then return true end
        local by_id={}; for _, slot in ipairs(s.slots) do by_id[slot.id]=slot end
        local complete=true
        local restored={}
        for id,saved in pairs(st.ammo) do
            local slot=by_id[id]
            if not slot then complete=false
            elseif slot.value~=0 then
                -- External refill wins; do not overwrite ammunition from another source.
            elseif saved.value~=0 then
                s.g:validate()
                if W.i32(slot.p,0,saved.value) then restored[#restored+1]={p=slot.p,value=saved.value}
                else complete=false end
            end
        end
        if complete then st.ammo=nil
        else
            -- A partly restored magazine could auto-reload from its spare store.
            -- Roll back our writes immediately and keep the entire escrow for retry.
            for _, slot in ipairs(restored) do
                local valid=pcall(function()s.g:validate()end)
                if valid then W.i32(slot.p,slot.value,0) end
            end
        end
        return complete
    end
    function F.blocked(d) local st=F.states[key(d)]; return st~=nil and st.broken==true end
    local function service(v)
        local d=v.d
        local s=snapshot(d)
        local parent,why,chain=R.arm_parent(d,s.g); need(parent~=nil,why)
        need(not s.model.shield or parent.resource=='35dbf54f016f3624', 'shield parent is not EXO-55')
        s.parent,s.chain=parent,chain
        local k=key(d)
        local st=F.states[k] or {d=d}; F.states[k]=st
        need(not st.bash_owned or N.same(parent,st.parent), 'shield parent changed while input bit held')
        st.seen=true; st.hp,st.mx=s.hp,s.mx; st.parent=parent; st.parts=st.parts or {}
        local protected=arm_config(s)
        if not protected then report(d,'protection write incomplete; retrying') end
        st.own_broken=false
        for i,part in ipairs(s.parts) do
            local state=st.parts[i] or {}; st.parts[i]=state
            state.hash,state.hp,state.mx=part.hash,part.hp,part.mx
            if part.hp<=1 and not state.broken then
                state.broken=true
                log('weapon part failed %s ent=%d zone=%s hp=%d/%d; disabled until >5%%',s.model.name,d.entity,part.hash,part.hp,part.mx)
            elseif state.broken and part.hp>part.mx*0.05 then state.broken=false end
            st.own_broken=st.own_broken or state.broken==true
        end
        if protected and s.model.shield then
            -- The shield's two pools have different maxima. A whole-arm heal
            -- would also heal the other pool outside the bubble; only floor the
            -- current, authoritative live component's depleted pool.
            for _,part in ipairs(s.parts) do
                if part.hp<1 then
                    s.g:validate()
                    local p=s.rec+0xF8+part.index*4
                    local old=N.i32(N.win.read(p,4),0)
                    if old<1 and not W.i32(p,old,1) then report(d,'shield floor write failed; retrying') end
                end
            end
            if s.main_hp<1 then
                s.g:validate()
                local old=N.i32(N.win.read(s.rec+0x14,4),0)
                if old<1 and not W.i32(s.rec+0x14,old,1) then report(d,'shield main floor write failed; retrying') end
            end
        elseif protected and s.hp<1 then
            local ok,why=R.heal(d,1/s.mx,true)
            if not ok then report(d,'floor maintenance: '..tostring(why)) end
            if ok then
                local fresh=snapshot(d)
                if fresh.hp<1 then report(d,'engine floor readback still below 1 HP; inspect live behavior') end
            end
        end
        return s,st
    end
    local function ammunition(s,st,blocked,why)
        local d=s.d
        if blocked and not st.broken then
            st.broken=true; log('weapon failed %s ent=%d hp=%d/%d; disabled until >5%% (%s)',s.model.name,d.entity,s.hp,s.mx,why)
        end
        if st.broken then
            if not blocked then
                if release_ammo(st,s) then
                    st.broken=false
                    log('weapon recovered %s ent=%d hp=%d/%d (>5%%); ammunition restored',F.models[d.resource].name,d.entity,s.hp,s.mx)
                else report(d,'ammunition restore incomplete; retrying') end
            elseif not hold_ammo(st,s) then report(d,'ammunition hold incomplete; retrying') end
        end
    end
    local function restore_bash(st,s)
        if not st.bash_owned then return true end
        need(s.bash~=nil, 'shield bash snapshot unavailable')
        local parent,why=R.arm_parent(s.d,s.g)
        need(parent and N.same(parent,st.parent), why or 'shield parent changed before input restore')
        s.g:validate()
        local flags=s.bash.flags
        if bit.band(flags,8)==0 and not W.u32(s.bash.p,flags,flags+8) then return false end
        st.bash_owned=nil
        return true
    end
    local function shield_input(s,st)
        if st.own_broken then
            st.broken=true
            s.g:validate()
            if bit.band(s.bash.flags,8)~=0 then
                if W.u32(s.bash.p,s.bash.flags,s.bash.flags-8) then
                    if st.bash_owned then
                        st.bash_rewrites=(st.bash_rewrites or 0)+1
                        if st.bash_rewrites==1 then log('shield bash bit rewritten by engine ent=%d; reapplied',s.d.entity) end
                    else log('shield bash disabled ent=%d: shield pool failed; flak ammunition independent',s.d.entity) end
                    st.bash_owned=true
                else report(s.d,'shield bash disable write failed; retrying') end
            end
        elseif restore_bash(st,s) then
            if st.broken then log('shield bash recovered ent=%d: all failed pools strictly >5%%',s.d.entity) end
            st.broken=false
        else report(s.d,'shield bash restore write failed; retrying') end
    end
    function F.step(vehicles)
        if not N.weapon_ready or not R.health or not R.attach then F.close(); return end
        N.win.begin_sample()
        for _, e in pairs(F.configs) do e.users=0 end
        for _, st in pairs(F.states) do st.seen=false end
        local samples={}
        for _, v in ipairs(vehicles) do
            local model=F.models[v.d.resource]
            if model and ((model.shield and C.exo_shield_guard) or (not model.shield and C.exo_weapon_guard)) then
                local ok,s,st=pcall(service,v)
                if not ok then report(v.d,tostring(s))
                else
                    samples[#samples+1]={s=s,st=st}
                end
            end
        end
        for _,sample in ipairs(samples) do
            local s,st=sample.s,sample.st
            local ok,err
            if s.model.shield then ok,err=pcall(shield_input,s,st)
            else ok,err=pcall(ammunition,s,st,st.own_broken,'own damage zone') end
            if not ok then report(s.d,tostring(err)) end
        end
        for cfg,e in pairs(F.configs) do
            if e.users==0 and close_config(e) then F.configs[cfg]=nil end
        end
        for k,st in pairs(F.states) do
            if not st.seen then
                local ok,s=pcall(snapshot,st.d,true)
                if ok then
                    local restored,done=pcall(function() return release_ammo(st,s) and restore_bash(st,s) end)
                    if restored and done then F.states[k]=nil end
                end
                if not ok then
                    local gone,missing=pcall(function()
                        local g=N.sample_graph()
                        local d=g:net(g:root('network'),st.d.entity,true)
                        g:validate()
                        return d==nil or not N.same(d,st.d)
                    end)
                    if gone and missing then
                        F.states[k]=nil
                        log('weapon guard owner gone %s ent=%d: escrow discarded; no write to replacement',st.d.resource,st.d.entity)
                    end
                end
            end
        end
    end
    function F.close()
        if not N.ready then return end
        if N.weapon_ready then
            for _, st in pairs(F.states) do
                if st.ammo or st.bash_owned then
                    local ok,s=pcall(snapshot,st.d,true)
                    if ok then pcall(function() release_ammo(st,s); restore_bash(st,s) end) end
                end
            end
        end
        for cfg,e in pairs(F.configs) do if close_config(e) then F.configs[cfg]=nil end end
    end
    function F.reset()
        F.close()
        local pending={}
        for k,st in pairs(F.states) do if st.bash_owned then pending[k]=st end end
        F.states,F.reports=pending,{}
        -- Failed config restores remain tracked for retry; never silently abandon them.
    end
    function F.status()
        local n,b=0,0
        for _, st in pairs(F.states) do n=n+1; if st.broken then b=b+1 end end
        log('weapon guard: enabled=%s shield_guard=%s components=%d failed=%d; fail at 1 HP, recover strictly >5%%',tostring(C.exo_weapon_guard),tostring(C.exo_shield_guard),n,b)
        for _, st in pairs(F.states) do
            log('  weapon %s ent=%d hp=%s/%s failed=%s held_ammo=%s bash_owned=%s bit_rewrites=%d',F.models[st.d.resource].name,st.d.entity,tostring(st.hp),tostring(st.mx),tostring(st.broken==true),tostring(st.ammo~=nil),tostring(st.bash_owned==true),st.bash_rewrites or 0)
            if F.models[st.d.resource].shield then
                for _,part in ipairs(st.parts or {}) do log('    shield part zone=%s hp=%d/%d failed=%s',part.hash,part.hp,part.mx,tostring(part.broken==true)) end
            end
        end
    end
    return F
end

end)()
local TyreFault=(function()
-- Preserve live FRV wheel models, with independent latched physical punctures.
return function(N,W,R,C,log)
    local T={states={},configs={},reports={}}
    local hashes={'fed0a478','f3cb00ad','c6bf05a9','f12186b7'}
    local function key(d)return d.entity..':'..d.goid..':'..d.unit..':'..d.resource end
    local function need(v,s)if not v then error(s,0)end end
    local function report(d,why)
        local k=key(d)..':'..why
        if not T.reports[k] then T.reports[k]=true;log('tyre guard skip ent=%d: %s',d.entity,why)end
    end
    local function snapshot(d)
        need(d.resource=='9b2140378640432e' or d.resource=='cc21c7ffd3ebefb9','unknown FRV resource')
        need(R.wheels and R.wheels.damage,'wheel damage transformation guard unavailable')
        local g=N.sample_graph();local net,hm=g:root('network'),g:root('health')
        g:roundtrip(net,d)
        local j,hd=g:component(hm,d.entity,0x1030,0x1048)
        need(j~=nil and N.same(hd,d) and hd.flags%2==1 and d.flags%2==1,'FRV Health owner/authority changed')
        local rec=N.ptr(g:watch(hm+0x1058,8),0)+j*0x1B8
        local data=g:read(rec,0x1B8)
        g:watch(rec+0x14,4);g:watch(rec+0x19C,4)
        need(N.i32(data,0x14)>0 and N.u32(data,0x19C)==0,'FRV hull is dead')
        local cfg=T.config_address(g,net,hm,d)
        local mx=N.i32(g:watch(cfg,4),0);need(mx==2400,'unexpected FRV hull maximum')
        local hp={}
        for i,hash in ipairs(hashes) do
            local z=cfg+0x208+(i-1)*0x228
            need(string.format('%08x',N.u32(g:watch(z+0x60,4),0))==hash
                and N.i32(g:watch(z+0xE8,4),0)==350,'unexpected FRV wheel zone')
            need(g:read(z+0xF8,4)=='\0\0\0\0' and N.i32(g:read(z+0xEC,4),0)==0,'unexpected wheel damage contribution')
            need(g:read(z+0xF0,1):byte(1)<=1 and g:read(z+0xF4,1)=='\0','unexpected wheel death flags')
            hp[i]=N.i32(data,0xF8+(i-1)*4)
            need(hp[i]>-1000000 and hp[i]<=350,'invalid wheel HP')
        end
        local physics=R.tyre_snapshot(d);g:validate()
        R.maps[d.resource]=physics.map
        return {g=g,d=d,cfg=cfg,rec=rec,mx=mx,hp=hp,physics=physics}
    end
    local function identity(e)
        local b=N.win.read(e.cfg,4);if not b then return nil end
        if N.i32(b,0)~=2400 then return false end
        for i,hash in ipairs(hashes) do
            local z=e.cfg+0x208+(i-1)*0x228
            local name,mx=N.win.read(z+0x60,4),N.win.read(z+0xE8,4)
            if not name or not mx then return nil end
            if string.format('%08x',N.u32(name,0))~=hash or N.i32(mx,0)~=350 then return false end
        end
        return true
    end
    local function restore_config(e)
        local valid=identity(e)
        if valid==nil then return false end
        if not valid then log('tyre guard config identity changed; original bytes not written');return true end
        local done=true
        for p,original in pairs(e.orig) do
            local cur=N.win.read(p,1)
            if not cur then done=false
            elseif cur==e.wrote[p] and cur~=original and not W.raw(p,1,cur,original) then done=false end
        end
        return done
    end
    local function arm_config(s)
        local e=T.configs[s.cfg]
        if not e then e={cfg=s.cfg,orig={},wrote={},users=0};T.configs[s.cfg]=e end
        need(identity(e),'tyre guard config identity changed');e.users=e.users+1;s.g:validate()
        local ready=true
        for i in ipairs(hashes) do
            local p=s.cfg+0x208+(i-1)*0x228+0xF0
            local cur=N.win.read(p,1);need(cur and cur:byte(1)<=1,'wheel immortal field unreadable')
            if e.orig[p]==nil then e.orig[p]=cur end
            if cur=='\1' then e.wrote[p]=cur
            elseif W.raw(p,1,cur,'\1') then e.wrote[p]='\1'
            else ready=false end
        end
        if ready and not e.logged then
            e.logged=true;log('tyre guard armed %s ent=%d: four 350-HP zones; VRW centres map physical indices',s.d.resource,s.d.entity)
        end
        return ready
    end
    local function restore_part(st,part)
        if not part.wrote then return true end
        local ok,done=pcall(R.restore_guard_wheel,st.d,part.api,part.hash,part.wrote,part.intact,part.handle)
        if ok and done then part.wrote=nil;return true end
        report(st.d,'wheel restore pending: '..tostring(done));return false
    end
    local function service(v)
        local s=snapshot(v.d);local k=key(v.d)
        local st=T.states[k] or {d=v.d,parts={}};T.states[k]=st;st.seen=true
        local protected=arm_config(s)
        if not protected then report(v.d,'wheel protection write incomplete; retrying');return end
        for i,hash in ipairs(hashes) do
            local part=st.parts[i] or {hash=hash};st.parts[i]=part;part.hp=s.hp[i]
            local api
            for j=0,3 do if s.physics.map[j]==hash then api=j end end
            need(api~=nil,'missing physical wheel mapping')
            if part.api~=nil then need(part.api==api and part.handle==s.physics.h,'wheel identity changed') end
            part.api,part.handle=api,s.physics.h
            local cur=s.physics.values[api]
            if not part.intact and cur:byte(0x29)==0 and s.hp[i]>1 then part.intact=cur end
            if s.hp[i]<=1 and not part.broken then
                part.broken=true;log('tyre failed ent=%d zone=%s api=%d hp=%d/350',v.d.entity,hash,api,s.hp[i])
            end
            if part.broken and s.hp[i]>350*0.05 then
                if restore_part(st,part) then
                    part.broken=false;log('tyre recovered ent=%d zone=%s hp=%d/350 (>5%%)',v.d.entity,hash,s.hp[i])
                end
            end
            if protected and s.hp[i]<1 then
                s.g:validate()
                if not W.i32(s.rec+0xF8+(i-1)*4,s.hp[i],1) then report(v.d,'wheel HP floor write failed; retrying') end
            end
            if part.broken and cur:byte(0x29)==0 then
                need(part.intact,'no intact wheel parameters; spawn an intact FRV')
                s.g:validate()
                local raw,h=R.damage_wheel(v.d,api,hash)
                part.wrote,part.handle=raw,h
                log('tyre puncture applied ent=%d zone=%s api=%d: native physical damage, model retained by Immortal',v.d.entity,hash,api)
            end
        end
    end
    local function owner_gone(d)
        local ok,gone=pcall(function()
            local g=N.sample_graph();local fresh=g:net(g:root('network'),d.entity,true)
            g:validate();return not fresh or not N.same(fresh,d)
        end)
        return ok and gone
    end
    function T.allowed(d,allowed)
        local st=T.states[key(d)];if not st then return allowed end
        local out={};for i=0,3 do out[i]=allowed[i] end
        for _,part in pairs(st.parts) do if part.api~=nil and (part.broken or part.wrote) then out[part.api]=false end end
        return out
    end
    function T.step(vehicles)
        N.win.begin_sample()
        for _,e in pairs(T.configs) do e.users=0 end
        for _,st in pairs(T.states) do st.seen=false end
        for _,v in ipairs(vehicles) do
            if v.kind=='frv' then local ok,why=pcall(service,v);if not ok then report(v.d,tostring(why)) end end
        end
        for cfg,e in pairs(T.configs) do if e.users==0 and restore_config(e) then T.configs[cfg]=nil end end
        for k,st in pairs(T.states) do
            if not st.seen then
                if owner_gone(st.d) then T.states[k]=nil
                else
                    local done=true;for _,part in pairs(st.parts) do if not restore_part(st,part) then done=false end end
                    if done then T.states[k]=nil end
                end
            end
        end
    end
    function T.close()
        if not N.ready then return end
        for cfg,e in pairs(T.configs) do if restore_config(e) then T.configs[cfg]=nil end end
        for k,st in pairs(T.states) do
            if owner_gone(st.d) then T.states[k]=nil
            else
                for _,part in pairs(st.parts) do restore_part(st,part) end
            end
        end
    end
    function T.reset()T.close();T.reports={}end
    function T.status()
        for _,st in pairs(T.states) do
            for _,part in pairs(st.parts) do log('tyre guard ent=%d zone=%s api=%s hp=%s/350 failed=%s',st.d.entity,part.hash,tostring(part.api),tostring(part.hp),tostring(part.broken==true)) end
        end
    end
    return T
end

end)()
-- ===========================================================================
-- Shield Vehicle Resupply — main body
-- 读取层来自 DRIVER HUD / HUD（上面拼接进来的 N），这里只加了：
--   * 遍历 Health / Magazine / Rounds 组件表
--   * 坐标（UnitSynchronizer 或 tagged UnitReference）
--   * 护盾检测（World.units + 资源 hash）
--   * 回血：v0.13 起用游戏自带的回血开关（HealthComponent 配置，字段布局来自 filediver datalibrary），
--     不再全内存扫描找血量拷贝（v0.12 的 shadow/hunt 已删除）
--   * compare-before-write 写回
-- ===========================================================================
local sr = rawget(_G, 'stingray')
if rawget(_G, '__SHIELD_VEHICLE_RESUPPLY') then return { installed = true, duplicate = true } end
if type(sr) ~= 'table' then return { installed = false, reason = 'stingray missing' } end
rawset(_G, '__SHIELD_VEHICLE_RESUPPLY', true)

local ffi = require('ffi')
local u32, i32, ptr, hex64, same = N.u32, N.i32, N.ptr, N.hex64, N.same

-- ---------------------------------------------------------------------------
-- 配置（可被 Logs/shield_resupply_settings.txt 覆盖，见 load_settings）
-- ---------------------------------------------------------------------------
local C = {
    enabled        = true,
    tick           = 0.5,    -- 秒（v0.10：0.25 -> 0.5）
    roster_every   = 3.0,    -- 重新遍历组件表/找护盾的间隔（秒）
    spot           = false,  -- 诊断：记录载具附近新出现的实体（耗性能，默认关）
    radius         = 14.5,    -- 护盾半径（米），需实测
    exo_heal       = 0.04,   -- 每秒回复最大值的比例
    tank_heal      = 0.03,
    frv_heal       = 0.05,
    ammo           = true,
    ammo_rate      = 0.10,   -- 每秒补充上限的比例
    cooldown       = 2.0,    -- 受伤后多少秒内不回复
    revive         = false,  -- 修复被打爆（HP≤0）的部位（数据能回来，但模型不会恢复，默认关）
    shield_duration = 45,    -- 护盾最长持续时间（秒，wiki：FX-12 40 秒 + 展开时间）。生成器实体消失也立即结束。0 = 不限时
    tires          = true,   -- FRV：用 VehicleApi 恢复完好轮胎参数和爆胎标志；模型不重建
    wheel_interval = 2.0,    -- 每辆 FRV 至多每隔这些秒修一个轮胎
    part_repair    = true,   -- 调用游戏维修函数处理已毁部位；整车接口要求所有部位均未禁用
    exo_leg_fix    = true,   -- 机甲修满后恢复 0.75 移速倍率，并停止已确认的腿部火焰
    exo_weapon_guard = true, -- 非盾牌武器：1HP 故障锁存；修复严格超过 5% 后恢复使用
    exo_shield_guard = true, -- 大盾机甲：手臂/盾面任一区到 1HP，仅禁用盾击
    frv_tire_guard  = true,  -- 轮胎保留模型，1HP 后施加物理爆胎状态
    net_heal       = true,   -- 用引擎 set_game_object_field 给坦克/FRV 车体（HUD 显示的网络血量）回血（v0.8b 实测 FRV 可行）
    hull_zones     = true,   -- 坦克/FRV：被打爆部位的 HP 数值也回满（模型不变），车体血量才会回（v0.8 推断：车体 = 上限 - 各部位损失）
    authority_only = true,   -- 只改本机有权威的组件（descriptor flags bit0）
    heal           = 'native', -- v0.13：native = 用游戏自带的回血（写 HealthComponent 配置；不扫内存）
                               --        write  = 旧的逐帧写血量（没有扫描，用来对照/兜底）
                               --        off    = 完全不回血（诊断用）
    native_zone    = 0x141,  -- filediver 二进制类型表：RegenerationEnabled；逐部位校验后才写。0 = 保留旧路径
    part_regen     = true,   -- 原生部位再生默认开关；part=<资源hash>:<部位hash>=0|1 可逐部位覆盖
    part           = {},     -- 按资源 + 部位 hash 选取；不依赖不同车型的部位数组顺序
    native_segments = 1,     -- v0.13：RegenerationSegments（回血段数）
    native_force   = true,   -- v0.13：配置页只读时临时改页保护再写（每次都会记日志）
    test           = false,  -- 测试模式：忽略护盾，所有载具都回复
    shield         = { ['ed13ddc480ec6910'] = true }, -- 护盾生成器本体（v0.10 修正：73f8498bffdcf415 是通用空降仓，每个战略配备/增援都会生成）
    weapon         = {},     -- 额外允许补弹的武器实体资源 hash
    ammo_max       = {},     -- ['资源hash:字段'] = 上限，覆盖“观察到的最大值”
}

-- ---------------------------------------------------------------------------
-- 资源 hash（全部来自 HUD / DRIVER HUD，已在游戏中观测）
-- ---------------------------------------------------------------------------
local KIND = {
    ['35dbf54f016f3624'] = 'exo', ['79e4b3d2da5e45e3'] = 'exo',
    ['c2d449ecf7facab1'] = 'exo', ['7b2326f6fd9c8069'] = 'exo',
    -- 机甲手臂（独立的 Health 实体）
    ['65489809a8181b96'] = 'arm', ['df51fe8d62f294be'] = 'arm',
    ['824b7e0c4c879eb5'] = 'arm', ['08f6089289c83d22'] = 'arm',
    ['e5f64dcc3bfe9dd1'] = 'arm', ['ff9878576a4c543b'] = 'arm',
    ['0736bee2d6328726'] = 'arm', ['17c5d12d8d5dee2c'] = 'arm',
    ['cc21c7ffd3ebefb9'] = 'frv', ['9b2140378640432e'] = 'frv',
    ['16474112801385b6'] = 'tank', ['b0c9faf4af8903f9'] = 'tank',
}
local ARM_WEAPON = {  -- 这些实体自身可能带弹匣组件
    ['65489809a8181b96'] = true, ['df51fe8d62f294be'] = true, ['824b7e0c4c879eb5'] = true,
    ['08f6089289c83d22'] = true, ['e5f64dcc3bfe9dd1'] = true, ['ff9878576a4c543b'] = true,
    ['0736bee2d6328726'] = true, ['17c5d12d8d5dee2c'] = true,
    ['8aff7f0793a5bced'] = true, -- 新坦克火箭巢（DRIVER HUD）
}
-- 弹药总量（helldivers.wiki.gg，2026-09 查询）。total = 弹匣/已装填 + 备弹，load = 弹匣容量（已知时）
-- 手臂与载具的对应关系来自 HUD zones.lua / mount_policy.lua；坦克武器 goid 规则来自 DRIVER HUD
local AMMO_SPEC = {
    -- EXO-55 Breakthrough：左臂护盾（无弹药），右臂破片炮 弹匣 6 + 备弹 64 = 70（v0.12g：按用户实测总量 70 含弹匣）
    ['df51fe8d62f294be'] = { total = 70, load = 6, name = 'EXO-55 flak cannon' },
    -- EXO-45 Patriot：左火箭 14，右转管机枪 1350
    ['824b7e0c4c879eb5'] = { total = 14, name = 'EXO-45 rockets' },
    ['08f6089289c83d22'] = { total = 1350, name = 'EXO-45 minigun' },
    -- EXO-49 Emancipator：双机炮各 100
    ['e5f64dcc3bfe9dd1'] = { total = 100, name = 'EXO-49 autocannon L' },
    ['ff9878576a4c543b'] = { total = 100, name = 'EXO-49 autocannon R' },
    -- EXO-51 Lumberer：左喷火 500 燃料，右反坦克炮 25
    ['0736bee2d6328726'] = { total = 500, name = 'EXO-51 flamethrower' },
    ['17c5d12d8d5dee2c'] = { total = 25, name = 'EXO-51 AT cannon' },
    -- TD-220 Bastion：主炮 30 + 1 已装填（DRIVER HUD），同轴重机枪 2000
    -- 两个武器实体的 goid = 车体 goid-2 / -1（DRIVER HUD），资源 hash 为游戏内 SPOT 观测
    -- 游戏内实测字段布局：主炮 mag reserve=30 current=1；机枪 current=2000
    ['1fa1f596769225c2'] = { caps = { reserve = 30, current = 1 }, name = 'Bastion 120mm cannon' },
    ['439f9e65c18567da'] = { caps = { current = 2000 }, name = 'Bastion coax HMG' },
    -- TD-110 Maelstrom：转管机枪 每条弹链 300 × 7 条。游戏内实测 current=300，reserve 是“备用弹链数”（最多 6）
    ['d58ae6a04edb10de'] = { caps = { current = 300, reserve = 6 }, name = 'Maelstrom gatling' },
    -- 两个导弹巢各 10 发（实测 mag current）
    ['8aff7f0793a5bced'] = { caps = { current = 10 }, name = 'Maelstrom missile pod' },
    -- 3a061009aa31e9cb：Maelstrom 上另一个 mag（实测 current=20，推测是烟雾弹），上限未知，只用观察值
    ['3a061009aa31e9cb'] = { name = 'Maelstrom (smoke?)' },
}
-- 坦克武器实体 goid = 车体 goid - n（Bastion 来自 DRIVER HUD；Maelstrom 为游戏内实测），只用来确定归属
local TANK_WEAPON_GOIDS = { ['16474112801385b6'] = { 2, 1 }, ['b0c9faf4af8903f9'] = { 5, 3, 2, 1 } }
local WHEEL = { fed0a478 = true, f3cb00ad = true, c6bf05a9 = true, f12186b7 = true }
local WHEEL_NAME = { fed0a478 = 'front_left', f3cb00ad = 'front_right', c6bf05a9 = 'rear_left', f12186b7 = 'rear_right' }
local HEAL_RATE = { exo = 'exo_heal', arm = 'exo_heal', tank = 'tank_heal', frv = 'frv_heal' }
local AMMO_KIND = { exo = true, arm = true, tank = true }  -- FRV 不补弹

-- 武器组件：root RVA, 表偏移, owner 数组偏移, 数据数组偏移, 步长, {字段名, 偏移}
local WEAPON_COMPONENTS = {
    { name = 'mag', root = 0x3326648, to = 0x20, dp = 0x38, arr = 0x50, stride = 12,
      fields = { { 'reserve', 0 }, { 'current', 4 } } },
    { name = 'rounds', root = 0x3326CF0, to = 0x28, dp = 0x40, arr = 0x58, stride = 20,
      fields = { { 'reserve', 0 }, { 'r0', 8 }, { 'r1', 12 } } },
}

-- ---------------------------------------------------------------------------
-- 日志 / 命令 / 设置
-- ---------------------------------------------------------------------------
local POD = { ['73f8498bffdcf415'] = true }  -- 空降仓：旧设置文件里的 shield=73f8… 一律忽略
local DIR = (os.getenv('LOCALAPPDATA') or ''):gsub('\\', '/') .. '/CowboyBingus/Helldivers2/Logs/'
local LOG, CMD, SET = DIR .. 'ShieldVehicleResupply.log', DIR .. 'shield_resupply_cmd.txt', DIR .. 'shield_resupply_settings.txt'
local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    local f = io.open(LOG, 'a')
    if f then f:write(os.date('%H:%M:%S '), ok and s or fmt, '\n'); f:close() end
end
local REPAIR = RepairNative(N, log)
for res in pairs(REPAIR.arm_types) do KIND[res] = 'arm'; ARM_WEAPON[res] = true end

local stage_seen = {}
local function stage(name)
    if not stage_seen[name] then stage_seen[name] = true; log('stage: %s', name) end
end

-- 资源 hash 索引：RES[低 32 位][高 32 位] = hex 字符串
-- 遍历表时直接用两个 u32 查表，不再给每个实体都 string.format 一次
local RES = {}
local function rebuild_res()
    RES = {}
    for _, set in ipairs({ KIND, ARM_WEAPON, AMMO_SPEC, C.shield, C.weapon }) do
        for h in pairs(set) do
            local hi, lo = tonumber(h:sub(1, 8), 16), tonumber(h:sub(9, 16), 16)
            if hi and lo then RES[lo] = RES[lo] or {}; RES[lo][hi] = h end
        end
    end
end
local function res_of(lo, hi)
    local m = RES[lo]
    return m and m[hi]
end

local function read_settings()
    local f = io.open(SET, 'r')
    if not f then
        f = io.open(SET, 'w')
        if f then
            f:write('# Shield Vehicle Resupply 设置。改完在 shield_resupply_cmd.txt 写 reload\n',
                '# shield=<16位hex> 可写多行；weapon=<hex> 同理；ammo_max=<hex>:<字段>=<数值>\n',
                'radius=14.5\nshield_duration=45\nspot=0\ntest=0\nrevive=0\nnet_heal=1\nhull_zones=1\ntires=1\nwheel_interval=2\npart_repair=1\nexo_leg_fix=1\nexo_weapon_guard=1\nexo_shield_guard=1\nfrv_tire_guard=1\nammo=1\nexo_heal=0.04\ntank_heal=0.03\nfrv_heal=0.05\n',
                'ammo_rate=0.10\ncooldown=2\nauthority_only=1\nheal=native\nnative_zone=0x141\npart_regen=1\nnative_segments=1\nnative_force=1\n',
                '# part=<16位资源hash>:<8位部位hash>=0|1，可写多行；parts 命令列出这些 hash\n')
            f:close()
        end
        return
    end
    C.shield, C.weapon, C.ammo_max, C.part = { ['ed13ddc480ec6910'] = true }, {}, {}, {}
    for line in f:lines() do
        line = line:gsub('^\239\187\191', ''):gsub('#.*', ''):gsub('%s', '')
        local k, v = line:match('^([%w_]+)=(.+)$')
        if k == 'shield' or k == 'weapon' then
            local h = v:lower():gsub('^0x', '')
            if #h == 16 and not h:find('[^%x]') and not (k == 'shield' and POD[h]) then C[k][h] = true end
        elseif k == 'ammo_max' then
            local key, n = v:lower():match('^(%x+:%w+)=(%d+)$')
            if key then C.ammo_max[key] = tonumber(n) end
        elseif k == 'part' then
            local res, zone, enabled = v:lower():match('^(%x+):(%x+)=([01])$')
            if res and #res == 16 and #zone == 8 then C.part[res .. ':' .. zone] = enabled == '1'
            else log('invalid part setting: %s', tostring(v)) end
        elseif k == 'heal' then
            local m = v:lower()
            if m == 'native' or m == 'write' or m == 'off' then C.heal = m end
        elseif k == 'native_zone' then
            local n = tonumber(v) or tonumber((v:gsub('^0[xX]', '')), 16)
            if n and n >= 0 and n + 1 < 0x228 then C.native_zone = math.floor(n) end
        elseif k and type(C[k]) == 'boolean' then C[k] = (v == '1' or v == 'true')
        elseif k and type(C[k]) == 'number' and tonumber(v) then C[k] = tonumber(v) end
    end
    f:close()
    if C.native_zone == 0x13D then
        C.native_zone = 0x141
        log('settings: v0.14 的 native_zone=0x13d 推导有误，已迁移到二进制类型表确认的 +141')
    end
    local n = 0; for _ in pairs(C.shield) do n = n + 1 end
    log('settings: radius=%.1f heal=%s native_zone=%s test=%s revive=%s hull_zones=%s tires=%s ammo=%s shields=%d',
        C.radius, C.heal, C.native_zone > 0 and string.format('+%x', C.native_zone) or 'off', tostring(C.test), tostring(C.revive), tostring(C.hull_zones), tostring(C.tires), tostring(C.ammo), n)
    log('settings: part_repair=%s exo_leg_fix=%s', tostring(C.part_repair), tostring(C.exo_leg_fix))
    log('settings: exo_weapon_guard=%s (non-shield weapons; fail at 1 HP, recover >5%%)',tostring(C.exo_weapon_guard))
    log('settings: exo_shield_guard=%s frv_tire_guard=%s',tostring(C.exo_shield_guard),tostring(C.frv_tire_guard))
end
local function load_settings() read_settings(); rebuild_res() end

-- ---------------------------------------------------------------------------
-- 写内存：只写 PAGE_READWRITE 的已提交页；写前比对旧值，写后读回
-- ---------------------------------------------------------------------------
local W = {}
do
    pcall(ffi.cdef, 'int __stdcall WriteProcessMemory(void *, void *, const void *, size_t, size_t *);')
    pcall(ffi.cdef, 'size_t __stdcall VirtualQuery(const void *, void *, size_t);')
    pcall(ffi.cdef, 'void * __stdcall GetCurrentProcess(void);')
    pcall(ffi.cdef, 'int __stdcall ReadProcessMemory(void *, const void *, void *, size_t, size_t *);')
    local ok, k = pcall(ffi.load, 'kernel32')
    local mbi, got = ffi.new('uint8_t[48]'), ffi.new('size_t[1]')
    W.writes, W.fails = 0, 0
    W.fast = ok  -- 离线测试里关掉
    -- 大块读取（v0.11）：先用 VirtualQuery 确认整段都是已提交、可读、非 guard 页（和 N.win.read 同样的规则），
    -- 再一次 ReadProcessMemory 读完。原来每 4 KB 一次 RPM + 字符串拼接
    local rbuf, rcap = nil, 0
    function W.read_big(p, n)
        if not (W.fast and ok) or type(p) ~= 'number' or p < 65536 or n < 1 or p + n > 140737488355328 then return nil end
        local at, finish = p, p + n
        for _ = 1, 64 do
            if at >= finish then break end
            if tonumber(k.VirtualQuery(ffi.cast('const void *', at), ffi.cast('void *', mbi), 48)) ~= 48 then return nil end
            local b = ffi.string(mbi, 48)
            local start, extent, state, prot = ptr(b, 0), ptr(b, 24), u32(b, 32), u32(b, 36)
            local kind = prot % 256
            if state ~= 0x1000 or math.floor(prot / 256) % 2 == 1
                or not (kind == 2 or kind == 4 or kind == 8 or kind == 32 or kind == 64 or kind == 128)
                or start > at or extent == 0 or start + extent <= at then return nil end
            at = start + extent
        end
        if at < finish then return nil end
        if n > rcap then rcap = math.max(n, 65536); rbuf = ffi.new('uint8_t[?]', rcap) end
        got[0] = 0
        if k.ReadProcessMemory(k.GetCurrentProcess(), ffi.cast('const void *', p), rbuf, n, got) == 0
            or tonumber(got[0]) ~= n then return nil end
        return ffi.string(rbuf, n)
    end
    function W.writable(p)
        if not ok then return false end
        if tonumber(k.VirtualQuery(ffi.cast('const void *', p), ffi.cast('void *', mbi), 48)) ~= 48 then return false end
        local b = ffi.string(mbi, 48)
        local start, size, state, prot = ptr(b, 0), ptr(b, 24), u32(b, 32), u32(b, 36)
        return state == 0x1000 and prot == 4 and start <= p and p + 4 <= start + size
    end
    function W.i32(p, old, new)
        if not ok or new == old then return false end
        local ob = ffi.new('int32_t[1]', old)
        local nb = ffi.new('int32_t[1]', new)
        local before = N.win.read(p, 4)
        if before ~= ffi.string(ob, 4) or not W.writable(p) then W.fails = W.fails + 1; return false end
        stage('first memory write')
        got[0] = 0
        local r = k.WriteProcessMemory(k.GetCurrentProcess(), ffi.cast('void *', p), nb, 4, got)
        local good = r ~= 0 and tonumber(got[0]) == 4 and N.win.read(p, 4) == ffi.string(nb, 4)
        if good then W.writes = W.writes + 1 else W.fails = W.fails + 1 end
        return good
    end
    function W.u32(p, old, new)  -- 用于伤害状态字
        local function s(v) return v >= 2147483648 and v - 4294967296 or v end
        return W.i32(p, s(old), s(new))
    end
    -- float 字段（v0.12 影子字段）：旧值按原始 4 字节比对，所以不受浮点误差影响
    function W.f32(p, oldraw, new)
        if not ok then return false end
        local nb = ffi.new('float[1]', new)
        local ns = ffi.string(nb, 4)
        if ns == oldraw then return false end
        if N.win.read(p, 4) ~= oldraw or not W.writable(p) then W.fails = W.fails + 1; return false end
        got[0] = 0
        local r = k.WriteProcessMemory(k.GetCurrentProcess(), ffi.cast('void *', p), nb, 4, got)
        local good = r ~= 0 and tonumber(got[0]) == 4 and N.win.read(p, 4) == ns
        if good then W.writes = W.writes + 1 else W.fails = W.fails + 1 end
        return good
    end
    -- v0.13：写配置用的原始字节写（写前比对、写后读回）。
    -- 配置页可能是 PAGE_READONLY（引擎的静态数据），native_force 打开时临时改成可写再写回来，
    -- 每次走这条路都会记日志（W.forced 计数）。
    pcall(ffi.cdef, 'int __stdcall VirtualProtect(void *, size_t, unsigned long, unsigned long *);')
    function W.prot(p)
        if not ok then return nil end
        if tonumber(k.VirtualQuery(ffi.cast('const void *', p), ffi.cast('void *', mbi), 48)) ~= 48 then return nil end
        return u32(ffi.string(mbi, 48), 36)
    end
    function W.raw(p, n, oldraw, newraw)
        if not ok or not (n == 1 or n == 4) then return false end
        if N.win.read(p, n) ~= oldraw then W.fails = W.fails + 1; return false end
        local prot = ffi.new('unsigned long[1]')
        local forced = false
        if not W.writable(p) then
            if not (C.native_force) then W.fails = W.fails + 1; return false end
            if ffi.C.VirtualProtect(ffi.cast('void *', p), n, 4, prot) == 0 then W.fails = W.fails + 1; return false end
            forced = true
            W.forced = (W.forced or 0) + 1
        end
        local buf = ffi.new('uint8_t[?]', n)
        ffi.copy(buf, newraw, n)
        got[0] = 0
        local r = k.WriteProcessMemory(k.GetCurrentProcess(), ffi.cast('void *', p), buf, n, got)
        local good = r ~= 0 and tonumber(got[0]) == n and N.win.read(p, n) == newraw
        if forced then
            local back = ffi.new('unsigned long[1]')
            ffi.C.VirtualProtect(ffi.cast('void *', p), n, prot[0], back)
        end
        if good then W.writes = W.writes + 1 else W.fails = W.fails + 1 end
        return good
    end
    function W.raw4(p, oldraw, newraw) return W.raw(p, 4, oldraw, newraw) end
    function W.raw1(p, oldraw, newraw) return W.raw(p, 1, oldraw, newraw) end
    -- 保留：一次性整段读取（healcfg 导出配置记录用）
    function W.rpm(p, buf, n)
        if not ok then return false end
        got[0] = 0
        return k.ReadProcessMemory(k.GetCurrentProcess(), ffi.cast('const void *', p), buf, n, got) ~= 0 and tonumber(got[0]) == n
    end
end

local TEST_HOOK = rawget(_G, '__SVR_TEST')  -- 仅离线测试用
local FAULT = WeaponFault(N, W, REPAIR, C, log, WEAPON_COMPONENTS)
local TYRE = TyreFault(N,W,REPAIR,C,log)

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------
local S = {
    clock = 0, acc = 0, next_roster = 0, ctx = nil,
    vehicles = {},   -- {d=descriptor, kind=}
    weapons = {},    -- {d=descriptor, comp=, owner=vehicle entry}
    shields = {},    -- 护盾的网络描述符
    shield_born = {}, shield_expired = {}, vstate = {},
    prev_counts = nil, seen_ent = nil, spotted = {},
    last_total = {}, last_hit = {}, frac = {}, ammo_max = {}, reported = {},
}
REPAIR.vehicle_roster = function() return S.vehicles end
local function reset_context()
    S.vehicles, S.weapons, S.shields, S.seen_ent, S.spotted = {}, {}, {}, nil, {}
    S.last_total, S.last_hit, S.frac, S.ammo_max, S.reported, S.next_roster = {}, {}, {}, {}, {}, 0
    S.shield_born, S.shield_expired, S.vstate, S.want_units = {}, {}, {}, nil
    S.hptrace = nil
    S.wheel_trace, S.next_wheel_learn = nil, 0
    S.mech_trace = nil
    FAULT.reset()
    TYRE.reset()
    S.next_fault=0
    REPAIR.reset()
end


local function call(f, ...)
    if type(f) ~= 'function' then return nil end
    local ok, a, b, c = pcall(f, ...)
    if ok then return a, b, c end
end

-- 坦克车体的网络同步血量（DRIVER HUD 的读法：exists 校验后 game_object_field_batched，#15=上限 8000，#30=当前）
-- 只在 vehicles 命令里读一次，用来对照 Health 组件和 HUD 显示的是不是同一个数
local function net_hull(d)
    local GS = sr.GameSession
    if not (S.ctx and GS and type(GS.game_object_field_batched) == 'function') then return nil end
    if not (d.goid > 0 and d.goid < 32767) or call(GS.game_object_exists, S.ctx.session, d.goid) ~= true then return nil end
    local ok, f = pcall(GS.game_object_field_batched, S.ctx.session, d.goid, {})
    if not ok or type(f) ~= 'table' or type(f[15]) ~= 'number' or type(f[30]) ~= 'number' then return nil end
    return f[30], f[15]
end

-- HUD 上显示的车体血量（网络对象字段，只读）：坦克 = batched #30/#15，FRV = 'sd7m7FWA'/'nZ5Vxt8x'（DRIVER HUD 的读法）
local function net_body(v)
    local d, GS = v.d, sr.GameSession
    if v.kind == 'tank' then return net_hull(d) end
    if v.kind ~= 'frv' or not (S.ctx and GS) then return nil end
    if not (d.goid > 0 and d.goid < 32767) or call(GS.game_object_exists, S.ctx.session, d.goid) ~= true then return nil end
    local hp, mx = call(GS.game_object_field, S.ctx.session, d.goid, 'sd7m7FWA'), call(GS.game_object_field, S.ctx.session, d.goid, 'nZ5Vxt8x')
    if type(hp) ~= 'number' or type(mx) ~= 'number' then return nil end
    return hp, mx
end

-- 车体网络血量字段：FRV 'sd7m7FWA'（DRIVER HUD）。坦克先读同名字段，只有和 batched #30 一致才认
local HP_FIELD = 'sd7m7FWA'
local function net_hp_field_ok(v)
    if v.kind == 'frv' then return true end
    if v.hp_field_ok ~= nil then return v.hp_field_ok end
    local GS = sr.GameSession
    local a = net_hull(v.d)
    local ok, b = pcall(GS.game_object_field, S.ctx.session, v.d.goid, HP_FIELD)
    v.hp_field_ok = ok and type(a) == 'number' and type(b) == 'number' and math.abs(a - b) < 0.5
    log('net field check %s ent=%d batched30=%s %s=%s -> %s', v.kind, v.d.entity, tostring(a), HP_FIELD, tostring(ok and b or 'ERR'), tostring(v.hp_field_ok))
    return v.hp_field_ok
end

local function amount(key, max, rate, dt)
    local f = (S.frac[key] or 0) + max * rate * dt
    local whole = math.floor(f)
    S.frac[key] = f - whole
    return whole
end

local function net_heal(v, dt)
    local GS = sr.GameSession
    if not (C.net_heal and S.ctx and type(GS.set_game_object_field) == 'function') then return 0 end
    if call(GS.game_object_owned, S.ctx.session, v.d.goid) ~= true then return 'not_owner' end
    if not net_hp_field_ok(v) then return 'no_field' end
    local hp, mx
    if v.kind == 'tank' and v.net_max then
        hp, mx = call(GS.game_object_field, S.ctx.session, v.d.goid, HP_FIELD), v.net_max
    else
        hp, mx = net_body(v)
        if v.kind == 'tank' and type(mx) == 'number' and mx > 0 then v.net_max = mx end
    end
    if type(hp) ~= 'number' or type(mx) ~= 'number' or mx <= 0 or mx > 100000 or hp <= 0 or hp >= mx then return 0 end
    local key = v.d.entity .. ':' .. v.d.goid .. ':net'
    if v.last_net_hp and hp < v.last_net_hp then S.last_hit[key] = S.clock end
    if C.cooldown > 0 and S.last_hit[key] and S.clock - S.last_hit[key] < C.cooldown then v.last_net_hp = hp; return 'cooldown' end
    local n = amount(key, mx, C[HEAL_RATE[v.kind]], dt)
    if n <= 0 then v.last_net_hp = hp; return 0 end
    local new = math.min(mx, math.floor(hp) + n)
    local ok = pcall(GS.set_game_object_field, S.ctx.session, v.d.goid, HP_FIELD, new)
    v.last_net_hp = ok and new or hp
    return ok and 1 or 'set_error'
end

-- ---------------------------------------------------------------------------
-- 组件表遍历（仿 HUD arms.discover，一次性批量读）
-- ---------------------------------------------------------------------------
local function bulk(p, n)
    local big = W.read_big(p, n)
    if big then return big end
    local parts, off = {}, 0
    while off < n do
        local k = math.min(4096, n - off)
        local b = N.win.read(p + off, k)
        if type(b) ~= 'string' or #b ~= k then error('incomplete native read', 0) end
        parts[#parts + 1] = b; off = off + k
    end
    return table.concat(parts)
end

local ammo_caps  -- 定义在补弹部分

-- 字符串当 u32 数组读（使用期间字符串必须仍被局部变量引用）
local function u32s(str) return ffi.cast('const uint32_t *', str) end

-- 扫描 实体 -> 下标 哈希表，返回平行数组（不给每个条目建小表）
local function scan_index(t, bound, what)
    local raw = bulk(t.entries, t.capacity * 8)
    local a, empty = u32s(raw), t.empty
    local es, js, n, maxj = {}, {}, 0, -1
    for i = 0, t.capacity * 2 - 2, 2 do
        local e, j = a[i], a[i + 1]
        if e ~= empty and j ~= 4294967295 then
            if j >= bound then error(what, 0) end
            n = n + 1; es[n] = e; js[n] = j
            if j > maxj then maxj = j end
        end
    end
    return es, js, n, maxj, raw
end

-- 本帧读到的网络描述符数组。组件表里的 owner 指针通常就指向这里，同一帧内直接复用，
-- 不用再逐个 ReadProcessMemory 24 字节
local NETDESC = { raw = nil, base = 0, len = 0, frame = -1 }
S.desc_hit, S.desc_miss = 0, 0
local function desc_at(p)
    local nd = NETDESC
    if nd.raw and nd.frame == S.frame and p >= nd.base and p + 24 <= nd.base + nd.len and (p - nd.base) % 24 == 0 then
        S.desc_hit = S.desc_hit + 1
        local raw = nd.raw
        local a, o = u32s(raw), (p - nd.base) / 4
        return a[o], a[o + 1], a[o + 2], a[o + 3], a[o + 4], a[o + 5]
    end
    S.desc_miss = S.desc_miss + 1
    local b = N.win.read(p, 24)
    if type(b) ~= 'string' or #b ~= 24 then return nil end
    local a = u32s(b)
    return a[0], a[1], a[2], a[3], a[4], a[5]
end

-- 返回 manager 下所有 owner descriptor（filter(已知资源 hex 或 nil, entity, unit) 为真才保留）
local function enumerate(manager, to, dp, filter)
    local g = N.graph(N.win.read, N.base)
    local t = g:table(manager + to)
    if t.capacity == 0 then return {} end
    if t.capacity > 65536 then error('component table too large', 0) end
    local es, js, n, maxj = scan_index(t, 262144, 'dense index bound')
    if maxj < 0 then return {} end
    local descs = ptr(g:watch(manager + dp, 8), 0)
    local ptrs = bulk(descs, (maxj + 1) * 8)
    local pa = u32s(ptrs)
    local out = {}
    for i = 1, n do
        local j = js[i]
        local lo, hi = pa[j * 2], pa[j * 2 + 1]
        if hi >= 32768 then error('noncanonical pointer', 0) end
        local p = hi * 4294967296 + lo
        if p ~= 0 then
            local rlo, rhi, e, unit, goid, flags = desc_at(p)
            if rlo and e == es[i] then
                local res = res_of(rlo, rhi)
                if filter(res, e, unit) then
                    out[#out + 1] = { address = p, resource = res or string.format('%08x%08x', rhi, rlo),
                        entity = e, unit = unit, goid = goid, flags = flags, j = j }
                end
            end
        end
    end
    return out
end

-- 弹药上限“观察”：roster 时把整段组件数据一次读进来（原来是每个武器单独走一遍 refill：
-- roundtrip + component + validate，十几次 RPM）。只更新观察到的最大值，不写内存
local function observe_ammo(manager, comp, weapons, first)
    local lo, hi
    for i = first, #weapons do
        local w = weapons[i]
        if ((w.owner and AMMO_KIND[w.owner.kind]) or not w.owner) and not (C.authority_only and w.d.flags % 2 ~= 1) then
            local j = w.d.j
            if not lo or j < lo then lo = j end
            if not hi or j > hi then hi = j end
        end
    end
    if not lo then return end
    local n = (hi - lo + 1) * comp.stride
    if n > 262144 then error('weapon rows too spread', 0) end
    local arr = ptr(N.win.read(manager + comp.arr, 8) or error('incomplete native read', 0), 0)
    local rows = bulk(arr + lo * comp.stride, n)
    for i = first, #weapons do
        local w = weapons[i]
        if ((w.owner and AMMO_KIND[w.owner.kind]) or not w.owner) and not (C.authority_only and w.d.flags % 2 ~= 1) then
            local o = (w.d.j - lo) * comp.stride
            ammo_caps(w, rows:sub(o + 1, o + comp.stride))
        end
    end
end

local function rebuild_roster()
    N.win.begin_sample()
    local hm = ptr(N.win.read(N.base + N.roots.health, 8) or ('\0'):rep(8), 0)
    if hm == 0 then S.vehicles, S.weapons = {}, {}; return end
    local list = enumerate(hm, 0x1030, 0x1048, function(res) return res ~= nil and KIND[res] ~= nil end)
    local vehicles, by_unit, by_entity = {}, {}, {}
    for _, d in ipairs(list) do
        local sk = d.entity .. ':' .. d.goid .. ':' .. d.unit .. ':' .. d.resource
        local v = S.vstate[sk] or { kind = KIND[d.resource] }
        S.vstate[sk] = v; v.d = d; v.alive_at = S.clock
        vehicles[#vehicles + 1] = v
        if d.unit ~= 0 and d.unit ~= 4294967295 then by_unit[d.unit] = by_unit[d.unit] or v end
        by_entity[d.entity] = v
    end
    S.vehicles = vehicles
    for k, v in pairs(S.vstate) do
        if v.alive_at ~= S.clock then
            if v.kind == 'arm' then log('mech arm removed %s ent=%d goid=%d: Health owner disappeared; no respawn path', v.d.resource, v.d.entity, v.d.goid) end
            S.vstate[k] = nil
        end
    end
    -- A destroyed arm may no longer have an alive Unit, so range/position lookup
    -- would skip heal() and its trace. Record this read-only evidence during roster.
    local rows_raw = N.win.read(hm + 0x1058, 8)
    local rows = rows_raw and ptr(rows_raw, 0)
    if rows and rows >= 65536 then
        for _, v in ipairs(vehicles) do
            if v.kind == 'arm' then
                local b = N.win.read(rows + v.d.j * 0x1B8, 0x1B8)
                if b then
                    local hp, life = i32(b, 0x14), u32(b, 0x19C)
                    if hp <= 0 or life ~= 0 then
                        local report = 'arm-health:' .. v.d.entity .. ':' .. v.d.goid .. ':' .. tostring(life)
                        if not S.reported[report] then
                            S.reported[report] = true
                            log('mech arm unavailable %s ent=%d goid=%d hp=%d life=%08x: %s', v.d.resource, v.d.entity, v.d.goid, hp, life,
                                life ~= 0 and 'engine-dead; no respawn path' or 'zero HP; game repair requires a live native parent')
                        end
                    end
                end
            end
        end
    end
    local by_goid = {}
    for _, v in ipairs(vehicles) do
        local offs = v.kind == 'tank' and TANK_WEAPON_GOIDS[v.d.resource]
        if offs then for _, o in ipairs(offs) do if v.d.goid - o > 0 then by_goid[v.d.goid - o] = v end end end
    end
    local weapons = {}
    if C.ammo and N.weapon_ready then
        for _, comp in ipairs(WEAPON_COMPONENTS) do
            local m = ptr(N.win.read(N.base + comp.root, 8) or ('\0'):rep(8), 0)
            if m ~= 0 then
                local ok, ws = pcall(enumerate, m, comp.to, comp.dp, function(res, e, unit)
                    return by_entity[e] or by_unit[unit] or (res and (ARM_WEAPON[res] or C.weapon[res] or AMMO_SPEC[res]))
                end)
                if ok then
                    local first = #weapons + 1
                    for _, d in ipairs(ws) do
                        local owner = by_entity[d.entity] or by_unit[d.unit] or (not KIND[d.resource] and by_goid[d.goid])
                        local spec = AMMO_SPEC[d.resource]
                        weapons[#weapons + 1] = { d = d, comp = comp, owner = owner, spec = spec }
                    end
                    local okb, eb = pcall(observe_ammo, m, comp, weapons, first)
                    if not okb then log('ammo observe %s: %s', comp.name, tostring(eb)) end
                else log('weapon roster %s: %s', comp.name, tostring(ws)) end
            end
        end
    end
    S.weapons = weapons
end

-- ---------------------------------------------------------------------------
-- 网络实体表遍历（纯内存读取，零引擎调用）：用于找护盾和 units 差异统计
-- 表：net+0xF1AEB0 (entity -> 下标)，描述符：net+0xF32F18 + 下标*24（HUD native.lua）
-- ---------------------------------------------------------------------------
-- all=false 时只返回已知资源（护盾/载具/武器），不给其它几千个实体建表、格式化 hash
local function net_descriptors(all)
    N.win.begin_sample()
    NETDESC.raw = nil
    local g = N.graph(N.win.read, N.base)
    local net = g:root('network')
    local t = g:table(net + 0xF1AEB0)
    if t.capacity == 0 then return {} end
    if t.capacity > 262144 then error('network table too large', 0) end
    local es, js, n, maxj = scan_index(t, 262144, 'network dense index bound')
    if maxj < 0 then return {} end
    local base = net + 0xF32F18
    local descs = bulk(base, (maxj + 1) * 24)
    NETDESC.raw, NETDESC.base, NETDESC.len, NETDESC.frame = descs, base, (maxj + 1) * 24, S.frame
    local a = u32s(descs)
    local out = {}
    for i = 1, n do
        local o = js[i] * 6
        if a[o + 2] == es[i] then
            local lo, hi = a[o], a[o + 1]
            local res = res_of(lo, hi)
            if res == nil and all then res = string.format('%08x%08x', hi, lo) end
            if res then
                out[#out + 1] = { address = base + o * 4, resource = res, entity = es[i],
                    unit = a[o + 3], goid = a[o + 4], flags = a[o + 5] }
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- 坐标：只对已确认的网络对象取坐标，调用顺序与 HUD spatial_runtime 完全相同
--   game_object_exists -> game_object_id_to_unit -> unit_to_game_object_id 回查 -> alive -> world_position
-- 不遍历 World.units，不对任意/可能已销毁的 unit 调引擎函数
-- ---------------------------------------------------------------------------
local function fmtpos(p) return p and string.format('(%.1f,%.1f,%.1f)', p[1], p[2], p[3]) or '(no pos)' end
local pos_why = {}
local function pos_fail(why)
    if not pos_why[why] then pos_why[why] = true; log('position: %s', why) end
    return nil
end

-- tagged UnitReference 索引（照搬 HUD unit_ref_bridge：只做 ffi 标量转换，不对 unit 调引擎函数）
-- 每次重建都在同一帧内完成，Unit 句柄不跨帧保存
local REF = { map = nil, frame = -1 }
local function ref_index()
    if REF.frame == S.frame and REF.map then return REF.map end
    REF.frame, REF.map = S.frame, nil
    local f = sr.World and sr.World.units
    if type(f) ~= 'function' then return pos_fail('World.units missing') end
    local units = call(f, S.ctx.world)
    if type(units) ~= 'table' then return pos_fail('World.units not a table') end
    local map, n = {}, 0
    local cast, want = ffi.cast, S.want_units
    for i = 1, math.min(#units, 32768) do
        local u = units[i]
        local ok, c = pcall(cast, 'uintptr_t', u)
        if ok then
            local raw = tonumber(c)
            if raw and raw % 4 == 1 and raw < 17179869184 then
                local ref = (raw - 1) / 4
                -- 只保留这一轮要查的 unit（护盾 + 载具），不给整张表建索引
                if not want or want[ref] then
                    map[ref] = u; n = n + 1
                    if want and n >= S.want_n then break end  -- 要找的都找到了
                end
            end
        end
    end
    if n == 0 and not want then return pos_fail('no tagged unit references (' .. #units .. ' units)') end
    REF.map = map
    return map
end

local function read_pos(u, root_name)
    local U, V = sr.Unit, sr.Vector3
    if call(U.alive, u) ~= true then return pos_fail('unit not alive') end
    if type(U.world) == 'function' and call(U.world, u) ~= S.ctx.world then return pos_fail('unit in other world') end
    local node = 1
    if root_name and type(U.has_node) == 'function' and call(U.has_node, u, 'StingrayEntityRoot') == true then
        local i = call(U.node, u, 'StingrayEntityRoot')
        if type(i) == 'number' and i % 1 == 0 and i >= 0 and i < 65536 then node = i end
    end
    local p = call(U.world_position, u, node)
    if p == nil then return pos_fail('world_position nil') end
    local x, y, z = call(V.to_elements, p)
    for _, v in ipairs({ x, y, z }) do
        if type(v) ~= 'number' or v ~= v or math.abs(v) > 1000000 then return pos_fail('bad Vector3') end
    end
    return { x, y, z }
end

local function position_of(d)
    if not S.ctx or not d then return nil end
    local GS, US, U, V = sr.GameSession, sr.UnitSynchronizer, sr.Unit, sr.Vector3
    if not (U and V) or type(U.alive) ~= 'function' or type(U.world_position) ~= 'function' or type(V.to_elements) ~= 'function' then
        return pos_fail('Unit/Vector3 API missing')
    end
    stage('first position lookup')
    -- 路径 1：UnitSynchronizer（HUD 首选）
    if GS and US and type(GS.unit_synchronizer) == 'function' and type(US.game_object_id_to_unit) == 'function'
        and d.goid > 0 and d.goid < 32767 then
        local sync = call(GS.unit_synchronizer, S.ctx.session)
        if sync ~= nil then
            if call(GS.game_object_exists, S.ctx.session, d.goid) == true then
                local u = call(US.game_object_id_to_unit, sync, d.goid)
                if u ~= nil and call(US.unit_to_game_object_id, sync, u) == d.goid then
                    stage('position via UnitSynchronizer')
                    return read_pos(u, false)
                end
            end
        else pos_fail('unit_synchronizer returned nil, using tagged references') end
    end
    -- 路径 2：tagged UnitReference（HUD 在 synchronizer 为 nil 时的做法）
    if not d.unit or d.unit == 0 or d.unit >= 4294967295 then return nil end
    local map = ref_index()
    local u = map and map[d.unit]
    if u == nil then return nil end
    stage('position via tagged reference')
    return read_pos(u, true)
end

-- 最近生成的网络实体（entity id 最大的 N 个）
local function cmd_recent(n)
    local ok, list = pcall(net_descriptors, true)
    if not ok then log('recent: %s', tostring(list)); return end
    table.sort(list, function(a, b) return a.entity > b.entity end)
    log('---- recent %d network entities (newest first) ----', n)
    for i = 1, math.min(n, #list) do
        local d = list[i]
        log('  ent=%d goid=%d unit=%d %s %s%s', d.entity, d.goid, d.unit, d.resource, fmtpos(position_of(d)), KIND[d.resource] and (' [' .. KIND[d.resource] .. ']') or '')
    end
end

-- 自动侦测：载具 30 米内新出现的网络实体（每种资源只记一次）-> 日志 SPOT 行
local function spot_new(list)
    local fresh = {}
    local now = {}
    for _, d in ipairs(list) do now[d.entity] = d.resource end
    if S.seen_ent then
        for _, d in ipairs(list) do
            if S.seen_ent[d.entity] ~= d.resource and not KIND[d.resource] and not S.spotted[d.resource] then
                fresh[#fresh + 1] = d
            end
        end
    end
    S.seen_ent = now
    if #fresh == 0 or #fresh > 64 then return end
    local vpos = {}
    for _, v in ipairs(S.vehicles) do
        if v.kind ~= 'arm' then local p = position_of(v.d); if p then vpos[#vpos + 1] = { v, p } end end
    end
    if #vpos == 0 then return end
    for _, d in ipairs(fresh) do
        local p = position_of(d)
        if p then
            local best, bv = math.huge, nil
            for _, vp in ipairs(vpos) do
                local dx, dy, dz = p[1] - vp[2][1], p[2] - vp[2][2], p[3] - vp[2][3]
                local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                if dist < best then best, bv = dist, vp[1] end
            end
            if best <= 30 then
                S.spotted[d.resource] = true
                log('SPOT %s ent=%d goid=%d %.1fm from %s%s', d.resource, d.entity, d.goid, best, bv.kind,
                    C.shield[d.resource] and ' [shield]' or '')
            end
        end
    end
end

local function in_shield(pos, centers)
    if C.test then return true end
    if not pos then return false end
    local r2 = C.radius * C.radius
    for _, c in ipairs(centers) do
        -- 水平距离（z 轴朝上）；罩子是穹顶，机甲手臂比机身高 3 米，不算垂直方向
        local dx, dy, dz = pos[1] - c[1], pos[2] - c[2], pos[3] - c[3]
        if dx * dx + dy * dy <= r2 and math.abs(dz) <= C.radius then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- 回血
-- ---------------------------------------------------------------------------
local function config_address(g, net, hm, d)
    local j = g:lookup(g:table(hm + 0x1070), d.entity)
    if j ~= nil then return ptr(g:watch(hm + 0x10B0, 8), 0) + j * 0x5650 end
    local t = ptr(g:watch(net + 0xF12B78, 8), 0); local start = N.mod64hex(d.resource, 1002)
    for step = 0, 63 do
        local row = g:watch(t + ((start + step) % 1002) * 16, 16); local key = hex64(row, 0)
        if key == d.resource then
            local k = u32(row, 8); if k >= 1002 then error('Health settings index', 0) end
            return t + 0x3EA0 + k * 0x5650
        elseif key == '0000000000000000' then break end
    end
    error('no Health configuration', 0)
end
FAULT.config_address = config_address
TYRE.config_address = config_address


-- ---------------------------------------------------------------------------
-- v0.13：游戏自带的回血（替换 v0.12 的“扫内存找血量拷贝”）
--
-- 字段布局来自 filediver 的 datalibrary（HealthComponent，明文数据）：
--   +0x00 Health                    int32   最大血量（v0.12 已在游戏内确认）
--   +0x04 HeathChangerate           float32 未受伤时每秒恢复多少血量（游戏里的拼写少一个 l）
--   +0x08 HealthChangerateDisabled  uint8   1 = 关闭回血。这就是游戏自带的“回血开关”
--   +0x0C HeathChangerateCooldown   float32 受伤后等几秒开始回血
--   +0x10 RegenerationSegments      uint32  回血段数
--   +0x14 RegenerationChangerate    float32 回血阶段每秒恢复多少血量
--   +0x208 DamageableZones[38]，步长 0x228：部位名 +0x60、部位上限 +0xE8（v0.12 已在游戏内确认）
-- 部位自己的开关是 DamageableZoneInfo.RegenerationEnabled（datalibrary 注释：护盾/部位在血量的回复冷却结束后回血）。
--
-- 为什么这样比逐帧写血量好：游戏扣血时用的是它自己另存的一份血量，mod 只改 Health 记录里的血量，
-- 下一次受伤就会被盖回去（v0.12h 就是为此去全内存扫描，扫的时候会卡）。把游戏自己的回血打开，
-- 两份血量由游戏一起更新，不用扫内存。v0.12 的扫描/影子字段代码在 v0.13 全部删除。
--
-- 代价：配置表按“单位资源”共享，打开期间同种单位（包括不在罩子里的）都会回血，所以只在
-- 本机有权威的载具停在罩子里时打开，载具离开罩子 / 护盾结束 / 关掉 mod 时写回原值。
-- ---------------------------------------------------------------------------
local CFG = {
    health = 0x00, rate = 0x04, disabled = 0x08, cooldown = 0x0C,
    segments = 0x10, regen_rate = 0x14,
    zones = 0x208, zone_stride = 0x228, zone_name = 0x60, zone_health = 0xE8, zone_info = 0x1C8,
    zone_regen = 0x141, zone_heal_event = 0xAC, zone_disable_actors = 0x14C,
    zone_dead_animation = 0x68,
}
local CFG_ON = {}   -- [配置地址] = { orig/wrote = 4 字节原值/我们写的值, users = 本轮罩子里的载具数 }

local function f32_at(s, o) return ffi.cast('const float *', s)[o / 4] end
local function raw_f32(x) return ffi.string(ffi.new('float[1]', x), 4) end
local function raw_u32(x) return ffi.string(ffi.new('uint32_t[1]', x), 4) end
local function finite_pos(x) return type(x) == 'number' and x == x and x >= 0 and x < 1e7 end
local function cfg_read(cfg, off)
    local b = N.win.read(cfg + off, 4)
    if type(b) == 'string' and #b == 4 then return b end
    return nil
end

-- 读配置头并检查它是不是真的 HealthComponent：不像就一个字节都不写（偏移猜错时保护游戏）
local function cfg_header(cfg)
    local b = N.win.read(cfg, 0x20)
    if type(b) ~= 'string' or #b ~= 0x20 then return nil, 'unreadable' end
    local h = { max = i32(b, 0), rate = f32_at(b, 4), disabled = b:byte(9), cooldown = f32_at(b, 0x0C),
                segments = u32(b, 0x10), regen_rate = f32_at(b, 0x14) }
    if not (h.max > 0 and h.max <= 10000000) then return nil, 'max=' .. tostring(h.max) end
    if h.disabled > 1 then return nil, 'disabled=' .. tostring(h.disabled) end
    if not finite_pos(h.rate) then return nil, 'rate=' .. tostring(h.rate) end
    if not finite_pos(h.cooldown) or h.cooldown > 3600 then return nil, 'cooldown=' .. tostring(h.cooldown) end
    if h.segments > 1024 then return nil, 'segments=' .. tostring(h.segments) end
    if not finite_pos(h.regen_rate) then return nil, 'regen=' .. tostring(h.regen_rate) end
    return h
end

-- 写一个 4 字节字段（写前比对、写后读回）；原始值只在第一次打开时记
local function cfg_put(e, off, new)
    local cur = cfg_read(e.cfg, off)
    if not cur then return false end
    if e.orig[off] == nil then e.orig[off] = cur end
    if cur ~= new then
        if W.raw4(e.cfg + off, cur, new) then
            e.wrote[off] = new; e.changed = true
        else
            if not e.wfail then
                e.wfail = true
                log('native 写失败 %s %s cfg=%x +%x（页保护 %s）：设置 native_force=1 可以临时改页保护再写',
                    e.kind, e.res, e.cfg, off, tostring(W.prot(e.cfg)))
            end
            return false
        end
    end
    return true
end

local function part_enabled(res, hash)
    local value = C.part[res .. ':' .. hash]
    if value ~= nil then return value end
    return C.part_regen
end

-- 以 dl_library.dl_typelib.gz 的 64 位成员偏移为准。Go 的手写结构漏了字段，
-- v0.14 据此误推 +13D（实际在 ChildZones 内）；+158 是枚举，不是 bool。
-- 来源：https://github.com/xypwn/filediver/blob/master/datalibrary/dl_library.dl_typelib.gz
-- 0/1 字节本身不能证明布局；同时核对已确认的名字/上限、邻近字段与子部位引用。
local function zone_layout(cfg, z, zc, off)
    if off ~= CFG.zone_regen then return nil, 'unsupported offset (expected +141)' end
    local base = cfg + CFG.zones + z.i * CFG.zone_stride
    local b = N.win.read(base + CFG.zone_name, CFG.zone_info - CFG.zone_name)
    if type(b) ~= 'string' or #b ~= CFG.zone_info - CFG.zone_name then return nil, 'unreadable' end
    local function at(o) return o - CFG.zone_name end
    if string.format('%08x', u32(b, 0)) ~= z.hash then return nil, 'zone name changed' end
    local max = i32(b, at(CFG.zone_health))
    if max == -1 then max = zc.mx end
    if max ~= z.max then return nil, 'zone max changed' end
    local constitution = i32(b, at(0xEC))
    if constitution < 0 or constitution > 10000000 then return nil, 'constitution' end
    for _, o in ipairs({0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0x140, 0x141, 0x142, 0x143, 0x14C, 0x14D, 0x14E, 0x154, 0x15C}) do
        if b:byte(at(o) + 1) > 1 then return nil, string.format('bool +%x', o) end
    end
    local affects = f32_at(b, at(0xF8))
    if not finite_pos(affects) or affects > 1 then return nil, 'main health multiplier' end
    local names = {}
    for _, child in ipairs(zc.zones) do names[tonumber(child.hash, 16)] = true end
    for o = 0x100, 0x13C, 4 do
        local child = u32(b, at(o))
        if child ~= 0 and not names[child] then return nil, 'unknown child zone' end
    end
    -- FRV body zones use FLT_MAX at +144 as a valid sentinel; HP-rate limits do not apply here.
    local f1, f2 = f32_at(b, at(0x144)), f32_at(b, at(0x148))
    if f1 ~= f1 or f1 < 0 or f1 == math.huge or f2 ~= f2 or f2 < 0 or f2 == math.huge
        or u32(b, at(0x150)) > 4096 or u32(b, at(0x158)) > 4096 then return nil, 'zone tail layout' end
    return b:sub(at(off) + 1, at(off) + 1)
end

-- 每个配置只打开一次。记录实际写入地址，reload 改偏移也不会恢复到错误地址。
local function native_zone_open(e, zc)
    if e.zone_tried then return e.native_zones end
    e.zone_tried, e.native_zones = true, {}
    local on, blocked = 0, 0
    for _, z in ipairs(zc.zones) do
        local cur, why = zone_layout(e.cfg, z, zc, e.zone_offset)
        local enabled = part_enabled(e.res, z.hash)
        if cur and z.max > 0 then
            local p = e.cfg + CFG.zones + z.i * CFG.zone_stride + e.zone_offset
            local new = enabled and '\1' or '\0'
            local patch = e.zone_patches[z.i]
            if not patch then
                patch = { p = p, orig = cur, hash = z.hash }
                e.zone_patches[z.i] = patch
            end
            if cur == new or W.raw1(p, cur, new) then
                if cur ~= new then patch.wrote = new end
                if enabled then e.native_zones[z.i] = true; on = on + 1 end
            else
                e.zone_tried = false -- 写失败的部位下个 tick 重试；已成功部位保留原值
                blocked = blocked + 1
            end
        elseif not cur then
            blocked = blocked + 1
            local key = 'nz' .. e.res .. z.hash .. tostring(why)
            if not S.reported[key] then
                S.reported[key] = true
                log('native zone skip %s zone=%s: %s', e.res, z.hash, tostring(why))
            end
        end
    end
    if not e.zone_logged then
        e.zone_logged = true
        log('native zone %s %s offset=+%x: on=%d/%d blocked=%d（交给游戏再生；模型恢复待实测）',
            e.kind, e.res, e.zone_offset, on, #zc.zones, blocked)
    end
    return e.native_zones
end

-- 打开游戏自带回血：rate 是“每秒恢复多少点血量”
local native_close
local function native_apply(v, cfg, mx, rate, zc)
    local e = CFG_ON[cfg]
    if e and e.closing then
        native_close(cfg, 'retry before open')
        e = CFG_ON[cfg]
        if e then e.users = e.users + 1; return false end
    end
    if not e then
        local h, why = cfg_header(cfg)
        if not h then
            local k = 'nc' .. v.d.resource
            if not S.reported[k] then
                S.reported[k] = true
                log('native: %s %s 的配置头不像 HealthComponent（%s），这次不改配置；发 healcfg 看原始字节', v.kind, v.d.resource, tostring(why))
            end
            return false
        end
        e = { cfg = cfg, res = v.d.resource, kind = v.kind, max = h.max, orig = {}, wrote = {},
              zone_offset = C.native_zone, zone_patches = {}, users = 0 }
        CFG_ON[cfg] = e
        log('native open %s %s cfg=%x max=%d 现状: rate=%s dis=%d cooldown=%s segments=%d regen=%s', v.kind, v.d.resource, cfg, h.max,
            tostring(h.rate), h.disabled, tostring(h.cooldown), h.segments, tostring(h.regen_rate))
    end
    e.users = e.users + 1
    rate = math.max(0, rate)
    local ready = cfg_put(e, CFG.rate, raw_f32(rate))
    ready = cfg_put(e, CFG.regen_rate, raw_f32(rate)) and ready
    ready = cfg_put(e, CFG.cooldown, raw_f32(C.cooldown)) and ready
    ready = cfg_put(e, CFG.segments, raw_u32(C.native_segments)) and ready
    local cur = cfg_read(e.cfg, CFG.disabled)
    if cur then  -- HealthChangerateDisabled：只改第一个字节，后面的填充字节保持原样
        ready = cfg_put(e, CFG.disabled, string.char(0) .. cur:sub(2, 4)) and ready
    else ready = false end
    local native_zones = {}
    if ready and rate > 0 and e.zone_offset > 0 then native_zones = native_zone_open(e, zc) end
    if ready and not e.logged then
        e.logged = true
        log('native on %s %s cfg=%x: 每秒 %.1f 点血量，受伤后 %.1f 秒开始回血', v.kind, v.d.resource, e.cfg, rate, C.cooldown)
    end
    return ready, native_zones
end

-- 关掉：只写回“确实还是我们写进去的值”的字段，游戏自己改过的不动
native_close = function(cfg, why)
    local e = CFG_ON[cfg]
    if not e then return end
    if e.close_retry and S.clock < e.close_retry then return end
    e.closing = true
    local back, pending = 0, false
    for off, orig in pairs(e.orig) do
        local cur = cfg_read(cfg, off)
        if cur and cur == e.wrote[off] and cur ~= orig then
            if W.raw4(cfg + off, cur, orig) then back = back + 1 else pending = true end
        end
    end
    for i, patch in pairs(e.zone_patches) do
        local name = N.win.read(cfg + CFG.zones + i * CFG.zone_stride + CFG.zone_name, 4)
        local cur = N.win.read(patch.p, 1)
        if patch.wrote and name and string.format('%08x', u32(name, 0)) == patch.hash
            and cur == patch.wrote and cur ~= patch.orig then
            if W.raw1(patch.p, cur, patch.orig) then back = back + 1 else pending = true end
        end
    end
    if pending then
        e.close_retry = S.clock + 1
        if not e.close_logged then
            e.close_logged = true
            log('native close pending %s %s cfg=%x（%s）：恢复写失败，保留原值并每秒重试', e.kind, e.res, cfg, tostring(why))
        end
    else
        CFG_ON[cfg] = nil
        log('native close %s %s cfg=%x（%s）写回 %d 个字段', e.kind, e.res, cfg, tostring(why), back)
    end
end
local function native_close_all(why)
    for _, v in pairs(S.vstate) do v.repair_credit = nil end
    local list = {}
    for cfg in pairs(CFG_ON) do list[#list + 1] = cfg end
    for _, cfg in ipairs(list) do native_close(cfg, why) end
end
local function native_reset_users() for _, e in pairs(CFG_ON) do e.users = 0 end end
local function native_idle(why)
    local list = {}
    for cfg, e in pairs(CFG_ON) do if e.users == 0 then list[#list + 1] = cfg end end
    for _, cfg in ipairs(list) do native_close(cfg, why) end
end

local function read_record(v)
    local d = v.d
    local g = N.sample_graph()
    local net, hm = g:root('network'), g:root('health')
    g:roundtrip(net, d)
    local hi, hd = g:component(hm, d.entity, 0x1030, 0x1048)
    if hi == nil or not same(hd, d) then error('Health owner changed', 0) end
    local rec = ptr(g:watch(hm + 0x1058, 8), 0) + hi * 0x1B8
    local data = g:read(rec, 0x1B8)
    local cfg = config_address(g, net, hm, d)
    local zc = v.zcache
    if not zc or zc.cfg ~= cfg then
        local mx = i32(g:read(cfg, 4), 0)
        if mx <= 0 or mx > 10000000 then error('invalid max', 0) end
        zc = { cfg = cfg, mx = mx, zones = {} }
        for i = 0, 37 do
            local b = g:read(cfg + 0x208 + i * 0x228 + 0x60, 140)
            local name = u32(b, 0)
            if name == 0 then break end
            local zmax = i32(b, 136)
            -- max = -1 的部位和主血量共用上限（坦克车体 c182f110/900f8255/474c6747、机甲手臂 fd7c9885，游戏内观测）
            if zmax == -1 then zmax = mx end
            zc.zones[#zc.zones + 1] = { i = i, hash = string.format('%08x', name), max = zmax, shared = zmax == mx,
                key = ':z' .. i }
        end
        -- 缓存下次还要核对：只 watch 主上限这 4 字节（配置换了地址也会变）
        g:watch(cfg, 4)
    elseif i32(g:watch(cfg, 4), 0) ~= zc.mx then
        v.zcache = nil; error('Health config changed', 0)
    end
    v.zcache = zc
    g:validate()
    return rec, data, zc, hd, cfg
end

-- 仅在护盾服务时记录 FRV 四轮的状态变化，避免必须手动抢在护盾结束前发命令。
-- death_ability 是 filediver 名称库中的线索，不作为 TagComponent 位掩码写入。
local function trace_wheels(v, data, zc, cfg, native_zones)
    if v.kind ~= 'frv' then return end
    if C.tires and REPAIR.wheels then
        local ok, why = pcall(REPAIR.observe_damage, v.d, zc.zones, data)
        local report = 'wm' .. v.d.resource .. tostring(why)
        if not ok and not S.reported[report] then S.reported[report] = true; log('wheel mapping skip %s: %s', v.d.resource, tostring(why)) end
    end
    S.wheel_trace = S.wheel_trace or {}
    local key = v.d.entity .. ':' .. v.d.goid .. ':' .. v.d.resource
    local seen = S.wheel_trace[key] or { next_t = 0 }
    S.wheel_trace[key] = seen
    if S.clock < seen.next_t then return end
    seen.next_t = S.clock + 2
    for _, z in ipairs(zc.zones) do
        local name = WHEEL_NAME[z.hash]
        if name then
            local hp = i32(data, 0xF8 + 4 * z.i)
            local bits = z.i < 16 and tostring(math.floor(u32(data, 0x20) / 4 ^ z.i) % 4) or '?'
            local active = native_zones[z.i] == true
            local value = tostring(hp) .. ':' .. bits .. ':' .. tostring(active)
            if seen[z.hash] ~= value then
                seen[z.hash] = value
                local base = cfg + CFG.zones + z.i * CFG.zone_stride
                local anim = N.win.read(base + CFG.zone_dead_animation, 4)
                local event = N.win.read(base + CFG.zone_heal_event, 4)
                local actors = N.win.read(base + CFG.zone_disable_actors, 1)
                log('wheel %s ent=%d zone=%s hp=%d/%d state=%s native=%s dead_anim=%s heal_event=%s disable_actors=%s death_ability=AbilityId_vehicle_%s_wheel_dead',
                    name, v.d.entity, z.hash, hp, z.max, bits, tostring(active),
                    anim and string.format('%08x', u32(anim, 0)) or '?',
                    event and string.format('%08x', u32(event, 0)) or '?', actors and tostring(actors:byte(1)) or '?', name)
            end
        end
    end
end

local function repair_parts(v, zones, data, rate, dt, key, cfg)
    if rate <= 0 then v.repair_credit = nil; return 0 end
    local d, changed = v.d, 0
    local function report(prefix, reason)
        local report_key = prefix .. key .. reason
        if not S.reported[report_key] then
            S.reported[report_key] = true
            log('%s %s ent=%d: %s', prefix, v.kind, d.entity, reason)
        end
    end
    local mech = v.kind == 'exo' or v.kind == 'arm'
    local engine_vehicle = mech or (v.kind == 'frv' and C.frv_tire_guard)
    local damaged = engine_vehicle and i32(data, 0x14) < v.zcache.mx or false
    local smallest = damaged and v.zcache.mx or nil
    local all_selected = true
    for _, z in ipairs(zones) do
        if z.max > 0 then
            if not part_enabled(d.resource, z.hash) then all_selected = false end
            local bits = z.i < 16 and math.floor(u32(data, 0x20) / 4 ^ z.i) % 4 or 0
            if (z.hp > -1000000 and z.hp < (engine_vehicle and z.max or 1)) or bits == 2 then
                damaged = true
                smallest = math.min(smallest or z.max, z.max)
            end
        end
    end
    if C.part_repair then
        if damaged and all_selected then
            local fraction = math.min(1, rate * dt)
            if engine_vehicle then
                -- Native repair truncates max*fraction to integer HP. Accumulate
                -- eligible service time until even the smallest damaged pool can
                -- gain a point (EXO-55 has two 10-HP pools). Carry the remainder;
                -- increasing every call to 0.1 would multiply the configured rate.
                local credit = v.repair_credit
                if not credit or credit.cfg ~= cfg or credit.rate ~= rate
                    or math.abs(S.clock - credit.at - dt) > 0.000001 then
                    credit = {fraction=0, cfg=cfg, rate=rate}
                end
                credit.fraction = math.min(1, credit.fraction + fraction)
                credit.at = S.clock; v.repair_credit = credit
                fraction = math.min(1, math.floor(credit.fraction * smallest + 0.0000001) / smallest)
            end
            if fraction > 0 then
                local ok, done, why = pcall(REPAIR.heal, d, fraction, v.kind == 'arm')
                if ok and done then
                    if v.repair_credit then
                        v.repair_credit.fraction = math.max(0, v.repair_credit.fraction - fraction)
                    end
                    changed = changed + 1
                    report('part repair', 'game repair function')
                else
                    v.repair_credit = nil
                    report('part repair skip', tostring(ok and why or done))
                end
            end
        elseif damaged and not all_selected then
            v.repair_credit = nil
            report('part repair skip', 'a part is disabled; game repair function affects all zones')
        else v.repair_credit = nil end
    else v.repair_credit = nil end
    if C.exo_leg_fix and v.kind == 'exo' and not damaged and all_selected then
        local ok, done, why = pcall(REPAIR.fix_leg, d, cfg, zones, W.f32, config_address)
        if ok and done then changed = changed + 1
        elseif not ok or (why and why ~= 'no 0.75 leg penalty' and why ~= 'no stat modifier row'
            and why ~= 'exosuit is not fully repaired') then report('exo leg repair skip', tostring(ok and why or done)) end
        local fire_ok, stopped, reason = pcall(REPAIR.stop_leg_fire, d, cfg, zones, config_address)
        if fire_ok and stopped then changed = changed + 1
        elseif not fire_ok or (reason and reason ~= 'no active leg fire' and reason ~= 'no effect reference row'
            and reason ~= 'no recognized leg fire pair' and reason ~= 'exosuit is not fully repaired') then
            report('exo leg fire skip', tostring(fire_ok and reason or stopped))
        end
    end
    if C.tires and v.kind == 'frv' and S.clock >= (v.next_wheel or 0) then
        v.next_wheel = S.clock + math.max(0.5, C.wheel_interval)
        local expected = {'fed0a478', 'f3cb00ad', 'c6bf05a9', 'f12186b7'}
        local selected, mapped = {}, true
        for i = 0, 3 do
            local z = zones[i + 1]
            if not z or z.i ~= i or z.hash ~= expected[i + 1] then mapped = false; break end
            selected[z.hash] = part_enabled(d.resource, z.hash)
        end
        local ok, done, why
        if mapped then
            local allowed, partial = REPAIR.allowed(d, selected)
            if C.frv_tire_guard then allowed=TYRE.allowed(d,allowed) end
            ok, done, why = pcall(REPAIR.repair_wheel, d, allowed)
            if ok and not done and partial and why == 'no selected blown tyre' then
                why = 'no selected blown tyre with a confirmed API/health mapping; damage one tyre at a time to learn'
            end
        else ok, done, why = true, false, 'FRV wheel zone order is not recognized' end
        if ok and done then changed = changed + 1
        elseif not ok or (why and why ~= 'no selected blown tyre') then
            report('wheel repair skip', tostring(ok and why or done))
        end
    end
    return changed
end

-- Capture mech part transitions automatically while serviced, including independent arm death.
local function trace_mech(v, data, zones)
    if v.kind ~= 'exo' and v.kind ~= 'arm' then return end
    local key = v.d.entity .. ':' .. v.d.goid .. ':' .. v.d.resource
    S.mech_trace = S.mech_trace or {}
    local seen = S.mech_trace[key] or {next_t = 0}; S.mech_trace[key] = seen
    if S.clock < seen.next_t then return end
    seen.next_t = S.clock + 2
    local life, hp = u32(data, 0x19C), i32(data, 0x14)
    local snapshot = string.format('%d:%d:%08x', hp, life, u32(data, 0x20))
    for _, z in ipairs(zones) do snapshot = snapshot .. ':' .. z.hp end
    if seen.value == snapshot then return end
    seen.value = snapshot
    log('mech health %s %s ent=%d hp=%d/%d life=%08x (nonzero=dead)', v.kind, v.d.resource, v.d.entity, hp, v.zcache.mx, life)
    for _, z in ipairs(zones) do
        log('mech part %s ent=%d zone=%s hp=%d/%d state=%s selected=%s', v.kind, v.d.entity, z.hash, z.hp, z.max,
            z.i < 16 and tostring(math.floor(u32(data, 0x20) / 4 ^ z.i) % 4) or '?', tostring(part_enabled(v.d.resource, z.hash)))
    end
    if v.kind == 'arm' and hp <= 0 then
        local ok, parent, why = pcall(REPAIR.arm_parent, v.d)
        log('mech arm ent=%d parent=%s life=%08x: %s', v.d.entity, ok and parent and tostring(parent.entity) or '?', life,
            life ~= 0 and 'engine-dead arm; reference mod has no reattach/respawn path'
                or (ok and parent and 'mounted zero-HP arm can use game repair' or tostring(ok and why or parent)))
    end
end

local function heal(v, dt)
    if C.heal == 'off' then return 'heal off' end
    local d = v.d
    local rec, data, zc, hd, cfg = read_record(v)
    if C.authority_only and hd.flags % 2 ~= 1 then return 'no_authority' end
    local mx = zc.mx
    local zones = {}
    for n, z in ipairs(zc.zones) do
        zones[n] = { i = z.i, hash = z.hash, max = z.max, shared = z.shared, key = z.key, hp = i32(data, 0xF8 + 4 * z.i) }
    end

    local hp = i32(data, 0x14)
    trace_mech(v, data, zones)
    if u32(data, 0x19C) ~= 0 then return 'dead' end
    if hp <= 0 then
        if v.kind ~= 'arm' or not C.part_repair or hp <= -1000000 then return 'dead' end
        local ok, parent = pcall(REPAIR.arm_parent, d)
        if not ok or not parent then return 'detached_arm' end
    end
    local rate = C[HEAL_RATE[v.kind]]
    -- Mechs and guarded FRVs use one healing backend; the repair function heals main HP.
    -- Running config regeneration alongside it would double healing and may consume
    -- the damaged-zone transition before the engine's repair event can handle it.
    local engine_repair = (v.kind == 'exo' or v.kind == 'arm' or (v.kind == 'frv' and C.frv_tire_guard))
        and C.part_repair and REPAIR.health ~= nil
    if engine_repair then
        for _, z in ipairs(zones) do
            if z.max > 0 and not part_enabled(d.resource, z.hash) then engine_repair = false; break end
        end
    end
    -- v0.13：主血量交给游戏自带的回血（打开 HealthComponent 配置里的开关/速率）。
    -- 游戏自己涨的血不会在下一次受伤时被它另存的那份血量盖回去，所以不用扫内存。
    local native_zones = {}
    if C.heal == 'native' and cfg and not engine_repair then
        local _, active = native_apply(v, cfg, mx, mx * rate, zc)
        native_zones = active or {}
    end
    trace_wheels(v, data, zc, cfg, native_zones)

    -- 受伤检测（总血量下降 -> 冷却）
    local total = hp
    for _, z in ipairs(zones) do if z.hp > 0 then total = total + z.hp end end
    local key = d.entity .. ':' .. d.goid
    if S.last_total[key] and total < S.last_total[key] then S.last_hit[key] = S.clock end
    S.last_total[key] = total
    if C.cooldown > 0 and S.last_hit[key] and S.clock - S.last_hit[key] < C.cooldown then return 'cooldown' end

    local changed = repair_parts(v, zones, data, rate, dt, key, cfg)
    if C.heal == 'write' and not engine_repair and hp < mx then  -- 游戏维修函数也处理主血量
        local n = amount(key .. ':h', mx, rate, dt)
        if n > 0 and W.i32(rec + 0x14, hp, math.min(mx, hp + n)) then changed = changed + 1 end
    end
    local state = u32(data, 0x20)
    for _, z in ipairs(zones) do
        -- 已开启原生再生的部位（包含 HP<=0）由游戏负责，保留 OnHeal 的触发机会。
        -- 按部位禁用时也不走逐帧回填；native_zone=0 可退回原先的修血路径。
        -- A protected wheel at 1 HP is alive, so the old destroyed-only repair
        -- trigger misses it. If whole-unit repair is unavailable/disabled by a
        -- part policy, maintain selected wheels through the existing HP fallback.
        local guarded_wheel = v.kind == 'frv' and C.frv_tire_guard and WHEEL[z.hash]
        if not engine_repair and part_enabled(d.resource, z.hash) and (not native_zones[z.i] or guarded_wheel) and z.max > 0 and z.hp < z.max then
            local zk = key .. z.key
            local zo = 0xF8 + 4 * z.i
            if z.hp > 0 then
                local n = amount(zk, z.max, rate, dt)
                if n > 0 and W.i32(rec + zo, z.hp, math.min(z.max, z.hp + n)) then changed = changed + 1 end
            elseif z.hp > -1000000 and C.hull_zones and not C.revive and (v.kind == 'tank' or v.kind == 'frv') and not WHEEL[z.hash] then
                -- 坦克/FRV 被打爆的部位：只把 HP 数值慢慢加回上限，不动损坏状态位（部件照样是坏的/掉的）
                -- 游戏内实测：坦克 net 车体 6750/8000 = 8000 - (750+250+250)，正好是三个被打爆部位的损失
                local n = amount(zk, z.max, rate, dt)
                if n > 0 and W.i32(rec + zo, z.hp, math.min(z.max, z.hp + n)) then
                    changed = changed + 1
                    if not S.reported['hz' .. key .. z.i] then
                        S.reported['hz' .. key .. z.i] = true
                        log('hull zone %s entity=%d zone=%s from %d (state kept)', v.kind, d.entity, z.hash, z.hp)
                    end
                end
            elseif z.hp > -1000000 and not WHEEL[z.hash] and C.revive then
                -- 被打爆的部位（HP≤0）：拉回 25%，并清掉该区的 2-bit 损坏状态（2=已摧毁，游戏内实测）
                -- 之后按正常速度继续回满。实验性：模型/脱落的部件能否恢复取决于游戏
                if W.i32(rec + zo, z.hp, math.ceil(z.max * 0.25)) then
                    changed = changed + 1
                    if z.i < 16 then
                        local shift = 4 ^ z.i
                        local bits = math.floor(state / shift) % 4
                        if bits ~= 0 then
                            local ns = state - bits * shift
                            if W.u32(rec + 0x20, state, ns) then state = ns end
                        end
                    end
                    log('zone revive %s entity=%d zone=%s %d -> %d', v.kind, d.entity, z.hash, z.hp, math.ceil(z.max * 0.25))
                end
            end
        end
    end
    if changed > 0 then S.last_total[key] = nil end  -- 自己加的血不算“受伤”基线
    return changed
end

-- ---------------------------------------------------------------------------
-- 补弹：上限 = 配置值，否则为观察到的最大值（载具刚召唤时是满的）
-- ---------------------------------------------------------------------------
-- 每个字段的上限：设置文件 > wiki 总量推算 > 观察到的最大值
-- 观察每次检查都做（不管在不在罩子里），所以刚召唤时的满弹量会被记住
function ammo_caps(w, b)
    local d, comp, spec = w.d, w.comp, w.spec
    local obs = {}
    for _, f in ipairs(comp.fields) do
        local cur = i32(b, f[2])
        local mk = d.entity .. ':' .. d.goid .. ':' .. comp.name .. f[1]
        local rk = d.resource .. ':' .. comp.name .. f[1]
        if cur >= 0 and cur <= 100000 then
            if cur > (S.ammo_max[mk] or -1) then S.ammo_max[mk] = cur end
            if cur > (S.ammo_max[rk] or -1) then S.ammo_max[rk] = cur end
        end
        obs[f[1]] = math.max(S.ammo_max[mk] or 0, S.ammo_max[rk] or 0)
    end
    local caps = {}
    for k, v in pairs(obs) do caps[k] = v end
    local load_f = comp.name == 'mag' and 'current' or 'r0'
    if spec and spec.caps then
        for k, v in pairs(spec.caps) do if caps[k] ~= nil then caps[k] = v end end
    elseif spec and spec.total then
        local load = spec.load or obs[load_f]
        if (spec.load == nil or obs[load_f] <= spec.load) and load <= spec.total then
            caps[load_f] = math.max(obs[load_f], load)
            caps.reserve = math.max(obs.reserve or 0, spec.total - load)
        end
    end
    for _, f in ipairs(comp.fields) do
        local cfg = C.ammo_max[d.resource .. ':' .. comp.name .. f[1]]
        if cfg then caps[f[1]] = cfg end
    end
    return caps
end

local function refill(w, dt, observe_only)
    local d, comp = w.d, w.comp
    if not observe_only and (C.exo_weapon_guard or C.exo_shield_guard) and FAULT.blocked(d) then return 'weapon_failed' end
    if C.authority_only and d.flags % 2 ~= 1 then return 'no_authority' end
    local g = N.sample_graph()
    local net = g:root('network')
    g:roundtrip(net, d)
    local manager = ptr(g:watch(N.base + comp.root, 8), 0)
    if manager == 0 then return 'no_manager' end
    local j, owner = g:component(manager, d.entity, comp.to, comp.dp)
    if j == nil or not same(owner, d) then error('weapon owner changed', 0) end
    local row = ptr(g:watch(manager + comp.arr, 8), 0) + j * comp.stride
    local b = g:read(row, comp.stride)
    g:validate()
    local changed = 0
    local caps = ammo_caps(w, b)
    for _, f in ipairs(comp.fields) do
        local cur = i32(b, f[2])
        local mk = d.entity .. ':' .. d.goid .. ':' .. comp.name .. f[1]
        if cur >= 0 and cur <= 100000 then
            local mx = caps[f[1]]
            if not observe_only and mx and mx > 0 and cur < mx then
                local n = math.max(amount(mk, mx, C.ammo_rate, dt), 0)
                if n > 0 and W.i32(row + f[2], cur, math.min(mx, cur + n)) then changed = changed + 1 end
            end
        end
    end
    return changed
end

-- ---------------------------------------------------------------------------
-- 命令
-- ---------------------------------------------------------------------------
local function cmd_units()
    local ok, list = pcall(net_descriptors, true)
    if not ok then log('units: %s', tostring(list)); return end
    local cur = {}
    for _, d in ipairs(list) do cur[d.resource] = (cur[d.resource] or 0) + 1 end
    if S.prev_counts then
        log('---- units diff (新增/减少的资源) ----')
        local seen = {}
        for h, n in pairs(cur) do
            seen[h] = true
            local o = S.prev_counts[h] or 0
            if n ~= o then log('  %s  %d -> %d%s', h, o, n, C.shield[h] and '  [shield]' or '') end
        end
        for h, o in pairs(S.prev_counts) do if not seen[h] then log('  %s  %d -> 0', h, o) end end
    else
        local n = 0; for _ in pairs(cur) do n = n + 1 end
        log('units: baseline saved (%d resource types). 部署护盾后再发一次 units 看新增的 hash', n)
    end
    local copy = {}; for h, n in pairs(cur) do copy[h] = n end
    S.prev_counts = copy
end


local function cmd_vehicles()
    log('---- vehicles (%d) ----', #S.vehicles)
    for _, v in ipairs(S.vehicles) do
        local d = v.d
        local ok, info = pcall(function()
            local g = N.sample_graph()
            local net, hm = g:root('network'), g:root('health')
            local hi = g:component(hm, d.entity, 0x1030, 0x1048)
            local data = g:read(ptr(g:watch(hm + 0x1058, 8), 0) + hi * 0x1B8, 0x1B8)
            local cfg = config_address(g, net, hm, d)
            local zs = {}
            for i = 0, 37 do
                local b = g:read(cfg + 0x208 + i * 0x228 + 0x60, 140)
                if u32(b, 0) == 0 then break end
                zs[#zs + 1] = string.format('%08x=%d/%d', u32(b, 0), i32(data, 0xF8 + 4 * i), i32(b, 136))
            end
            return string.format('hp=%d/%d state=%08x life=%08x zones[%s]', i32(data, 0x14), i32(g:read(cfg, 4), 0), u32(data, 0x20), u32(data, 0x19C), table.concat(zs, ' '))
        end)
        local extra = ''
        if v.kind == 'tank' or v.kind == 'frv' then
            local okn, a, b = pcall(net_body, v)
            extra = okn and a and string.format(' net_hp=%s/%s', tostring(a), tostring(b)) or ' net_hp=?'
        end
        log('  %-4s %s ent=%d goid=%d unit=%d auth=%s %s%s %s', v.kind, d.resource, d.entity, d.goid, d.unit,
            tostring(d.flags % 2 == 1), fmtpos(position_of(d)), extra, ok and info or ('ERR ' .. tostring(info)))
    end
end

-- parts：列出独立开关与再生相关事件，不把血量回满当作模型已经恢复。
local function cmd_parts()
    log('---- parts: native_zone=+%x part_regen=%s ----', C.native_zone, tostring(C.part_regen))
    for _, v in ipairs(S.vehicles) do
        local ok, err = pcall(function()
            local _, data, zc, hd, cfg = read_record(v)
            for _, z in ipairs(zc.zones) do
                local cur, why = zone_layout(cfg, z, zc, C.native_zone)
                local base = cfg + CFG.zones + z.i * CFG.zone_stride
                local event = N.win.read(base + CFG.zone_heal_event, 4)
                local actors = N.win.read(base + CFG.zone_disable_actors, 1)
                local anim = N.win.read(base + CFG.zone_dead_animation, 4)
                local bits = z.i < 16 and tostring(math.floor(u32(data, 0x20) / 4 ^ z.i) % 4) or '?'
                log('part %s ent=%d i=%d %s hp=%d/%d state=%s requested=%s regen=%s auth=%s heal_event=%s disable_actors=%s dead_anim=%s%s',
                    v.kind, v.d.entity, z.i, v.d.resource .. ':' .. z.hash, i32(data, 0xF8 + 4 * z.i), z.max,
                    bits, tostring(part_enabled(v.d.resource, z.hash)), cur and tostring(cur:byte(1)) or '?',
                    tostring(hd.flags % 2 == 1), cur and event and string.format('%08x', u32(event, 0)) or '?',
                    cur and actors and tostring(actors:byte(1)) or '?',
                    cur and anim and string.format('%08x', u32(anim, 0)) or '?', why and (' layout=' .. why) or '')
            end
        end)
        if not ok then log('parts %s %s: %s', v.kind, v.d.resource, tostring(err)) end
    end
end

local NET_TYPES = { '0XdGDIMr', '0y7l0QeN', '13NWb9b4', '1Agpa5Go', '1U4RO9x9', '1WInU5zi', '1d8UAM8X', '1qrBea82', '1y3kV2RF', '2UaFstb9', '33tTKuBx', '37v4RANg', '3JyWPMmp', '3LHk6DNB', '4L2lAhHw', '4bJq0jZR', '4vbuOeX6', '59vM5uM3', '5HAXCmRy', '5q80wl2C', '6JJ2KEcW', '6PbNW0d8', '6dWX1t6T', '6hg2aAnG', '6kbD51Xx', '6nCDJIIO', '6qEARSB5', '6ugE3vNs', '6ykLNGcD', '7E9RrAfA', '7U34wVsx', '82mm3kqJ', '84ufSRap', '8Fod6jU1', '8Xb1bA4q', '8YG2we6r', '8hg8HAw6', '901qiB7F', '9P3hwtQV', '9WL7Rliv', 'A2xzKGnq', 'A69xyHpk', 'ACKHl9Xm', 'ADbtkO2h', 'AR62F1rI', 'AYtHsvgZ', 'BD5QAD3e', 'BEZhAo5V', 'BI234Nln', 'BJ8HSBj6', 'BJDSwjuN', 'BNCyayV7', 'BxrSiZJs', 'CM1rGKnH', 'CXpgv7AO', 'CYpr25ch', 'CZrBoIsc', 'CqC6onVU', 'D33t4Yq4', 'D7JCO2Mf', 'DC4hjnLa', 'DLL9rgyD', 'DO8EsVax', 'DR0qy4Oq', 'DSABFuE0', 'DZ2VbIUK', 'De7tagkk', 'DkIBk3pW', 'DklquRRt', 'DngqTgmg', 'E44mEnzI', 'E7hdT1gf', 'E8PdVbxY', 'ETvIjb00', 'EUZPM0P8', 'Ea5lP5yv', 'EgVBinkV', 'Ezb6IXvp', 'FKuPsook', 'FlxCS9q5', 'FzLfCXXL', 'GBOzTDQv', 'GRdesBBX', 'GrRkjKnK', 'GsZftK5s', 'HXKv5Hto', 'HlvPmSLK', 'HvWv6fVc', 'HvmWGMdc', 'IYWgKQf0', 'IiVHF36Q', 'Imd1bdSH', 'IzGAzB11', 'J4StVAdF', 'JKUKBAef', 'JSy55q4b', 'JgyQjtSu', 'JhJKzgIx', 'JmVdNJdW', 'JxYAip3r', 'K9PDApjZ', 'KQ4dnvxo', 'KYIz3wOe', 'KzjuB86r', 'L3nSxTaG', 'LEbinxaq', 'LLeLDaOH', 'LbxcDJPg', 'M2yoGCO3', 'M86b4LWW', 'M9lKJpkm', 'MIWyUoSq', 'MJAkcNku', 'MNoIdfUn', 'MU4c5HHY', 'MvmBshOn', 'MxiDo2VG', 'Nf7cYA1Q', 'Nm0TQY3i', 'NmJstHF0', 'O1utWERF', 'OOeBKS07', 'OUSpKVon', 'OdO9IpMd', 'OyPvwHVR', 'PEqirql6', 'PLWpyKhh', 'PnuEPlQR', 'Pr77BrvV', 'PtE5eSAN', 'PuouxBx0', 'Q8WPyCgN', 'QTy2ToLH', 'QoHgU161', 'R9u6Lz7a', 'RdHwBIxp', 'RrqbQpz4', 'S8pAsI7Y', 'SH3YTx0S', 'SItHVcrp', 'SSvLXkYU', 'ShYEl3p4', 'SoLWJ5Lg', 'TEDfNjpT', 'TmOKDKTK', 'TvBHuMki', 'TxZKD7Jt', 'U2vlVWku', 'U4dhYSWp', 'UPciGtwi', 'Um3MMe4L', 'V7AINQtp', 'V92yZqGg', 'VIf1E2DR', 'VSWTQQFi', 'W16lvntr', 'W39LbrUR', 'W4aoiPNm', 'WIQvpJQb', 'WNTBCq6O', 'Wxqxtfmp', 'XDeQy9oE', 'XGR2nJo4', 'XZfcNh3y', 'Y76HdQm1', 'YXCAELoC', 'Ya7auduJ', 'Z5YGpNGQ', 'Z6VzY3yJ', 'ZJ1b9Ahf', 'ZOJBgY50', 'ZRQCfaLJ', 'a8VdruCJ', 'aACY7h0e', 'aKXpM4z0', 'aYQGmjlX', 'ac2aYKwB', 'bTJUrtuo', 'bb14Em9T', 'bkw6pFy9', 'bsBMuIVZ', 'bw4G9tXw', 'c7WEVAvf', 'c7Zd0uXW', 'cEitkNtE', 'cG7oY0ES', 'cvjBs8Wv', 'dWMgnjBO', 'dpTn49Ym', 'dvQBs8Il', 'eJk59LKi', 'f0QhhXWF', 'fECZdbQv', 'fYPmjvKj', 'fZwFCDKT', 'fp1DwXPR', 'fvXnCLeO', 'g18jjLob', 'g6BcKTn2', 'gEWqNbKK', 'giUpqlCN', 'hsBS26F5', 'hth6MYPf', 'iBpMg1n2', 'iLpqaa4Q', 'iQ6EoFmm', 'iaykIw21', 'incUXe4M', 'ipJX9Wyx', 'iuhtfy7R', 'jGPtSa4Q', 'jSz7RdwQ', 'jTj5zCzv', 'jgnfGqrg', 'k6sOS9E1', 'kR8Wt84A', 'kXGcIuIi', 'kZQHPWOx', 'l9182Xsq', 'lD4ajClR', 'lHL7eIoX', 'lkakIMiW', 'loNSFG2W', 'm8zZJCiw', 'mVRZuV4X', 'mVdLxCvC', 'mfF0o0Gm', 'mzohJST2', 'nM6fk00C', 'nNDrtLKN', 'niOqavRX', 'nkAn6ag9', 'nqHKoKUy', 'nv3XEPTG', 'o2akuixy', 'o3mPP8Yy', 'oEM5Garr', 'oYrsgCxu', 'odBQRXe0', 'onA35xQx', 'ou6xcKpr', 'p8Pbgujj', 'pJtqnoTt', 'pdMG3nWj', 'pihpFLlF', 'qCrez3w1', 'qD9SMFSs', 'qId6jM4R', 'qciZDjGk', 'r9NkfOBC', 'rHVbvgIu', 'rYIyZPzu', 'rpZ2bCDz', 'rtrfrywL', 'sPQLfFt2', 'syr4tkzd', 't55cYrRU', 't9sxjuv8', 'tmAFBgfS', 'txXYboZT', 'uUQY4v8C', 'uy0hfBmC', 'vamGR36I', 'vbcZUKZk', 'vrNKKeFq', 'wNGBrVCG', 'wSiN4FfF', 'wWaJYoCx', 'wkARpI1b', 'wlrNDnp6', 'xQExJF3F', 'xbKbp8F4', 'xlo1r28A', 'xvcR94QE', 'y9mcMPJg', 'yIRNiJvL', 'yK3X1Mh2', 'yK9rsnyk', 'yMuXzxfg', 'ykO3xi59', 'ylnZPCUn', 'yo5XZ75S', 'z2t7zI8M', 'zFFmTqVX', 'zdmjNbiG', 'zpVUjezE', 'zxLvnAU1' }

-- netinfo：找坦克/FRV 的网络对象类型和字段表（只读查询）
local function dump_val(x, depth)
    if type(x) ~= 'table' then return tostring(x) end
    if depth > 1 then return '{..}' end
    local parts, n = {}, 0
    for k, v in pairs(x) do
        n = n + 1; if n > 12 then parts[#parts + 1] = '...'; break end
        parts[#parts + 1] = tostring(k) .. '=' .. dump_val(v, depth + 1)
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function net_type_of(v)
    local GS = sr.GameSession
    if v.net_type ~= nil then return v.net_type or nil end
    local found = false
    for _, t in ipairs(NET_TYPES) do
        if call(GS.game_object_is_type, S.ctx.session, v.d.goid, t) == true then found = t; break end
    end
    v.net_type = found
    return found or nil
end

local function cmd_netinfo()
    local Net, GS = sr.Network, sr.GameSession
    local names = {}
    if type(Net) == 'table' then for k, f in pairs(Net) do if type(f) == 'function' then names[#names + 1] = k end end end
    table.sort(names)
    log('Network fns: %s', table.concat(names, ' '))
    if not S.ctx then log('netinfo: no session'); return end
    for _, v in ipairs(S.vehicles) do
        if (v.kind == 'tank' or v.kind == 'frv') and call(GS.game_object_exists, S.ctx.session, v.d.goid) == true then
            v.net_type = nil
            local t = net_type_of(v)
            local owned = call(GS.game_object_owned, S.ctx.session, v.d.goid)
            local f = select(2, pcall(GS.game_object_field_batched, S.ctx.session, v.d.goid, {}))
            local vals = {}
            if type(f) == 'table' then for i = 1, 90 do if f[i] ~= nil then vals[#vals + 1] = i .. ':' .. dump_val(f[i], 1) end end end
            log('netinfo %s %s goid=%d type=%s owned=%s', v.kind, v.d.resource, v.d.goid, tostring(t), tostring(owned))
            log('  batched: %s', table.concat(vals, ' '))
            if t then
                local info = call(Net.object_info, t)
                if type(info) == 'table' then
                    local top = {}; for k, x in pairs(info) do if k ~= 'fields' then top[#top + 1] = tostring(k) .. '=' .. dump_val(x, 1) end end
                    log('  info: %s', table.concat(top, ' '))
                    if type(info.fields) == 'table' then
                        for i = 1, 120 do
                            local fi = info.fields[i]
                            if fi == nil then break end
                            log('  field[%d] %s', i, dump_val(fi, 0))
                        end
                    end
                else log('  object_info -> %s', tostring(info)) end
            end
        end
    end
end

-- netset：一次性实验 —— 用引擎自带的 set_game_object_field 把 FRV 车体网络血量 +100，然后连续读回看会不会被游戏改回去
local function cmd_netset()
    local GS = sr.GameSession
    if not S.ctx or type(GS.set_game_object_field) ~= 'function' then log('netset: unavailable'); return end
    for _, v in ipairs(S.vehicles) do
        if v.kind == 'frv' and call(GS.game_object_exists, S.ctx.session, v.d.goid) == true then
            local hp, mx = net_body(v)
            if not hp then log('netset: frv %d no net hp', v.d.entity)
            elseif call(GS.game_object_owned, S.ctx.session, v.d.goid) ~= true then log('netset: frv %d not owned by us, skip', v.d.entity)
            else
                local new = math.min(mx, hp + 100)
                local ok, err = pcall(GS.set_game_object_field, S.ctx.session, v.d.goid, 'sd7m7FWA', new)
                local back = net_body(v)
                log('netset frv ent=%d %s -> %s ok=%s err=%s readback=%s', v.d.entity, tostring(hp), tostring(new), tostring(ok), tostring(err), tostring(back))
                S.watch = { v = v, t0 = S.clock, marks = { 0.5, 2, 5, 10 }, i = 1 }
            end
        end
    end
end

-- probe：把坦克/FRV 的 Health 记录整段 dump 出来，并找和 net 车体血量相等的 i32/float，方便定位
local function cmd_probe()
    local GS = sr.GameSession
    local names = {}
    if type(GS) == 'table' then for k, f in pairs(GS) do if type(f) == 'function' then names[#names + 1] = k end end end
    table.sort(names)
    log('GameSession fns: %s', table.concat(names, ' '))
    for _, v in ipairs(S.vehicles) do
        if v.kind == 'tank' or v.kind == 'frv' then
            local d = v.d
            local okn, a, b = pcall(net_body, v)
            local ok, err = pcall(function()
                local g = N.sample_graph()
                local hm = g:root('health')
                local hi = g:component(hm, d.entity, 0x1030, 0x1048)
                local data = g:read(ptr(g:watch(hm + 0x1058, 8), 0) + hi * 0x1B8, 0x1B8)
                local hits = {}
                if okn and type(a) == 'number' then
                    local fb = ffi.new('float[1]')
                    for o = 0, 0x1B8 - 4, 4 do
                        local iv = i32(data, o)
                        ffi.copy(fb, data:sub(o + 1, o + 4), 4)
                        if iv == math.floor(a + 0.5) then hits[#hits + 1] = string.format('i32@+%x', o) end
                        if math.abs(fb[0] - a) < 0.01 and iv ~= math.floor(a + 0.5) then hits[#hits + 1] = string.format('f32@+%x', o) end
                    end
                end
                log('probe %s %s ent=%d goid=%d net=%s/%s matches[%s]', v.kind, d.resource, d.entity, d.goid, tostring(a), tostring(b), table.concat(hits, ' '))
                for o = 0, 0x1B8 - 1, 32 do
                    local row = {}
                    for k = o, math.min(o + 31, 0x1B7), 4 do row[#row + 1] = string.format('%08x', u32(data, k)) end
                    log('  +%03x %s', o, table.concat(row, ' '))
                end
            end)
            if not ok then log('probe %s ent=%d: %s', v.kind, d.entity, tostring(err)) end
        end
    end
end

local function cmd_weapons()
    log('---- linked weapon components (%d), weapon guards=%s ----', #S.weapons, tostring(N.weapon_ready))
    for _, w in ipairs(S.weapons) do
        local ok, b = pcall(function()
            local g = N.sample_graph()
            local m = ptr(g:watch(N.base + w.comp.root, 8), 0)
            local j = g:component(m, w.d.entity, w.comp.to, w.comp.dp)
            return g:read(ptr(g:watch(m + w.comp.arr, 8), 0) + j * w.comp.stride, w.comp.stride)
        end)
        local vals = {}
        if ok then
            local caps = ammo_caps(w, b)
            for _, f in ipairs(w.comp.fields) do vals[#vals + 1] = f[1] .. '=' .. i32(b, f[2]) .. '/' .. tostring(caps[f[1]]) end
            if w.spec then vals[#vals + 1] = '[' .. w.spec.name .. ']' end
        end
        log('  %-6s %s ent=%d goid=%d unit=%d owner=%s auth=%s %s', w.comp.name, w.d.resource, w.d.entity, w.d.goid, w.d.unit,
            w.owner and (w.owner.kind .. ':' .. w.owner.d.entity) or 'arm/whitelist', tostring(w.d.flags % 2 == 1),
            ok and table.concat(vals, ' ') or ('ERR ' .. tostring(b)))
    end
    -- 帮助找坦克武器：列出所有弹匣组件里离载具 8 米内、但还没被关联的
    if N.weapon_ready then
        local vpos = {}
        for _, v in ipairs(S.vehicles) do local p = position_of(v.d); if p then vpos[#vpos + 1] = { v, p } end end
        for _, comp in ipairs(WEAPON_COMPONENTS) do
            local m = ptr(N.win.read(N.base + comp.root, 8) or ('\0'):rep(8), 0)
            local ok, all = pcall(enumerate, m, comp.to, comp.dp, function() return true end)
            if ok then
                for idx, d in ipairs(all) do
                    if idx > 256 then break end
                    local p = position_of(d)
                    if p then
                        for _, vp in ipairs(vpos) do
                            local dx, dy, dz = p[1] - vp[2][1], p[2] - vp[2][2], p[3] - vp[2][3]
                            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
                            if dist < 8 and not KIND[d.resource] and not ARM_WEAPON[d.resource] and not C.weapon[d.resource] then
                                log('  [nearby unlinked %s] %s ent=%d unit=%d  %.1fm from %s %d  (可加 weapon=%s)', comp.name,
                                    d.resource, d.entity, d.unit, dist, vp[1].kind, vp[1].d.entity, d.resource)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- v0.13 诊断：healcfg（配置记录 + 部位回血开关候选偏移）、hptrace（血量走势）
-- ---------------------------------------------------------------------------
-- 在部位记录里找“4 个连续的 0/1 字节”（KillChildrenOnDeath / RegenerationEnabled /
-- BleedoutEnabled / AffectedByExplosions），要求后面跟着两个像 float 的字段和一个小枚举。
-- 部位上限 +0xE8、部位信息 +0x1C8 这两个锚点 v0.12 已在游戏内确认，所以范围收得很窄。
local function zone_candidates(cfg, zc)
    local out = {}
    for o = CFG.zone_health - 8, CFG.zone_info - 0x18, 4 do
        local good, bad = 0, 0
        for _, z in ipairs(zc.zones) do
            local b = N.win.read(cfg + CFG.zones + z.i * CFG.zone_stride + o, 0x18)
            local ok = type(b) == 'string' and #b == 0x18
            if ok then
                for k = 1, 4 do
                    local byte = b:byte(k)
                    if not (byte == 0 or byte == 1) then ok = false break end
                end
                if ok then
                    local f1, f2, e1 = f32_at(b, 4), f32_at(b, 8), u32(b, 0x10)
                    if not (finite_pos(f1) and f1 <= 100 and finite_pos(f2) and f2 <= 100000 and e1 < 4096) then ok = false end
                end
            end
            if ok then good = good + 1 else bad = bad + 1 end
        end
        if good > 0 and bad == 0 then out[#out + 1] = string.format('+%x(%d/%d)', o + 1, good, #zc.zones) end
    end
    return out
end

local function cmd_healcfg()
    local seen, any = {}, false
    for _, v in ipairs(S.vehicles) do
        if not seen[v.d.resource] then
            seen[v.d.resource] = true
            any = true
            local ok, err = pcall(function()
                local g = N.sample_graph()
                local net, hm = g:root('network'), g:root('health')
                g:roundtrip(net, v.d)
                local cfg = config_address(g, net, hm, v.d)
                local b = N.win.read(cfg, 0x20)
                if type(b) ~= 'string' or #b ~= 0x20 then error('config unreadable', 0) end
                local hex = {}
                for o = 0, 28, 4 do hex[#hex + 1] = string.format('%08x', u32(b, o)) end
                log('healcfg %-4s %s cfg=%x prot=%s', v.kind, v.d.resource, cfg, tostring(W.prot(cfg)))
                log('  +00..+1c %s', table.concat(hex, ' '))
                log('  Health=%d HeathChangerate=%s HealthChangerateDisabled=%d HeathChangerateCooldown=%s RegenerationSegments=%d RegenerationChangerate=%s',
                    i32(b, 0), tostring(f32_at(b, 4)), b:byte(9), tostring(f32_at(b, 0xC)), u32(b, 0x10), tostring(f32_at(b, 0x14)))
                local rec, data, zc = read_record(v)
                local cands = zone_candidates(cfg, zc)
                log('  部位数=%d 部位上限=+%x RegenerationEnabled 候选偏移: %s', #zc.zones, CFG.zone_health,
                    #cands > 0 and table.concat(cands, ' ') or '(没找到)')
                local name = DIR .. 'shield_resupply_healthcfg_' .. v.d.resource .. '.txt'
                local f = io.open(name, 'w')
                local big = f and W.read_big and W.read_big(cfg, 0x5650)
                if f and big then
                    f:write(string.format('# %s %s cfg=%x size=%x（HealthComponent，字段布局来自 filediver datalibrary）\n',
                        v.kind, v.d.resource, cfg, #big))
                    for o = 1, #big, 32 do
                        local row = {}
                        for k = o, math.min(o + 31, #big) do row[#row + 1] = string.format('%02x', big:byte(k)) end
                        f:write(string.format('%04x %s\n', o - 1, table.concat(row, ' ')))
                    end
                end
                if f then f:close() end
                if big then log('  完整配置记录（%d 字节）-> %s', #big, name) end
            end)
            if not ok then log('healcfg %s %s: %s', v.kind, v.d.resource, tostring(err)) end
        end
    end
    if not any then log('healcfg: 现在没有载具（先叫一台下来，再发 healcfg）') end
end

local function cmd_hptrace(secs)
    secs = math.max(1, math.min(120, tonumber(secs) or 10))
    S.hptrace = { until_t = S.clock + secs, next_t = 0 }
    log('hptrace: 采样 %.0f 秒，每 0.5 秒记一次主血量 / 部位和 / 配置开关', secs)
end

local function cmd_status()
    local n = 0; for _ in pairs(C.shield) do n = n + 1 end
    local ncfg = 0; for _ in pairs(CFG_ON) do ncfg = ncfg + 1 end
    log('status: enabled=%s heal=%s test=%s native=%s weapon=%s vehicles=%d weapons=%d shields_cfg=%d shields_live=%d native_open=%d forced=%d writes=%d fails=%d',
        tostring(C.enabled), C.heal, tostring(C.test), tostring(N.ready), tostring(N.weapon_ready), #S.vehicles, #S.weapons, n, #S.shields,
        ncfg, W.forced or 0, W.writes, W.fails)
    log('status: part_repair=%s exo_leg_fix=%s legs_fixed=%d leg_fires_stopped=%d health_guard=%s stat_guard=%s attach_guard=%s effect_guard=%s',
        tostring(C.part_repair), tostring(C.exo_leg_fix), REPAIR.legs_fixed, REPAIR.leg_fires_stopped,
        tostring(REPAIR.health_status), tostring(REPAIR.stats_status), tostring(REPAIR.attach_status), tostring(REPAIR.effects_status))
    FAULT.status()
    TYRE.status()
    for _, d in ipairs(S.shields) do log('  shield %s ent=%d goid=%d at %s', d.resource, d.entity, d.goid, fmtpos(position_of(d))) end
end

local function poll_commands()
    local f = io.open(CMD, 'r')
    if not f then return end
    local text = f:read('*a'); f:close()
    if not text or text:match('^%s*$') then return end
    local w = io.open(CMD, 'w'); if w then w:close() end
    for line in text:gsub('^\239\187\191', ''):gmatch('[^\r\n]+') do
        local c = line:match('^%s*(%S+)')
        if c == 'units' then cmd_units()
        elseif c == 'vehicles' then cmd_vehicles()
        elseif c == 'parts' then cmd_parts()
        elseif c == 'weapons' then cmd_weapons(); FAULT.status()
        elseif c == 'status' then cmd_status()
        elseif c == 'probe' then cmd_probe()
        elseif c == 'healcfg' then cmd_healcfg()
        elseif c == 'hptrace' then cmd_hptrace(line:match('^%s*%S+%s+(%d+)'))
        elseif c == 'heal' then
            local m = (line:match('^%s*%S+%s+(%S+)') or ''):lower()
            if m == 'native' or m == 'write' or m == 'off' then
                if m ~= 'native' then native_close_all('heal=' .. m) end
                C.heal = m
                log('heal = %s', m)
            else
                log('heal: 用法 heal native|write|off（当前 %s）', C.heal)
            end
        elseif c == 'netinfo' then cmd_netinfo()
        elseif c == 'netset' then cmd_netset()
        elseif c == 'recent' then cmd_recent(tonumber(line:match('recent%s+(%d+)')) or 40)
        elseif c == 'reload' then native_close_all('reload'); FAULT.close(); TYRE.close(); load_settings()
        elseif c == 'on' then C.enabled = true; log('enabled')
        elseif c == 'off' then C.enabled = false; native_close_all('mod off'); FAULT.close(); TYRE.close(); log('disabled')
        elseif c == 'test' then C.test = not C.test; log('test mode = %s', tostring(C.test))
        elseif c then log('unknown command: %s (units|recent [n]|vehicles|parts|weapons|status|probe|healcfg|hptrace [secs]|heal native|write|off|reload|on|off|test)', c) end
    end
end

-- ---------------------------------------------------------------------------
-- 主循环
-- ---------------------------------------------------------------------------
local next_cmd = 0
local function tick(dt)
    stage('first tick')
    S.frame = (S.frame or 0) + 1
    S.clock = S.clock + dt
    local App, Net = sr.Application, sr.Network
    local world, session = call(App.main_world), call(Net.game_session)
    if not world or not session then if S.ctx then S.ctx = nil; reset_context(); CFG_ON = {} end; return end
    if not S.ctx or S.ctx.world ~= world or S.ctx.session ~= session then
        S.ctx = { world = world, session = session }; reset_context(); CFG_ON = {}
    end
    local ready, why = N.ensure(S.clock)
    if not ready then
        if S.native_reason ~= why then S.native_reason = why; log('native not ready: %s', tostring(why)) end
        return
    end
    stage('native layout ok')
    if C.enabled and (C.tires or C.part_repair or C.exo_leg_fix or C.exo_weapon_guard or C.exo_shield_guard or C.frv_tire_guard) then REPAIR.ensure(S.clock) end
    if N.weapon_base ~= N.base then
        N.weapon_base = N.base
        N.win.begin_sample()
        local ok, valid, r = pcall(N.check_weapon_module, N.win.read, N.base)
        N.weapon_ready = ok and valid == true
        log('native ok (%s); weapon layout %s %s', tostring(N.reason), N.weapon_ready and 'ok' or 'FAILED', tostring(r or ''))
    end
    -- 命令等 native 就绪后再处理（v0.10 启动时残留的 units 命令会报 N.win 为 nil）
    if S.clock >= next_cmd then next_cmd = S.clock + 0.5; poll_commands() end

    if S.clock >= S.next_roster then
        S.next_roster = S.clock + C.roster_every
        stage('first roster')
        -- 先读网络表：rebuild_roster 里的 owner 描述符直接从这份缓存取
        local ok2, list = pcall(net_descriptors, C.spot)
        local ok, err = pcall(rebuild_roster)
        if not ok then log('roster: %s', tostring(err)) end
        NETDESC.raw = nil
        if ok2 then
            -- 护盾生成器实体在罩子消失后还会留在地上，所以按 wiki 持续时间（40 秒）计时：
            -- 从第一次看到这个实体开始算，超时就不再当作护盾
            local sh, born, now, present = {}, S.shield_born, S.clock, {}
            for _, d in ipairs(list) do
                if C.shield[d.resource] then
                    local k = d.entity .. ':' .. d.goid .. ':' .. d.resource
                    present[k] = true
                    if not born[k] then
                        born[k] = now
                        log('shield up %s ent=%d goid=%d', d.resource, d.entity, d.goid)
                    end
                    if C.shield_duration <= 0 or now - born[k] <= C.shield_duration then sh[#sh + 1] = d
                    elseif not S.shield_expired[k] then S.shield_expired[k] = true; log('shield timeout ent=%d goid=%d (%.0f s)', d.entity, d.goid, C.shield_duration) end
                end
            end
            -- 生成器实体消失 = 护盾结束（记录实际存活时间，用来核对）
            for k, t0 in pairs(born) do
                if not present[k] then log('shield gone %s after %.0f s', k, now - t0); born[k] = nil; S.shield_expired[k] = nil end
            end
            S.shields = sh
            if C.spot then
                local ok3, e3 = pcall(spot_new, list)
                if not ok3 then log('spot: %s', tostring(e3)) end
            else S.seen_ent = nil end
        else log('net roster: %s', tostring(list)) end
        -- 弹药上限的“观察”已在 rebuild_roster 里批量完成（observe_ammo）
    end
    if C.enabled and C.tires and REPAIR.wheels and S.clock >= (S.next_wheel_learn or 0) then
        S.next_wheel_learn = S.clock + 1
        for _, v in ipairs(S.vehicles) do
            if v.kind == 'frv' then
                local ok, done, why = pcall(REPAIR.learn, v.d)
                if not ok or (not done and why) then
                    local reason = tostring(ok and why or done)
                    local report = 'wl' .. v.d.resource .. reason
                    if not S.reported[report] then S.reported[report] = true; log('wheel learn skip %s: %s', v.d.resource, reason) end
                end
            end
        end
    end
    if S.hptrace then  -- v0.13 诊断：看不用 mod 写血量时，血量会不会自己涨
        local t = S.hptrace
        if S.clock >= t.next_t then
            t.next_t = S.clock + 0.5
            for _, v in ipairs(S.vehicles) do
                local oke, rec, data, zc, hd, cfg = pcall(read_record, v)
                if oke then
                    local zsum = 0
                    for _, z in ipairs(zc.zones) do zsum = zsum + math.max(0, i32(data, 0xF8 + 4 * z.i)) end
                    log('hptrace %-4s ent=%d hp=%d/%d 部位和=%d 配置=%s', v.kind, v.d.entity, i32(data, 0x14), zc.mx, zsum,
                        CFG_ON[cfg] and 'open' or '-')
                end
            end
        end
        if S.clock >= t.until_t then S.hptrace = nil; log('hptrace: 结束') end
    end
    if S.watch then
        local w = S.watch
        if S.clock - w.t0 >= w.marks[w.i] then
            local okn, a = pcall(net_body, w.v)
            log('netset watch +%.1fs net=%s', w.marks[w.i], tostring(okn and a))
            w.i = w.i + 1; if w.i > #w.marks then S.watch = nil end
        end
    end
    if not C.enabled then native_close_all('mod off'); FAULT.close(); TYRE.close(); return end
    -- Prevention and failure latch also run outside the shield. Always sample
    -- before a repair pass, so healing cannot conceal a just-reached 1 HP state.
    if C.exo_weapon_guard or C.exo_shield_guard or C.frv_tire_guard then
        if S.clock >= (S.next_fault or 0) or S.acc+dt >= C.tick then
            S.next_fault=S.clock+0.05
            if C.exo_weapon_guard or C.exo_shield_guard then FAULT.step(S.vehicles) else FAULT.close() end
            if C.frv_tire_guard then TYRE.step(S.vehicles) else TYRE.close() end
        end
    else FAULT.close(); TYRE.close() end
    S.acc = S.acc + dt
    if S.acc < C.tick then return end
    local step = math.min(S.acc, 1); S.acc = 0

    stage('first service pass')
    if #S.shields == 0 and not C.test then  -- 没有护盾：停止常规维修；上方的武器保底和故障检测继续运行
        native_close_all('没有护盾')
        return
    end
    -- 这一轮只需要这些 unit 的坐标
    local want, wn = {}, 0
    local function add(u) if not want[u] then want[u] = true; wn = wn + 1 end end
    for _, d in ipairs(S.shields) do add(d.unit) end
    for _, v in ipairs(S.vehicles) do add(v.d.unit) end
    for _, w in ipairs(S.weapons) do if not w.owner then add(w.d.unit) end end
    S.want_units, S.want_n = want, wn; REF.frame = -1
    local centers = {}
    for _, d in ipairs(S.shields) do local p = position_of(d); if p then centers[#centers + 1] = p end end
    local any = #centers > 0 or C.test
    if not any then S.want_units = nil; native_close_all('护盾坐标读不到'); return end

    native_reset_users()  -- 这一轮重新统计哪些配置还有人用，没人用的关掉（写回原值）
    local inside = {}
    for _, v in ipairs(S.vehicles) do
        if any and in_shield(position_of(v.d), centers) then
            inside[v.d.entity] = true
            if v.kind == 'tank' or v.kind == 'frv' then
                local okh, rh = pcall(net_heal, v, step)
                if not okh or type(rh) == 'string' then
                    local k = 'n' .. v.d.entity .. tostring(rh)
                    if not S.reported[k] then S.reported[k] = true; log('net heal %s %d: %s', v.kind, v.d.entity, tostring(rh)) end
                end
            end
            local ok, r = pcall(heal, v, step)
            if not ok then
                v.repair_credit = nil
                local k = v.d.entity .. tostring(r)
                if not S.reported[k] then S.reported[k] = true; log('heal %s %d: %s', v.kind, v.d.entity, tostring(r)) end
            end
        else v.repair_credit = nil end
    end
    native_idle('没有载具在罩子里')
    if C.ammo and N.weapon_ready then
        for _, w in ipairs(S.weapons) do
            local owner = w.owner
            local ok_kind = (owner and AMMO_KIND[owner.kind]) or (not owner)
            local here = owner and inside[owner.d.entity] or (not owner and in_shield(position_of(w.d), centers))
            if ok_kind and here then
                local ok, r = pcall(refill, w, step, false)
                if not ok then
                    local k = 'w' .. w.d.entity .. tostring(r)
                    if not S.reported[k] then S.reported[k] = true; log('ammo %s %d: %s', w.comp.name, w.d.entity, tostring(r)) end
                end
            end
        end
    end
    S.want_units = nil
end

load_settings()
if TEST_HOOK then TEST_HOOK(N, W, S, C, REPAIR, FAULT, TYRE) end
local previous = rawget(_G, 'update')
rawset(_G, 'update', function(dt, ...)
    if type(dt) == 'number' and dt > 0 and dt < 1 then
        local ok, err = pcall(tick, dt)
        if not ok then
            S.errors = (S.errors or 0) + 1
            if S.errors <= 20 then log('tick error: %s', tostring(err)) end
        end
    end
    if previous then return previous(dt, ...) end
end)
log('loaded v0.23 (机甲小血池累计维修；修满后恢复移速并停止腿部燃烧特效；读取层来自 DRIVER HUD / HUD, MIT FireScallion)')
return { installed = true }

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
 function G:read_fields(p,n,fields)
  local raw=self:read(p,n)
  for _,field in ipairs(fields) do
   local at,size=p+field[1],field[2]
   if field[1]<0 or size<1 or field[1]+size>n then error('watched field bounds',0) end
   local key=string.format('%.0f:%d',at,size)
   local b=raw:sub(field[1]+1,field[1]+size)
   local old=self.seen[key]
   if old and old~=b then error('identity changed during sample',0) end
   if not old then self.seen[key]=b;self.watches[#self.watches+1]={at,size,b} end
  end
  return raw
 end
 function G:validate()
  -- Adjacent/overlapping watched ranges share one fresh read. Compare only the
  -- original bytes; never validate against cached first-pass data or padding.
  local plan=self.validation
  if not plan or plan.count~=#self.watches then
   local ordered={};for i,w in ipairs(self.watches) do ordered[i]=w end
   table.sort(ordered,function(a,b)return a[1]<b[1]end)
   plan={ordered=ordered,ranges={},count=#ordered}
   local i=1
   while i<=#ordered do
    local first=ordered[i][1];local finish=first+ordered[i][2];local j=i+1
    while j<=#ordered and ordered[j][1]<=finish and math.max(finish,ordered[j][1]+ordered[j][2])-first<=4096 do
     finish=math.max(finish,ordered[j][1]+ordered[j][2]);j=j+1
    end
    plan.ranges[#plan.ranges+1]={first,finish-first,i,j-1};i=j
   end
   self.validation=plan
  end
  for _,range in ipairs(plan.ranges) do
   local fresh=self:read(range[1],range[2])
   for k=range[3],range[4] do
    local w=plan.ordered[k];local offset=w[1]-range[1]
    if fresh:sub(offset+1,offset+w[2])~=w[3] then error('identity changed during sample',0) end
   end
  end
 end
 -- Reuse the identity layout only; every patrol gets fresh Health and proof bytes.
 function G:poll(p,n)
  self.calls,self.bytes=0,0
  local data=self:read(p,n);self:validate();return data
 end
 function G:root(name)
  local p=ptr(self:watch(self.base+N.roots[name],8),0)
  if p==0 then error(name..' manager not ready',0) end
  addr(p,1);return p
 end
 function G:table(p)
  local b=self:watch(p,20);local cap=u32(b,8)
  if cap>1048576 or (cap>0 and 2^math.floor(math.log(cap)/math.log(2)+0.5)~=cap) then error('invalid table capacity',0) end
  local t={p=p,entries=ptr(b,0),capacity=cap,empty=u32(b,12),multiplier=u32(b,16),signature=b}
  if cap>0 then addr(t.entries,1) end;return t
 end
 function G:lookup(t,key)
  if type(key)~='number' or key<0 or key>4294967295 or key~=math.floor(key) then error('invalid identity key',0) end
  if key==t.empty or t.capacity==0 then return nil end
  local tables=N.lookup_cache
  if not tables then tables={};N.lookup_cache=tables;N.lookup_tables=0 end
  local cached=tables[t.p]
  if not cached then
   if N.lookup_tables>=16 then tables={};N.lookup_cache=tables;N.lookup_tables=0 end
   cached={signature=t.signature,slots={}};tables[t.p]=cached;N.lookup_tables=N.lookup_tables+1
  elseif cached.signature~=t.signature then cached.signature=t.signature;cached.slots={} end
  local bucket=key%256;local hit=cached.slots[bucket]
  -- Cache locations, never contents: dense indices and owners may move.
  if hit and hit.key==key then
   local b=self:watch(t.entries+hit.slot*8,8)
   if u32(b,0)==key then
    local j=u32(b,4)
    if j==4294967295 then return nil end
    if j>=1048576 then error('invalid dense index',0) end
    return j
   end
   cached.slots[bucket]=nil
  end
  local first=mul32(key,t.multiplier)%t.capacity
  for step=0,math.min(t.capacity,64)-1 do
   local slot=(first+step)%t.capacity
   local b=self:watch(t.entries+slot*8,8)
   local k,j=u32(b,0),u32(b,4)
   if k==key then
    if j==4294967295 then return nil end
    if j>=1048576 then error('invalid dense index',0) end
    cached.slots[bucket]={key=key,slot=slot}
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
  if N.ready and N.base==base then return true,N.reason end
  N.lookup_cache=nil;N.lookup_tables=0
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


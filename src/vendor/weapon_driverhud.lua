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

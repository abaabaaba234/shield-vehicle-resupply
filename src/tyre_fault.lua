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

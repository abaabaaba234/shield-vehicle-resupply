-- Weapon failure is latched at 1 HP; only repair above 5% releases the latch.
-- Protect known independent arm Health zones before damage. No executable patch.
-- Empty, saved ammunition stores suppress firing while failed; restoration is
-- tied to the original network/Health/weapon owners, never just an entity ID.
return function(N, W, R, C, log, ammo_components)
    local ffi = require('ffi')
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
    } -- Shield resource 65489809a8181b96 deliberately has no entry.
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
        need(allow_dead or N.u32(data,0x19C)==0, 'already engine-dead; spawn a new mech')
        local cfg = F.config_address(g,net,hm,d)
        local mx = N.i32(g:watch(cfg,4),0)
        need(mx >= 20 and mx <= 1000000, 'invalid weapon maximum')
        local model = F.models[d.resource]
        need(model ~= nil, 'unsupported weapon resource')
        local z = cfg+0x208
        need(string.format('%08x',N.u32(g:watch(z+0x60,4),0)) == model.zone
            and N.u32(g:watch(z+0x228+0x60,4),0)==0, 'weapon must have its known single damage zone')
        local zm = N.i32(g:watch(z+0xE8,4),0)
        if zm == -1 then zm = mx end
        need(zm == mx and N.i32(g:watch(cfg+0x40+0xE8,4),0)==-1, 'weapon/default zone maximum changed')
        -- Named weapon zones already have a separate pool in filediver's configs.
        need(g:watch(z+0xF8,4)=='\0\0\0\0', 'unexpected weapon-to-main damage contribution')
        for _, base in ipairs({cfg+0x40,z}) do
            for o=0xF0,0xF4 do need(g:read(base+o,1):byte(1)<=1, 'invalid death flags') end
            need(N.i32(g:read(base+0xEC,4),0)==0 and g:read(base+0xF1,3)=='\0\0\0', 'unexpected constitution/death propagation')
        end
        local contribution=g:read(cfg+0x40+0xF8,4)
        local f=ffi.new('float[1]'); ffi.copy(f,contribution,4)
        need(f[0]==f[0] and f[0]>=0 and f[0]<=1, 'invalid default-to-main damage contribution')
        local slots = {}
        for _, comp in ipairs(ammo_components) do
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
        need(#slots > 0, 'no verified ammunition stores; protection not armed')
        g:validate()
        local hp = math.min(N.i32(data,0x14),N.i32(data,0xF8))
        need(hp > -1000000 and hp <= mx, 'invalid effective weapon HP')
        return {g=g,d=d,cfg=cfg,mx=mx,hp=hp,slots=slots,life=N.u32(data,0x19C),zone=model.zone}
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
        local z = N.win.read(e.cfg+0x208+0x60,4)
        if not b or not z then return nil end
        return N.i32(b,0)==e.mx and string.format('%08x',N.u32(z,0))==e.zone
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
        if not e then e={cfg=s.cfg,mx=s.mx,zone=s.zone,orig={},wrote={},users=0}; F.configs[s.cfg]=e end
        need(e.mx==s.mx and e.zone==s.zone and config_identity(e), 'protected config identity changed')
        e.users=e.users+1
        s.g:validate()
        -- Stop the named zone from killing its independent arm; Immortal lets the
        -- engine keep the zone alive. Default hits must not kill the separate main pool.
        local ready=true
        for _, p in ipairs({{0x208+0xF4,'\0'}, {0x208+0xF0,'\1'},
                            {0x40+0xF4,'\0'}, {0x40+0xF0,'\1'}, {0x40+0xF8,'\0\0\0\0'}}) do
            if not put(e,p[1],p[2]) then ready=false end
        end
        if not ready then return false end
        if not e.logged then
            e.logged=true; log('weapon guard armed %s ent=%d zone=%s max=%d parent=%d parent_unit=%d/%08x chain=%s (Immortal; shield excluded)',s.d.resource,s.d.entity,s.zone,s.mx,s.parent.entity,s.parent.unit,s.parent.unit,s.chain)
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
        s.parent,s.chain=parent,chain
        local k=key(d)
        local st=F.states[k] or {d=d}; F.states[k]=st
        st.seen=true; st.hp,st.mx=s.hp,s.mx
        local protected=arm_config(s)
        if not protected then report(d,'protection write incomplete; retrying') end
        if s.hp<=1 and not st.broken then
            st.broken=true; log('weapon failed %s ent=%d hp=%d/%d; disabled until >5%%',F.models[d.resource].name,d.entity,s.hp,s.mx)
        end
        if st.broken then
            if s.hp>s.mx*0.05 then
                if release_ammo(st,s) then
                    st.broken=false
                    log('weapon recovered %s ent=%d hp=%d/%d (>5%%); ammunition restored',F.models[d.resource].name,d.entity,s.hp,s.mx)
                else report(d,'ammunition restore incomplete; retrying') end
            elseif not hold_ammo(st,s) then report(d,'ammunition hold incomplete; retrying') end
        end
        if protected and s.hp<1 then
            -- Use the engine repair to update its HP bookkeeping, at most one HP.
            -- This is floor maintenance outside the shield, not background regeneration.
            local ok,why=R.heal(d,1/s.mx,true)
            if not ok then report(d,'floor maintenance: '..tostring(why)) end
            if ok then
                local fresh=snapshot(d)
                if fresh.hp<1 then report(d,'engine floor readback still below 1 HP; inspect live behavior') end
            end
        end
    end
    function F.step(vehicles)
        if not N.weapon_ready or not R.health or not R.attach then F.close(); return end
        N.win.begin_sample()
        for _, e in pairs(F.configs) do e.users=0 end
        for _, st in pairs(F.states) do st.seen=false end
        for _, v in ipairs(vehicles) do
            if F.models[v.d.resource] then
                local ok,why=pcall(service,v)
                if not ok then report(v.d,tostring(why)) end
            end
        end
        for cfg,e in pairs(F.configs) do
            if e.users==0 and close_config(e) then F.configs[cfg]=nil end
        end
        for k,st in pairs(F.states) do
            if not st.seen then
                local ok,s=pcall(snapshot,st.d,true)
                if ok and release_ammo(st,s) then F.states[k]=nil end
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
                if st.ammo then
                    local ok,s=pcall(snapshot,st.d,true)
                    if ok then release_ammo(st,s) end
                end
            end
        end
        for cfg,e in pairs(F.configs) do if close_config(e) then F.configs[cfg]=nil end end
    end
    function F.reset()
        F.close()
        F.states,F.reports={},{}
        -- Failed config restores remain tracked for retry; never silently abandon them.
    end
    function F.status()
        local n,b=0,0
        for _, st in pairs(F.states) do n=n+1; if st.broken then b=b+1 end end
        log('weapon guard: enabled=%s weapons=%d failed=%d; fail at 1 HP, recover strictly >5%%; shield excluded',tostring(C.exo_weapon_guard),n,b)
        for _, st in pairs(F.states) do
            log('  weapon %s ent=%d hp=%s/%s failed=%s held_ammo=%s',F.models[st.d.resource].name,st.d.entity,tostring(st.hp),tostring(st.mx),tostring(st.broken==true),tostring(st.ammo~=nil))
        end
    end
    return F
end

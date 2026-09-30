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

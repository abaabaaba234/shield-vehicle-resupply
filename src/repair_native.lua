-- Native repair interfaces identified in the user-provided Vehicle Supply Tower 1.0.1.
-- This module uses fixed, guarded call sites on the already validated HUD build.
-- It never scans or patches executable pages. All calls run in the game's Lua update.
return function(N, log)
    local ffi = require('ffi')
    local R = { cache = {}, maps = {}, observations = {}, calls = 0, fixed = 0, next_check = 0 }
    local wheel_names = {'fed0a478', 'f3cb00ad', 'c6bf05a9', 'f12186b7'}
    local U32 = 4294967296
    local signatures = {
        heal = {0x4B9B50, '40 57 48 83 EC 20 48 8B 39 4C 8B 1D ?? ?? ?? ?? 8B 47 08 3B 05 ?? ?? ?? ?? 74 ?? 45 8B 93 ?? ?? ?? ?? 45 33 C0 48 89 5C 24 30 41 8B 9B ?? ?? ?? ?? 0F AF D8 4C 89 74 24 48 45 8D 72 FF 45 85 D2 74 ?? 48 89 6C 24 38 41 8B AB ?? ?? ?? ?? 48 89 74 24 40 49 8B B3 ?? ?? ?? ?? 66 0F 1F 44 00 00 41 8D 14 18 41 8B CE 48 23 D1 44 8B 0C D6 44 3B CD 74 ?? 44 3B C8 74 ?? 41 FF C0 45 3B C2 72 ?? 48 8B 74 24 40 48 8B 6C 24 38 48 8B 5C 24 30 4C 8B 74 24 48 0F 28 D1 8B D0 49 8B CB 48 83 C4 20 5F E9 ?? ?? ?? ??'},
        wheel = {0x11A8490, '48 89 5C 24 18 48 89 6C 24 20 57 48 81 EC C0 00 00 00 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 84 24 B0 00 00 00 8B 41 08 8B EA 3B 05 ?? ?? ?? ?? 48 8B 1D ?? ?? ?? ?? 75 ?? B8 FF FF FF FF EB ?? 44 8B 4B 48 33 D2 44 8B 53 50 44 0F AF D0'},
    }
    local ctypes = {
        heal = 'void (*)(void *, uint32_t, float)',
        query = 'uint64_t (*)(uint32_t, uint32_t, void *)',
        get = 'uint64_t (*)(uint32_t, uint32_t, void *)',
        set = 'uint64_t (*)(uint32_t, uint32_t, void *)',
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
        return {query = rel(p + 0xB3, 3, 7), api = api, get = get, set = set}
    end
    function R.ensure(now)
        if not N.ready then return false end
        if R.base == N.base and now < R.next_check then return R.health ~= nil or R.wheels ~= nil end
        R.base, R.next_check = N.base, now + 10
        N.win.begin_sample()
        local exe_ok, exe = pcall(resolve_exe)
        R.exe = exe_ok and exe or nil
        for name, resolve in pairs({health = resolve_heal, wheels = resolve_wheel}) do
            local ok, value = pcall(resolve)
            R[name] = ok and value or nil
            local status = ok and 'ok' or tostring(value)
            if R[name .. '_status'] ~= status then
                R[name .. '_status'] = status
                log('repair native %s: %s', name, status)
            end
        end
        return R.health ~= nil or R.wheels ~= nil
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
    local function owner(d)
        local g = N.sample_graph()
        local net, hm = g:root('network'), g:root('health')
        g:roundtrip(net, d)
        local i, hd = g:component(hm, d.entity, 0x1030, 0x1048)
        need(i ~= nil and N.same(hd, d) and hd.flags % 2 == 1, 'repair requires current authoritative owner')
        local rec = N.ptr(g:watch(hm + 0x1058, 8), 0) + i * 0x1B8
        need(N.i32(g:read(rec + 0x14, 4), 0) > 0 and N.u32(g:read(rec + 0x19C, 4), 0) == 0, 'repair does not revive dead vehicles')
        g:validate()
        return hm
    end
    function R.heal(d, fraction)
        if not R.health then return false, R.health_status end
        if type(fraction) ~= 'number' or fraction ~= fraction or fraction <= 0 or fraction > 1 then return false, 'invalid repair fraction' end
        local hm = owner(d)
        need(rq(R.health.root) == hm, 'repair manager changed')
        R.invoke('heal', R.health.fn, pointer(hm), d.entity, fraction)
        return true
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
        return {h = h, get = get, set = set}
    end
    local function get_wheel(a, index)
        local b = ffi.new('uint8_t[48]')
        if tonumber(R.invoke('get', a.get, a.h, index, b)) == 0 then return nil end
        local s = ffi.string(b, 48)
        return s:byte(0x29) <= 1 and s or nil
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

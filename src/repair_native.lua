-- Native repair interfaces identified in the user-provided Vehicle Supply Tower 1.0.1.
-- This module uses fixed, guarded call sites on the already validated HUD build.
-- It never scans or patches executable pages. All calls run in the game's Lua update.
return function(N, log)
    local ffi = require('ffi')
    local R = { cache = {}, maps = {}, observations = {}, calls = 0, fixed = 0, legs_fixed = 0, leg_fires_stopped = 0, gait_events = 0, gait_pending = {}, next_check = 0 }
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
    local animation_code = {
        {'game.dll', 0x808810, '48895c2418565741574883ec203b15fdb3c702450fb6f9418bf88bda488bf10f8428010000448b415033d2448b5158440fafd34c89742448458d70ff4585c00f84030100004c8b594848896c24408b6954418bc6428d0c124823c8418b04cb4d8d0ccb3bc574103bc37414ffc2413bd072dfe9cc0000003bc30f85c4000000418b410483f8ff0f84b70000004c8d34c500000000488b4660498b0c068b490c85c90f849c000000488b054adab102488b5018488b8220070000ffd084c00f8480000000488b052edab1028bd7488b4818488b46604c8b8150030000498b0c068b490c41ffd085c0745a4584ff7416488b46604533c9448bc7498b0c068b5108e83c4e7d00488b05edd9b1028bd74c8b4018488b4660498b0c068b490c41ff90700300008b442460ffc883f8017715450fb6cf448bc78bd348c7c1feffffffe83d523e00488b6c24404c8b742448488b5c24504883c420415f5f5ec3'},
        {'game.dll', 0x11234D0, '40574883ec30488bf985d27569895424284533c98854242041b86355119bbaa0000000e8489d0800ba96a83f4a488bcfe86bbb09008b57084533c9488b0dd638200241b8ab1a7850c744242000000000e8eb526efff64714017413f30f101ddd362a014533c08b5708e8a2958affb0014883c4305fc332c04883c4305fc3cccc'},
        {'game.dll', 0x1123560, '40574883ec30488bf985d27569895424284533c98854242041b86355119bbaa0000000e8b89c0800ba5e34d3a1488bcfe8dbba09008b57084533c9488b0d4638200241b8379334b8c744242000000000e85b526efff64714017413f30f101d4d362a014533c08b5708e812958affb0014883c4305fc332c04883c4305fc3cccc'},
        {'helldivers2.exe', 0x9D8C0, '48895c24084889742410574883ec20488b351a2897018bd9488d8ed0000000ff157b8e35018bc325ffff3f003b8698000000720433dbeb1c8bc8488b86a0000000c1eb16381c0175eb488b8688000000488b1cc8488d8ed0000000ff15378e3501488b742438488bc3488b5c24304883c4205fc3'},
        {'helldivers2.exe', 0x201710, '48895c2408574883ec208bfae89fc1e9ff488bc8488bd84c8b0041ff90b00100004885c0750b488b5c24304883c4205fc3488b03488bcbff90b00100008bd7488b4828e8e899ffff488b5c24300fb6c04883c4205fc3'},
        {'helldivers2.exe', 0x201900, '48895c2408574883ec208bda8bf9e8adbfe9ff448bc38bd7488b4818488b5c24304883c4205fe9d5e3f2ff'},
        {'helldivers2.exe', 0x12FD00, '48895c240848896c24104889742418574883ec20488bf1418be88bca8bdae89ddbf6ff488bf84885c0744a488b10488bc8ff92b00100004885c075394c8b07488d542448488bcf41ff90b8010000488b4730488b0848894c2448488d4c2448e89c324900488bd0488d0d32b85301e86d194900eb2cb801000000f00fc186380017008bc0486bc858c784318800010003000000899c313800010089ac313c000100488b5c2430488b6c2438488b7424404883c420'},
        {'helldivers2.exe', 0x1FB140, '4883ec08448b410c4585c07507b0014883c408c3448b59104c03d948891c2433db448bcb0f1f40000f1f840000000000438d0408d1e8413914834d8d14837306448d4801eb057617448bc0453bc177e0'},
        {'helldivers2.exe', 0x2BD9C0, '488b8178010000c3'},
        {'helldivers2.exe', 0x1FEEB0, '4883ec28e807eae9ff4885c00f95c04883c428c3cccccccccccccccccccccccc40534883ec20e8e5e9e9ff488bc8488bd8488b10ff523084c07412488b13488b'},
    }
    local ctypes = {
        animation_event = 'void (*)(void *, uint32_t, uint32_t, bool, uint32_t)',
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
    local function resolve_animation()
        need(R.exe ~= nil, 'animation engine module unavailable')
        for _, span in ipairs(animation_code) do
            local base = span[1] == 'game.dll' and N.base or R.exe.base
            local pattern = span[3]:gsub('..', '%0 ')
            need(matches(base + span[2], pattern), 'animation code guard '..span[1]..string.format('+%X', span[2]))
        end
        local left, right = N.base + 0x1123560, N.base + 0x11234D0
        -- Same dispatcher and manager used by both native leg-damage callbacks.
        local root = rel(left + 0x3B, 3, 7)
        need(root == N.base + 0x3326DE8 and root == rel(right + 0x3B, 3, 7)
            and rel(left + 0x50, 1, 5) == N.base + 0x808810
            and rel(right + 0x50, 1, 5) == N.base + 0x808810, 'animation damage manager differs')
        local resolver = R.exe.base + 0x9D8C0
        local units = rel(resolver + 0xF, 3, 7)
        need(units == R.exe.base + 0x1A100F0, 'animation UnitReference manager differs')
        return {root=root, fn=N.base+0x808810, api=N.base+0x3326308, units=units}
    end
    function R.ensure(now)
        if not N.ready then return false end
        if R.base == N.base and now < R.next_check then return R.health ~= nil or R.wheels ~= nil or R.stats ~= nil end
        local force = R.next_check == 0
        local handle = kernel_ok and kernel.GetModuleHandleA('helldivers2.exe') or nil
        local exe_base = handle ~= nil and tonumber(ffi.cast('uintptr_t', handle)) or nil
        if R.base ~= N.base or R.exe_base ~= exe_base then
            for _, name in ipairs({'health','wheels','stats','attach','bash','effects','animations'}) do R[name]=nil end
            R.exe=nil; functions={}
        end
        R.exe_base=exe_base
        R.base, R.next_check = N.base, now + 10
        N.win.begin_sample()
        if force or not R.exe then
            local exe_ok, exe = pcall(resolve_exe)
            R.exe = exe_ok and exe or nil
        end
        for name, resolve in pairs({health = resolve_heal, wheels = resolve_wheel, stats = resolve_stat, attach = resolve_attach, bash = resolve_bash, effects = resolve_effects, animations = resolve_animation}) do
            if force or not R[name] then
                local ok, value = pcall(resolve)
                R[name] = ok and value or nil
                local status = ok and 'ok' or tostring(value)
                if R[name .. '_status'] ~= status then
                    R[name .. '_status'] = status
                    log('repair native %s: %s', name, status)
                end
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
    function R.arm_parent(d, graph, defer_validation)
        need(R.arm_types[d.resource], 'unsupported arm resource')
        local g = graph or owner_graph(d)
        local pd, why, chain = mounted_parent(g, d)
        -- Guard service validates the combined arm/parent graph before its first edit.
        if not graph or not defer_validation then g:validate() end
        return pd, why, chain
    end
    -- Shared fresh proof for speed, gait and particles; never trust a cached full snapshot.
    local function fully_repaired(d, cfg, zones, config_address, proof)
        if proof then
            need(N.same(proof.d,d) and proof.cfg==cfg and proof.zones==zones and proof.base==N.base, 'leg proof owner changed')
            local g=N.graph(N.win.read,N.base)
            for key,raw in pairs(proof.g.seen) do g.seen[key]=raw end
            for i,w in ipairs(proof.g.watches) do g.watches[i]=w end
            g.calls,g.bytes=proof.g.calls,proof.g.bytes
            return g
        end
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
    function R.leg_proof(d,cfg,zones,config_address)
        local g,why=fully_repaired(d,cfg,zones,config_address)
        if not g then return nil,why end
        return {g=g,d=d,cfg=cfg,zones=zones,base=N.base}
    end
    -- The first float in the guarded 13-float StatModifier row is movement speed.
    function R.fix_leg(d, cfg, zones, write_float, config_address, proof)
        if not R.stats then return false, R.stats_status end
        local g, why = fully_repaired(d, cfg, zones, config_address, proof)
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
    R.effect_cache = {}
    local function effect_access(d, cfg, zones, config_address, proof)
        local g, why = fully_repaired(d, cfg, zones, config_address, proof)
        if not g then return nil, why end
        local fx = R.effects
        local manager = N.ptr(g:watch(fx.root, 8), 0)
        local row, fd = g:component(manager, d.entity, fx.tbl, fx.owners)
        if row == nil then return nil, 'no effect reference row' end
        need(N.same(fd, d) and fd.flags % 2 == 1, 'leg effect owner changed')
        local rows = N.ptr(g:watch(manager + fx.rows, 8), 0) + row * fx.stride
        local net = g:root('network')
        local settings = N.ptr(g:watch(net + 0xF127B8, 8), 0)
        -- Keep the native constant: 0x560 is 1376 (not 1360).
        local count = 0x560
        local cached = R.effect_cache[d.resource]
        local start, ecfg, slot = N.mod64hex(d.resource, count), nil, nil
        if cached and cached.settings == settings then
            local entry = g:watch(cached.slot, 16)
            if N.hex64(entry, 0) == d.resource then
                local index = N.u32(entry, 8)
                need(index < count, 'EffectReference settings index')
                ecfg, slot = settings + 0x5600 + index * 0xF48, cached.slot
            end
        end
        if not ecfg then
            for step = 0, 63 do
                local at = settings + ((start + step) % count) * 16
                local entry = g:watch(at, 16)
                local resource = N.hex64(entry, 0)
                if resource == d.resource then
                    local index = N.u32(entry, 8)
                    need(index < count, 'EffectReference settings index')
                    ecfg, slot = settings + 0x5600 + index * 0xF48, at; break
                elseif resource == '0000000000000000' then break end
            end
        end
        need(ecfg ~= nil, 'no EffectReference configuration')
        local raw = g:watch(ecfg + 8, 32 * 80)
        if not cached or cached.cfg ~= ecfg or cached.raw ~= raw then
            local specs, found = {}, {}
            for i = 0, 31 do
                local setting = raw:sub(i * 80 + 1, (i + 1) * 80)
                local name = string.format('%08x', N.u32(setting, 48))
                if leg_fire[name] then
                    need(not found[name], 'duplicate leg fire name'); found[name] = true
                    need(N.hex64(setting, 0) == '1b9236a0c8137ed1'
                        and string.format('%08x', N.u32(setting, 32)) == leg_fire[name]
                        and N.u32(setting, 68) == 2, 'leg fire configuration differs')
                    specs[#specs + 1] = {name=N.u32(setting,48), offset=i*4}
                end
            end
            if #specs ~= 2 then return nil, 'no recognized leg fire pair' end
            cached = {settings=settings,slot=slot,cfg=ecfg,raw=raw,specs=specs}
            R.effect_cache[d.resource] = cached
            R.effect_scans = (R.effect_scans or 0) + 1
        end
        local particles = {}
        for _, spec in ipairs(cached.specs) do particles[#particles+1]={name=spec.name,at=rows+spec.offset} end
        return {g=g, manager=manager, cfg=ecfg, particles=particles}
    end
    function R.stop_leg_fire(d, cfg, zones, config_address, proof)
        if not R.effects then return false, R.effects_status end
        -- Stop one active leg effect per service. Reacquire ownership/health on
        -- the next service, including when movement speed is already normal.
        local a, why = effect_access(d, cfg, zones, config_address, proof)
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
    local FINE, LEFT_LIMP, RIGHT_LIMP = 0xBDF3A6A1, 0xB8349337, 0x50781AAB
    local function animation_access(d, cfg, zones, config_address, proof)
        local g, why = fully_repaired(d, cfg, zones, config_address, proof)
        if not g then return nil, why end
        local a = R.animations
        local manager = N.ptr(g:watch(a.root, 8), 0)
        local row, owner = g:component(manager, d.entity, 0x48, 0x60)
        need(row ~= nil and N.same(owner, d) and owner.flags % 2 == 1, 'animation owner changed')
        local api = N.ptr(g:watch(a.api, 8), 0)
        api = N.ptr(g:watch(api + 0x18, 8), 0)
        for slot, rva in pairs({[0x350]=0x201710, [0x370]=0x201900, [0x720]=0x1feeb0}) do
            need(N.ptr(g:watch(api + slot, 8), 0) == R.exe.base + rva, 'animation Unit API differs')
        end
        local units = N.ptr(g:watch(a.units, 8), 0)
        local index = d.unit % 0x400000
        need(index < N.u32(g:watch(units + 0x98, 4), 0), 'animation Unit index')
        local generations = N.ptr(g:watch(units + 0xA0, 8), 0)
        need(g:watch(generations + index, 1):byte(1) == math.floor(d.unit / 0x400000) % 256, 'animation Unit generation changed')
        local objects = N.ptr(g:watch(units + 0x88, 8), 0)
        local object = N.ptr(g:watch(objects + index * 8, 8), 0)
        local vtable = N.ptr(g:watch(object, 8), 0)
        need(N.ptr(g:watch(vtable + 0x1B0, 8), 0) == R.exe.base + 0x2BD9C0, 'animation getter differs')
        local controller = N.ptr(g:watch(object + 0x178, 8), 0)
        need(N.ptr(g:watch(controller, 8), 0) == object, 'animation controller owner changed')
        local definition = N.ptr(g:watch(controller + 0x28, 8), 0)
        local header = g:watch(definition, 0x14)
        need(N.u32(header, 0) == 0x1B, 'animation definition version')
        local count, offset = N.u32(header, 4), N.u32(header, 8)
        need(count > 0 and count <= 32 and offset == 0x50, 'animation graph count/layout')
        local ec, eo = N.u32(header, 12), N.u32(header, 16)
        need(ec > 0 and ec <= 256 and eo >= 0x50 and eo < 0x40000, 'animation event list bounds')
        local events, has_fine = g:watch(definition + eo, ec * 4), false
        for i = 0, ec - 1 do if N.u32(events, i*4) == FINE then has_fine = true end end
        need(has_fine, 'animation has no fine event')
        local sizes = g:watch(controller + 0x48, 8)
        need(N.u32(sizes, 0) == count and N.u32(sizes, 4) >= count and N.u32(sizes, 4) <= 64, 'animation state count')
        local active = N.ptr(g:watch(controller + 0x50, 8), 0)
        active = g:watch(active, count * 8)
        local nodes = g:watch(definition + offset, 4 + count * 4)
        need(N.u32(nodes, 0) == count, 'animation graph table count')
        local damaged = 0
        for i = 0, count - 1 do
            local no = N.u32(nodes, 4 + i*4)
            need(no >= 4 + count*4 and no < eo - offset, 'animation node bounds')
            local node = definition + offset + no
            local limit = i+1 < count and definition + offset + N.u32(nodes, 8+i*4) or definition + eo
            need(limit > node and limit <= definition + eo, 'animation node ordering')
            local sc = N.u32(g:watch(node + 8, 4), 0)
            need(sc > 0 and sc <= 64, 'animation node state count')
            local state_offsets = g:watch(node + 12, sc*4)
            local state = N.ptr(active, i*8)
            local state_index
            local function state_at(j)
                need(j >= 0 and j < sc, 'animation transition state index')
                local p = node + N.u32(state_offsets, j*4)
                need(p >= node+12+sc*4 and p+0x38 <= limit, 'animation state bounds')
                return p
            end
            for j = 0, sc - 1 do if state_at(j) == state then state_index = j end end
            need(state_index ~= nil, 'animation active state outside graph')
            local function transitions(p)
                local h = g:watch(p+0x28, 16)
                local n, off, tn, to = N.u32(h,0), N.u32(h,4), N.u32(h,8), N.u32(h,12)
                need(n <= 64 and tn <= 64, 'animation transition count')
                if n == 0 then return {} end
                need(off >= 0x38 and p+off+n*8 <= limit and to >= 0x38 and p+to+tn*16 <= limit, 'animation transition bounds')
                local ev, tr, result = g:watch(p+off,n*8), g:watch(p+to,tn*16), {}
                for j = 0, n - 1 do
                    local name, k = N.u32(ev,j*8), N.u32(ev,j*8+4)
                    need(k < tn and result[name] == nil, 'animation event transition index')
                    local target = N.u32(tr,k*16)
                    need(target < sc, 'animation transition destination')
                    result[name] = target
                end
                return result
            end
            local current = transitions(state)
            if current[FINE] ~= nil then
                local normal = transitions(state_at(current[FINE]))
                -- Verify the actual inverse of a leg-damage transition. Other
                -- graph states with an unrelated fine event are left alone.
                if normal[LEFT_LIMP] == state_index or normal[RIGHT_LIMP] == state_index then damaged = damaged + 1 end
            end
        end
        return {g=g,manager=manager,controller=controller,definition=definition,damaged=damaged}
    end
    function R.fix_gait(d, cfg, zones, config_address, now, proof)
        if not R.animations then return false, R.animations_status end
        local a, why = animation_access(d, cfg, zones, config_address, proof)
        if not a then return false, why end
        local key = d.entity..':'..d.unit..':'..d.goid..':'..d.resource
        if a.damaged == 0 then
            a.g:validate()
            if R.gait_pending[key] then
                R.gait_pending[key] = nil
                log('exo gait state normal %s ent=%d (animation readback)', d.resource, d.entity)
            end
            return false, 'no limp animation state'
        end
        local pending = R.gait_pending[key]
        if pending and pending.controller == a.controller and now < pending.next_try then return false, 'gait event pending' end
        a.g:validate()
        need(rq(R.animations.root) == a.manager, 'animation manager changed')
        R.invoke('animation_event', R.animations.fn, pointer(a.manager), d.entity, FINE, false, 1)
        R.gait_events = R.gait_events + 1
        R.gait_pending[key] = {controller=a.controller,next_try=now+2}
        log('exo gait event sent %s ent=%d states=%d event=fine (native animation)', d.resource, d.entity, a.damaged)
        return true
    end
    local query_buffer,wheel_buffer=ffi.new('uint8_t[128]'),ffi.new('uint8_t[48]')
    local function wheel_access(d)
        need(R.wheels ~= nil, R.wheels_status or 'wheel interface unavailable')
        owner(d)
        local query_table = rq(R.wheels.query)
        local query = query_table and rq(query_table)
        need(query and in_engine(query), 'wheel query function unavailable')
        local buffer=query_buffer;ffi.fill(buffer,128)
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
        local b=wheel_buffer;ffi.fill(b,48)
        if tonumber(R.invoke('get', a.get, a.h, index, b)) == 0 then return nil end
        local s = ffi.string(b, 48)
        return s:byte(0x29) <= 1 and s or nil
    end
    -- Runtime VRW centres identify physical wheels independently of Health order.
    -- Only the two known FRV resources and the captured axle/centre schema qualify.
    R.wheel_layouts={}
    function R.tyre_snapshot(d,indices)
        need(d.resource=='9b2140378640432e' or d.resource=='cc21c7ffd3ebefb9','unsupported tyre resource')
        local a=wheel_access(d); local values,raws={},{}
        local header=read(a.header,24);need(header,'wheel resource offsets unreadable')
        for i=0,3 do
            local off=N.u32(header,8+i*4)
            need(off and off>=24 and off<=0x10000,'wheel resource offset')
            raws[i+1]=read(a.header+off,24);need(raws[i+1],'wheel centre unreadable')
        end
        local signature=header..table.concat(raws)
        local cached=R.wheel_layouts[a.header]
        if not cached or cached.signature~=signature then
            local map,seen={},{}
            for i=0,3 do
                local raw=raws[i+1];local f=ffi.cast('const float *',raw)
                local x,y,z=tonumber(f[3]),tonumber(f[4]),tonumber(f[5])
                local axle,steered=N.u32(raw,0),N.u32(raw,4)
                need(x==x and y==y and z==z and math.abs(x)>=0.5 and math.abs(x)<=3
                    and math.abs(y)>=0.5 and math.abs(y)<=4 and math.abs(z)<=1,'unknown FRV wheel centre')
                need((axle==1 and steered==0 and y>0) or (axle==2 and steered==1 and y<0),'unknown FRV axle layout')
                local hash=y>0 and (x<0 and 'fed0a478' or 'f3cb00ad') or (x<0 and 'c6bf05a9' or 'f12186b7')
                need(not seen[hash],'duplicate FRV wheel location');seen[hash]=true;map[i]=hash
            end
            local count=0;for _ in pairs(R.wheel_layouts) do count=count+1 end
            if count>=8 then R.wheel_layouts={} end
            cached={signature=signature,map=map};R.wheel_layouts[a.header]=cached
            R.wheel_layout_scans=(R.wheel_layout_scans or 0)+1
        end
        for i=0,3 do
            if not indices or indices[i] then
                values[i]=get_wheel(a,i);need(values[i],'wheel parameters unavailable')
            end
        end
        return {h=a.h,map=cached.map,values=values}
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
    function R.prune(vehicles)
        local live,gait={},{}
        for _,v in ipairs(vehicles) do
            local d=v.d;live[d.entity..':'..d.goid..':'..d.unit..':'..d.resource]=true
            gait[d.entity..':'..d.unit..':'..d.goid..':'..d.resource]=true
        end
        for k in pairs(R.observations) do if not live[k] then R.observations[k]=nil end end
        for k in pairs(R.gait_pending) do if not gait[k] then R.gait_pending[k]=nil end end
    end
    function R.reset() R.cache, R.maps, R.observations, R.gait_pending, R.effect_cache, R.wheel_layouts = {}, {}, {}, {}, {}, {}; functions = {} end
    R.signatures = signatures
    if rawget(_G, "__SVR_TEST") then R.resolve_animation = resolve_animation end -- read-only metadata used by offline guard tests
    return R
end

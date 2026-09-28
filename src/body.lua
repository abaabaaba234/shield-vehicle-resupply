-- ===========================================================================
-- Shield Vehicle Resupply — main body
-- 读取层来自 DRIVER HUD / HUD（上面拼接进来的 N），这里只加了：
--   * 遍历 Health / Magazine / Rounds 组件表
--   * 坐标（UnitSynchronizer 或 tagged UnitReference）
--   * 护盾检测（World.units + 资源 hash）
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
    tires          = false,  -- FRV 爆胎修复（实验性）
    net_heal       = true,   -- 用引擎 set_game_object_field 给坦克/FRV 车体（HUD 显示的网络血量）回血（v0.8b 实测 FRV 可行）
    hull_zones     = true,   -- 坦克/FRV：被打爆部位的 HP 数值也回满（模型不变），车体血量才会回（v0.8 推断：车体 = 上限 - 各部位损失）
    authority_only = true,   -- 只改本机有权威的组件（descriptor flags bit0）
    shadow         = true,   -- v0.12：自动学习并同步血量的影子字段（修好的血下一次受伤就消失的问题）
    hunt           = true,   -- v0.12c：每辆载具第一次给主血量回血时自动 hunt（扫描内存找游戏另存的血量）
    hunt_ms        = 3,      -- v0.12g：hunt 扫描分到每帧做，每帧至少用这么多毫秒（原来一次扫完会卡 4~5 秒）
    hunt_ms_max    = 12,     -- v0.12h：落后于进度时每帧最多用这么多毫秒
    hunt_secs      = 15,     -- v0.12h：目标扫描时长（秒）。按进度自动调每帧用时，一般 15~20 秒扫完
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
                'radius=14.5\nshield_duration=45\nspot=0\ntest=0\nrevive=0\nnet_heal=1\nhull_zones=1\ntires=0\nammo=1\nexo_heal=0.04\ntank_heal=0.03\nfrv_heal=0.05\n',
                'ammo_rate=0.10\ncooldown=2\nauthority_only=1\nshadow=1\nhunt=1\n')
            f:close()
        end
        return
    end
    C.shield, C.weapon, C.ammo_max = { ['ed13ddc480ec6910'] = true }, {}, {}
    for line in f:lines() do
        line = line:gsub('^\239\187\191', ''):gsub('#.*', ''):gsub('%s', '')
        local k, v = line:match('^([%w_]+)=(.+)$')
        if k == 'shield' or k == 'weapon' then
            local h = v:lower():gsub('^0x', '')
            if #h == 16 and not h:find('[^%x]') and not (k == 'shield' and POD[h]) then C[k][h] = true end
        elseif k == 'ammo_max' then
            local key, n = v:lower():match('^(%x+:%w+)=(%d+)$')
            if key then C.ammo_max[key] = tonumber(n) end
        elseif k and type(C[k]) == 'boolean' then C[k] = (v == '1' or v == 'true')
        elseif k and type(C[k]) == 'number' and tonumber(v) then C[k] = tonumber(v) end
    end
    f:close()
    local n = 0; for _ in pairs(C.shield) do n = n + 1 end
    log('settings: radius=%.1f test=%s revive=%s hull_zones=%s tires=%s ammo=%s shields=%d', C.radius, tostring(C.test), tostring(C.revive), tostring(C.hull_zones), tostring(C.tires), tostring(C.ammo), n)
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
    -- hunt 诊断用：进程里所有已提交、PAGE_READWRITE、MEM_PRIVATE 的内存区
    function W.rw_regions()
        local out, at = {}, 65536
        if not ok then return out end
        for _ = 1, 1000000 do
            if at >= 140737488355328 then break end
            if tonumber(k.VirtualQuery(ffi.cast('const void *', at), ffi.cast('void *', mbi), 48)) ~= 48 then break end
            local b = ffi.string(mbi, 48)
            local start, size, state, prot, typ = ptr(b, 0), ptr(b, 24), u32(b, 32), u32(b, 36), u32(b, 40)
            if size == 0 or start + size <= at then break end
            if state == 0x1000 and prot == 4 and typ == 0x20000 then out[#out + 1] = { start, size } end
            at = start + size
        end
        return out
    end
    function W.rpm(p, buf, n)
        if not ok then return false end
        got[0] = 0
        return k.ReadProcessMemory(k.GetCurrentProcess(), ffi.cast('const void *', p), buf, n, got) ~= 0 and tonumber(got[0]) == n
    end
end

local TEST_HOOK = rawget(_G, '__SVR_TEST')  -- 仅离线测试用

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
local function reset_context()
    S.vehicles, S.weapons, S.shields, S.seen_ent, S.spotted = {}, {}, {}, nil, {}
    S.last_total, S.last_hit, S.frac, S.ammo_max, S.reported, S.next_roster = {}, {}, {}, {}, {}, 0
    S.shield_born, S.shield_expired, S.vstate, S.want_units = {}, {}, {}, nil
    S.hunt_n, S.scan = 0, nil
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
        local sk = d.entity .. ':' .. d.goid .. ':' .. d.resource
        local v = S.vstate[sk] or { kind = KIND[d.resource] }
        S.vstate[sk] = v; v.d = d; v.alive_at = S.clock
        vehicles[#vehicles + 1] = v
        if d.unit ~= 0 and d.unit ~= 4294967295 then by_unit[d.unit] = by_unit[d.unit] or v end
        by_entity[d.entity] = v
    end
    S.vehicles = vehicles
    for k, v in pairs(S.vstate) do if v.alive_at ~= S.clock then S.vstate[k] = nil end end
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


-- ---------------------------------------------------------------------------
-- 影子字段（v0.12）
-- 现象：护盾里修好的血，下一次受伤就整段消失。说明游戏受伤时不是从 +0x14 / +0xF8 往下减，
-- 而是用记录里另一个我们没写的值（血量镜像、累计伤害或血量比例）重新算。
-- filediver 的 datalibrary 只有配置（HealthComponent：上限、回复速度、RegenerationSegments…），
-- 没有 0x1B8 运行时记录的布局，所以在游戏里自动学：
--   1. 每次写血时，记下记录里其它仍等于 旧血量 / 上限-旧血量 / 旧血量÷上限 的 i32/f32 字段（候选）
--   2. 之后游戏把血量改低时，哪个候选同时变成了对应的新值，它就是影子字段
--   3. 按资源 hash 存进 shield_resupply_learned.txt；以后每次写血同步写影子字段（同样写前比对、写后读回）
-- 学不到时把受伤前后整条记录的差异写进日志（heal lost …），用来人工定位。
-- ---------------------------------------------------------------------------
local LEARN = DIR .. 'shield_resupply_learned.txt'
local SHADOW = {}   -- SHADOW[资源][目标偏移] = { {o=偏移, f=是否 float, m='m' 镜像 | 'd' 伤害 | 'r' 比例}, ... }
local MODE_NAME = { m = 'mirror', d = 'damage', r = 'ratio' }
local function shadow_add(res, t, o, f, m)
    SHADOW[res] = SHADOW[res] or {}
    local list = SHADOW[res][t] or {}
    SHADOW[res][t] = list
    for _, s in ipairs(list) do if s.o == o then return false end end
    list[#list + 1] = { o = o, f = f, m = m }
    return true
end
local function load_shadows()
    SHADOW = {}
    local f = io.open(LEARN, 'r')
    if not f then return end
    for line in f:lines() do
        local res, t, o, ty, m = line:match('^shadow=(%x+):(%x+):(%x+):([if]):([mdr])')
        if res and #res == 16 then shadow_add(res:lower(), tonumber(t, 16), tonumber(o, 16), ty == 'f', m) end
    end
    f:close()
end
local function f32(s, o) return ffi.cast('const float *', s)[o / 4] end
-- 血量字段本身（主血量、38 个部位）和损坏状态字不当候选
local function is_slot(o) return o == 0x14 or (o >= 0x20 and o < 0x30) or (o >= 0xF8 and o < 0xF8 + 38 * 4) end
local function near(x, y, tol) return x == x and math.abs(x - y) < tol end  -- x == x 排除 NaN
local function shadow_value(m, max, hp) if m == 'm' then return hp elseif m == 'd' then return max - hp end return hp / max end
local function shadow_match(s, data, max, hp)
    local want = shadow_value(s.m, max, hp)
    if not s.f then return i32(data, s.o) == want end
    return near(f32(data, s.o), want, s.m == 'r' and 0.002 or 1)
end
local function candidates(data, A, max, known)
    local out = {}
    for o = 0, 0x1B4, 4 do
        if not is_slot(o) and not known[o] then
            local c
            for _, m in ipairs({ 'm', 'd', 'r' }) do
                local want = shadow_value(m, max, A)
                if want ~= 0 and (m ~= 'r' or (want > 0.001 and want < 0.999)) then
                    if m ~= 'r' and i32(data, o) == want then c = { o = o, f = false, m = m }; break end
                    if near(f32(data, o), want, m == 'r' and 0.002 or 1) then c = { o = o, f = true, m = m }; break end
                end
            end
            if c then
                c.raw = data:sub(o + 1, o + 4); out[#out + 1] = c
                if #out > 24 then return {} end  -- 太多巧合（比如血量很小），这次不学
            end
        end
    end
    return out
end
local function known_of(list)
    local k = {}
    if list then for _, s in ipairs(list) do k[s.o] = true end end
    return k
end
local function dump_diff(before, after)
    local out = {}
    for o = 0, 0x1B4, 4 do
        if before:sub(o + 1, o + 4) ~= after:sub(o + 1, o + 4) then
            out[#out + 1] = string.format('+%x %d->%d (%.3g->%.3g)', o, i32(before, o), i32(after, o), f32(before, o), f32(after, o))
        end
    end
    return table.concat(out, ' ')
end

-- 每次读到记录时（写血之前）核对上次写血后的候选
local function check_pending(v, data)
    local pend = v.pend
    if not pend then return end
    local res = v.d.resource
    for t, p in pairs(pend) do
        local now = i32(data, t)
        if now == p.B then
            -- 游戏没动血量，候选自己变了就不是影子
            for i = #p.cands, 1, -1 do
                local c = p.cands[i]
                if data:sub(c.o + 1, c.o + 4) ~= c.raw then table.remove(p.cands, i) end
            end
            p.snap = data
            if S.clock - p.t0 > 180 then pend[t] = nil end
        else
            pend[t] = nil
            if now < p.B then
                local learned = 0
                for _, c in ipairs(p.cands) do
                    if data:sub(c.o + 1, c.o + 4) ~= c.raw and shadow_match(c, data, p.max, now) then
                        if shadow_add(res, t, c.o, c.f, c.m) then
                            learned = learned + 1
                            local fh = io.open(LEARN, 'a')
                            if fh then fh:write(string.format('shadow=%s:%x:%x:%s:%s\n', res, t, c.o, c.f and 'f' or 'i', c.m)); fh:close() end
                            log('shadow learned %s %s hp=+%x field=+%x %s %s (%d -> %d)', v.kind, res, t, c.o,
                                c.f and 'f32' or 'i32', MODE_NAME[c.m], p.B, now)
                        end
                    end
                end
                -- 已学到的影子跟着变了 = 正常受伤，不是“修的血消失”
                local followed = false
                local list = SHADOW[res] and SHADOW[res][t]
                if list then for _, s in ipairs(list) do if shadow_match(s, data, p.max, now) then followed = true end end end
                if learned == 0 and not followed and now <= p.A then
                    v.lost_logs = (v.lost_logs or 0) + 1
                    if v.lost_logs <= 5 then
                        log('heal lost %s %s ent=%d hp=+%x: before heal %d, healed to %d, after hit %d (max %d); changed: %s',
                            v.kind, res, v.d.entity, t, p.A, p.B, now, p.max, dump_diff(p.snap, data))
                    end
                end
            end
        end
    end
end

local hunt_sync, hunt_zsync  -- 见下面的 hunt
-- 写血量字段，并同步已学到的影子字段；没学到时登记候选
local function write_hp(v, rec, data, t, old, new, max)
    if not W.i32(rec + t, old, new) then return false end
    if t == 0x14 then hunt_sync(v, old, new) elseif t >= 0xF8 then hunt_zsync(v, t, old, new) end
    if not C.shadow then return true end
    local res = v.d.resource
    local list = SHADOW[res] and SHADOW[res][t]
    if list then
        for _, s in ipairs(list) do
            if shadow_match(s, data, max, old) then
                local want = shadow_value(s.m, max, new)
                if s.f then W.f32(rec + s.o, data:sub(s.o + 1, s.o + 4), want)
                else W.i32(rec + s.o, i32(data, s.o), want) end
            elseif not S.reported['sm' .. res .. t .. ':' .. s.o] then
                S.reported['sm' .. res .. t .. ':' .. s.o] = true
                log('shadow mismatch %s hp=+%x field=+%x: hp %d, field %d / %.3f (skipped)', res, t, s.o, old, i32(data, s.o), f32(data, s.o))
            end
        end
    end
    v.pend = v.pend or {}
    local p = v.pend[t]
    if p then p.B = new
    else
        v.pend[t] = { A = old, B = new, max = max, t0 = S.clock, snap = data, cands = candidates(data, old, max, known_of(list)) }
    end
    return true
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
    return rec, data, zc, hd
end

-- ---------------------------------------------------------------------------
-- hunt（v0.12b 诊断 + 实验修复）
-- v0.12 实测：受伤前后 Health 记录里只有 +0x14 / 部位血量 / +0x1A4（距上次受伤的计时器）变了，
-- 而受伤后的血量 = 修之前的血量 − 伤害（机甲 1543→修到 1800→挨一下 1444，部位 451→550→352）。
-- 所以游戏在记录之外另存了一份血量，扣血时用它算完再盖回记录。用 Cheat Engine 式两段扫描找这份拷贝：
--   1. hunt：对正在回血的载具，扫描进程里所有 PAGE_READWRITE 私有内存，记下等于修前血量 A 的 i32/float，
--      以及等于 上限−A 的 i32/float（可能存的是“已受伤害”）
--   2. 之后游戏每扣一次血，只留下跟着变成新值的地址
--   3. 剩下 1~8 个时，回血时同步写这些地址（写前比对、写后读回、只写 PAGE_READWRITE），日志 `hunt fix`
-- ---------------------------------------------------------------------------
local H = nil
local hunt_dump, zone_blocks, hunt_run
local HUNT_CAP = 400000
local function fbits(x)
    local f = ffi.new('float[1]', x)
    return ffi.cast('int32_t *', f)[0]
end
local HUNT_KIND = { 'i32 hp', 'i32 max-hp', 'f32 hp', 'f32 max-hp' }
-- 第 k 种候选在血量为 hp 时应该是什么值（int32 位模式的范围）
local function hunt_range(kind, hp, max)
    local x = (kind == 2 or kind == 4) and max - hp or hp
    if kind <= 2 then return x, x end
    return fbits(math.max(0, x - 1)), fbits(x + 1)
end
local function hex_around(a)
    local buf = ffi.new('uint8_t[64]')
    if not W.rpm(a - 32, buf, 64) then return '?' end
    local s = ffi.string(buf, 64)
    local row = {}
    for o = 0, 60, 4 do row[#row + 1] = string.format(o == 32 and '[%08x]' or '%08x', u32(s, o)) end
    return table.concat(row, ' ')
end
local function where(a)
    local out = {}
    if N.base and N.image_size and a >= N.base and a < N.base + N.image_size then out[#out + 1] = string.format('module+%x', a - N.base) end
    if H.rec and math.abs(a - H.rec) < 0x100000 then out[#out + 1] = string.format('rec%s0x%x', a < H.rec and '-' or '+', math.abs(a - H.rec)) end
    if H.hm and math.abs(a - H.hm) < 0x1000000 then out[#out + 1] = string.format('hm%s0x%x', a < H.hm and '-' or '+', math.abs(a - H.hm)) end
    return table.concat(out, ' ')
end

local function hunt_report(tag)
    local n, parts = 0, {}
    for k = 1, 4 do
        local l = H.lists[k]
        n = n + #l
        parts[#parts + 1] = string.format('%s=%d%s', HUNT_KIND[k], #l, H.trunc[k] and '(满)' or '')
    end
    log('hunt %s: %s', tag, table.concat(parts, ' '))
    if n > 0 and n <= 16 then
        for k = 1, 4 do
            for _, a in ipairs(H.lists[k]) do
                log('  hunt %s @%x %s  %s', HUNT_KIND[k], a, where(a), hex_around(a))
            end
        end
    end
    return n
end

-- v0.12g：扫描放进协程，每帧只做一小段（update 里 scan_step 推进）。
-- v0.12h：每帧用时按进度调：进度跟上 hunt_secs 的节奏就只用 hunt_ms，落后了最多用到 hunt_ms_max。
-- 扫描期间载具挨了打（游戏那份拷贝变了），这次扫描作废，下次回血再来。
local function scan_yield(done, all)
    local sc = S.scan
    if not (sc and sc.t0 and coroutine.running() == sc.co) then return end
    local used = os.clock() - sc.t0
    if used < C.hunt_ms / 1000 then return end
    local behind = all and all > 0 and done / all < (os.clock() - sc.start) / math.max(1, C.hunt_secs)
    if behind and used < C.hunt_ms_max / 1000 then return end
    coroutine.yield()
end

local function region_bytes(regions)
    local n = 0
    for _, r in ipairs(regions) do n = n + r[2] end
    return n
end

function hunt_run(v)
    local p = v.pend[0x14]
    local A, max = p.A, p.max
    local rec, data = read_record(v)
    local hm = ptr(N.win.read(N.base + N.roots.health, 8) or ('\0'):rep(8), 0)
    H = { v = v, A = A, max = max, rec = rec, hm = hm, last = i32(data, 0x14), hits = 0, lists = {}, trunc = {}, scanning = true }
    v.H = H  -- 每辆载具各自一份（v0.12f：原来全局只有一份，机甲占了，坦克/小车从没扫过）
    H.zlast, H.zbase = {}, {}
    local zb, nz = {}, 0
    if v.zcache then
        for _, z in ipairs(v.zcache.zones) do
            local t = 0xF8 + 4 * z.i
            H.zlast[t] = i32(data, t)
            -- 游戏那份拷贝里是“上次受伤后/开始修之前”的值
            H.zbase[t] = (v.pend[t] and v.pend[t].A) or i32(data, t)
            zb[z.i] = H.zbase[t]
            nz = math.max(nz, z.i + 1)
        end
    end
    local zb0 = nz >= 2 and zb[0] or nil
    local blocks, nb = {}, 0
    local CH = 1048576
    local buf = ffi.new('uint8_t[?]', CH)
    local bufa = tonumber(ffi.cast('uintptr_t', buf))
    local ip = ffi.cast('const int32_t *', buf)
    local lo, hi = {}, {}
    for k = 1, 4 do lo[k], hi[k] = hunt_range(k, A, max); H.lists[k] = {} end
    local l1, l2, l3, l4 = H.lists[1], H.lists[2], H.lists[3], H.lists[4]
    local n1, n2, n3, n4 = 0, 0, 0, 0
    local a1, a2, f3a, f3b, f4a, f4b = lo[1], lo[2], lo[3], hi[3], lo[4], hi[4]
    local total, t0 = 0, os.clock()
    local regions = W.rw_regions()
    local all, done = region_bytes(regions), 0
    for _, r in ipairs(regions) do
        local at, finish = r[1], r[1] + r[2]
        while at < finish do
            local n = math.min(CH, finish - at)
            -- 跳过自己的扫描缓冲区和载具记录本身
            if at + n > bufa and at < bufa + CH then
            elseif W.rpm(at, buf, n) then
                total = total + n
                for i = 0, n / 4 - 1 do
                    local x = ip[i]
                    if x == zb0 and i + nz <= n / 4 then
                        local j = 1
                        while j < nz and ip[i + j] == zb[j] do j = j + 1 end
                        if j == nz and nb < 64 then nb = nb + 1; blocks[nb] = at + 4 * i end
                    end
                    if x == a1 then
                        if n1 < HUNT_CAP then n1 = n1 + 1; l1[n1] = at + 4 * i end
                    elseif x == a2 then
                        if n2 < HUNT_CAP then n2 = n2 + 1; l2[n2] = at + 4 * i end
                    elseif x >= f3a and x <= f3b then
                        if n3 < HUNT_CAP then n3 = n3 + 1; l3[n3] = at + 4 * i end
                    elseif x >= f4a and x <= f4b then
                        if n4 < HUNT_CAP then n4 = n4 + 1; l4[n4] = at + 4 * i end
                    end
                end
            end
            at = at + n
            done = done + n
            scan_yield(done, all)
        end
    end
    H.scanning = nil
    for k, n in ipairs({ n1, n2, n3, n4 }) do H.trunc[k] = n >= HUNT_CAP end
    H.nz = nz
    if nz >= 2 then zone_blocks(blocks, rec, '扫描时') end
    for k = 1, 4 do
        local l, out = H.lists[k], {}
        for _, a in ipairs(l) do if a < rec or a >= rec + 0x1B8 then out[#out + 1] = a end end
        H.lists[k] = out
    end
    log('hunt armed %s %s ent=%d: 修前血量 %d / 上限 %d，扫描 %.0f MB 用时 %.1f s（分 %d 帧）。现在让它挨一下打（留在护盾里）',
        v.kind, v.d.resource, v.d.entity, A, max, total / 1048576, os.clock() - t0, S.scan and S.scan.frames or 1)
    hunt_report('候选')
end

-- 开一个扫描任务（同一时间只跑一个）；先在这一帧跑一个时间片
local function scan_start(fn, h)
    S.scan = { co = coroutine.create(fn), h = h, frames = 0, start = os.clock() }
end

local function scan_step()
    local sc = S.scan
    if not sc then return end
    sc.frames = sc.frames + 1
    sc.t0 = os.clock()
    H = sc.h
    local ok, e = coroutine.resume(sc.co)
    if S.scan == sc then sc.h = H end
    if not ok then log('hunt: %s', tostring(e)); if sc.h then sc.h.scanning, sc.h.zscanning = nil, nil end end
    if (not ok or coroutine.status(sc.co) == 'dead') and S.scan == sc then S.scan = nil end
end

local function cmd_hunt(arg, v)
    if arg == 'off' then for _, x in pairs(S.vstate) do x.H = false end; H = nil; S.scan = nil; log('hunt off'); return end
    if S.scan then log('hunt: 上一次扫描还没做完'); return end
    if not v then for _, x in ipairs(S.vehicles) do if x.pend and x.pend[0x14] then v = x; break end end end
    if not v then
        log('hunt: 没有正在回血的载具。先让载具掉血、开进护盾里修一会（主血量涨了），再发 hunt，然后让它挨一下打')
        return
    end
    scan_start(function() hunt_run(v) end, nil)
    scan_step()
end

-- 游戏扣了血：只留下跟着变成新血量的地址
local function hunt_filter(hp)
    local pbuf = ffi.new('uint8_t[4096]')
    local pip = ffi.cast('const int32_t *', pbuf)
    for k = 1, 4 do
        local lo, hi = hunt_range(k, hp, H.max)
        local page, okp, out = -1, false, {}
        for _, a in ipairs(H.lists[k]) do
            local pg = a - a % 4096
            if pg ~= page then page = pg; okp = W.rpm(pg, pbuf, 4096) end
            if okp then
                local x = pip[(a - pg) / 4]
                if x >= lo and x <= hi then out[#out + 1] = a end
            end
        end
        H.lists[k] = out
    end
    H.hits = H.hits + 1
    local n = hunt_report(string.format('第 %d 次受伤后 (hp=%d)', H.hits, hp))
    if n == 0 then
        log('hunt %s: 没找到 i32/float 形式的拷贝（可能是量化后的网络值），hunt 结束', H.v.kind)
        H.v.H = false; H = nil
    elseif n <= 8 and not H.fix then
        H.fix = true
        log('hunt fix: 以后回血会同步写这 %d 个地址。修满后再挨一下，看血是否还会掉回去', n)
        for k = 1, 4 do for _, a in ipairs(H.lists[k]) do hunt_dump(a) end end
    end
end

-- ---------------------------------------------------------------------------
-- 部位血量（v0.12e）
-- v0.12d 实测：游戏扣部位血用的拷贝和 Health 记录布局一样（部位数组也在 +0xF8），
-- 里面存的是“上次受伤后/开始修之前”的部位血量（修过的部位在拷贝里还是旧值），一挨打就用它减伤害再盖回记录。
-- 所以按整段找：hunt 扫描时顺便找连续 nz 个 i32 = 各部位的修前值（H.zbase）的位置（不是按单个值找，误中极少）。
-- 之后每次有部位掉血，把掉血部位的基准值更新成新值，只留下整段仍然等于基准值的块；
-- 过滤后剩 1~4 块时启用同步：回血写记录的部位时，块里对应位置等于基准值才改成新值（写前比对、写后读回）。
-- 找不到时在下一次掉血时全内存再找（每局最多 3 次，每次卡 1~2 秒）。
-- ---------------------------------------------------------------------------
function hunt_dump(a)
    local buf = ffi.new('uint8_t[512]')
    if not W.rpm(a - 0x100, buf, 512) then return end
    local s = ffi.string(buf, 512)
    log('  hunt dump @%x %s (-0x100..+0x100):', a, where(a))
    for r = 0, 448, 64 do
        local row = {}
        for o = r, r + 60, 4 do row[#row + 1] = string.format(o == 0x100 and '[%08x]' or '%08x', u32(s, o)) end
        log('    %s%03x %s', r < 0x100 and '-' or '+', math.abs(r - 0x100), table.concat(row, ' '))
    end
end


local function zone_vec()
    local zb = {}
    for i = 0, H.nz - 1 do zb[i] = H.zbase[0xF8 + 4 * i] end
    return zb
end

-- 块里的部位值是否整段等于基准值
local function block_ok(b)
    local n = H.nz
    local buf = ffi.new('uint8_t[?]', 4 * n)
    if not W.rpm(b, buf, 4 * n) then return false end
    local ip = ffi.cast('const int32_t *', buf)
    for i = 0, n - 1 do
        local want = H.zbase[0xF8 + 4 * i]
        if want and ip[i] ~= want then return false end
    end
    return true
end

function zone_blocks(list, rec, tag)
    local out = {}
    for _, b in ipairs(list) do if b ~= rec + 0xF8 then out[#out + 1] = b end end
    H.blocks, H.bfix, H.bhits = out, false, 0
    log('hunt zone %s: %d 块部位数组 = 修前值', tag, #out)
    for n, b in ipairs(out) do
        if n > 8 then break end
        log('  hunt zone block @%x %s  %s', b, where(b), hex_around(b + 0x20))
    end
end

-- 全内存找整段部位数组
local function block_scan(rec)
    local zb, nz = zone_vec(), H.nz
    for i = 0, nz - 1 do if zb[i] == nil then return {} end end
    local zb0 = zb[0]
    local CH = 1048576
    local buf = ffi.new('uint8_t[?]', CH)
    local bufa = tonumber(ffi.cast('uintptr_t', buf))
    local ip = ffi.cast('const int32_t *', buf)
    local blocks, t0, total = {}, os.clock(), 0
    local regions = W.rw_regions()
    local all, done = region_bytes(regions), 0
    for _, r in ipairs(regions) do
        local at, finish = r[1], r[1] + r[2]
        while at < finish do
            local n = math.min(CH, finish - at)
            if at + n > bufa and at < bufa + CH then
            elseif W.rpm(at, buf, n) then
                total = total + n
                for i = 0, n / 4 - nz do
                    if ip[i] == zb0 then
                        local j = 1
                        while j < nz and ip[i + j] == zb[j] do j = j + 1 end
                        if j == nz and #blocks < 64 then blocks[#blocks + 1] = at + 4 * i end
                    end
                end
            end
            at = at + n
            done = done + n
            scan_yield(done, all)
        end
    end
    log('hunt zone scan: %.0f MB 用时 %.1f s（分 %d 帧）', total / 1048576, os.clock() - t0, S.scan and S.scan.frames or 1)
    return blocks
end

-- 有部位掉血：更新基准值，过滤块
local function hunt_zones(v, data, rec)
    if not (H.nz and H.nz >= 2) then return end
    local dropped = {}
    for i = 0, H.nz - 1 do
        local t = 0xF8 + 4 * i
        local val = i32(data, t)
        if H.zlast[t] and val < H.zlast[t] then
            dropped[#dropped + 1] = string.format('+%x %d->%d', t, H.zlast[t], val)
            H.zbase[t] = val
        end
        H.zlast[t] = val
    end
    if #dropped == 0 or H.zscanning then return end
    local desc = table.concat(dropped, ' ')
    if H.blocks and #H.blocks > 0 then
        local out = {}
        for _, b in ipairs(H.blocks) do if block_ok(b) then out[#out + 1] = b end end
        H.blocks = out
        H.bhits = H.bhits + 1
        if #out > 0 and #out <= 4 and not H.bfix then H.bfix = true end
        log('hunt zone 掉血 (%s)：剩 %d 块%s', desc, #out, H.bfix and '，已启用同步' or '')
        for _, b in ipairs(out) do log('  hunt zone block @%x %s  %s', b, where(b), hex_around(b + 0x20)) end
        if #out > 0 then return end
    end
    if S.scan then return end  -- 别的载具正在扫，下次掉血再说
    H.zscans = (H.zscans or 0) + 1
    if H.zscans > 3 then
        if H.zscans == 4 then log('hunt zone: 全内存扫描次数用完，放弃部位同步') end
        return
    end
    H.zscanning = true
    scan_start(function()
        local b = block_scan(rec)
        zone_blocks(b, rec, '重新扫描 (' .. desc .. ')')
        H.zscanning = nil
    end, H)
end

-- 回血写部位后：同步写块里对应的位置（必须还等于基准值）
function hunt_zsync(v, t, old, new)
    H = v.H
    if not (H and H.zlast) then return end
    H.zlast[t] = new
    if not (H.bfix and H.blocks) then return end
    local base = H.zbase[t]
    if not base then return end
    local done = 0
    for _, b in ipairs(H.blocks) do
        if W.i32(b + (t - 0xF8), base, new) then done = done + 1 end
    end
    if done > 0 then
        H.zbase[t] = new
        if not H.blogged then H.blogged = true; log('hunt zone fix: 已同步写 %d 块 (+%x %d -> %d)', done, t, base, new) end
    end
end

-- 每次读到 hunt 载具的记录时调用
local function hunt_observe(v, data, rec)
    H = v.H
    if not H then return end
    local hp = i32(data, 0x14)
    if H.scanning then
        local hit = H.last and hp < H.last
        for t, z in pairs(H.zlast) do if i32(data, t) < z then hit = true end end
        if hit then
            if S.scan and S.scan.h == H then S.scan = nil end
            v.hunt_tries = (v.hunt_tries or 0) + 1
            if v.hunt_tries < 3 then v.H = nil else v.H = false end
            log('hunt %s ent=%d: 扫描中挨了打，这次作废%s', v.kind, v.d.entity, v.H == nil and '，下次回血再扫' or '，不再重试')
            H = nil
            return
        end
        H.last = hp
        return
    end
    if H.last and hp < H.last and hp > 0 then hunt_filter(hp) end
    if H then H.last = hp end
    if H and rec then hunt_zones(v, data, rec) end
end

-- 回血写 +0x14 后：同步写 hunt 找到的拷贝（当前值必须等于旧血量对应的值）
function hunt_sync(v, old, new)
    H = v.H
    if not H then return end
    H.last = new
    if not H.fix then return end
    local done = 0
    for k = 1, 4 do
        local lo, hi = hunt_range(k, old, H.max)
        for _, a in ipairs(H.lists[k]) do
            local raw = N.win.read(a, 4)
            if raw and #raw == 4 then
                local x = i32(raw, 0)
                if x >= lo and x <= hi then
                    local want = (k == 2 or k == 4) and H.max - new or new
                    local okw
                    if k <= 2 then okw = W.i32(a, x, want) else okw = W.f32(a, raw, want) end
                    if okw then done = done + 1 end
                end
            end
        end
    end
    if done > 0 and not H.logged then H.logged = true; log('hunt fix: 已同步写 %d 个地址 (%d -> %d)', done, old, new) end
end

-- 不在罩子里的载具：只要还有待核对的候选（或正在 hunt），就继续看它下一次受伤
local function watch_pending(v)
    local rec, data = read_record(v)
    check_pending(v, data)
    hunt_observe(v, data, rec)
end

local function heal(v, dt)
    local d = v.d
    local rec, data, zc, hd = read_record(v)
    if C.authority_only and hd.flags % 2 ~= 1 then return 'no_authority' end
    if C.shadow then check_pending(v, data) end
    hunt_observe(v, data, rec)
    local mx = zc.mx
    local zones = {}
    for n, z in ipairs(zc.zones) do
        zones[n] = { i = z.i, hash = z.hash, max = z.max, shared = z.shared, key = z.key, hp = i32(data, 0xF8 + 4 * z.i) }
    end

    local hp = i32(data, 0x14)
    if hp <= 0 then return 'dead' end  -- 不复活
    -- 受伤检测（总血量下降 -> 冷却）
    local total = hp
    for _, z in ipairs(zones) do if z.hp > 0 then total = total + z.hp end end
    local key = d.entity .. ':' .. d.goid
    if S.last_total[key] and total < S.last_total[key] then S.last_hit[key] = S.clock end
    S.last_total[key] = total
    if C.cooldown > 0 and S.last_hit[key] and S.clock - S.last_hit[key] < C.cooldown then return 'cooldown' end

    local rate = C[HEAL_RATE[v.kind]]
    local changed = 0
    if hp < mx then
        local n = amount(key .. ':h', mx, rate, dt)
        if n > 0 and write_hp(v, rec, data, 0x14, hp, math.min(mx, hp + n), mx) then changed = changed + 1 end
    end
    local state = u32(data, 0x20)
    for _, z in ipairs(zones) do
        if z.max > 0 and z.hp < z.max then
            local zk = key .. z.key
            local zo = 0xF8 + 4 * z.i
            if z.hp > 0 then
                local n = amount(zk, z.max, rate, dt)
                if n > 0 and write_hp(v, rec, data, zo, z.hp, math.min(z.max, z.hp + n), z.max) then changed = changed + 1 end
            elseif z.hp > -1000000 and C.hull_zones and not C.revive and (v.kind == 'tank' or v.kind == 'frv') and not WHEEL[z.hash] then
                -- 坦克/FRV 被打爆的部位：只把 HP 数值慢慢加回上限，不动损坏状态位（部件照样是坏的/掉的）
                -- 游戏内实测：坦克 net 车体 6750/8000 = 8000 - (750+250+250)，正好是三个被打爆部位的损失
                local n = amount(zk, z.max, rate, dt)
                if n > 0 and write_hp(v, rec, data, zo, z.hp, math.min(z.max, z.hp + n), z.max) then
                    changed = changed + 1
                    if not S.reported['hz' .. key .. z.i] then
                        S.reported['hz' .. key .. z.i] = true
                        log('hull zone %s entity=%d zone=%s from %d (state kept)', v.kind, d.entity, z.hash, z.hp)
                    end
                end
            elseif z.hp > -1000000 and ((v.kind == 'frv' and WHEEL[z.hash] and C.tires) or (not WHEEL[z.hash] and C.revive)) then
                -- 被打爆的部位（HP≤0）：拉回 25%，并清掉该区的 2-bit 损坏状态（2=已摧毁，游戏内实测）
                -- 之后按正常速度继续回满。实验性：模型/脱落的部件能否恢复取决于游戏
                if write_hp(v, rec, data, zo, z.hp, math.ceil(z.max * 0.25), z.max) then
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
    -- 自动 hunt：每辆载具第一次回血时扫一次（v.H=false 表示扫过/放弃，不再重试）
    -- 扫描分帧做（不卡），同一时间只扫一辆，每局最多 16 次
    if C.hunt and v.H == nil and not S.scan and (S.hunt_n or 0) < 16 and v.pend and v.pend[0x14] then
        v.H = false
        S.hunt_n = (S.hunt_n or 0) + 1
        log('hunt auto: %s ent=%d 第一次回血，自动开始 hunt（设置 hunt=0 可关）', v.kind, v.d.entity)
        local okh, eh = pcall(cmd_hunt, nil, v)
        if not okh then log('hunt: %s', tostring(eh)) end
    end
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
            return string.format('hp=%d/%d state=%08x zones[%s]', i32(data, 0x14), i32(g:read(cfg, 4), 0), u32(data, 0x20), table.concat(zs, ' '))
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

local function cmd_status()
    local n = 0; for _ in pairs(C.shield) do n = n + 1 end
    log('status: enabled=%s test=%s native=%s weapon=%s vehicles=%d weapons=%d shields_cfg=%d shields_live=%d writes=%d fails=%d',
        tostring(C.enabled), tostring(C.test), tostring(N.ready), tostring(N.weapon_ready), #S.vehicles, #S.weapons, n, #S.shields, W.writes, W.fails)
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
        elseif c == 'weapons' then cmd_weapons()
        elseif c == 'status' then cmd_status()
        elseif c == 'probe' then cmd_probe()
        elseif c == 'hunt' then
            local okh, eh = pcall(cmd_hunt, line:match('^%s*%S+%s+(%S+)'))
            if not okh then log('hunt: %s', tostring(eh)) end
        elseif c == 'netinfo' then cmd_netinfo()
        elseif c == 'netset' then cmd_netset()
        elseif c == 'recent' then cmd_recent(tonumber(line:match('recent%s+(%d+)')) or 40)
        elseif c == 'reload' then load_settings(); load_shadows()
        elseif c == 'on' then C.enabled = true; log('enabled')
        elseif c == 'off' then C.enabled = false; log('disabled')
        elseif c == 'test' then C.test = not C.test; log('test mode = %s', tostring(C.test))
        elseif c then log('unknown command: %s (units|recent [n]|vehicles|weapons|status|probe|hunt|reload|on|off|test)', c) end
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
    if not world or not session then if S.ctx then S.ctx = nil; reset_context() end; return end
    if not S.ctx or S.ctx.world ~= world or S.ctx.session ~= session then
        S.ctx = { world = world, session = session }; reset_context()
    end
    local ready, why = N.ensure(S.clock)
    if not ready then
        if S.native_reason ~= why then S.native_reason = why; log('native not ready: %s', tostring(why)) end
        return
    end
    stage('native layout ok')
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
    if S.watch then
        local w = S.watch
        if S.clock - w.t0 >= w.marks[w.i] then
            local okn, a = pcall(net_body, w.v)
            log('netset watch +%.1fs net=%s', w.marks[w.i], tostring(okn and a))
            w.i = w.i + 1; if w.i > #w.marks then S.watch = nil end
        end
    end
    if not C.enabled then return end
    if S.scan then scan_step() end
    S.acc = S.acc + dt
    if S.acc < C.tick then return end
    local step = math.min(S.acc, 1); S.acc = 0

    stage('first service pass')
    -- 修过血、还没等到下一次受伤、这一轮又不在罩子里的载具：继续核对影子字段候选（最多 180 秒）
    if C.shadow or C.hunt or H then
        for _, v in ipairs(S.vehicles) do
            if ((v.pend and next(v.pend)) or v.H) and S.clock - (v.pend_seen or -1e9) > C.tick * 1.5 then
                local ok = pcall(watch_pending, v)
                if not ok then v.pend = nil end
            end
        end
    end
    if #S.shields == 0 and not C.test then return end  -- 没有护盾：什么都不做（不取坐标、不读内存）
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
    if not any then S.want_units = nil; return end

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
            v.pend_seen = S.clock
            local ok, r = pcall(heal, v, step)
            if not ok then
                local k = v.d.entity .. tostring(r)
                if not S.reported[k] then S.reported[k] = true; log('heal %s %d: %s', v.kind, v.d.entity, tostring(r)) end
            end
        end
    end
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

load_settings(); load_shadows()
if TEST_HOOK then TEST_HOOK(N, W, S, C) end
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
log('loaded v0.12h (native layer from DRIVER HUD / HUD, MIT FireScallion)')
return { installed = true }

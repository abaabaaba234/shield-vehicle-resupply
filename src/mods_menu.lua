-- Optional ModOptionsMenu API 1/version 2 adapter. No game memory operations.
local M = {}
local PREFIX = 'shield_vehicle_resupply_'
local function toggle(key, zh, en, zdesc, edesc)
    return {key=key, type='toggle', zh=zh, en=en, zdesc=zdesc, edesc=edesc}
end
local function slider(key, zh, en, min, max, step, zdesc, edesc, scale)
    return {key=key, type='slider', zh=zh, en=en, min=min, max=max, step=step,
        zdesc=zdesc, edesc=edesc, scale=scale or 1}
end
local entries = {
    {key='language', type='choice', zh='Language', en='Language', values={'zh','en'},
        choices={'简体汉字','English'},
        zdesc='仅改变本模组文字。应用后关闭并重新打开 Esc 菜单刷新。',
        edesc='Change this mod\'s text. Apply, then close and reopen the Esc menu.'},
    toggle('enabled','启用模组','Enable Mod',
        '关闭时停止维修、补弹和故障保护，并执行原有配置、暂存弹药及物理状态恢复。',
        'Disable repair, resupply and failure protection; restore configuration, escrowed ammo and physics.'),
    {key='heal', type='choice', zh='回血方式', en='Healing Mode', values={'native','write','off'},
        choices={{zh='游戏原生',en='Native'},{zh='旧版数值回填',en='Legacy Writes'},{zh='关闭回血',en='Off'}},
        zdesc='默认游戏原生。旧版数值回填用于对照；关闭只停回血，补弹和故障保护由各自开关控制。',
        edesc='Native by default. Legacy writes are a fallback. Off stops healing; resupply and protection have separate switches.'},
    slider('radius','护盾半径（米）','Shield Radius (m)',1,100,0.5,
        '按水平距离判断是否在护盾内，默认 14.5 米。','Horizontal distance from the shield; default 14.5 m.'),
    slider('shield_duration','护盾最长持续时间（秒）','Shield Duration (s)',0,300,1,
        '默认 45 秒；0 表示不限时。发生器消失仍立即结束。','Default 45 seconds. 0 removes the timeout; a missing generator still ends the shield.'),
    slider('exo_heal','机甲每秒回血（%）','Mech Healing per Second (%)',0,100,0.1,
        '每秒回复最大血量的百分比，默认 4%。包括机甲手臂。','Percent of maximum HP per second; default 4%. Includes mech arms.',100),
    slider('tank_heal','坦克每秒回血（%）','Tank Healing per Second (%)',0,100,0.1,
        '每秒回复最大血量的百分比，默认 3%。','Percent of maximum HP per second; default 3%.',100),
    slider('frv_heal','FRV 每秒回血（%）','FRV Healing per Second (%)',0,100,0.1,
        '每秒回复最大血量的百分比，默认 5%。','Percent of maximum HP per second; default 5%.',100),
    slider('cooldown','受伤后回血冷却（秒）','Healing Cooldown (s)',0,60,0.5,
        '受伤后等待这些秒数再回血，默认 2 秒。','Wait after damage before healing; default 2 seconds.'),
    toggle('ammo','补充弹药','Ammo Resupply',
        '给关联的机甲和坦克武器补弹，FRV 不补弹；不改变故障保护的暂存弹药。',
        'Resupply linked mech and tank weapons, excluding FRV; does not change failure-protection ammo escrow.'),
    slider('ammo_rate','每秒补弹（%）','Ammo Resupply per Second (%)',0,100,0.1,
        '每秒补充弹药上限的百分比，默认 10%。','Percent of ammo capacity per second; default 10%.',100),
    toggle('part_regen','部位再生默认开关','Default Part Regeneration',
        '允许部位再生；设置文件中的 part= 独立覆盖继续生效。','Allow part regeneration; individual part= overrides in the settings file still apply.'),
    toggle('part_repair','原生部位维修','Native Part Repair',
        '使用游戏维修函数；任一部位被独立禁用时跳过整车维修。','Use native repair functions; skip whole-vehicle repair when any part is individually disabled.'),
    toggle('exo_leg_fix','修满后恢复机甲腿部','Restore Repaired Mech Legs',
        '全部部位修满后恢复移速、残留跛行动画和已确认的腿部火焰。','Restore movement speed, residual limp and confirmed leg fires after all parts are fully repaired.'),
    toggle('exo_weapon_guard','机甲武器故障保护','Mech Weapon Protection',
        '非盾牌武器触底到 1 HP 时暂存弹药，修复严格超过 5% 后归还；罩外也检测。',
        'Non-shield weapons escrow ammo at 1 HP and recover above 5%; detection also runs outside shields.'),
    toggle('exo_shield_guard','EXO-55 盾臂保护','EXO-55 Shield Protection',
        '盾臂或盾面触底时只禁用盾击；各故障区域超过 5% 后恢复。','Disable shield bash when either shield pool bottoms out; recover each failed pool above 5%.'),
    toggle('frv_tire_guard','FRV 轮胎故障保护','FRV Tyre Protection',
        '保留轮胎模型，触底施加原生爆胎状态，超过 5% 恢复；需先观察完好轮胎。',
        'Preserve tyre models; apply native puncture at the floor and recover above 5%. Requires observing healthy tyres.'),
    toggle('tires','FRV 轮胎维修','FRV Tyre Repair',
        '恢复已学习的完好轮胎参数和爆胎标志，不重建已经丢失的模型。','Restore learned healthy tyre physics and puncture flags; missing models are not rebuilt.'),
    slider('wheel_interval','轮胎维修间隔（秒）','Tyre Repair Interval (s)',0.5,30,0.5,
        '每辆 FRV 每个间隔最多修一个轮胎，默认 2 秒。','Repair at most one tyre per FRV per interval; default 2 seconds.'),
    toggle('net_heal','坦克与 FRV 网络车体回血','Tank / FRV Network Healing',
        '使用原有网络字段回血，仅对本机拥有的网络对象生效。','Use existing network HP fields; only for locally owned network objects.'),
    toggle('hull_zones','坦克与 FRV 车体部位回填','Tank / FRV Hull Pools',
        '修复已毁车体部位的 HP 数值，外观不重建。','Restore destroyed hull HP pools without rebuilding their appearance.'),
    toggle('authority_only','仅本机有权威时写入','Require Local Authority',
        '默认开启，保持原有本机权威检查；联机客机通常不会生效。','Enabled by default; retain local authority checks. Clients usually cannot apply repairs.'),
    toggle('revive','旧版损坏部位回填（实验）','Legacy Part Revival (experimental)',
        '旧的 HP 和损坏位回填；数值恢复不保证模型恢复。','Legacy HP and damage-state restoration; numeric repair does not guarantee model restoration.'),
    slider('tick','补给检查间隔（秒）','Service Interval (s)',0.1,5,0.1,
        '默认 0.5 秒。缩短间隔会增加检查频率。','Default 0.5 seconds. Shorter intervals increase service checks.'),
    slider('roster_every','实体刷新间隔（秒）','Entity Refresh Interval (s)',0.5,30,0.5,
        '重新发现载具和护盾的间隔，默认 3 秒。','Rediscover vehicles and shields; default 3 seconds.'),
    toggle('test','忽略护盾（测试模式）','Ignore Shields (test mode)',
        '默认关闭。开启后所有载具均可回复，用于单人私人任务测试。','Off by default. Service all vehicles without shields; for testing in solo private missions.'),
    toggle('spot','记录附近实体（诊断）','Log Nearby Entities (diagnostic)',
        '默认关闭。记录新出现的附近实体，会增加处理量。','Off by default. Record newly appearing nearby entities; adds processing work.'),
}

function M.new(spec)
    local api, blocked
    local next_check = 0
    local function config() return spec.get_config() end
    local function text(entry, description)
        return function()
            local en = config().language == 'en'
            if description then return en and entry.edesc or entry.zdesc end
            return en and entry.en or entry.zh
        end
    end
    local function title()
        return config().language == 'en' and 'SHIELD VEHICLE RESUPPLY' or '护盾载具回血补弹'
    end
    local function checked(ok, reason)
        if ok ~= true then error(tostring(reason or 'menu operation failed'),0) end
    end
    local function snap(entry, value)
        -- Match version 2's displayed slider precision. File values remain
        -- authoritative, even when outside the menu range or between steps.
        local steps = math.floor((value-entry.min)/entry.step+0.5)
        return tonumber(string.format('%.3f', math.max(entry.min,
            math.min(entry.max,entry.min+steps*entry.step))))
    end
    local function wanted(entry)
        local value = config()[entry.key]
        if entry.type == 'choice' then
            for i,v in ipairs(entry.values) do if value == v then return i end end
            return 1
        elseif entry.type == 'slider' then return snap(entry,value*entry.scale) end
        return value == true
    end
    local function sync()
        for _,entry in ipairs(entries) do
            local id, value = PREFIX..entry.key, wanted(entry)
            if api.get(id) ~= value then checked(api.set(id,value)) end
        end
    end
    local function callback(entry)
        return function(value)
            if blocked then return end
            local mapped
            if entry.type == 'choice' then
                if type(value) ~= 'number' or value%1 ~= 0 then return end
                mapped = entry.values[value]
                if mapped == nil then return end
            elseif entry.type == 'toggle' then
                if type(value) ~= 'boolean' then return end
                mapped = value
            else
                if type(value) ~= 'number' or value ~= value or value < entry.min or value > entry.max
                    or math.abs(snap(entry,value)-value) > 1e-6 then return end
                mapped = value/entry.scale
            end
            if config()[entry.key] == mapped then return end
            local ok, reason = spec.save_setting(entry.key,mapped)
            if ok ~= true then
                spec.log('MODS menu save failed: %s: %s',entry.key,tostring(reason))
                return -- Keep runtime config; sync restores the menu's applied value.
            end
            config()[entry.key] = mapped
            if entry.key ~= 'language' then spec.request_apply(entry.key) end
        end
    end
    local function attach(menu)
        if menu.api ~= 1 or (tonumber(menu.version) or 1) < 2 then
            error('requires ModOptionsMenu API 1/version 2',0)
        end
        for _,method in ipairs{'register_option','on_change','get','set'} do
            if type(menu[method]) ~= 'function' then error('missing '..method,0) end
        end
        for _,entry in ipairs(entries) do
            local option = {type=entry.type,mod=title,label=text(entry),
                description=text(entry,true),default=wanted(entry)}
            if entry.type == 'slider' then
                option.min, option.max, option.step = entry.min, entry.max, entry.step
            elseif entry.type == 'choice' then
                option.choices = {}
                for i,choice in ipairs(entry.choices) do
                    option.choices[i] = type(choice) == 'table' and text(choice) or choice
                end
            end
            checked(menu.register_option(PREFIX..entry.key,option))
        end
        -- Register all rows before binding callbacks; a registration failure
        -- leaves no active handlers. Never retry a partially failed attach.
        for _,entry in ipairs(entries) do checked(menu.on_change(PREFIX..entry.key,callback(entry))) end
        api = menu
        sync()
        spec.log('MODS menu registered: %d options',#entries)
    end
    local adapter = {}
    function adapter.step(now)
        if blocked or now < next_check then return end
        next_check = now+0.5
        local ok,reason = pcall(function()
            if api then sync();return end
            local menu = rawget(_G,'ModOptionsMenu')
            if type(menu) == 'table' then attach(menu) end
        end)
        if not ok then
            blocked = tostring(reason)
            spec.log('Optional MODS menu unavailable: %s',blocked)
        end
    end
    return adapter
end
return M

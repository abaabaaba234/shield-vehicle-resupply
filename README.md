# Shield Vehicle Resupply（护盾内载具回血补弹）

[English](README_EN.md)

Helldivers 2 Lua mod。**FX-12 护盾发生器**的罩子张开期间，罩子里的载具会持续回复：

| 载具 | 回血 | 补弹 |
|---|---|---|
| EXO 机甲（4 种，含手臂） | ✅ | ✅ |
| 坦克（TD-220 Bastion / TD-110 Maelstrom） | ✅ 车体 + 部位 | ✅ |
| FRV | ✅ 车体 + 部位 | — |

罩子消失（发生器实体消失，实测约 42 秒），回复就停止。

机甲武器故障保护：提前设置部位免死配置，武器到 1 HP 时暂存并清空弹药；修复到**严格超过 5%** 才归还弹药。正常受伤低于 5%、但尚未到 1 HP 时仍可使用。保护与故障检测在罩外也运行，持续维修仍需要护盾。用户已测试 v0.19，反馈除大盾外其他机甲武器均可保留；EXO-49 的日志记录见 [本次实测记录](docs/v0.19实测记录.md)。首次致命伤采样曾短暂为 -1 HP，随后保持 1 HP，因此保底不是逐帧严格下限。见 [武器故障保护](docs/武器故障保护.md)。

FRV 轮胎到 1 HP 后保留模型并施加原生爆胎物理状态，维修严格超过 5%（350 HP 轮胎需至少 18 HP）后恢复；用户已确认 v0.21 的完整维修过程正常。两项保护均需先发现完好部件；已掉落的模型不重建。

**v0.22** 将 EXO-55 的盾击与破片炮独立控制：盾臂（800 HP）或盾面（5000 HP）任一区到 1 HP，仅关闭该盾臂的技能输入位；已故障区域分别超过 5% 后恢复。破片炮仅按自身血量暂存／归还弹药。离线回归通过，盾击实际禁用及恢复仍待安装新版实测。见 [轮胎与大盾保护](docs/轮胎与大盾保护.md) 和 [v0.22 实现记录](docs/v0.22独立盾击控制.md)。

**v0.23** 修复 EXO-55 的两个 10 HP 区域因整数取整而无法回血的问题，累计有效维修时间后调用游戏维修函数，保留原设定速率；用户已实测确认小血池修满后移动正常。该版火焰清理被错误的效果资源表容量挡住，实际未执行。见 [调查与验证](docs/v0.23机甲维修与火焰.md)。

**v0.24** 将原生效果资源表容量修正为 `0x560`（1376），使用实际游戏的表和配置索引回归，修满后独立调用原生 `StopEffect` 停止左右腿燃烧。10 组离线回归通过；用户已实测确认 EXO-55 左腿维修后移动正常、火焰消失，日志和后续只读采样确认移速为 1、全部部位满血、效果句柄清零。见 [查表修正与实测](docs/v0.24特效查表修正.md)。

**v0.25** 处理用户随后确认的“速度正常，但走路动画仍跛行”：修满后读取实际动画状态，仅对仍处于腿部受损状态的机甲发送原生 `fine` 恢复事件。完好机甲不触发；保留已有火焰修复及回血速率。11 组离线回归和两机只读核对通过，安装后用户确认本次正常，日志确认动画回到正常状态、左右腿火焰停止。见 [动画调查与实测](docs/v0.25跛行动画.md)。

v0.19 根据运行中机甲的只读采样修正挂接解析：Attachable 保存的是父机甲的完整 Unit 句柄，之前误当成实体 ID，导致保护一直未开启。现在按完整句柄匹配已知机甲，并检查当前身份、存活和权威。新日志包含 `parent`、`parent_unit` 和 `chain`；先确认出现 `weapon guard armed` 再测试致命伤害。

## 安装
1. 先装 [Bingus Shared Loader v17](https://www.nexusmods.com/helldivers2/mods/16292)。
2. 从 [Releases](../../releases) 下载 `ShieldVehicleResupply_<版本号>.zip`，用 mod 管理器导入。

游戏版本需要和 DRIVER HUD 1.4.5 / HUD 1.11.1 一致（Steam build 25480438）。版本不对时，内置的代码特征校验会失败，mod 自动停用，**不会写任何内存**。

## 设置与命令
本仓库当前构建版本为 `v0.25-menu`，支持 **ModOptionsMenu API 1 / version 2** 的 27 项参数控件。另装参数菜单模组后打开 **Esc → MODS → 护盾载具回血补弹**。第一行 Language 可选择简体汉字／English，应用后关闭并重新打开 Esc 菜单刷新文字。修改会保存到原设置文件；没有菜单也可继续使用文件与命令。安装、范围及验证见 [MODS 菜单说明](docs/MODS菜单.md)，源码与构建布局见 [仓库说明](docs/REPOSITORY.md)。Bingus Shared Loader 和 ModOptionsMenu 参数菜单各自独立。

文件都在 `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\`：
- `shield_resupply_settings.txt`：设置，第一次运行时自动生成。改完后发 `reload`。
- `shield_resupply_cmd.txt`：往里写命令，每行一条，0.5 秒内执行。
- `ShieldVehicleResupply.log`：日志与命令输出。

主要设置：

| 设置 | 默认 | 说明 |
|---|---|---|
| `radius` | 14.5 | 护盾半径（米，水平距离） |
| `shield_duration` | 45 | 护盾最长持续秒数（兜底；发生器消失就会立即结束）。0 = 不限时 |
| `exo_heal` / `tank_heal` / `frv_heal` | 0.04 / 0.03 / 0.05 | 每秒回复最大血量的比例 |
| `ammo` / `ammo_rate` | 1 / 0.10 | 是否补弹 / 每秒补充上限的比例 |
| `cooldown` | 2 | 受伤后多少秒内不回复 |
| `net_heal` | 1 | 坦克/FRV 车体血量（HUD 显示的网络血量）回复 |
| `heal` | native | `native` = 用游戏自带的回血开关回血（写 HealthComponent 配置，不扫内存）；`write` = 旧的逐帧写血量（用来对照/兜底）；`off` = 不回血 |
| `native_zone` | 0x141 | 部位 `RegenerationEnabled` 的偏移，由 filediver 二进制类型表确认，逐部位校验后才写；0 = 保留旧的部位回填路径。其他偏移只诊断、不写 |
| `part_regen` | 1 | 部位维修默认开关（包括 HP≤0 的部位）；原生模式交给游戏再生，模型/物理恢复仍需实测 |
| `part=` | — | 独立覆盖某个车型的部位，例如 `part=35dbf54f016f3624:ca47a7a9=0`。用 `parts` 查 hash，可写多行；禁用的部位也不会被旧路径回填 |
| `native_segments` / `native_force` | 1 / 1 | 回血段数 / 配置页只读时临时改页保护再写 |
| `hull_zones` | 1 | 坦克/FRV 被打爆部位的 HP 数值也回满（外观不恢复） |
| `authority_only` | 1 | 只改本机有权威的组件（游戏自带回血也只给这类载具打开） |
| `part_repair` | 1 | 游戏维修函数处理已毁部位；任何部位禁用时跳过整车调用 |
| `exo_leg_fix` | 1 | 机甲全部部位修满后恢复 0.75 移速倍率，并停止已确认的腿部燃烧特效 |
| `exo_weapon_guard` | 1 | 非盾牌机甲武器免死与故障保护：1 HP 时清空弹药，修复超过 5% 后归还；罩外也运行 |
| `exo_shield_guard` | 1 | EXO-55 盾臂/盾面保留模型，任一区触底只禁用盾击；每个已故障区域各自超过 5% 才解除 |
| `frv_tire_guard` | 1 | FRV 轮胎保留模型，触底应用原生爆胎参数，超过 5% 恢复；不保护车体免死，需先观察完好轮胎 |
| `tires` / `wheel_interval` | 1 / 2 | VehicleApi 恢复爆胎参数，每车每两秒最多一个；不重建外观，需先学习完好轮胎 |
| `revive` | 0 | 旧的数值与损坏位回填（实验） |
| `test` | 0 | 测试模式：忽略护盾，所有载具都回复 |
| `spot` | 0 | 诊断：记录载具附近新出现的实体 |
| `shield=` / `weapon=` | — | 额外的护盾 / 允许补弹的武器资源 hash（16 位 hex，可写多行） |
| `ammo_max=` | — | 固定弹药上限，例如 `ammo_max=df51fe8d62f294be:roundsreserve=60` |

命令：

| 命令 | 作用 |
|---|---|
| `status` | 状态、写入次数、失败次数及武器故障/暂存弹药状态 |
| `on` / `off` / `reload` | 开 / 关 / 重新读取设置 |
| `test` | 切换测试模式（在单人私人任务里用） |
| `vehicles` / `weapons` | 列出载具血量 / 已关联的武器弹药 |
| `parts` | 列出每个部位的配置键、HP、再生开关、布局检查、OnHeal 事件和死亡时禁用 actor 的标志 |
| `units` / `recent [n]` | 统计网络实体 / 列出最新 n 个实体（找资源 hash 用） |
| `healcfg` | 打印每种载具的 HealthComponent 配置头、部位回血开关的候选偏移，并把整段配置记录导出成文件 |
| `hptrace [秒]` | 每 0.5 秒记一次主血量 / 部位和 / 开关状态，用来看血是不是游戏自己在涨 |
| `heal native` / `heal write` / `heal off` | 游戏里直接切换回血方式，不用改设置文件 |
| `probe` / `netinfo` / `netset` | 诊断用 |

## 工作原理（简述）
- 读取层直接复用 DRIVER HUD / HUD 的 native reader，包括 Health、Magazine/Rounds 组件的布局和代码特征校验。
- 护盾：在网络实体表里找资源 `ed13ddc480ec6910`（FX-12 发生器）。注意 `73f8498bffdcf415` 是通用空降仓，不是护盾。
- 坐标：用 tagged UnitReference 取载具和护盾的位置，按水平距离判断是否在罩内。
- 写入：
  - **回血（v0.13）**：打开每个单位 HealthComponent 配置里的**游戏自带回血开关**（`HealthChangerateDisabled = 0`、
    `HeathChangerate` / `RegenerationChangerate` = 每秒回血量、`HeathChangerateCooldown` = `cooldown`），
    让游戏自己的血量系统回血。写前先检查配置头像不像 `HealthComponent`，不像就一个字节都不写；
    载具离开罩子、护盾结束、关掉 mod 时写回原值。
  - **部位再生（v0.15 修正）**：逐部位打开 `RegenerationEnabled`，支持独立选择全部 38 个部位。已经开启原生再生的部位不再直接回填 HP 或清损坏位，保留游戏处理回血事件的机会。离开罩子、`off`、`reload` 时按原地址恢复原值；写回失败会保留记录并重试。
  - 旧的部位回填路径 / 弹药组件：在进程内调用 `WriteProcessMemory`。只写 `PAGE_READWRITE` 页，写前比对旧值，写后读回确认。
  - 坦克/FRV 车体血量：通过 `GameSession.set_game_object_field` 写，只在本机拥有该对象时写。
- 没有护盾时，mod 每 3 秒更新实体列表，并把持续回血开关写回原值。开启保护后，已发现的武器和轮胎约每 0.05 秒检查一次。普通武器用游戏维修函数维护 1 HP；轮胎和双血量盾臂只维护耗尽的血量池，不在罩外持续维修其他部位。

## 回血原理（v0.13：不再扫内存）
游戏扣血时用的是它自己另存的一份血量，而不是 mod 改过的那份。v0.12 的解决办法是每辆载具第一次回血时
扫描内存找那份拷贝（拆到每帧做，不卡，但每局要扫 15~20 秒）。v0.13 改成直接打开**游戏自带的回血开关**
（字段布局来自 filediver 的 datalibrary），让游戏自己把两份血量一起涨，扫描代码全部删除。

- 配置表按“单位资源”共享，所以只在**本机有权威**的载具停在罩子里时打开，离开后写回原值；
  打开期间同种载具（包括不在罩子里的）也会回血。
- v0.15 根据 filediver 二进制类型表修正 `RegenerationEnabled=+0x141`，并逐部位检查邻近字段。**这不是当前游戏中的模型恢复验证**；已掉落的门、手臂和被禁用的物理部件能否恢复，需要进游戏观察。
- 老设置文件如果含 `native_zone=0`，升级后仍会使用旧路径。测试新功能时改为 `native_zone=0x141`、`part_regen=1`、`heal=native`，发 `reload`。
- 实现和实测步骤见 [docs/部位再生.md](docs/部位再生.md)。
- **v0.16 机甲维修**：机体及独立手臂优先用游戏维修函数修到满血，避免和配置再生叠加；新增升级版手臂识别、腿部移速恢复，以及仍挂接且未被游戏标记死亡的零血量手臂维修。已死亡/脱落/移除手臂的重建尚未实现，游戏内效果待实测。见 [机甲部位修复.md](docs/机甲部位修复.md)。
- 原理、字段表、限制和验证方法见 [docs/回血原理.md](docs/回血原理.md)。

## 风险提示
- 这个 mod 会**写游戏内存**，风险高于纯读的 HUD。建议只在私人任务里使用。
- 回血只在本机有权威时生效。联机当客机时基本不起作用。
- 使用风险自负。

## 从源码构建
```
python tools/build.py          # -> dist/ShieldVehicleResupply_<version>.zip
pip install lupa
python tests/svr_test.py         # heal=write 兜底路径（LuaJIT + 模拟内存）
python tests/native_heal_test.py # 游戏自带回血：打开配置 / 不写主血量 / 离开后写回原值
python tests/native_guard_test.py# 配置头不对时拒绝写入
python tests/part_regen_test.py   # 38 个部位 / 独立开关 / 异常布局 / 恢复与重试
python tests/exo_repair_test.py   # 机甲腿部移速 / 升级手臂 / 原生挂接链 / 死亡与写入检查
python tests/exo_leg_effect_test.py # EXO-55 整数小血池 / 原生腿部火焰停止 / 两台机甲隔离
python tests/repair_native_test.py # 原生维修 / 轮胎参数 / 独立选择与接口校验
python tests/weapon_fault_test.py # 真实武器配置 / 1 HP 与 5% 状态 / 弹药暂存、归还、写失败重试
python tests/shield_fault_test.py # 真实双区 / 独立盾击输入 / 破片炮互不影响 / 身份与恢复
python tests/tyre_fault_test.py   # 实际轮心 / 原生爆胎调度 / 5% 门槛 / 恢复重试与代数
```

## 目录
```
src/body.lua            本 mod 的逻辑
src/weapon_fault.lua    机甲武器及双区盾臂故障、免死配置、弹药暂存与独立盾击输入
src/tyre_fault.lua      FRV 轮胎模型保护、故障锁定与物理状态恢复
src/vendor/             来自 DRIVER HUD / HUD 的读取层（MIT，FireScallion）
tools/build.py          拼接成单文件 addon 并打包
tools/pack_patch.py     生成 Bingus 可识别的 patch + mod 管理器 zip
tests/*.py              离线测试（LuaJIT + 模拟内存）：svr_test / native_heal_test / native_guard_test
docs/回血原理.md         回血原理：游戏自带回血开关、旧的扫描方案、限制和验证方法
```

## 许可与致谢
本项目采用 MIT 许可，见 [LICENSE](LICENSE)。读取层来自 FireScallion 的 DRIVER HUD / HUD（MIT），详见 [CREDITS.md](CREDITS.md)。

## v0.15 已毁部位与爆胎

`part_repair=1` 调用游戏维修函数处理已毁部位；`tires=1` 通过 VehicleApi 恢复爆胎参数与移动能力，不重建轮胎外观。更新 Lua 包后重启游戏。加载时已有爆胎且缺少完好参数样本时，召唤一辆同型号完好车供脚本观察。逐轮选择使用单轮损坏确认的接口编号对应，不混用 Health 索引。详见 [部位修复与爆胎](docs/部位修复与爆胎.md)。

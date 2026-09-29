# Shield Vehicle Resupply（护盾内载具回血补弹）

[English](README_EN.md)

Helldivers 2 Lua mod。**FX-12 护盾发生器**的罩子张开期间，罩子里的载具会持续回复：

| 载具 | 回血 | 补弹 |
|---|---|---|
| EXO 机甲（4 种，含手臂） | ✅ | ✅ |
| 坦克（TD-220 Bastion / TD-110 Maelstrom） | ✅ 车体 + 部位 | ✅ |
| FRV | ✅ 车体 + 部位 | — |

罩子消失（发生器实体消失，实测约 42 秒），回复就停止。

## 安装
1. 先装 [Bingus Shared Loader v17](https://www.nexusmods.com/helldivers2/mods/16292)。
2. 从 [Releases](../../releases) 下载 `ShieldVehicleResupply_<版本号>.zip`，用 mod 管理器导入。

游戏版本需要和 DRIVER HUD 1.4.5 / HUD 1.11.1 一致（Steam build 25480438）。版本不对时，内置的代码特征校验会失败，mod 自动停用，**不会写任何内存**。

## 设置与命令
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
| `native_zone` | 0 | 部位回血开关 `RegenerationEnabled` 的字节偏移（十六进制，例如 `0x13d`）。0 = 关，偏移要先用 `healcfg` 在游戏里确认 |
| `native_segments` / `native_force` | 1 / 1 | 回血段数 / 配置页只读时临时改页保护再写 |
| `hull_zones` | 1 | 坦克/FRV 被打爆部位的 HP 数值也回满（外观不恢复） |
| `authority_only` | 1 | 只改本机有权威的组件（游戏自带回血也只给这类载具打开） |
| `revive` / `tires` | 0 / 0 | 实验性：修复被打爆的部位 / FRV 爆胎（模型不会恢复） |
| `test` | 0 | 测试模式：忽略护盾，所有载具都回复 |
| `spot` | 0 | 诊断：记录载具附近新出现的实体 |
| `shield=` / `weapon=` | — | 额外的护盾 / 允许补弹的武器资源 hash（16 位 hex，可写多行） |
| `ammo_max=` | — | 固定弹药上限，例如 `ammo_max=df51fe8d62f294be:roundsreserve=60` |

命令：

| 命令 | 作用 |
|---|---|
| `status` | 状态、写入次数和失败次数 |
| `on` / `off` / `reload` | 开 / 关 / 重新读取设置 |
| `test` | 切换测试模式（在单人私人任务里用） |
| `vehicles` / `weapons` | 列出载具血量 / 已关联的武器弹药 |
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
  - Health 部位 / 弹药组件：在进程内调用 `WriteProcessMemory`。只写 `PAGE_READWRITE` 页，写前比对旧值，写后读回确认。
  - 坦克/FRV 车体血量：通过 `GameSession.set_game_object_field` 写，只在本机拥有该对象时写。
- 没有护盾时，mod 每 3 秒只做一次轻量扫描，并且会把配置里的回血开关写回原值。

## 回血原理（v0.13：不再扫内存）
游戏扣血时用的是它自己另存的一份血量，而不是 mod 改过的那份。v0.12 的解决办法是每辆载具第一次回血时
扫描内存找那份拷贝（拆到每帧做，不卡，但每局要扫 15~20 秒）。v0.13 改成直接打开**游戏自带的回血开关**
（字段布局来自 filediver 的 datalibrary），让游戏自己把两份血量一起涨，扫描代码全部删除。

- 配置表按“单位资源”共享，所以只在**本机有权威**的载具停在罩子里时打开，离开后写回原值；
  打开期间同种载具（包括不在罩子里的）也会回血。
- 部位的回血开关 `RegenerationEnabled` 偏移还没在游戏内确认，默认关（`native_zone=0`）；
  发一次 `healcfg` 看候选偏移，确认后再填。
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
```

## 目录
```
src/body.lua            本 mod 的逻辑
src/vendor/             来自 DRIVER HUD / HUD 的读取层（MIT，FireScallion）
tools/build.py          拼接成单文件 addon 并打包
tools/pack_patch.py     生成 Bingus 可识别的 patch + mod 管理器 zip
tests/*.py              离线测试（LuaJIT + 模拟内存）：svr_test / native_heal_test / native_guard_test
docs/回血原理.md         回血原理：游戏自带回血开关、旧的扫描方案、限制和验证方法
```

## 许可与致谢
本项目采用 MIT 许可，见 [LICENSE](LICENSE)。读取层来自 FireScallion 的 DRIVER HUD / HUD（MIT），详见 [CREDITS.md](CREDITS.md)。

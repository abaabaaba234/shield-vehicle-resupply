# 仓库与构建

主仓库为 `shield-vehicle-resupply`，当前构建版本为 **v0.25-menu-perf3**：在 v0.25-menu 的中英参数菜单和维修逻辑上优化缓存、读取批次、保护巡检与状态清理。原版和前两轮性能优化安装包保留，历史版本由原有 Git 标签保留。

| 位置 | 用途 |
|---|---|
| `src/body.lua` | 配置、保存、维修调度与原有恢复路径 |
| `src/mods_menu.lua` | 27 项 ModOptionsMenu 控件与中英文字 |
| `src/repair_native.lua` | 原生维修、腿部火焰和跛行动画恢复 |
| `src/weapon_fault.lua` / `src/tyre_fault.lua` | 武器、大盾和轮胎故障保护 |
| `src/vendor/` / `third_party/` | 第三方读取层及许可 |
| `tools/build.py` / `tools/pack_patch.py` | 拼接源码与生成可导入的 ZIP |
| `tests/` / `tests/fixtures/` | 离线回归和已采集的配置、代码样本 |
| `docs/` | 使用方法、实现调查、历史实测 |
| `validation/mods_menu_report.json` | 本次菜单版离线验证记录 |
| `validation/performance_release_report.json` | perf3 回归、安装包校验与用户实测确认 |
| `dist/shield_vehicle_resupply.lua` | 当前构建拼接源码 |
| `dist/ShieldVehicleResupply_v0.25-menu-perf3.zip` | 当前性能优化版安装包 |
| `dist/ShieldVehicleResupply_v0.25-menu-perf2.zip` | 保留的第二轮性能优化版安装包 |
| `dist/ShieldVehicleResupply_v0.25-menu-perf.zip` | 保留的第一轮性能优化版安装包 |
| `dist/ShieldVehicleResupply_v0.25-menu.zip` | 保留的原菜单版安装包 |
| `dist/ShieldVehicleResupply_v*.zip` | 历史安装包 |

在仓库根目录运行：

```powershell
python tools/build.py
python tests/mods_menu_test.py
python tests/performance_cache_test.py
python tests/hotpath_test.py
python tests/guard_patrol_test.py
```

测试依赖 Python 的 `lupa`（LuaJIT 2.1 后端）。真实菜单 API 测试需要本地菜单 Lua 源码；通过环境变量 `HD2_MOD_OPTIONS_MENU_SOURCE` 指定文件。测试在提供者安装游戏 UI hook 前停止，并使用隔离目录和模拟内存。

`src/` 是修改入口，`dist/shield_vehicle_resupply.lua` 由构建脚本生成。历史 ZIP 的原有文件名和路径保留；新的发布 ZIP 需要显式纳入 Git，因为 `dist/` 默认忽略新生成文件。

当前离线回归共 15 个测试脚本，覆盖原有业务、菜单配置／恢复、缓存失效和保护巡检。v0.25 的历史游戏验证见 [跛行动画](v0.25跛行动画.md)；2026-10-04 用户完成 perf3 游戏内测试并确认性能可接受，未提供本版分项耗时报告。参数范围、语言刷新与设置文件规则见 [MODS 菜单](MODS菜单.md)，性能变化与验证见 [性能检查与优化](性能检查与优化.md)，本版发布记录见 [perf3](releases/v0.25-menu-perf3.md)。

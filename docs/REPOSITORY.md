# 仓库与构建

主仓库为 `shield-vehicle-resupply`，当前构建版本为 **v0.25-menu**：在 v0.25 的维修逻辑上增加中英参数菜单。历史版本由原有 Git 标签保留。

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
| `dist/shield_vehicle_resupply.lua` | 当前构建拼接源码 |
| `dist/ShieldVehicleResupply_v0.25-menu.zip` | 当前菜单版安装包 |
| `dist/ShieldVehicleResupply_v*.zip` | 历史安装包 |

在仓库根目录运行：

```powershell
python tools/build.py
python tests/mods_menu_test.py
```

测试依赖 Python 的 `lupa`（LuaJIT 2.1 后端）。真实菜单 API 测试需要本地菜单 Lua 源码；通过环境变量 `HD2_MOD_OPTIONS_MENU_SOURCE` 指定文件。测试在提供者安装游戏 UI hook 前停止，并使用隔离目录和模拟内存。

`src/` 是修改入口，`dist/shield_vehicle_resupply.lua` 由构建脚本生成。历史 ZIP 的原有文件名和路径保留；新的发布 ZIP 需要显式纳入 Git，因为 `dist/` 默认忽略新生成文件。

本次通过 12 个测试脚本，覆盖原有业务回归和菜单配置／恢复。v0.25 的历史游戏验证见 [跛行动画](v0.25跛行动画.md)；本次新菜单尚未进行游戏内实测。参数范围、语言刷新与设置文件规则见 [MODS 菜单](MODS菜单.md)。

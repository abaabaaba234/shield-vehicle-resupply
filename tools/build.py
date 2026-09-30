#!/usr/bin/env python3
"""拼接出单文件 addon 并打包。

用法（在仓库根目录）：python tools/build.py
输出：dist/shield_vehicle_resupply.lua、dist/ShieldVehicleResupply_<版本号>.zip
"""
import os, subprocess, sys

VERSION = 'v0.23'
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = os.path.join(root, 'src')
dist = os.path.join(root, 'dist')
read = lambda *p: open(os.path.join(src, *p), encoding='utf-8').read()

out = '\n'.join([
    '-- HD2-Addon: mods/shieldresupply/shield_vehicle_resupply',
    '-- Shield Vehicle Resupply ' + VERSION,
    '-- Native read layer: DRIVER HUD 1.4.5 / HUD 1.11.1, Copyright (c) 2026 FireScallion, MIT License',
    '-- (see third_party/LICENSE-DRIVER-HUD.txt). Writes are added by this mod.',
    'local N=(function()',
    read('vendor', 'native_hud.lua'),
    'end)()',
    'do',
    ' local ptr,u32,i32,same=N.ptr,N.u32,N.i32,N.same',
    ' local G=getmetatable(N.graph(function() end,0)).__index',
    read('vendor', 'weapon_driverhud.lua'),
    'end',
    'local RepairNative=(function()',
    read('repair_native.lua'),
    'end)()',
    'local WeaponFault=(function()',
    read('weapon_fault.lua'),
    'end)()',
    'local TyreFault=(function()',
    read('tyre_fault.lua'),
    'end)()',
    read('body.lua'),
])
os.makedirs(dist, exist_ok=True)
dst = os.path.join(dist, 'shield_vehicle_resupply.lua')
open(dst, 'w', encoding='utf-8', newline='\n').write(out)
print('wrote', dst, len(out), 'bytes')
subprocess.check_call([sys.executable, os.path.join(root, 'tools', 'pack_patch.py'),
                       os.path.join(dist, 'ShieldVehicleResupply_' + VERSION + '.zip'), 'Shield Vehicle Resupply', dst])

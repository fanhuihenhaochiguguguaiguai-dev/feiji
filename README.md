# 苍穹锋刃 V18.3

独立的安卓原生空战工程，继承 V18.2 Native 的 `dcfd0ae34a0de948e96b74d7169266e6c934a0d8`。`v18.2-native` 保留为回退基线。

## 运行

使用 Godot 4.7.2 打开 `project.godot`。工程包含 Linux x86_64 和 Android ARM64 的 Terrain3D 1.1.0 与原生地形扩展。需要重新编译时，将 `ANDROID_NDK_HOME` 指向 Android NDK 后运行 `tools/build_extension.sh`。GitHub Actions 默认交付 ARM64 定制 Release，手动运行时可选择 Debug。

安卓导出从主场景跟随资源依赖。动态读取的机型、音频、战区、计算着色器和扩展列在 `export_presets.cfg`，新增动态资源时需更新对应条目。跑道、空中出生点和首段航路的 6 米间距精细地形通过 `godot --headless --script tools/compile_battlefields.gd -- --detail-only` 离线生成。

大厅的金色「开始战斗」继续战役，「无限空战」位于正下方。战役每波同时出现 5～6 架敌机。无限空战为每局 10 分钟，12 架战机各自为战，击落后 3 秒复活，难度固定。最终按击落数降序和死亡数升序排名。2 个指标均相同时共享名次。正常结束且达到参战条件时按排名和战绩结算信用点。

手机在 HUD 空白区滑动飞行，双击空白处不触发特殊动作。按住「加速」持续提升推力，松手恢复额定推力。桌面可用 WASD 或方向键，空格发射航炮，F 发射导弹，Q 反制，E 躲避，按住 Shift 加速，G 收放起落架。未锁定时仍可发射导弹。

安卓包名沿用 `com.skyblade.nativegame`，存档格式沿用 V18.2。首次读取 V18.1 档案仍会迁移。存档使用校验及备份文件。主动退出计入独立退出统计，无结算奖励。

## 操控约束（云端开发须遵守）

按用户要求删除玩家专用掉头动作、双击掉头及 R 键掉头入口，不保留隐藏开关或备用入口。设计理由：减少触控误触风险，避免预设掉头动作抢占正常滑动操控，减少重复飞控分支。普通手动转向、自动锁定跟随、躲避、人机航向控制、导弹制导与现有 HUD 布局保持不变。详见 [开发约束](AGENTS.md) 与 [替换记录](MIGRATION.md)。

## 本地核对

```sh
godot --headless --editor --import
godot --headless --script res://qa/smoke.gd
godot --headless --script res://qa/v182.gd
godot --headless --script res://qa/refinement.gd
godot --headless --script res://qa/campaign.gd
godot --headless --script res://qa/missile.gd
godot --headless --script res://qa/endurance.gd -- --matches=3
```

桌面录制可用 `--rendering-method mobile --rendering-driver vulkan --write-movie out.avi --fixed-fps 30 --script res://qa/desktop.gd -- --output=/absolute/output --pause`。记录中的硬件、帧时间与测试边界见 [替换记录](MIGRATION.md)。

大厅及海岸战区的同机位画面和渲染计时可用下列命令采集。路径应指向工程之外。

```sh
godot --rendering-method mobile --rendering-driver vulkan --resolution 960x432 --disable-vsync --audio-driver Dummy --fixed-fps 30 -s res://qa/environment.gd -- --output=/tmp/skyblade-environment
```

构建直接使用仓库中的已烘焙资源。重新制作时，将原始扫描图和高程文件按脚本中的文件名放在同一目录，以 `python tools/build_scenery.py <原图目录>` 重制地形和岩层，以 `godot --headless -s res://tools/bake_sky.gd -- <原图目录>` 重制天空。地形制作需要 GDAL、NumPy、SciPy 和 Pillow。原图及授权见 [场景素材来源](assets/licenses/scenery.txt)。

### J-20 制作源

`tools/build_j20_airframe.py` 使用 NumPy、SciPy 和 Pillow，将机身截面、座舱曲线和进气口轮廓编译为大厅、战斗及远距离网格。运行资产同时输出一张共享蒙皮贴图、部件碰撞代理、喷口挂点和五块离线碎片。继承的舵面、起落架和座舱内饰来自本仓库的 J-20 资源。

```sh
git show dcbd32c:assets/fleet/j20.glb > /tmp/j20-rig.glb
python tools/build_j20_airframe.py /tmp/j20-rig.glb assets/fleet/j20.glb
mkdir -p /tmp/j20-source
cp assets/fleet/shared-{panel-normal,recess}.png /tmp/j20-source/
python tools/build_j20_airframe.py /tmp/j20-rig.glb /tmp/j20-source/j20-master.glb --master
```

母版只用于离线编辑。将母版 GLB 导入 Blender，同目录的共享法线和遮蔽贴图可一并打包到 Blender 文件。姿态和外形的目视校核可参考公开航展照片。[2022 年珠海航展](https://english.news.cn/northamerica/20221108/b008c006943c4fb1a099f45d6cdefcf4/c.html) · [2025 年长春航空展](https://commons.wikimedia.org/wiki/File:J-20_at_China%27s_Air_Force_Aviation_Open_Activity_20250921.jpg)

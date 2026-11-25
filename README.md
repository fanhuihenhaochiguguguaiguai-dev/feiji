# 苍穹锋刃 V18.3

独立的安卓原生空战工程，自 V18.2 Native 的 `4940dc6990c305fb751bb4bcdc2034a82d91525a` 派生。`v18.2-native` 保留为回退基线。

## 运行

使用 Godot 4.7.2 打开 `project.godot`。工程包含 Linux x86_64 和 Android ARM64 的 Terrain3D 1.1.0 与原生地形扩展。需要重新编译时，将 `ANDROID_NDK_HOME` 指向 Android NDK 后运行 `tools/build_extension.sh`。GitHub Actions 配置 ARM64 Gradle 流程。

大厅的金色「开始战斗」继续战役，「无限空战」位于正下方。战役每波同时出现 5～6 架敌机。无限空战为每局 10 分钟，12 架战机各自为战，击落后 3 秒复活，难度固定。最终按击落数降序和死亡数升序排名。2 个指标均相同时共享名次。正常结束且达到参战条件时按排名和战绩结算信用点。

手机在 HUD 空白区滑动飞行，双击可掉头。动力自动保持额定推力，使用「加速」短时提升推力。桌面可用 WASD 或方向键，空格发射航炮，F 发射导弹，Q 反制，E 躲避，R 掉头，Shift 加速，G 收放起落架。未锁定时仍可发射导弹。

安卓包名沿用 `com.skyblade.nativegame`，存档格式沿用 V18.2。首次读取 V18.1 档案仍会迁移。存档使用校验及备份文件。主动退出计入独立退出统计，无结算奖励。

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

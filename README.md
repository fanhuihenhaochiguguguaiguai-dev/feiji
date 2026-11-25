# 苍穹锋刃 V18.2

独立的安卓原生空战工程，自 V18.1 Native 的 `e170fc88a34d9dd6d98c6ef1c95c299f5edecdec` 派生。`v18.1-native` 保留为回退基线。

## 运行

使用 Godot 4.7.2 打开 `project.godot`。工程包含 Linux x86_64 和 Android ARM64 的 Terrain3D 1.1.0 与原生地形扩展。需要重新编译时，将 `ANDROID_NDK_HOME` 指向 Android NDK 后运行 `tools/build_extension.sh`。GitHub Actions 配置 ARM64 Gradle 流程。

大厅的金色「开始战斗」继续战役，「无限空战」位于正下方。战役每波同时出现 5～6 架敌机。无限空战为每局 10 分钟，12 架战机各自为战，击落后 3 秒复活，难度固定。最终按击落数降序和死亡数升序排名。2 个指标均相同时共享名次。正常结束且达到参战条件时按排名和战绩结算信用点。

手机在 HUD 空白区滑动飞行，双击空白处不触发特殊动作。动力自动保持额定推力，使用「加速」短时提升推力。桌面可用 WASD 或方向键，空格发射航炮，F 发射导弹，Q 反制，E 躲避，Shift 加速，G 收放起落架。未锁定时仍可发射导弹。

安卓包名沿用 `com.skyblade.nativegame`。同签名覆盖安装后，V18.2 在首次读取时迁移已有 V18.1 档案。新存档使用校验及备份文件。主动退出计入独立退出统计，无结算奖励。

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

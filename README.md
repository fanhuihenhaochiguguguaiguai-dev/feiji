# 苍穹锋刃 V18.1

独立的 Godot Mobile 原生安卓工程。继承来源为正式 V18.0.0 的 `fcf3138081edfc5509571cdd9a18c1b67484bc82`。原版工程和 Git 标签独立保留。

## 运行

使用 Godot 4.7.2 打开 `project.godot`。Linux x86_64 与 Android ARM64 的 Terrain3D 1.1.0 和地形扩展随工程提供。运行 `tools/build_extension.sh` 可用 Android NDK r27c 和本机 C++ 编译器重新编译地形扩展。GitHub Actions 的 `V18.1 native Android` 工作流配置了 ARM64 Gradle 导出，生成调试签名 APK。

大厅的金色「开始战斗」继续当前战役，「无限空战」位于正下方。战役每波 5～6 架编队同时进场，清空当前波次后下一波进场。无限空战为 10 分钟，每局 12 架战机各自为战。玩家和 11 架电脑战机均在被击落 3 秒后复活，难度保持固定。倒计时结束后按击落数降序、死亡数升序结算，同战绩共享名次。信用点由名次、击落数和正的击落死亡差值共同决定。暂停期间计时冻结，提前退出返回大厅。手机在 HUD 空白区滑动控制飞行。电脑可用 WASD 或方向键，空格为航炮，F 为导弹，Q 为反制，E 为躲避，Shift 为加速，G 为起落架。

原生档案保存在 Godot `user://pilot-v18.1.json`。需迁移网页资料时，可将正式 V18 导出的档案 JSON 放入原生数据目录并命名为 `v18-import.json`，在创建原生存档前载入。浏览器站点存储与安卓应用沙箱彼此独立。

## 核对

```sh
godot --headless --editor --import
godot --headless --script res://qa/smoke.gd
```

回归脚本检查战机资源、战役表、第三章无人机、无限空战复活及地形坐标重定位。带图形的实际录制使用 `--write-movie out.avi --fixed-fps 20 -- --capture-dir=/absolute/output`。素材来源及验收范围见 [迁移记录](MIGRATION.md)。

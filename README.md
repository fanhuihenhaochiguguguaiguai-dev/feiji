# 苍穹锋刃 · WORLD-FORGE V18

单机空战网页游戏。使用 PlayCanvas 2.24.3、Babylon.js Core 9.0.0 和 TypeScript，优先启用 WebGPU，回退到 WebGL2。战役、每日任务、装备和战绩保存在当前浏览器中，已兼容旧版存档并写入 IndexedDB。

## 操作

全游戏使用横屏。竖屏只显示旋转提示，战斗中转为竖屏会暂停。手机横屏时，从空白区域滑动控制飞行。另一根手指可同时开火、加速或释放反制措施。轻滑微调，长滑增强机动。点击右上雷达打开实时战术地图。机库支持拖动旋转、双指捏合和鼠标滚轮缩放。

电脑使用方向键或 W/A/S/D 飞行，Q/E 偏航，R/V 调油门，Shift 加力，空格发射航炮，F 发射导弹，B 投弹，K 自动选择方向躲避，J/L 向左或向右躲避，Z 反制，C 切换座舱，G 收放起落架，Esc 暂停。

进入战役司令部可查看全球地图和六章六十关。每章十关，第十关末波有王牌。第三章部分空域有影隼无人机编队。击落全部敌机才会结算胜利并解锁下关。点「全球视图」返回全图。大厅右侧的「自由空战」从有敌机的空域开始，每次开局强度变化。清掉一波继续迎击，可在暂停时结算撤离。

## 配置与成长

- 所有可驾驶战机的基础配置为 1,200 发航炮弹及 20 枚空空导弹。战役中跨波次保留用量，自由空战在波次间补给。
- 航炮和导弹各有三个独立升级等级。武器页和部件升级页可打开对应的属性预览并用信用点购买。战斗自动锁定可见空中目标。点击躲避键向威胁反方向机动，也可在按钮上向左或向右滑动来指定方向。旧反制补给包按每份 300 信用点折算。
- 圆形准星统一使用机头轴线，双视角共用；独立菱形显示炸弹落点或对地制导目标。
- 战斗结算按命中战果、目标进度、胜负和难度结算经验。晋升奖励和首胜奖励随同一存档写入。
- 玩家战机的耐久由机型决定，最低为 2000。护甲升级降低伤害，耐久耗尽会结束出击。
- 战役按关卡顺序解锁。飞行经验保留并继续用于机型、升级和军需解锁。在「游戏设置」可以导出飞行员存档。

## 构建与部署

推荐 Node.js 24。浏览器需要 WebGL2 或 WebGPU。设置里可选择 60 或 90 FPS 上限，实际帧率取决于屏幕刷新率和设备。将 `dist/` 整体发布到静态 HTTPS 网站。首次加载及服务工作线程预缓存完成后可离线游玩。

```sh
npm ci
npm run check
npm test
npm run build
npm run test:assets
npm run preview -- --host 127.0.0.1
```

GitHub 的 Android 工作流编译横屏 WebView 包并使用 Android 调试签名。APK 与校验值随发布提供。

## 美术资源

`qa/reference/` 保存用户提供的 12 张概念图。`public/ui-v7/sources.json` 记录复用素材的来源、尺寸、裁切区域和使用场景。独立金属框、翼徽和界面图标与实时文字、数值和交互分别渲染。机库和战斗使用实时三维渲染。

`art/models/` 包含可编辑的 Blender 战机和机库。飞行资产提供近景、中景和远景网格并使用 Meshopt 压缩。`art/world_forge.py` 导出的高度场和水深数据由地表、海岸、碰撞和任务共用。世界渲染和文字符号独立控制分辨率。机库、晴天、黄昏、风暴和夜航使用不同环境反射探针，挂载、预备和战斗复用同一套机身材料定义。

```sh
python -m pip install pillow numpy scipy
python art/extract_ui.py
python art/world_forge.py
python art/campaign_charts.py  # 需要 GDAL 命令行工具
python art/apron_lighting.py
python art/light_probes.py
python art/dusk_atmosphere.py
python art/impact_sprites.py
python art/lobby_mountains.py
```

## 验证

`qa/world-forge-v18/` 包含低空尾流、第三章无人机群和存档迁移的截图及测试记录。此前的战役、武器、准星和海岸飞行记录保留在相应版本目录。全球地貌资料来源见 `art/geodata/SOURCE.md`。测试构建可访问 `/?world-forge=1`，读取后端、画质、分辨率、帧率和敌机 LOD，并独立切换云层、海面和地形。

```sh
python -m pip install playwright
VITE_GAME_QA=1 npx vite build --outDir /tmp/cangqiong-qa
python tests/flight_browser.py /tmp/cangqiong-qa /tmp/cangqiong-gl --backend gl --quick --water-drone --all-air --airframe j20
python tests/flight_browser.py /tmp/cangqiong-qa /tmp/cangqiong-gpu --backend gpu --quick --water-drone --all-air --airframe j20
python tests/visual_reference.py qa/reference /tmp/cangqiong-gl /tmp/cangqiong-comparison
```

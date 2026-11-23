# 苍穹锋刃 · WORLD-FORGE V16

单机空战网页游戏。使用 PlayCanvas 2.24.2 和 TypeScript，优先启用 WebGPU，回退到 WebGL2。战役、每日任务、装备和战绩保存在当前浏览器中。

## 操作

全游戏使用横屏。竖屏只显示旋转提示，战斗中转为竖屏会暂停。手机横屏时，从空白区域滑动控制飞行。另一根手指可同时开火、锁定、加力或释放反制措施。轻滑微调，长滑增强机动。点击右上雷达打开实时战术地图。机库支持拖动旋转、双指捏合和鼠标滚轮缩放。

电脑使用方向键或 W/A/S/D 飞行，Q/E 偏航，R/V 调油门，Shift 加力，空格发射航炮，F 发射导弹，B 投弹，T 锁定，Z 反制，C 切换座舱，G 收放起落架，Esc 暂停。

进入战役司令部可查看全球地图和六章六十关。点击关卡聚焦所在空域，点击「全球视图」返回全图。大厅底部「出击」直接打开当前战役的出击准备。对地出击时，缺少武器会显示具体条件、兼容挂位入口和可替换机型。

## 配置与成长

- 所有可驾驶战机自带固定航炮。按机型和升级等级自动配发弹药，出击中跨波次保留用量。兼容战机自动配发原厂空空弹。购买其他导弹型号后，可以在兼容挂位换装，出击时按同一机型配额补给。
- 歼-20原厂备弹为 340 发航炮和 10 枚空空弹。中央挂位可另装两枚重力炸弹，占用四枚空空弹的内部空间。航炮也可直接用于早期对地任务。
- 机务工位可分别提高航炮伤害、航炮射速及导弹发射频率、导弹伤害和出击弹量。军需页显示当前机型的实际发射数据。早期机型拥有较强的近距航炮表现，先进机型擅长高速拦截和制导。
- 圆形准星统一使用机头轴线，双视角共用；独立菱形显示炸弹落点或对地制导目标。
- 战斗结算按命中战果、目标进度、胜负和难度结算经验。晋升奖励和首胜奖励随同一存档写入。
- 战役同时校验章节进度、飞行员等级和武器要求。训练及已开放任务可以继续积累经验。

## 构建与部署

推荐 Node.js 24。浏览器需要 WebGL2 或 WebGPU。将 `dist/` 整体发布到静态 HTTPS 网站。首次加载及服务工作线程预缓存完成后可离线游玩。

```sh
npm ci
npm run check
npm test
npm run build
npm run test:assets
npm run preview -- --host 127.0.0.1
```

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
```

## 验证

`qa/world-forge-v16/` 包含本次武器、准星和海岸飞行的测试记录。此前的战役、成长和地图验收记录保留在 `qa/world-forge-v15/`。全球地貌资料来源见 `art/geodata/SOURCE.md`。测试构建可访问 `/?world-forge=1`，读取后端、画质、分辨率、帧率和敌机 LOD，并独立切换云层、海面和地形。

```sh
python -m pip install playwright
VITE_GAME_QA=1 npx vite build --outDir /tmp/cangqiong-qa
python tests/flight_browser.py /tmp/cangqiong-qa /tmp/cangqiong-gl --backend gl --quick --armory --sights
python tests/flight_browser.py /tmp/cangqiong-qa /tmp/cangqiong-gpu --backend gpu --quick --sights --airframe j20
python tests/visual_reference.py qa/reference /tmp/cangqiong-gl /tmp/cangqiong-comparison
```

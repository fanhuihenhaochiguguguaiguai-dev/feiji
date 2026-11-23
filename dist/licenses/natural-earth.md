# 全球地图地理数据

全球海岸矢量来自 Natural Earth 的 1:10m 数据，属于公有领域。源文件取自 QGIS 随附的 `world_map.gpkg` 的 `countries` 图层，经 GDAL 简化并去除属性后保存在 `natural-earth.gpkg`。渲染将各多边形合并为连续陆地面积。地表色彩与山脉阴影来自同一机构的 Natural Earth II 1:50m Shaded Relief, Water，以 2880 × 1440 像素源图随工程交付。战区标记代表游戏中的虚构任务。

- https://www.naturalearthdata.com/about/terms-of-use/
- https://www.naturalearthdata.com/downloads/50m-raster-data/50m-natural-earth-2/
- https://github.com/qgis/QGIS/blob/master/resources/data/README_world_map.md

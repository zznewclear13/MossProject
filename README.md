# README.md

## 系统需求

工程为Unity 2020.3.25f1(LTS)的默认SRP工程，低于或高于此版本可能会有URP Shader API的变化产生的错误。

## 支持的功能

1. 支持产生阴影和承接阴影。
2. 支持动态光照和光照贴图，支持参与烘焙。
3. 支持SRP Batcher。
4. 提供了移动平台和PC平台的切换开关`PLATFORM_PC`。
5. 提供了PC平台专属的贴花切换开关`ENABLE_DECAL`。
6. 提供了控制苔藓效果和贴花效果的一系列参数。

## 功能实现和相关的优化

1. 精度为half，减少了运算量。
2. 移动平台仅使用BRDF的漫反射部分，去掉了粗糙度贴图的读取。
3. 苔藓的绒状效果改编自对马岛之魂的技术讲解。
4. 贴花支持来自主光源的偏移阴影。

## 各参数说明

1. PLATFORM_PC，控制Shader的平台差异。
2. _BaseColor，基础颜色。
3. _BaseMap，基础贴图。
4. _BumpMap，切线空间的法线贴图。
5. _BumpIntensity，控制法线贴图的强度。
6. _RoughnessMap，粗糙度贴图，红通道为粗糙度。
7. _RoughnessIntensity，控制粗糙度贴图的强度。
9. _MetallicIntensity，控制金属度。
10. _FuzzColor，苔藓的绒毛颜色。
11. _FuzzMap，苔藓的贴图，白色为苔藓，黑色为树干。
12. _FuzzIntensity，控制苔藓贴图的强度。
13. _ScatterDensity，苔藓绒毛的散射强度。
14. ENABLE_DECAL，控制是否使用贴花。
15. _DecalColor，贴花颜色, 透明通道用于和基础贴图混合。
16. _DecalMap，贴花贴图，透明通道用于和基础贴图混合。
17. _DecalHeight，贴花高度，控制贴花阴影偏移的距离。
18. _DecalBumpMap，贴花切线空间法线贴图。
19. _DecalBumpIntensity，控制贴花法线贴图的强度。
20. _DecalRoughnessMap，贴花粗糙度贴图，红通道为粗糙度。
21. _DecalRoughnessIntensity，贴花粗糙度贴图的强度。

## 美术素材

美术素材来源MegaScans，略有PS修改。

带苔藓的树干：[Rock Assembly](https://quixel.com/megascans/home?assetId=titfbczfa)

树叶贴花：[Leaves](https://quixel.com/megascans/home?assetId=vfsdabyh)

## 相关参考

顽皮狗神秘海域4的技术分享：[The Technical Art of Uncharted 4](http://advances.realtimerendering.com/other/2016/naughty_dog/)

Sucker Punch Productions对马岛之魂的技术分享：[Samurai Shading in Ghost of Tsuma](https://blog.selfshadow.com/publications/s2020-shading-course/patry/slides/index.html)

## 许可

GNU General Public License v3.0
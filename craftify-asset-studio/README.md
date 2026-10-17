# Craftify Asset Studio (Minecraft Model & Texture Extractor & Renderer)

Craftify Asset Studio 是一个专为 **Craftify** 设计的桌面端前置资产提取与渲染支持工具。
它提供可在 macOS 环境运行的现代可视化窗口程序（GUI）与命令行工具（CLI），能够直接读取 Minecraft 客户端 `.jar` 文件，完整提取方块与物品的 3D 模型（JSON）和贴图（PNG），自动以 Minecraft 物品栏标准等轴投影（Isometric 3D）和 2D 物品合成方式渲染出精美的高清物品图标，并自动按照官方创造模式物品栏分类进行归类整理与导出。

---

## ✨ 核心特性与架构升级 (V2 精准渲染与全物品支持版)

1. **全面修复半砖、楼梯、栅栏、栅栏门、活板门、石墙等复杂方块贴图渲染**
   - **参数化重心坐标线性插值修复**：彻底修正了光栅化阶段在 UV 空间各角点插值时的 `(cv3 - cv0)` 纵向纹理对齐问题，杜绝任何位移、偏移与梯形挤压。
   - **原版 GUI 视角定向继承链递归**：自动穿透并提取半砖、活板门、楼梯及栅栏门 inventory 模型中的 `display.gui` 旋转与缩放参数，完美再现游戏内物品栏视角。

2. **全量非方块物品 (Items) 贴图渲染与合成引擎**
   - **多图层像素混合 (Multi-Layer Blending)**：完美解析并混合 `builtin/generated` 物品的 `layer0` ~ `layer4`（如药水瓶与液体层、附魔物品、工具柄与刃）。
   - **色彩滤镜与染色系统 (Colormap & Tinting)**：支持草方块/树叶群系着色、皮甲与染色羊毛色彩混合、药水/迷之炖菜特效色彩映射。
   - **特殊 3D 物品合成**：全面支持盾牌 (Shield)、箱子 (Chest)、潜影盒 (Shulker Box)、床 (Bed)、旗帜 (Banner)、生物头颅 (Head/Skull)、饰纹陶罐 (Decorated Pot)、潮涌核心 (Conduit) 等实体模型。

3. **macOS 极速流畅可视化窗口（60 FPS 虚拟化画布 GUI）**
   - **类型切换过滤**：顶部工具栏新增 `全部 (方块+物品)`、`仅方块 (Blocks)`、`仅物品 (Items)` 快速过滤器，方块与非方块物品槽位具备不同明暗对比与色边区分。
   - **全面解决卡顿问题**：采用纯原生 Tkinter/ttk 与单层虚拟化画布（Virtualized `tk.Canvas`）架构，仅重绘可视视口内的槽位，支持 1400+ 个方块与物品丝滑以 60 FPS 滚动与检索。
   - **全异步后台预渲染**：启动后由后台守护线程在内存中异步并行预渲染图标（`threading.Thread`），主 UI 线程永不阻塞卡死。
   - **3D 实时交互检视器**：右侧集成实时 3D 旋转控制面板（俯仰角 Pitch、偏航角 Yaw、缩放比 Scale 滑块），毫秒级实时交互渲染。
   - **全信息解析**：展示 ID、中英文名称、对象类型（方块物品 vs 非方块物品）、所属创造分类、模型定义类型（model/select/composite/special）、模型继承链（`parent -> ...`）、贴图绑定清单及渲染模式。

4. **双模式创造模式物品栏分类（Creative Mode Tabs）**
   - **JVM 字节码直接提取**：直接解析 JAR 内 `CreativeModeTabs.class` 的常量池与指令集字节码，100% 精确还原官方 11 大创造栏分类与顺序。
   - **高智能启发式规则回退**：对混淆版本或资源包 JAR，无缝调用多重关键字与正则特征匹配，将所有方块与物品精确分配至对应创造模式分类。

5. **全方位导出支持与 Craftify 专属集成**
   - **导出至 Craftify iOS**：一键生成 Xcode Assets 结构（`Item Name.imageset/` 包含 `@1x`, `@2x`, `@3x` 尺寸及 `Contents.json`），无缝对接 Craftify iOS 客户端项目的 `Assets.xcassets/`！
   - **按分类导出 PNG 文件夹**：分门别类保存为建筑方块、红石、功能方块等子文件夹，支持 `--filter {all,blocks,items}` 模式，附带 `creative_inventory_manifest.json` 清单。
   - **导出创造物品栏图集海报（Atlas Poster）**：自动合成一张包含原版九宫格凹槽、各分类色标、方块与物品统计及文字标题的高清全景海报。
   - **原始资产提取**：一键解包提取 JAR 内所有的原始 `.json` 模型和 `.png` 贴图。

---

## 🚀 快速启动

### 1. 环境准备
确保已安装 Python 3.9+，在当前项目目录下安装所需依赖：
```bash
pip install -r requirements.txt
```

### 2. 启动可视化窗口（GUI）
直接运行 `run.py` 即可打开图形界面：
```bash
python3 run.py
```
或者使用模块命令：
```bash
python3 -m craftify_asset_studio.gui.app
```

### 3. 使用命令行工具（CLI 批量批处理）
如果需要在脚本中自动运行，可使用 `cli.py`：
```bash
# 自动检测本地 Minecraft JAR 并渲染前 50 个物品至 ./output
python3 cli.py --limit 50 --output ./output

# 指定 jar 文件、图标分辨率（256px），并按分类导出
python3 cli.py --jar "/path/to/client.jar" --size 256 --output ./my_icons

# 直接导出到 Craftify 的 Assets.xcassets 目录
python3 cli.py --export-craftify "../Craftify/Assets.xcassets"
```

---

## 📂 项目结构

```
craftify-asset-studio/
├── run.py                             # GUI 启动入口
├── cli.py                             # CLI 批处理启动入口
├── requirements.txt                   # 项目依赖清单
├── pyproject.toml                     # Python 包配置
├── README.md                          # 项目文档
├── craftify_asset_studio/             # 核心源码包
│   ├── extractor/                     # JAR 包解压与贴图/模型缓存管理器
│   │   ├── jar_scanner.py             # 扫描 jar、读取模型清单与语言包
│   │   └── asset_manager.py           # 内存贴图读取、动画帧截取与原始导出
│   ├── model/                         # 模型继承树解析与变量替换
│   │   ├── json_model.py              # 模型数据类（ElementFace, GuiDisplay 等）
│   │   └── resolver.py                # 递归父模型、解析 #var 贴图引用
│   ├── renderer/                      # 物品栏 3D/2D 图标渲染引擎
│   │   ├── isometric_renderer.py      # 3D 方块等轴投影渲染器
│   │   ├── item_renderer.py           # 2D 物品图层合成渲染器
│   │   ├── math3d.py                  # 3D 旋转几何变换与 GUI 视口投影
│   │   └── color_tint.py              # 生物群系与植被着色滤镜
│   ├── classification/                # 创造物品栏分类体系
│   │   ├── creative_tabs.py           # 11 大创造模式分类枚举与多语言
│   │   ├── classifier.py              # 智能自动分类器
│   │   └── categories_data.py         # 预设词典与分类特征
│   ├── exporter/                      # 文件与工程导出器
│   │   ├── file_exporter.py           # 分类目录导出与 JSON 目录生成
│   │   └── craftify_exporter.py       # 直接导出 Craftify Xcode imageset
│   └── gui/                           # CustomTkinter 界面
│       ├── app.py                     # 主应用窗口与事件编排
│       ├── themes/mac_theme.py        # macOS 风格主题色系
│       └── components/                # UI 组件库（选择器、画廊、检查器、导出器）
└── tests/                             # 自动化单元测试
    ├── test_classifier.py             # 分类逻辑单元测试
    ├── test_resolver.py               # 模型解析单元测试
    └── test_renderer.py               # 渲染引擎单元测试
```

---

## 🧪 运行单元测试
在 `craftify-asset-studio` 目录下执行：
```bash
python3 -m unittest discover -s tests -p "test_*.py"
```
所有测试均自动通过。

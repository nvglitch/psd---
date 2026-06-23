# PSD Importer for Godot

> 将 Photoshop PSD 文件直接导入 Godot，自动生成场景树。

---

## 项目愿景

让 Godot 能像 Unity 的 Photoshop2Unity 或 FairyGUI 一样，直接将 PSD 作为一等资源导入，自动生成可用的节点树 —— 打通美术到引擎的"最后一公里"。

---

## 核心理念

**PSD Importer 不是 Photoshop 模拟器。** 它只提取对游戏引擎有意义的信息：图层结构、像素数据、位置、透明度、文本。调整图层、图层样式、智能对象等 Adobe 专有功能**刻意不支持** —— 这些在游戏引擎里没有运行时意义，投入产出比极低。

---

## 功能分级

### V1（MVP · 当前版本）

| PSD 元素 | Godot 输出 | 说明 |
|----------|-----------|------|
| Layer | `Sprite2D` / `TextureRect` | RGBA 图层转为纹理精灵 |
| Group | `Node2D` / `Control` | 图层组转为空节点，保持层级 |
| RGBA 像素 | `Image` → `ImageTexture` | 8-bit RGBA，支持 RLE 解压 |
| Position (Top/Left) | `position` / `anchors` | PSD 图层坐标直接映射 |
| Opacity (0-255) | `modulate.a` | 不透明度映射 |
| Visible/Hidden | `visible` | 可见性映射 |
| Layer Name | `name` | 图层名作为节点名 |
| Text Layer (`TySh`) | `Label` | 文字内容、字号、颜色 |
| 输出格式 | `.tscn` | 直接生成 Godot 场景文件 |

**覆盖率：满足 UI 素材、视觉小说、角色换装、Live2D 素材管理、纸娃娃系统 80%+ 需求。**

### V2（计划中）

- [ ] Layer Mask → Shader / SubViewport
- [ ] Blend Mode 映射（Multiply / Screen / Overlay → CanvasItem blend mode + Shader fallback）

### V3（远期）

- [ ] Shape Layer → Polygon2D（Vector Mask 解析）

### 明确不支持

- ❌ Adjustment Layer（Curves / Levels / Hue-Saturation / Selective Color…）
- ❌ Layer Style（Stroke / Glow / Shadow / Bevel…）
- ❌ Smart Object（PSD 嵌套、AI/SVG/PDF 引用）
- ❌ 16-bit / 32-bit 深度（仅支持 8-bit）
- ❌ CMYK / Lab / 其他非 RGB 色彩模式

---

## 架构

```
addons/psd_importer/
├── plugin.cfg              # Godot 编辑器插件配置
├── plugin.gd               # 插件入口，注册 Importer
├── psd_importer.gd         # EditorImportPlugin 实现
├── psd_parser.gd           # PSD 二进制格式解析器
├── scene_builder.gd        # 场景树构建器
└── README.md               # 用户文档
```

### 数据流

```
PSD 文件
  ↓
psd_parser.gd     —— 二进制解析 → LayerData[] 字典数组
  ↓
scene_builder.gd  —— 生成 Node 树 + ImageTexture 资源
  ↓
psd_importer.gd   —— EditorImportPlugin 保存 .tscn + .png 资源
  ↓
Godot 场景文件 (.tscn)
```

### PSD 二进制结构（解析用）

```
File Header (26B)
├── Signature      "8BPS" (4B)
├── Version        1 (2B)
├── Reserved       0 (6B)
├── Channels       2B
├── Height         4B
├── Width          4B
├── Depth          8 (2B)
└── Color Mode     RGB=3 (2B)

Color Mode Data (variable, skip)

Image Resources (variable, skip)

Layer and Mask Info (variable)
├── Total Length           4B
├── Layer Info Length      4B
├── Layer Count            2B
├── Layer Records[]
│   ├── Rect (Top/Left/Bottom/Right)  4×4B
│   ├── Channel Count      2B
│   ├── Channel Info[]     6B × count
│   ├── Blend Signature    "8BIM" (4B)
│   ├── Blend Key          4B
│   ├── Opacity            1B (0=transparent, 255=opaque)
│   ├── Clipping           1B
│   ├── Flags              1B (bit 0=transparency protected, bit 1=visible)
│   ├── Filler             1B
│   ├── Extra Data Length  4B
│   ├── Layer Mask Data    (Extra)
│   ├── Blending Ranges    (Extra)
│   ├── Layer Name         Pascal string (1B len + chars, padded to 4B)
│   └── Additional Info[]  (Tag "8BIM" + Key 4B + Length 4B + Data)
│       ├── "luni" — Layer Unicode Name
│       ├── "TySh" — Text Engine Data (Text Layer)
│       └── ...
└── Channel Image Data (PackBits RLE compressed)

Image Data (merged composite, skip for import)
```

---

## 使用方式

1. 将 `addons/psd_importer/` 放入项目
2. 在 Project Settings → Plugins 中启用 "PSD Importer"
3. 将 `.psd` 文件拖入 Godot 文件系统
4. Godot 自动导入，生成 `.tscn` 场景文件
5. 双击 `.tscn` 即可打开完整的图层场景

---

## 开发

### 环境要求

- Godot 4.6+
- 无外部依赖（纯 GDScript）

### 测试

```bash
# 在 Godot 编辑器中启用插件后
# 将测试 PSD 文件放入项目目录即可触发导入
```

---

## 参考资料

- [Adobe PSD File Format Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
- [Godot EditorImportPlugin Documentation](https://docs.godotengine.org/en/stable/classes/class_editorimportplugin.html)
- [PackBits RLE Compression](https://en.wikipedia.org/wiki/PackBits)

---

## 许可

MIT

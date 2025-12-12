#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "pillow",
# ]
# ///
"""
QuickClip 应用图标生成器
生成一个剪贴板样式的图标，带有代码片段元素
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_icon(size):
    """创建指定尺寸的图标"""
    # 创建图像，使用渐变蓝色背景
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # 计算比例
    scale = size / 512

    # 背景渐变色（蓝色到紫色）
    for y in range(size):
        progress = y / size
        r = int(50 + (140 - 50) * progress)
        g = int(130 + (90 - 130) * progress)
        b = int(255 + (230 - 255) * progress)
        draw.rectangle([0, y, size, y+1], fill=(r, g, b, 255))

    # 圆角矩形蒙版
    corner_radius = int(size * 0.18)
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, size, size], corner_radius, fill=255)
    img.putalpha(mask)

    # 绘制剪贴板图标（重新创建在蒙版之后）
    draw = ImageDraw.Draw(img)

    clipboard_size = int(size * 0.65)
    clipboard_x = (size - clipboard_size) // 2
    clipboard_y = int(size * 0.20)

    # 剪贴板夹子（顶部）
    clip_width = int(clipboard_size * 0.35)
    clip_height = int(clipboard_size * 0.12)
    clip_x = clipboard_x + (clipboard_size - clip_width) // 2
    clip_y = clipboard_y - int(clip_height * 0.3)

    draw.rounded_rectangle(
        [clip_x, clip_y, clip_x + clip_width, clip_y + clip_height],
        radius=int(clip_height * 0.4),
        fill=(220, 220, 220, 255),
        outline=(180, 180, 180, 255),
        width=max(1, int(scale * 1.5))
    )

    # 剪贴板背景（白色）
    draw.rounded_rectangle(
        [clipboard_x, clipboard_y, clipboard_x + clipboard_size, clipboard_y + clipboard_size],
        radius=int(clipboard_size * 0.10),
        fill=(255, 255, 255, 250),
        outline=(210, 210, 210, 255),
        width=max(2, int(scale * 3))
    )

    # 绘制三行代码线条（更简洁的代码图标）
    line_padding = int(clipboard_size * 0.20)
    line_y_start = clipboard_y + int(clipboard_size * 0.25)
    line_spacing = int(clipboard_size * 0.18)
    line_width = max(2, int(scale * 5))

    # 第一行 - 长
    draw.rounded_rectangle(
        [clipboard_x + line_padding, line_y_start,
         clipboard_x + clipboard_size - line_padding, line_y_start + line_width],
        radius=line_width // 2,
        fill=(70, 120, 220, 255)
    )

    # 第二行 - 中等
    draw.rounded_rectangle(
        [clipboard_x + line_padding, line_y_start + line_spacing,
         clipboard_x + clipboard_size - line_padding * 2, line_y_start + line_spacing + line_width],
        radius=line_width // 2,
        fill=(90, 140, 240, 255)
    )

    # 第三行 - 短
    draw.rounded_rectangle(
        [clipboard_x + line_padding, line_y_start + line_spacing * 2,
         clipboard_x + clipboard_size - line_padding * 2.5, line_y_start + line_spacing * 2 + line_width],
        radius=line_width // 2,
        fill=(110, 160, 250, 255)
    )

    return img

def main():
    """生成所有尺寸的图标"""
    # 创建输出目录
    output_dir = "QuickClip/Assets.xcassets/AppIcon.appiconset"

    # 需要的尺寸（实际像素）
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    print("🎨 开始生成 QuickClip 应用图标...")

    for filename, size in sizes.items():
        print(f"  📦 生成 {size}x{size} ({filename})")
        icon = create_icon(size)
        icon.save(os.path.join(output_dir, filename), 'PNG')

    print("✅ 图标生成完成！")
    print(f"📁 位置: {output_dir}")
    print("\n请在 Xcode 中重新打开项目以查看新图标。")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"❌ 错误: {e}")
        print("\n请确保已安装 Pillow: pip3 install Pillow")

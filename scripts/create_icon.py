#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Bayer POS - Icon Generator
"""

from PIL import Image, ImageDraw, ImageFont
import os

def create_b_icon(size, output_path):
    """Buyuk B harfi ikonu olustur"""
    # Turuncu gradient arkaplan
    img = Image.new('RGB', (size, size), color='#ff6b35')
    draw = ImageDraw.Draw(img)

    # Daire arka plan (daha modern görunum)
    margin = int(size * 0.05)
    draw.ellipse([margin, margin, size-margin, size-margin], fill='#ff6b35')

    # B harfi için font boyutu
    font_size = int(size * 0.7)

    try:
        # Windows sistem fontu kullan
        font = ImageFont.truetype("arial.ttf", font_size)
    except:
        try:
            font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", font_size)
        except:
            # Font bulunamazsa default kullan
            font = ImageFont.load_default()

    # B harfini merkeze çiz
    text = "B"

    # Text boyutunu al (Pillow 10+ için)
    try:
        bbox = draw.textbbox((0, 0), text, font=font)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]
    except:
        # Eski Pillow versiyonu için
        text_width, text_height = draw.textsize(text, font=font)

    # Metni ortala
    x = (size - text_width) // 2
    y = (size - text_height) // 2 - int(size * 0.05)  # Biraz yukari kaydir

    # Beyaz B harfi çiz
    draw.text((x, y), text, fill='white', font=font)

    # PNG olarak kaydet
    img.save(output_path, 'PNG')
    print(f"[OK] {output_path} olusturuldu ({size}x{size})")

def main():
    # Ikon dizini - script'in bulundugu yerden relative path kullan
    script_dir = os.path.dirname(os.path.abspath(__file__))
    icon_dir = os.path.join(script_dir, "local-pos", "src-tauri", "icons")

    if not os.path.exists(icon_dir):
        print(f"[X] Ikon dizini bulunamadi: {icon_dir}")
        return

    print("Bayer POS - Ikon Olusturuluyor...")
    print("=" * 50)

    # Farkli boyutlarda ikonlar olustur
    sizes = [
        (32, "32x32.png"),
        (128, "128x128.png"),
        (512, "icon.png")
    ]

    for size, filename in sizes:
        output_path = os.path.join(icon_dir, filename)
        create_b_icon(size, output_path)

    print("=" * 50)
    print("[OK] Tum ikonlar basariyla olusturuldu!")
    print("\nNot: .ico ve .icns dosyalari için tauri icon komutu çalistirin:")
    print("  cd local-pos")
    print("  npm run tauri icon")

if __name__ == "__main__":
    main()

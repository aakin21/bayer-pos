# Bayer POS

Yerel ağ bağlantısı veya internet gerektirmeyen, tamamen çevrimdışı çalışan satış noktası (POS) uygulaması. Küçük ve orta ölçekli işletmeler için geliştirilmiştir.

A fully offline point-of-sale (POS) application that requires no internet or local network connection. Built for small and medium-sized businesses.

---

## Özellikler / Features

- **Çevrimdışı çalışma** — İnternet bağlantısı olmadan tam işlevsellik  
  *Full functionality without any internet connection*

- **Barkodlu & Barkodsuz ürün satışı** — Barkod okuyucu desteği ve manuel ürün girişi  
  *Barcode scanner support and manual product entry*

- **Stok yönetimi** — Gerçek zamanlı stok takibi ve düşük stok uyarıları  
  *Real-time inventory tracking with low stock alerts*

- **Vardiya sistemi** — Kasa açılış/kapanış ve vardiya raporları  
  *Shift open/close management with shift reports*

- **Satış raporları** — Ciro, kâr, ürün bazlı istatistikler  
  *Revenue, profit, and per-product sales analytics*

- **İade işlemleri** — Kısmi ve tam iade desteği  
  *Partial and full refund support*

- **Nakit & Kart ödeme** — Karma ödeme seçeneğiyle  
  *Cash & card payments with split payment support*

- **Çoklu kullanıcı & yetki** — Admin ve kasiyer rolleri  
  *Multi-user support with admin and cashier roles*

- **Fiş yazdırma** — Termal yazıcı desteği  
  *Thermal printer receipt support*

---

## Teknolojiler / Tech Stack

| | |
|---|---|
| **Framework** | [Tauri](https://tauri.app/) v2 |
| **Frontend** | [Svelte](https://svelte.dev/) 5 + Vite |
| **Veritabanı / Database** | SQLite (via `@tauri-apps/plugin-sql`) |
| **Platform** | Windows |

---

## Kurulum / Setup

### Gereksinimler / Requirements

- [Node.js](https://nodejs.org/) v18+
- [Rust](https://rustup.rs/) (stable toolchain)

### Geliştirme / Development

```bash
cd local-pos
npm install
npm run tauri:dev
```

### Build (Windows installer)

```bash
cd local-pos
npm run tauri:build
```

Çıktı / Output: `local-pos/src-tauri/target/release/bundle/msi/`

---

## Ekran Görüntüleri / Screenshots

> Yakında eklenecek / Coming soon

---

## Lisans / License

Bu proje özel kullanım için geliştirilmiştir.  
*This project was developed for private commercial use.*

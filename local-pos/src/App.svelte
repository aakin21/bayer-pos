<script>
  import { onMount } from 'svelte';
  import { get } from 'svelte/store';
  import { currentView, user, deviceConfig, initializeApp, logout, toggleAutoPrint, cart, cartTotal, cartSubtotal, discount, removeFromCart, updateCartQuantity, clearCart, addToCart, applyDiscount, removeDiscount, getDiscountAmount, selectedQuantity } from './stores/appStore.js';
  import { initDatabase, productRepo } from './lib/db/database.js';
  import { saleRepo } from './lib/db/database.js';
  import { printReceipt } from './lib/printer/printerService.js';

  // Import components
  import Login from './components/login/Login.svelte';
  import SalesScreen from './components/sales/SalesScreen.svelte';
  import RefundScreen from './components/refund/RefundScreen.svelte';
  import StockAdjustment from './components/stock/StockAdjustment.svelte';
  import ReportsViewer from './components/reports/ReportsViewer.svelte';
  import UserManagement from './components/admin/UserManagement.svelte';
  import StockAlerts from './components/stock/StockAlerts.svelte';

  let currentMenu = 'sales'; // sales, refunds, stock, stock-alerts, reports, users
  let sidebarOpen = false; // Menü açık/kapalı durumu (başlangıçta kapalı)
  let isProcessingSale = false; // Satış işlemi devam ediyor mu
  let lastSaleTime = 0; // Son satış zamanı

  let saleDebounceTimer = null; // Debounce timer for sales
  let showDiscountModal = false; // İndirim modal'ı açık/kapalı
  let discountType = 'percentage'; // 'percentage' veya 'amount'
  let discountPercentage = 0; // Yüzde değeri
  let discountAmount = 0; // Manuel miktar


  // Reactive: İndirim tutarını hesapla
  $: currentDiscountAmount = getDiscountAmount();

  // Global Barkod Okuyucu
  let barcodeBuffer = ''; // Barkod karakterlerini biriktir
  let barcodeTimeout = null; // Barkod timeout
  let pendingBarcodeForStock = null; // Stok ekranına gönderilecek barkod
  let pendingProductForSales = null; // Satış ekranına gönderilecek ürün
  let pendingBarcodeForSales = null; // Satış ekranına gönderilecek barkod (yeni ürün için)
  let manualBarcodeInput = ''; // Manuel barkod girişi

  onMount(async () => {
    // Initialize local database first
    try {
      console.log('🚀 Starting app initialization...');
      await initDatabase();
      console.log('✅ Database initialized successfully');
    } catch (error) {
      console.error('❌ Failed to initialize database:', error);
      return;
    }

    // Initialize app from localStorage
    initializeApp();

    // GLOBAL BARKOD OKUYUCU - Her ekranda çalışır
    const handleGlobalBarcode = async (event) => {
      // Input/textarea içindeyse veya modal açıksa global barkod okuma yapma
      const activeElement = document.activeElement;
      const isInputActive = activeElement && (
        activeElement.tagName === 'INPUT' ||
        activeElement.tagName === 'TEXTAREA' ||
        activeElement.isContentEditable
      );

      // Eğer input active değilse, global barkod okuyucuyu aktif et
      if (!isInputActive && event.key.length === 1) {
        // Karakter ekle
        barcodeBuffer += event.key;

        // Timeout'u sıfırla
        if (barcodeTimeout) {
          clearTimeout(barcodeTimeout);
        }

        // 100ms sonra buffer'ı temizle (barkod okuyucu hızlı yazar)
        barcodeTimeout = setTimeout(() => {
          barcodeBuffer = '';
        }, 100);
      }

      // Enter tuşuna basıldığında barkodu işle
      if (event.key === 'Enter' && barcodeBuffer && !isInputActive) {
        event.preventDefault();
        const barcode = barcodeBuffer.trim();
        barcodeBuffer = '';

        if (barcode.length > 0) {
          await processGlobalBarcode(barcode);
        }
      }
    };

    async function processGlobalBarcode(barcode) {
      try {
        console.log('🔍 Global barkod okundu:', barcode, 'Ekran:', currentMenu);

        // Ürünü database'de ara
        const product = await productRepo.findByBarcode(barcode);

        // STOK AYARLAMA EKRANINDAYKen
        if (currentMenu === 'stock') {
          // Stok ekranına barkod gönder
          setTimeout(() => {
            window.dispatchEvent(new CustomEvent('stock-barcode-scanned', { detail: { barcode, product } }));
          }, 100);
          return;
        }

        // SATIŞ EKRANINDA veya diğer ekranlarda
        if (product) {
          // Ürün VARSA → Satış ekranına geç ve sepete ekle
          console.log('✅ Ürün bulundu, satış ekranına yönlendiriliyor:', product.name);
          currentMenu = 'sales';

          // Satış ekranına geçtikten sonra sepete ekle (seçili miktar kadar)
          setTimeout(() => {
            const qty = get(selectedQuantity);
            addToCart(product, qty);
            playBeep();
            // Miktarı 1'e sıfırla
            selectedQuantity.set(1);
          }, 100);
        } else {
          // Ürün YOKSA → Satış ekranına geç ve yeni ürün modal'ı aç
          console.log('❌ Ürün bulunamadı, yeni ürün ekleme modalı açılıyor');
          currentMenu = 'sales';

          // Sales ekranına geçtikten sonra modal'ı aç
          setTimeout(() => {
            window.dispatchEvent(new CustomEvent('open-new-product-modal', { detail: { barcode } }));
          }, 300);
        }
      } catch (error) {
        console.error('Barkod işleme hatası:', error);
      }
    }

    // Keyboard shortcuts for sales screen
    const handleKeyPress = (event) => {
      // Only handle shortcuts when in sales menu
      if (currentMenu !== 'sales') {
        return;
      }

      // Tekrarlanan tuş basışlarını engelle
      if (event.repeat) {
        return;
      }

      // F1 - Sepeti Sil
      if (event.key === 'F1' || event.code === 'F1') {
        event.preventDefault();
        event.stopPropagation();
        const cartItems = get(cart);
        if (cartItems.length > 0 && !isProcessingSale) {
          clearCart();
        }
        return;
      }

      // F2 - Kart, F3 - Nakit, F4 - Kart (eski uyumluluk)
      if ((event.key === 'F2' || event.code === 'F2') || (event.key === 'F3' || event.code === 'F3') || (event.key === 'F4' || event.code === 'F4')) {
        event.preventDefault();
        event.stopPropagation();
        event.stopImmediatePropagation();

        const now = Date.now();
        const timeSinceLastSale = now - lastSaleTime;

        if (isProcessingSale) {
          console.log('🚫 Satış zaten işleniyor, event engellendi');
          return;
        }

        if (timeSinceLastSale < 1000) {
          console.log('🚫 Çok hızlı tuş basışı engellendi:', timeSinceLastSale, 'ms');
          return;
        }

        if (saleDebounceTimer) {
          clearTimeout(saleDebounceTimer);
          saleDebounceTimer = null;
        }

        const cartItems = get(cart);
        if (!cartItems || cartItems.length === 0) {
          return;
        }

        // F2 = Nakit, F3 ve F4 = Kart
        const paymentMethod = (event.key === 'F2' || event.code === 'F2') ? 'cash' : 'card';

        saleDebounceTimer = setTimeout(() => {
          saleDebounceTimer = null;
          lastSaleTime = Date.now();
          completeSale(paymentMethod);
        }, 100);
      }
    };

    // Event listener'ları ekle
    window.addEventListener('keydown', handleGlobalBarcode); // Global barkod
    window.addEventListener('keydown', handleKeyPress); // Satış kısayolları

    return () => {
      window.removeEventListener('keydown', handleGlobalBarcode);
      window.removeEventListener('keydown', handleKeyPress);
      if (saleDebounceTimer) {
        clearTimeout(saleDebounceTimer);
        saleDebounceTimer = null;
      }
      if (barcodeTimeout) {
        clearTimeout(barcodeTimeout);
      }
    };
  });

  function handleLogout() {
    if (confirm('Çıkış yapmak istediğinize emin misiniz?')) {
      logout();
    }
  }

  function navigateTo(menu) {
    currentMenu = menu;
  }

  // Login olunca menüyü sıfırla
  $: if ($currentView === 'pos') {
    currentMenu = 'sales';
  }

  function toggleSidebar() {
    sidebarOpen = !sidebarOpen;
  }

  function handleQuantityChange(productId, newQuantity) {
    if (newQuantity <= 0) {
      removeFromCart(productId);
    } else {
      updateCartQuantity(productId, parseInt(newQuantity));
    }
  }

  async function completeSale(paymentMethod) {
    if (isProcessingSale) {
      console.log('⚠️ Satış zaten işleniyor, bekleniyor...');
      return;
    }

    const cartItems = get(cart);
    if (!cartItems || cartItems.length === 0) {
      console.log('⚠️ Sepet boş, satış yapılamaz');
      return;
    }

    isProcessingSale = true;
    lastSaleTime = Date.now();

    try {
      const receiptNumber = `RCP-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      const total = get(cartTotal);
      const config = get(deviceConfig);
      const currentUser = get(user);

      const subtotal = get(cartSubtotal);
      const discountAmt = getDiscountAmount();
      
      const saleData = {
        receipt_number: receiptNumber,
        store_id: config.store_id,
        user_id: currentUser.id,
        device_id: config.device_id,
        total_amount: subtotal,
        discount_amount: discountAmt,
        final_amount: total,
        shift_id: null
      };

      const payments = [{
        method: paymentMethod,
        amount: total
      }];

      const saleId = await saleRepo.create(saleData, cartItems, payments);
      console.log('✅ Satış kaydedildi:', saleId);

      // Print receipt automatically
      try {
        const printData = {
          ...saleData,
          sale_date: Date.now(),
          user_name: currentUser.full_name,
          store_name: config.store_name
        };
        await printReceipt(printData, cartItems, payments);
      } catch (printError) {
        console.error('⚠️ Fiş yazdırma hatası:', printError);
      }

      clearCart();
    } catch (error) {
      console.error('❌ Satış kaydedilemedi:', error);
      alert('Satış kaydedilemedi: ' + error.message);
    } finally {
      isProcessingSale = false;
    }
  }

  function openDiscountModal() {
    const currentDiscount = get(discount);
    if (currentDiscount.type === 'percentage') {
      discountType = 'percentage';
      discountPercentage = currentDiscount.value;
    } else if (currentDiscount.type === 'amount') {
      discountType = 'amount';
      discountAmount = currentDiscount.value;
    } else {
      discountType = 'percentage';
      discountPercentage = 0;
      discountAmount = 0;
    }
    showDiscountModal = true;
  }

  function closeDiscountModal() {
    showDiscountModal = false;
  }

  function applyPercentageDiscount(percentage) {
    discountPercentage = percentage;
    applyDiscount('percentage', percentage);
    showDiscountModal = false;
  }

  function applyAmountDiscount() {
    if (discountAmount > 0) {
      applyDiscount('amount', discountAmount);
      showDiscountModal = false;
    }
  }

  function removeCurrentDiscount() {
    removeDiscount();
    showDiscountModal = false;
  }

  function refreshCurrentScreen() {
    // F5 gibi direkt sayfayı yenile
    window.location.reload();
  }

  function playBeep() {
    try {
      const audioContext = new (window.AudioContext || window.webkitAudioContext)();
      const oscillator = audioContext.createOscillator();
      const gainNode = audioContext.createGain();

      oscillator.connect(gainNode);
      gainNode.connect(audioContext.destination);

      oscillator.frequency.value = 800;
      oscillator.type = 'sine';

      gainNode.gain.setValueAtTime(0.3, audioContext.currentTime);
      gainNode.gain.exponentialRampToValueAtTime(0.01, audioContext.currentTime + 0.1);

      oscillator.start(audioContext.currentTime);
      oscillator.stop(audioContext.currentTime + 0.1);
    } catch (error) {
      console.log('Beep ses çalınamadı:', error);
    }
  }

  // Manuel barkod girişi işleme
  async function handleManualBarcode() {
    const barcode = manualBarcodeInput.trim();
    if (!barcode) return;

    try {
      const product = await productRepo.findByBarcode(barcode);

      if (product) {
        const qty = get(selectedQuantity);
        addToCart(product, qty);
        playBeep();
        manualBarcodeInput = '';
        // Miktarı 1'e sıfırla
        selectedQuantity.set(1);
      } else {
        // Ürün yoksa yeni ürün modal'ı aç
        window.dispatchEvent(new CustomEvent('open-new-product-modal', { detail: { barcode } }));
        manualBarcodeInput = '';
      }
    } catch (error) {
      console.error('Manuel barkod işleme hatası:', error);
    }
  }

  function handleManualBarcodeKeypress(event) {
    if (event.key === 'Enter') {
      event.preventDefault();
      handleManualBarcode();
    }
  }
</script>

<main>
  {#if $currentView === 'loading'}
    <div class="loading-screen">
      <div class="spinner"></div>
      <h2>Yükleniyor...</h2>
    </div>
  {:else if $currentView === 'login'}
    <Login />
  {:else if $currentView === 'pos'}
    <div class="pos-app">
      <!-- Top Navigation Bar -->
      <div class="top-bar">
        <div class="brand">
          <button class="hamburger-menu" on:click={toggleSidebar} title="Menüyü Aç/Kapat">
            ☰
          </button>
          <h1>🏪 Bayer POS</h1>
          <span class="store-badge">{$deviceConfig.store_name}</span>
        </div>

        <div class="user-info">
          <button 
            class="btn-refresh-global" 
            on:click={refreshCurrentScreen}
            title="Ekranı Yenile"
          >
            🔄 Yenile
          </button>
          <button
            class="btn-printer {$deviceConfig.auto_print_enabled ? 'active' : ''}"
            on:click={toggleAutoPrint}
            title={$deviceConfig.auto_print_enabled ? 'Otomatik yazdırma AÇIK' : 'Otomatik yazdırma KAPALI'}
          >
            🖨️ {$deviceConfig.auto_print_enabled ? 'Yazdırma: AÇIK' : 'Yazdırma: KAPALI'}
          </button>
          <div class="user-details">
            <span class="username">👤 {$user.full_name}</span>
            <span class="role">{$user.role === 'admin' ? 'Yönetici' : 'Personel'}</span>
          </div>
          <button class="btn-logout" on:click={handleLogout}>
            🚪 Çıkış
          </button>
        </div>
      </div>

      <!-- Main Content Area -->
      <div class="main-content">
        <!-- Fixed Cart Panel (Only Visible in Sales Screen) -->
        {#if currentMenu === 'sales'}
        <div class="cart-panel">
          <div class="cart-header">
            <h3>🛒 Sepet</h3>
            {#if $cart.length > 0}
              <button class="btn-clear" on:click={clearCart}>🗑️ Temizle</button>
            {/if}
          </div>

          <!-- Manuel Barkod Girişi -->
          <div class="barcode-input-section-top">
            <div class="barcode-input-wrapper">
              <input
                type="text"
                bind:value={manualBarcodeInput}
                on:keypress={handleManualBarcodeKeypress}
                placeholder="Barkod numarası girin..."
                class="barcode-input"
              />
              <button class="btn-barcode-search" on:click={handleManualBarcode}>
                🔍
              </button>
            </div>
          </div>

          <div class="cart-items">
            {#if $cart.length === 0}
              <div class="empty-cart">
                <p>Sepet boş</p>
                <small>Barkod okutun veya ürün seçin</small>
              </div>
            {:else}
              {#each $cart as item}
                <div class="cart-item">
                  <button class="btn-remove" on:click={() => removeFromCart(item.product_id)}>✕</button>
                  <div class="item-details">
                    <div class="item-name">{item.product_name}</div>
                    <div class="item-price">₺{item.unit_price.toFixed(2)}</div>
                  </div>
                  <div class="item-quantity">
                    <button on:click={() => handleQuantityChange(item.product_id, item.quantity - 1)}>-</button>
                    <input
                      type="number"
                      value={item.quantity}
                      on:change={(e) => handleQuantityChange(item.product_id, parseInt(e.target.value))}
                      min="1"
                    />
                    <button on:click={() => handleQuantityChange(item.product_id, item.quantity + 1)}>+</button>
                  </div>
                  <div class="item-total">₺{item.total_price.toFixed(2)}</div>
                </div>
              {/each}
            {/if}
          </div>

          <div class="cart-footer">
            <div class="cart-summary">
              <div class="summary-row">
                <span>Ürün Sayısı:</span>
                <span>{$cart.reduce((sum, item) => sum + item.quantity, 0)} adet</span>
              </div>
              <div class="summary-row">
                <span>Ara Toplam:</span>
                <span>₺{$cartSubtotal.toFixed(2)}</span>
              </div>
              {#if $discount.type && $discount.value > 0}
                <div class="summary-row discount-row">
                  <span>İndirim{#if $discount.type === 'percentage'} (%{$discount.value}){/if}:</span>
                  <span class="discount-amount">
                    {#if $discount.type === 'percentage'}
                      -₺{($cartSubtotal * $discount.value / 100).toFixed(2)}
                    {:else}
                      -₺{Math.min($discount.value, $cartSubtotal).toFixed(2)}
                    {/if}
                  </span>
                </div>
              {/if}
              <div class="summary-row total">
                <span>TOPLAM:</span>
                <span class="total-amount">₺{$cartTotal.toFixed(2)}</span>
              </div>
            </div>

            {#if currentMenu === 'sales'}
              <div class="payment-buttons">
                <button 
                  class="btn-payment btn-cash" 
                  on:click={() => {
                    const now = Date.now();
                    if (isProcessingSale || (now - lastSaleTime) < 1000) {
                      return;
                    }
                    lastSaleTime = now;
                    completeSale('cash');
                  }} 
                  disabled={$cart.length === 0 || isProcessingSale}
                >
                  💵 Nakit (F2)
                </button>
                <button
                  class="btn-payment btn-card"
                  on:click={() => {
                    const now = Date.now();
                    if (isProcessingSale || (now - lastSaleTime) < 1000) {
                      return;
                    }
                    lastSaleTime = now;
                    completeSale('card');
                  }}
                  disabled={$cart.length === 0 || isProcessingSale}
                >
                  💳 Kart (F3)
                </button>
              </div>

              <div class="cart-actions">
                <button
                  class="btn-discount"
                  on:click={openDiscountModal}
                  disabled={$cart.length === 0 || isProcessingSale}
                >
                  🎁 İndirim
                </button>
                <button
                  class="btn-clear-cart"
                  on:click={clearCart}
                  disabled={$cart.length === 0 || isProcessingSale}
                >
                  🗑️ Sepeti Sil (F1)
                </button>
              </div>

            {/if}
          </div>
        </div>
        {/if}

        <!-- Content Area -->
        <div class="content-area {currentMenu === 'sales' ? 'with-cart' : 'full-width'}">
          {#if currentMenu === 'sales'}
            <SalesScreen />
          {:else if currentMenu === 'refunds'}
            <RefundScreen />
          {:else if currentMenu === 'reports'}
            <ReportsViewer />
          {:else if currentMenu === 'stock-alerts'}
            <StockAlerts />
          {:else if currentMenu === 'stock'}
            <StockAdjustment bind:pendingBarcode={pendingBarcodeForStock} />
          {:else if currentMenu === 'users' && $user?.role === 'admin'}
            <UserManagement />
          {/if}
        </div>

        <!-- Menu Overlay (Opens/Closes) -->
        {#if sidebarOpen}
          <div class="menu-overlay" on:click={toggleSidebar}>
            <div class="menu-sidebar" on:click|stopPropagation>
              <div class="menu-header">
                <h2>Menü</h2>
                <button class="btn-close-menu" on:click={toggleSidebar}>✕</button>
              </div>
              <div class="menu">
                <button
                  class="menu-item {currentMenu === 'sales' ? 'active' : ''}"
                  on:click={() => { navigateTo('sales'); toggleSidebar(); }}
                >
                  🛒 Satış Yap
                </button>

                <button
                  class="menu-item {currentMenu === 'refunds' ? 'active' : ''}"
                  on:click={() => { navigateTo('refunds'); toggleSidebar(); }}
                >
                  ↩️ İade İşlemleri
                </button>

                <button
                  class="menu-item {currentMenu === 'reports' ? 'active' : ''}"
                  on:click={() => { navigateTo('reports'); toggleSidebar(); }}
                >
                  📊 Raporlar
                </button>

                {#if $user.role === 'admin'}
                  <button
                    class="menu-item {currentMenu === 'stock-alerts' ? 'active' : ''}"
                    on:click={() => { navigateTo('stock-alerts'); toggleSidebar(); }}
                  >
                    ⚠️ Stok Uyarıları
                  </button>
                  <button
                    class="menu-item {currentMenu === 'stock' ? 'active' : ''}"
                    on:click={() => { navigateTo('stock'); toggleSidebar(); }}
                  >
                    📦 Stok Ayarlama
                  </button>
                  <button
                    class="menu-item {currentMenu === 'users' ? 'active' : ''}"
                    on:click={() => { navigateTo('users'); toggleSidebar(); }}
                  >
                    👥 Kullanıcılar
                  </button>
                {/if}
              </div>
            </div>
          </div>
        {/if}
      </div>
    </div>
  {/if}
</main>

<!-- İndirim Modal -->
{#if showDiscountModal}
  <div class="modal-overlay" on:click={closeDiscountModal} style="display: flex !important; visibility: visible !important; opacity: 1 !important;">
    <div class="discount-modal" on:click|stopPropagation style="display: block !important; visibility: visible !important;">
      <div class="modal-header">
        <h2>🎁 İndirim Uygula</h2>
        <button class="btn-close" on:click={closeDiscountModal}>✕</button>
      </div>

      <div class="modal-body">
        <div class="discount-tabs">
          <button 
            class="discount-tab {discountType === 'percentage' ? 'active' : ''}"
            on:click={() => discountType = 'percentage'}
          >
            Yüzde İndirim
          </button>
          <button 
            class="discount-tab {discountType === 'amount' ? 'active' : ''}"
            on:click={() => discountType = 'amount'}
          >
            Miktar İndirim
          </button>
        </div>

        {#if discountType === 'percentage'}
          <div class="discount-content">
            <h3>Yüzde İndirim Seçin</h3>
            <div class="percentage-buttons">
              <button class="percentage-btn" on:click={() => applyPercentageDiscount(5)}>
                5%
              </button>
              <button class="percentage-btn" on:click={() => applyPercentageDiscount(10)}>
                10%
              </button>
              <button class="percentage-btn" on:click={() => applyPercentageDiscount(15)}>
                15%
              </button>
              <button class="percentage-btn" on:click={() => applyPercentageDiscount(25)}>
                25%
              </button>
            </div>
            <div class="manual-input">
              <label>Özel Yüzde:</label>
              <input
                type="number"
                bind:value={discountPercentage}
                min="0"
                max="100"
                placeholder="0"
                class="discount-input"
              />
              <button 
                class="btn-apply-manual" 
                on:click={() => applyPercentageDiscount(discountPercentage)}
                disabled={discountPercentage <= 0 || discountPercentage > 100}
              >
                Uygula
              </button>
            </div>
          </div>
        {:else}
          {@const previewDiscount = discountAmount > 0 ? Math.min(discountAmount, $cartSubtotal) : 0}
          {@const previewTotal = Math.max(0, $cartSubtotal - previewDiscount)}
          <div class="discount-content">
            <h3>İndirim Miktarı (₺)</h3>
            <div class="amount-input-section">
              <input
                type="number"
                bind:value={discountAmount}
                min="0"
                step="0.01"
                placeholder="0.00"
                class="discount-input large"
              />
              <button 
                class="btn-apply-manual" 
                on:click={applyAmountDiscount}
                disabled={discountAmount <= 0}
              >
                Uygula
              </button>
            </div>
            <div class="discount-preview">
              <p>Ara Toplam: <strong>₺{$cartSubtotal.toFixed(2)}</strong></p>
              <p>İndirim: <strong>-₺{previewDiscount.toFixed(2)}</strong></p>
              <p class="final-total">Yeni Toplam: <strong>₺{previewTotal.toFixed(2)}</strong></p>
            </div>
          </div>
        {/if}

        {#if $discount.type && $discount.value > 0}
          <div class="current-discount">
            <p>Mevcut İndirim:
              {#if $discount.type === 'percentage'}
                %{$discount.value} (-₺{currentDiscountAmount.toFixed(2)})
              {:else}
                ₺{$discount.value.toFixed(2)} (-₺{currentDiscountAmount.toFixed(2)})
              {/if}
            </p>
            <button class="btn-remove-discount" on:click={removeCurrentDiscount}>
              İndirimi Kaldır
            </button>
          </div>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
    background: #f5f7fa;
  }

  :global(*) {
    box-sizing: border-box;
  }

  main {
    width: 100vw;
    height: 100vh;
    overflow: hidden;
  }

  .loading-screen {
    width: 100%;
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background: linear-gradient(135deg, #ff6b35 0%, #f7931e 100%);
    color: white;
  }

  .spinner {
    width: 60px;
    height: 60px;
    border: 5px solid rgba(255, 255, 255, 0.3);
    border-top-color: white;
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin-bottom: 20px;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .pos-app {
    width: 100%;
    height: 100%;
    display: flex;
    flex-direction: column;
  }

  .top-bar {
    background: linear-gradient(135deg, #ff6b35 0%, #f7931e 100%);
    color: white;
    padding: 6px 20px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  }

  .brand {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .hamburger-menu {
    background: rgba(255, 255, 255, 0.2);
    border: 1px solid rgba(255, 255, 255, 0.3);
    border-radius: 6px;
    padding: 8px 12px;
    font-size: 20px;
    color: white;
    cursor: pointer;
    transition: all 0.3s;
    margin-right: 10px;
  }

  .hamburger-menu:hover {
    background: rgba(255, 255, 255, 0.3);
    transform: scale(1.1);
  }

  .brand h1 {
    margin: 0;
    font-size: 14px;
    font-weight: 700;
  }

  .store-badge {
    background: rgba(255, 255, 255, 0.2);
    padding: 3px 8px;
    border-radius: 12px;
    font-size: 11px;
    font-weight: 500;
  }

  .user-info {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .user-details {
    display: flex;
    flex-direction: column;
    align-items: flex-end;
  }

  .username {
    font-weight: 600;
    font-size: 12px;
  }

  .role {
    font-size: 10px;
    opacity: 0.9;
  }

  .btn-printer {
    padding: 5px 12px;
    background: rgba(255, 255, 255, 0.2);
    color: white;
    border: 1px solid rgba(255, 255, 255, 0.3);
    border-radius: 6px;
    font-size: 11px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
    margin-right: 12px;
  }

  .btn-printer:hover {
    background: rgba(255, 255, 255, 0.3);
    transform: translateY(-2px);
  }

  .btn-printer.active {
    background: rgba(76, 175, 80, 0.3);
    border-color: rgba(76, 175, 80, 0.5);
  }

  .btn-logout {
    padding: 5px 12px;
    background: rgba(255, 255, 255, 0.2);
    color: white;
    border: 1px solid rgba(255, 255, 255, 0.3);
    border-radius: 6px;
    font-size: 11px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }

  .btn-logout:hover {
    background: rgba(255, 255, 255, 0.3);
    transform: translateY(-2px);
  }

  .btn-refresh-global {
    padding: 5px 12px;
    background: rgba(255, 255, 255, 0.2);
    color: white;
    border: 1px solid rgba(255, 255, 255, 0.3);
    border-radius: 6px;
    font-size: 11px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
    margin-right: 12px;
  }

  .btn-refresh-global:hover {
    background: rgba(255, 255, 255, 0.3);
    transform: translateY(-2px);
  }

  .main-content {
    flex: 1;
    display: flex;
    overflow: hidden;
    position: relative;
  }

  /* Fixed Cart Panel - Always Visible */
  .cart-panel {
    width: 70%;
    min-width: 400px;
    max-width: 70%;
    background: white;
    border-right: 1px solid #e0e0e0;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    flex-shrink: 0;
    box-sizing: border-box;
  }

  @media (max-width: 1200px) {
    .cart-panel {
      width: 60%;
      max-width: 60%;
      min-width: 350px;
    }
  }

  @media (max-width: 768px) {
    .cart-panel {
      width: 100%;
      max-width: 100%;
      min-width: 100%;
    }
  }

  /* Cart Panel Styles */
  .cart-panel .cart-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 15px;
    border-bottom: 1px solid #e0e0e0;
  }

  .cart-panel .cart-header h3 {
    margin: 0;
    color: #333;
    font-size: 18px;
  }

  .cart-panel .btn-clear {
    padding: 6px 12px;
    background: #f44336;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-size: 12px;
    color: white;
  }

  .cart-panel .btn-clear:hover {
    background: #d32f2f;
  }

  .cart-panel .cart-items {
    flex: 1;
    overflow-y: auto;
    overflow-x: hidden;
    min-height: 0;
    padding: 10px;
    box-sizing: border-box;
  }

  .cart-panel .empty-cart {
    text-align: center;
    padding: 50px 20px;
  }

  .cart-panel .empty-cart p {
    color: #999;
    margin-bottom: 8px;
    font-size: 14px;
  }

  .cart-panel .empty-cart small {
    color: #bbb;
    font-size: 12px;
  }

  .cart-panel .cart-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 12px;
    border-bottom: 1px solid #eee;
    font-size: 13px;
    box-sizing: border-box;
  }

  .cart-panel .btn-remove {
    background: #f44336;
    border: none;
    border-radius: 50%;
    width: 24px;
    height: 24px;
    cursor: pointer;
    flex-shrink: 0;
    font-size: 14px;
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .cart-panel .btn-remove:hover {
    background: #d32f2f;
  }

  .cart-panel .item-details {
    flex: 1;
    min-width: 0;
    overflow: hidden;
  }

  .cart-panel .item-name {
    font-weight: 600;
    margin-bottom: 4px;
    color: #333;
    font-size: 14px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .cart-panel .item-price {
    font-size: 12px;
    color: #666;
  }

  .cart-panel .item-quantity {
    display: flex;
    gap: 5px;
    align-items: center;
  }

  .cart-panel .item-quantity button {
    width: 28px;
    height: 28px;
    border: 1px solid #ddd;
    background: white;
    border-radius: 4px;
    cursor: pointer;
    font-size: 14px;
    color: #333;
  }

  .cart-panel .item-quantity button:hover {
    background: #f0f0f0;
  }

  .cart-panel .item-quantity input {
    width: 50px;
    text-align: center;
    border: 1px solid #ddd;
    border-radius: 4px;
    padding: 4px;
    font-size: 13px;
  }

  .cart-panel .item-total {
    font-weight: 700;
    font-size: 15px;
    min-width: 70px;
    text-align: right;
    color: #333;
  }

  .cart-panel .cart-footer {
    border-top: 2px solid #eee;
    padding: 15px;
    flex-shrink: 0;
    box-sizing: border-box;
  }

  .cart-panel .cart-summary {
    margin-bottom: 10px;
  }

  .cart-panel .summary-row {
    display: flex;
    justify-content: space-between;
    margin-bottom: 5px;
    color: #333;
    font-size: 14px;
  }

  .cart-panel .summary-row.total {
    font-size: 18px;
    font-weight: 700;
    color: #667eea;
    margin-top: 8px;
    padding-top: 8px;
    border-top: 1px solid #eee;
  }

  .cart-panel .total-amount {
    color: #667eea;
  }

  .cart-panel .payment-buttons {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
    margin-top: 10px;
  }

  .cart-panel .btn-payment {
    padding: 14px;
    border: none;
    border-radius: 8px;
    font-size: 15px;
    font-weight: 700;
    cursor: pointer;
    transition: all 0.3s;
    color: white;
  }

  .cart-panel .btn-payment:hover:not(:disabled) {
    transform: translateY(-2px);
  }

  .cart-panel .btn-cash {
    background: #4caf50;
  }

  .cart-panel .btn-cash:hover:not(:disabled) {
    background: #45a049;
  }

  .cart-panel .btn-card {
    background: #2196f3;
  }

  .cart-panel .btn-card:hover:not(:disabled) {
    background: #1976d2;
  }

  .cart-panel .btn-payment:disabled {
    background: #ccc;
    cursor: not-allowed;
    transform: none;
  }

  .cart-panel .btn-clear-cart {
    width: 100%;
    margin-top: 10px;
    padding: 14px;
    background: #f44336;
    border: none;
    border-radius: 8px;
    font-size: 15px;
    font-weight: 700;
    cursor: pointer;
    transition: all 0.3s;
    color: white;
  }

  .cart-panel .btn-clear-cart:hover:not(:disabled) {
    background: #d32f2f;
    transform: translateY(-2px);
  }

  .cart-panel .btn-clear-cart:disabled {
    background: #ccc;
    cursor: not-allowed;
    transform: none;
  }

  .cart-panel .cart-actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
    margin-top: 10px;
  }

  .cart-panel .btn-discount {
    padding: 14px;
    background: #ff9800;
    border: none;
    border-radius: 8px;
    font-size: 15px;
    font-weight: 700;
    cursor: pointer;
    transition: all 0.3s;
    color: white;
  }

  .cart-panel .btn-discount:hover:not(:disabled) {
    background: #f57c00;
    transform: translateY(-2px);
  }

  .cart-panel .btn-discount:disabled {
    background: #ccc;
    cursor: not-allowed;
    transform: none;
  }

  .cart-panel .discount-row {
    color: #ff9800;
    font-weight: 600;
  }

  .cart-panel .discount-amount {
    color: #ff9800;
  }

  /* Menu Styles */
  .menu {
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    flex: 1;
    overflow-y: auto;
  }

  .menu-item {
    padding: 15px 20px;
    background: white;
    border: 2px solid #e0e0e0;
    border-radius: 10px;
    font-size: 16px;
    font-weight: 600;
    text-align: left;
    cursor: pointer;
    transition: all 0.3s;
    color: #333;
  }

  .menu-item:hover:not(:disabled) {
    background: #f8f9fa;
    border-color: #ff6b35;
    transform: translateX(5px);
  }

  .menu-item.active {
    background: linear-gradient(135deg, #ff6b35 0%, #f7931e 100%);
    color: white;
    border-color: transparent;
  }

  .menu-item:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .shift-status {
    padding: 20px;
    border-top: 1px solid #e0e0e0;
  }

  .status-active, .status-closed {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 15px;
    border-radius: 10px;
  }

  .status-active {
    background: #e8f5e9;
    border: 2px solid #4caf50;
  }

  .status-closed {
    background: #ffebee;
    border: 2px solid #f44336;
  }

  .status-icon {
    font-size: 32px;
  }

  .status-text {
    display: flex;
    flex-direction: column;
  }

  .status-text strong {
    font-size: 14px;
    margin-bottom: 4px;
  }

  .status-text small {
    font-size: 12px;
    opacity: 0.8;
  }

  .content-area {
    flex: 1;
    overflow: hidden;
    background: #f5f7fa;
    display: flex;
    flex-direction: column;
    min-width: 0;
    box-sizing: border-box;
    transition: width 0.3s ease;
  }

  .content-area.with-cart {
    width: 30%;
  }

  .content-area.full-width {
    width: 100%;
    max-width: 100%;
  }

  @media (max-width: 1200px) {
    .content-area.with-cart {
      width: 40%;
      min-width: 300px;
    }
  }

  @media (max-width: 768px) {
    .content-area.with-cart {
      width: 0;
      min-width: 0;
      overflow: hidden;
      display: none;
    }

    .content-area.full-width {
      width: 100%;
      display: flex;
    }
  }

  /* Menu Overlay */
  .menu-overlay {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.5);
    z-index: 1000;
    display: flex;
    animation: fadeIn 0.3s ease;
  }

  @keyframes fadeIn {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }

  .menu-sidebar {
    width: 280px;
    background: white;
    box-shadow: 2px 0 10px rgba(0, 0, 0, 0.1);
    display: flex;
    flex-direction: column;
    animation: slideIn 0.3s ease;
    height: 100%;
  }

  @keyframes slideIn {
    from {
      transform: translateX(-100%);
    }
    to {
      transform: translateX(0);
    }
  }

  .menu-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 20px;
    border-bottom: 1px solid #e0e0e0;
  }

  .menu-header h2 {
    margin: 0;
    color: #333;
    font-size: 20px;
  }

  .btn-close-menu {
    background: none;
    border: none;
    font-size: 24px;
    cursor: pointer;
    color: #666;
    padding: 0;
    width: 30px;
    height: 30px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 4px;
  }

  .btn-close-menu:hover {
    background: #f0f0f0;
    color: #333;
  }

  .warning-box {
    margin: 40px auto;
    max-width: 600px;
    background: white;
    padding: 60px;
    border-radius: 16px;
    text-align: center;
    box-shadow: 0 4px 20px rgba(0,0,0,0.1);
  }

  .warning-box h2 {
    margin: 0 0 15px 0;
    color: #f44336;
    font-size: 28px;
  }

  .warning-box p {
    margin: 0 0 30px 0;
    color: #666;
    font-size: 16px;
  }

  .btn-primary {
    padding: 14px 28px;
    background: #ff6b35;
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }

  .btn-primary:hover {
    background: #e55a28;
    transform: translateY(-2px);
    box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
  }

  .placeholder {
    margin: 40px;
    padding: 60px;
    background: white;
    border-radius: 16px;
    text-align: center;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  }

  .placeholder h2 {
    margin: 0 0 15px 0;
    color: #333;
  }

  .placeholder p {
    margin: 0;
    color: #666;
    font-size: 16px;
  }

  /* İndirim Modal Styles */
  .modal-overlay {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.7);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 10000;
  }

  .discount-modal {
    background: white;
    border-radius: 16px;
    width: 90%;
    max-width: 500px;
    max-height: 90vh;
    overflow: auto;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.3);
    position: relative;
    z-index: 10001;
  }

  .discount-modal .modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 20px;
    border-bottom: 1px solid #eee;
  }

  .discount-modal .modal-header h2 {
    margin: 0;
    color: #333;
    font-size: 20px;
  }

  .discount-modal .btn-close {
    background: none;
    border: none;
    font-size: 24px;
    cursor: pointer;
    color: #999;
    padding: 0;
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 4px;
  }

  .discount-modal .btn-close:hover {
    background: #f5f5f5;
    color: #333;
  }

  .discount-modal .modal-body {
    padding: 20px;
  }

  .discount-tabs {
    display: flex;
    gap: 10px;
    margin-bottom: 20px;
    border-bottom: 2px solid #e0e0e0;
  }

  .discount-tab {
    flex: 1;
    padding: 12px;
    background: none;
    border: none;
    border-bottom: 3px solid transparent;
    font-size: 14px;
    font-weight: 600;
    color: #666;
    cursor: pointer;
    transition: all 0.3s;
  }

  .discount-tab:hover {
    color: #ff9800;
  }

  .discount-tab.active {
    color: #ff9800;
    border-bottom-color: #ff9800;
  }

  .discount-content {
    margin-bottom: 20px;
  }

  .discount-content h3 {
    margin: 0 0 15px 0;
    color: #333;
    font-size: 16px;
  }

  .percentage-buttons {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 10px;
    margin-bottom: 20px;
  }

  .percentage-btn {
    padding: 20px;
    background: #f8f9fa;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    font-size: 18px;
    font-weight: 700;
    cursor: pointer;
    transition: all 0.3s;
    color: #333;
  }

  .percentage-btn:hover {
    background: #ff9800;
    border-color: #ff9800;
    color: white;
    transform: translateY(-2px);
  }

  .manual-input {
    display: flex;
    gap: 10px;
    align-items: center;
  }

  .manual-input label {
    font-weight: 600;
    color: #333;
    min-width: 100px;
  }

  .discount-input {
    flex: 1;
    padding: 12px;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    font-size: 16px;
    font-weight: 600;
    text-align: center;
  }

  .discount-input.large {
    font-size: 24px;
    padding: 16px;
  }

  .discount-input:focus {
    outline: none;
    border-color: #ff9800;
  }

  .btn-apply-manual {
    padding: 12px 24px;
    background: #ff9800;
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }

  .btn-apply-manual:hover:not(:disabled) {
    background: #f57c00;
    transform: translateY(-2px);
  }

  .btn-apply-manual:disabled {
    background: #ccc;
    cursor: not-allowed;
  }

  .amount-input-section {
    display: flex;
    flex-direction: column;
    gap: 15px;
    margin-bottom: 20px;
  }

  .discount-preview {
    background: #f8f9fa;
    padding: 15px;
    border-radius: 8px;
    margin-top: 15px;
  }

  .discount-preview p {
    margin: 8px 0;
    color: #333;
    font-size: 14px;
  }

  .discount-preview .final-total {
    margin-top: 15px;
    padding-top: 15px;
    border-top: 2px solid #e0e0e0;
    font-size: 18px;
    color: #ff9800;
  }

  .discount-preview strong {
    color: #333;
  }

  .current-discount {
    background: #fff3cd;
    border: 2px solid #ffc107;
    border-radius: 8px;
    padding: 15px;
    margin-top: 20px;
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .current-discount p {
    margin: 0;
    color: #856404;
    font-weight: 600;
  }

  .btn-remove-discount {
    padding: 8px 16px;
    background: #f44336;
    color: white;
    border: none;
    border-radius: 6px;
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }

  .btn-remove-discount:hover {
    background: #d32f2f;
  }

  /* Manuel Barkod Girişi - Üst */
  .barcode-input-section-top {
    padding: 10px 15px;
    border-bottom: 1px solid #e0e0e0;
    background: #f8f9fa;
  }

  .barcode-input-wrapper {
    display: flex;
    gap: 8px;
  }

  .barcode-input {
    flex: 1;
    padding: 12px 15px;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    font-size: 14px;
    transition: all 0.3s;
  }

  .barcode-input:focus {
    outline: none;
    border-color: #667eea;
    box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
  }

  .barcode-input::placeholder {
    color: #999;
  }

  .btn-barcode-search {
    padding: 12px 16px;
    background: #667eea;
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    cursor: pointer;
    transition: all 0.3s;
  }

  .btn-barcode-search:hover {
    background: #5568d3;
    transform: translateY(-2px);
  }
</style>

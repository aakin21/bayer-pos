<script>
  import { onMount } from 'svelte';
  import { cart, addToCart, clearCart, selectedQuantity, user } from '../../stores/appStore.js';
  import { productRepo, stockRepo } from '../../lib/db/database.js';
  import { v4 as uuidv4 } from 'uuid';


  let barcodelessProducts = [];
  let showNewProductModal = false;
  let isBarcodeless = false;

  // New Product Modal State
  let newProductBarcode = '';
  let newProductName = '';
  let newProductSalePrice = '';
  let newProductPurchasePrice = '';
  let newProductStock = '';

  onMount(async () => {
    await loadBarcodelessProducts();
    
    // Global refresh event listener
    const handleRefresh = () => {
      loadBarcodelessProducts();
    };
    window.addEventListener('refresh-screen', handleRefresh);
    
    // Yeni ürün modal'ı açma event listener
    const handleOpenNewProduct = (event) => {
      const barcode = event.detail?.barcode || null;
      openNewProductModal(barcode);
    };
    window.addEventListener('open-new-product-modal', handleOpenNewProduct);
    
    return () => {
      window.removeEventListener('refresh-screen', handleRefresh);
      window.removeEventListener('open-new-product-modal', handleOpenNewProduct);
    };
  });

  async function loadBarcodelessProducts() {
    const allProducts = await productRepo.findAll();
    // Barkodsuz ürünler: barcode yok, "BARCODESIZ" veya "BARCODESIZ-XXXX" ile başlayan
    barcodelessProducts = allProducts.filter(p => 
      !p.barcode || 
      p.barcode === 'BARCODESIZ' || 
      p.barcode.startsWith('BARCODESIZ-')
    );
  }

  function selectQuantity(qty) {
    selectedQuantity.set(qty);
  }

  function openNewProductModal(barcode = null) {
    isBarcodeless = !barcode;
    // Barkodsuz ürünler için benzersiz barcode oluştur
    if (!barcode) {
      newProductBarcode = `BARCODESIZ-${uuidv4().substring(0, 8).toUpperCase()}`;
    } else {
      newProductBarcode = barcode;
    }
    newProductName = '';
    newProductSalePrice = '';
    newProductPurchasePrice = '';
    newProductStock = '';
    showNewProductModal = true;
  }

  async function saveNewProduct() {
    // Validation
    if (!newProductName || !newProductSalePrice) {
      alert('Ürün adı ve satış fiyatı zorunludur!');
      return;
    }

    const salePrice = parseFloat(newProductSalePrice);
    const purchasePrice = newProductPurchasePrice ? parseFloat(newProductPurchasePrice) : 0;

    if (isNaN(salePrice) || salePrice <= 0) {
      alert('Geçerli bir satış fiyatı girin!');
      return;
    }

    try {
      // Barkodsuz ürünler için benzersiz barcode oluştur (eğer hala "BARCODESIZ" ise)
      let finalBarcode = newProductBarcode;
      if (isBarcodeless && (newProductBarcode === 'BARCODESIZ' || newProductBarcode.startsWith('BARCODESIZ-'))) {
        // Eğer zaten benzersiz değilse, yeni bir tane oluştur
        if (newProductBarcode === 'BARCODESIZ') {
          finalBarcode = `BARCODESIZ-${uuidv4().substring(0, 8).toUpperCase()}`;
        }
      }

      // Ürünü kaydet
      const productId = await productRepo.upsert({
        barcode: finalBarcode,
        name: newProductName.trim(),
        category_id: null,
        purchase_price: purchasePrice,
        sale_price: salePrice,
        is_active: 1
      });

      // Stok ekle (eğer girildiyse ve pozitif ise)
      if (newProductStock && !isNaN(parseInt(newProductStock))) {
        const stockQty = Math.max(0, parseInt(newProductStock));
        if (stockQty > 0) {
          await stockRepo.updateQuantity(productId, stockQty);
        }
      }

      // Barkodsuz ürünleri yenile
      await loadBarcodelessProducts();

      // Modal'ı kapat
      showNewProductModal = false;
    } catch (error) {
      console.error('Ürün kaydedilemedi:', error);
      const errorMessage = error.message || error.toString() || 'Bilinmeyen hata';
      alert('Ürün kaydedilemedi: ' + errorMessage);
    }
  }

  function cancelNewProduct() {
    showNewProductModal = false;
  }

  function selectProduct(product) {
    // Direkt sepete ekle, seçili miktar kadar
    addToCart(product, $selectedQuantity);
    playBeep();
    // Miktarı 1'e çek
    selectedQuantity.set(1);
  }



  function playBeep() {
    // Simple beep sound
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
  }
</script>

<div class="sales-screen">
  <!-- Main Content Panel -->
  <div class="main-panel">
    <!-- Quantity Buttons -->
    <div class="quantity-selection">
      <label>Miktar Seç:</label>
      <div class="quantity-buttons">
        {#each [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] as qty}
          <button
            class="quantity-btn {$selectedQuantity === qty ? 'active' : ''}"
            on:click={() => selectQuantity(qty)}
          >
            {qty}
          </button>
        {/each}
      </div>
    </div>

    <!-- Barcodeless Products -->
    <div class="barcodeless-section">
      <div class="category-header">
        <h3>📦 Barkodsuz Ürünler</h3>
        {#if $user?.role === 'admin'}
          <button class="btn-add-barcodeless" on:click={() => openNewProductModal()}>
            ➕ Yeni Ekle
          </button>
        {/if}
      </div>
      <div class="products-list">
        {#if barcodelessProducts.length === 0}
          <div class="empty-state">
            <p>Henüz barkodsuz ürün yok</p>
            <small>Yukarıdaki "➕ Yeni Ekle" butonuna tıklayarak ekleyin</small>
          </div>
        {:else}
          <div class="products-scroll">
            {#each barcodelessProducts as product}
              <button class="product-card" on:click={() => selectProduct(product)}>
                <div class="product-info">
                  <div class="product-name">{product.name}</div>
                </div>
                <div class="product-price">₺{product.sale_price.toFixed(2)}</div>
              </button>
            {/each}
          </div>
        {/if}
      </div>
    </div>
  </div>
</div>



<!-- New Product Modal -->
{#if showNewProductModal}
  <div class="modal-overlay">
    <div class="new-product-modal">
      <div class="modal-header">
        <h2>🆕 Yeni Ürün Ekle</h2>
        <button class="btn-close" on:click={cancelNewProduct}>✕</button>
      </div>

      <div class="modal-body">
        {#if !isBarcodeless}
          <div class="form-group">
            <label>Barkod Numarası:</label>
            <input
              type="text"
              bind:value={newProductBarcode}
              readonly
              class="barcode-display"
              style="pointer-events: none;"
            />
          </div>
        {/if}

        <div class="form-group">
          <label>Ürün Adı: *</label>
          <input
            type="text"
            bind:value={newProductName}
            placeholder="Ürün adını girin"
            class="product-input"
            autofocus
          />
        </div>

        <div class="form-row">
          <div class="form-group">
            <label>Satış Fiyatı (₺): *</label>
            <input
              type="number"
              bind:value={newProductSalePrice}
              placeholder="0.00"
              step="0.01"
              min="0"
              class="product-input"
            />
          </div>

          <div class="form-group">
            <label>Alış Fiyatı (₺):</label>
            <input
              type="number"
              bind:value={newProductPurchasePrice}
              placeholder="0.00"
              step="0.01"
              min="0"
              class="product-input"
            />
          </div>
        </div>

        <div class="form-group">
          <label>Başlangıç Stok:</label>
          <input
            type="number"
            bind:value={newProductStock}
            placeholder="0"
            step="1"
            min="0"
            class="product-input"
          />
        </div>

        <div class="help-text">
          * Zorunlu alanlar
        </div>
      </div>

      <div class="modal-footer">
        <button class="btn-cancel" on:click={cancelNewProduct}>İptal</button>
        <button class="btn-save" on:click={saveNewProduct}>
          💾 Kaydet ve Sepete Ekle
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  /* GENEL YAZILAR SİYAH */
  * {
    color: #000;
  }

  .sales-screen {
    height: 100%;
    width: 100%;
    padding: 15px;
    background: #f5f5f5;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    box-sizing: border-box;
  }

  .main-panel {
    background: white;
    border-radius: 12px;
    padding: 15px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
    overflow: hidden;
    box-sizing: border-box;
    min-width: 0;
  }

  .quantity-selection {
    margin-bottom: 20px;
    padding: 15px;
    background: #f8f9fa;
    border-radius: 8px;
  }

  .quantity-selection label {
    display: block;
    margin-bottom: 10px;
    font-weight: 600;
    color: #333;
    font-size: 14px;
  }

  .quantity-buttons {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 6px;
  }

  .quantity-btn {
    padding: 12px 8px;
    font-size: 18px;
    font-weight: 700;
    border: 2px solid #667eea;
    background: white;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.2s;
    color: #667eea;
  }

  .quantity-btn:hover {
    background: #667eea;
    color: white;
    transform: scale(1.05);
  }

  .quantity-btn.active {
    background: #667eea;
    color: white;
    box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
  }

  .quantity-btn.active, .quantity-btn.active * {
    color: white !important;
  }

  .barcodeless-section {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0;
    overflow: hidden;
    width: 100%;
    box-sizing: border-box;
  }

  .category-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 15px;
    flex-shrink: 0;
  }

  .category-header h3 {
    margin: 0;
    color: #333;
  }

  .btn-add-barcodeless {
    padding: 10px 20px;
    background: #4caf50;
    border: none;
    border-radius: 8px;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
    white-space: nowrap;
  }

  .btn-add-barcodeless, .btn-add-barcodeless * {
    color: white !important;
  }

  .btn-add-barcodeless:hover {
    background: #45a049;
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(76, 175, 80, 0.3);
  }

  .category-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
    gap: 15px;
    overflow-y: auto;
    flex: 1;
  }

  .category-card {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border: none;
    border-radius: 12px;
    padding: 30px 20px;
    cursor: pointer;
    transition: all 0.3s;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
    min-height: 120px;
  }

  .category-card * {
    color: white !important;
  }

  .category-card:hover {
    transform: translateY(-5px);
    box-shadow: 0 10px 25px rgba(102, 126, 234, 0.3);
  }

  .category-icon {
    font-size: 48px;
  }

  .category-name {
    font-size: 16px;
    font-weight: 600;
    text-align: center;
  }

  /* Products List */
  .products-header {
    display: flex;
    align-items: center;
    gap: 15px;
    margin-bottom: 20px;
    padding-bottom: 15px;
    border-bottom: 2px solid #eee;
  }

  .products-header h3 {
    flex: 1;
    margin: 0;
    color: #333;
  }

  .btn-back {
    padding: 8px 16px;
    background: #667eea;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-size: 14px;
  }

  .btn-back, .btn-back * {
    color: white !important;
  }

  .btn-back:hover {
    background: #5568d3;
  }

  .btn-close-cat {
    padding: 8px 12px;
    background: #f44336;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-size: 16px;
  }

  .btn-close-cat, .btn-close-cat * {
    color: white !important;
  }

  .products-list {
    flex: 1;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    min-height: 0;
    width: 100%;
    box-sizing: border-box;
  }

  .products-scroll {
    flex: 1;
    overflow-y: auto;
    overflow-x: hidden;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    gap: 8px;
    align-content: start;
    padding-right: 8px;
    width: 100%;
    box-sizing: border-box;
  }

  /* Küçük ekranlar için */
  @media (max-width: 400px) {
    .products-scroll {
      grid-template-columns: repeat(2, 1fr);
      gap: 6px;
    }
  }

  /* Kare/dar ekranlar için */
  @media (max-height: 600px) {
    .products-scroll {
      grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
      gap: 6px;
    }
  }

  .products-scroll::-webkit-scrollbar {
    width: 8px;
  }

  .products-scroll::-webkit-scrollbar-track {
    background: #f1f1f1;
    border-radius: 4px;
  }

  .products-scroll::-webkit-scrollbar-thumb {
    background: #667eea;
    border-radius: 4px;
  }

  .products-scroll::-webkit-scrollbar-thumb:hover {
    background: #5568d3;
  }

  .product-card {
    background: #f8f9fa;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    padding: 12px;
    cursor: pointer;
    transition: all 0.2s;
    text-align: left;
    min-height: 70px;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    width: 100%;
    box-sizing: border-box;
  }

  @media (max-height: 600px) {
    .product-card {
      padding: 8px;
      min-height: 60px;
    }
  }

  .product-card:hover {
    border-color: #667eea;
    transform: translateY(-2px);
    box-shadow: 0 5px 15px rgba(0,0,0,0.1);
  }

  .product-name {
    font-weight: 600;
    margin-bottom: 5px;
    color: #333;
  }

  .product-barcode {
    font-size: 12px;
    color: #666;
  }

  .product-price {
    font-size: 12px;
    font-weight: 700;
    color: #667eea;
    margin-top: 4px;
    white-space: nowrap;
  }

  /* Payment Modal */
  .modal-overlay {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0,0,0,0.7);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
  }

  .payment-modal {
    background: white;
    border-radius: 16px;
    width: 90%;
    max-width: 500px;
    max-height: 90vh;
    overflow: auto;
  }

  .payment-modal .modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 20px;
    border-bottom: 1px solid #eee;
  }

  .payment-modal .modal-header h2 {
    margin: 0;
    color: #333;
  }

  .btn-close {
    background: none;
    border: none;
    font-size: 24px;
    cursor: pointer;
    color: #999;
  }

  .btn-close:hover {
    color: #333;
  }

  .payment-summary {
    background: #f8f9fa;
    padding: 20px;
    border-radius: 8px;
    margin-bottom: 20px;
  }

  .payment-summary .summary-row {
    color: #333;
  }

  .payment-summary .large {
    font-size: 32px;
    font-weight: 700;
    color: #667eea;
  }

  .payment-methods {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
    margin-bottom: 20px;
  }

  .payment-method {
    padding: 20px;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    background: white;
    cursor: pointer;
    font-size: 16px;
    transition: all 0.2s;
    color: #333;
  }

  .payment-method.active {
    border-color: #667eea;
    background: #667eea;
  }

  .payment-method.active, .payment-method.active * {
    color: white !important;
  }

  .cash-input-section {
    margin-top: 20px;
  }

  .cash-input-section label {
    display: block;
    margin-bottom: 8px;
    font-weight: 600;
    color: #333;
  }

  .cash-input {
    width: 100%;
    padding: 16px;
    font-size: 24px;
    font-weight: 700;
    text-align: center;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    margin: 10px 0;
  }

  .quick-cash {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 10px;
    margin: 15px 0;
  }

  .quick-cash button {
    padding: 12px;
    border: 1px solid #ddd;
    border-radius: 6px;
    background: white;
    cursor: pointer;
  }

  .quick-cash button:hover {
    background: #f0f0f0;
  }

  .change-amount {
    background: #e8f5e9;
    padding: 20px;
    border-radius: 8px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-top: 15px;
    color: #333;
  }

  .change-value {
    font-size: 28px;
    font-weight: 700;
    color: #4caf50;
  }

  .insufficient-payment {
    background: #ffebee;
    color: #c62828;
    padding: 15px;
    border-radius: 8px;
    margin-top: 15px;
    text-align: center;
  }

  .modal-footer {
    padding: 20px;
    border-top: 1px solid #eee;
    display: flex;
    gap: 10px;
  }

  .btn-cancel {
    flex: 1;
    padding: 14px;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    font-weight: 600;
    cursor: pointer;
    background: #f5f5f5;
    color: #333;
  }

  .btn-cancel:hover {
    background: #e0e0e0;
  }

  .btn-complete, .btn-add {
    flex: 1;
    padding: 14px;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    font-weight: 600;
    cursor: pointer;
    background: #4caf50;
  }

  .btn-complete, .btn-complete *, .btn-add, .btn-add * {
    color: white !important;
  }

  .btn-complete:hover, .btn-add:hover {
    background: #45a049;
  }

  .empty-state {
    text-align: center;
    padding: 50px;
  }

  .empty-state p {
    color: #999;
  }

  /* New Product Modal Styles */
  .new-product-modal {
    background: white;
    border-radius: 16px;
    max-width: 600px;
    width: 90%;
    max-height: 90vh;
    overflow-y: auto;
  }

  .form-group {
    margin-bottom: 20px;
  }

  .form-group label {
    display: block;
    margin-bottom: 8px;
    font-weight: 600;
    color: #333;
    font-size: 14px;
  }

  .form-row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 15px;
  }

  .barcode-display {
    width: 100%;
    padding: 14px;
    font-size: 18px;
    font-weight: 700;
    text-align: center;
    border: 2px solid #4caf50;
    border-radius: 8px;
    background: #e8f5e9;
    color: #2e7d32;
  }

  .product-input, .product-select {
    width: 100%;
    padding: 12px;
    font-size: 16px;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    color: #333;
  }

  .product-input:focus, .product-select:focus {
    outline: none;
    border-color: #667eea;
  }

  .help-text {
    font-size: 12px;
    color: #666;
    font-style: italic;
    margin-top: 10px;
  }

  .btn-save {
    flex: 1;
    padding: 14px;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    font-weight: 600;
    cursor: pointer;
    background: #667eea;
    color: white;
  }

  .btn-save:hover {
    background: #5568d3;
  }
</style>

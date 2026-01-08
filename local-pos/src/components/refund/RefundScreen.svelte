<script>
  import { get } from 'svelte/store';
  import { user, deviceConfig, currentShift } from '../../stores/appStore.js';
  import { saleRepo, refundRepo } from '../../lib/db/database.js';

  let receiptNumber = '';
  let searchError = '';
  let foundSale = null;
  let selectedItems = [];
  let showRefundModal = false;
  let refundSuccess = false;

  import { onMount } from 'svelte';
  
  onMount(() => {
    // Global refresh event listener
    const handleRefresh = () => {
      // Refund ekranında özel bir refresh işlemi yok
      // Sadece formu temizle
      resetForm();
    };
    window.addEventListener('refresh-screen', handleRefresh);
    
    return () => {
      window.removeEventListener('refresh-screen', handleRefresh);
    };
  });

  async function searchSale() {
    searchError = '';
    foundSale = null;
    selectedItems = [];

    if (!receiptNumber || receiptNumber.trim().length === 0) {
      searchError = 'Lütfen fiş numarası girin';
      return;
    }

    try {
      const sale = await saleRepo.findByReceiptNumber(receiptNumber.trim());

      if (!sale) {
        searchError = 'Fiş bulunamadı. Fiş numarasını kontrol edin.';
        return;
      }

      foundSale = sale;

      // Load existing refunds for this sale
      console.log('📦 Checking refunds for sale:', sale.id);
      console.log('📦 refundRepo:', refundRepo);
      console.log('📦 refundRepo.findBySaleId:', refundRepo.findBySaleId);

      const existingRefunds = await refundRepo.findBySaleId(sale.id);
      console.log('📦 Existing refunds:', existingRefunds);

      // Initialize selected items with zero quantities
      selectedItems = sale.items.map(item => {
        // Calculate how much of this item has already been refunded
        const refundedQty = existingRefunds
          .filter(r => r.product_id === item.product_id)
          .reduce((sum, r) => sum + r.quantity, 0);

        const remainingQty = item.quantity - refundedQty;

        console.log(`📦 Item ${item.product_name}: original=${item.quantity}, refunded=${refundedQty}, remaining=${remainingQty}`);

        return {
          ...item,
          refund_quantity: 0,
          max_quantity: remainingQty,
          already_refunded: refundedQty
        };
      });

    } catch (error) {
      searchError = 'Fiş aranırken hata oluştu: ' + error.message;
    }
  }

  function updateRefundQuantity(index, value) {
    const quantity = parseInt(value) || 0;
    const maxQty = selectedItems[index].max_quantity;

    selectedItems[index].refund_quantity = Math.max(0, Math.min(quantity, maxQty));
  }

  function getRefundTotal() {
    return selectedItems.reduce((sum, item) => {
      // İndirimli fiyatı hesapla
      const discountedPrice = getDiscountedUnitPrice(item);
      return sum + (item.refund_quantity * discountedPrice);
    }, 0);
  }

  function getDiscountedUnitPrice(item) {
    // Eğer satışta indirim varsa, indirimli fiyatı hesapla
    if (!foundSale || !foundSale.discount_amount || foundSale.discount_amount === 0) {
      return item.unit_price;
    }

    // Toplam tutarı hesapla
    const totalOriginalPrice = foundSale.items.reduce((sum, i) => {
      return sum + (i.quantity * i.unit_price);
    }, 0);

    if (totalOriginalPrice === 0) {
      return item.unit_price;
    }

    // İndirim oranını hesapla
    const discountRatio = foundSale.discount_amount / totalOriginalPrice;
    
    // Bu ürün için indirimli fiyatı hesapla
    const discountedPrice = item.unit_price * (1 - discountRatio);
    
    return discountedPrice;
  }

  function canProceedRefund() {
    return selectedItems.some(item => item.refund_quantity > 0);
  }

  function openRefundModal() {
    if (selectedItems.every(item => item.refund_quantity === 0)) {
      return;
    }

    showRefundModal = true;
  }

  async function processRefund() {
    if (!canProceedRefund()) {
      return;
    }

    try {
      console.log('🔄 İade işlemi başlatılıyor...');
      const itemsToRefund = selectedItems.filter(item => item.refund_quantity > 0);

      const config = get(deviceConfig);
      const currentUser = get(user);
      const shift = get(currentShift);

      console.log('📦 İade edilecek ürünler:', itemsToRefund.length);
      console.log('📦 Config:', config);
      console.log('📦 User:', currentUser);
      console.log('📦 Shift:', shift);

      for (const item of itemsToRefund) {
        console.log(`🔄 İade ediliyor: ${item.product_name} x${item.refund_quantity}`);

        // Validate item data
        if (!item.product_id) {
          throw new Error(`Ürün ID eksik: ${item.product_name}`);
        }
        if (!item.product_name) {
          throw new Error(`Ürün adı eksik: ${item.product_id}`);
        }
        if (!foundSale.id) {
          throw new Error('Satış ID eksik');
        }

        // İndirimli fiyatı hesapla
        const discountedUnitPrice = getDiscountedUnitPrice(item);
        
        const refundData = {
          sale_id: foundSale.id,
          sale_item_id: item.id, // sale_item id'si
          product_id: item.product_id,
          product_name: item.product_name,
          quantity: item.refund_quantity,
          unit_price: discountedUnitPrice, // İndirimli fiyat
          purchase_price: item.purchase_price || 0,
          refund_amount: item.refund_quantity * discountedUnitPrice, // İndirimli tutar
          store_id: config.store_id,
          user_id: currentUser.id,
          device_id: config.device_id,
          shift_id: shift ? shift.id : null
        };

        console.log('📦 Refund data:', refundData);

        // Validate refundData
        if (!refundData.store_id) {
          throw new Error('Store ID eksik - lütfen cihazı yeniden aktifleştirin');
        }
        if (!refundData.user_id) {
          throw new Error('User ID eksik - lütfen yeniden giriş yapın');
        }

        console.log('📦 Calling refundRepo.create...');
        console.log('📦 refundRepo:', refundRepo);

        // AWAIT kullan - bu çok önemli!
        const refundId = await refundRepo.create(refundData);
        console.log(`✅ İade kaydedildi: ${refundId}`);
      }

      showRefundModal = false;
      refundSuccess = true;

      console.log('✅ Tüm iade işlemleri tamamlandı!');

      // Fişi yeniden yükle (refund_status güncellenmiş olacak)
      await searchSale();

      setTimeout(() => {
        resetForm();
      }, 3000);

    } catch (error) {
      console.error('❌ İade hatası:', error);
      console.error('Error type:', typeof error);
      console.error('Error object:', error);
      console.error('Error message:', error?.message);
      console.error('Error stack:', error?.stack);
      console.error('Error string:', String(error));

      const errorMsg = error?.message || error?.toString() || 'Bilinmeyen hata';
      alert('İade işlemi başarısız: ' + errorMsg);
      showRefundModal = false;
    }
  }

  function resetForm() {
    receiptNumber = '';
    foundSale = null;
    selectedItems = [];
    searchError = '';
    refundSuccess = false;
  }

  function handleKeyPress(event) {
    if (event.key === 'Enter') {
      searchSale();
    }
  }
</script>

<div class="refund-screen">
  <div class="header">
    <h2>↩️ İade İşlemleri</h2>
  </div>

  {#if refundSuccess}
    <div class="success-banner">
      ✅ İade işlemi başarıyla tamamlandı!
    </div>
  {/if}

  <!-- Search Section -->
  <div class="search-section">
    <div class="search-box">
      <label for="receipt-input">Fiş Numarası:</label>
      <div class="search-input-group">
        <input
          id="receipt-input"
          type="text"
          bind:value={receiptNumber}
          on:keypress={handleKeyPress}
          placeholder="RCP-1234567890-ABC"
          class="receipt-input"
        />
        <button class="btn-search" on:click={searchSale}>
          🔍 Ara
        </button>
      </div>
      {#if searchError}
        <div class="error-message">{searchError}</div>
      {/if}
    </div>
  </div>

  {#if foundSale}
    <!-- Sale Details -->
    <div class="sale-details">
      <div class="details-header">
        <h3>📋 Satış Detayları</h3>
        <button class="btn-new-search" on:click={resetForm}>
          🔄 Yeni Arama
        </button>
      </div>

      <div class="info-grid">
        <div class="info-item">
          <span class="label">Fiş No:</span>
          <span class="value">{foundSale.receipt_number}</span>
        </div>
        <div class="info-item">
          <span class="label">Tarih:</span>
          <span class="value">{new Date(foundSale.created_at).toLocaleString('tr-TR')}</span>
        </div>
        <div class="info-item">
          <span class="label">Toplam Tutar:</span>
          <span class="value">₺{foundSale.final_amount.toFixed(2)}</span>
        </div>
        <div class="info-item">
          <span class="label">Ödeme Yöntemi:</span>
          <span class="value">
            {foundSale.payments.map(p => p.method === 'cash' ? 'Nakit' : 'Kart').join(', ')}
          </span>
        </div>
      </div>
    </div>

    <!-- Items to Refund -->
    <div class="items-section">
      <h3>🛒 Ürünler</h3>
      <p class="instruction">İade edilecek ürünlerin miktarını girin:</p>

      <div class="items-table">
        <div class="table-header">
          <div class="col">Ürün</div>
          <div class="col">Birim Fiyat</div>
          <div class="col">Satılan Miktar</div>
          <div class="col">İade Miktarı</div>
          <div class="col">İade Tutarı</div>
        </div>

        {#each selectedItems as item, index}
          <div class="table-row">
            <div class="col product-name">
              {item.product_name}
              <small>{item.barcode}</small>
              {#if item.already_refunded > 0}
                <small class="refunded-info">⚠️ Daha önce {item.already_refunded} adet iade edildi</small>
              {/if}
            </div>
            <div class="col">
              ₺{getDiscountedUnitPrice(item).toFixed(2)}
              {#if foundSale.discount_amount > 0}
                <br/><small class="original-price">Orijinal: ₺{item.unit_price.toFixed(2)}</small>
              {/if}
            </div>
            <div class="col">
              {item.quantity}
              {#if item.already_refunded > 0}
                <br/><small class="refunded-qty">İade edilebilir: {item.max_quantity}</small>
              {/if}
            </div>
            <div class="col">
              <input
                type="number"
                min="0"
                max={item.max_quantity}
                value={item.refund_quantity}
                on:input={(e) => updateRefundQuantity(index, e.target.value)}
                class="quantity-input"
                disabled={item.max_quantity === 0}
              />
            </div>
            <div class="col total">
              ₺{(item.refund_quantity * getDiscountedUnitPrice(item)).toFixed(2)}
            </div>
          </div>
        {/each}
      </div>

      <div class="refund-summary">
        <div class="summary-label">İade Toplam:</div>
        <div class="summary-amount">₺{getRefundTotal().toFixed(2)}</div>
      </div>

      <button
        class="btn-proceed-refund"
        on:click={openRefundModal}
        disabled={selectedItems.every(item => item.refund_quantity === 0)}
      >
        ✅ İade İşlemine Geç
      </button>
    </div>
  {:else if !searchError}
    <div class="empty-state">
      <div class="empty-icon">🔍</div>
      <h3>Fiş Ara</h3>
      <p>İade işlemi yapmak için fiş numarasını girin ve arama yapın.</p>
    </div>
  {/if}
</div>

<!-- Refund Confirmation Modal -->
{#if showRefundModal}
  <div class="modal-overlay">
    <div class="modal">
      <div class="modal-header">
        <h2>↩️ İade Onayı</h2>
        <button class="btn-close" on:click={() => showRefundModal = false}>✕</button>
      </div>

      <div class="modal-body">
        <div class="confirmation-summary">
          <h3>İade Özeti</h3>
          <div class="summary-grid">
            <div class="summary-item">
              <span>Fiş No:</span>
              <strong>{foundSale.receipt_number}</strong>
            </div>
            <div class="summary-item">
              <span>İade Tutarı:</span>
              <strong>₺{getRefundTotal().toFixed(2)}</strong>
            </div>
          </div>

          <div class="refunded-items">
            <h4>İade Edilecek Ürünler:</h4>
            <ul>
              {#each selectedItems.filter(i => i.refund_quantity > 0) as item}
                <li>
                  {item.product_name} - {item.refund_quantity} adet
                  (₺{(item.refund_quantity * getDiscountedUnitPrice(item)).toFixed(2)})
                </li>
              {/each}
            </ul>
          </div>
        </div>
      </div>

      <div class="modal-footer">
        <button class="btn-cancel" on:click={() => showRefundModal = false}>
          İptal
        </button>
        <button
          class="btn-confirm"
          on:click={processRefund}
          disabled={!canProceedRefund()}
        >
          ✅ İade İşlemini Onayla
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .refund-screen {
    padding: 10px;
    width: 100%;
    height: 100%;
    overflow-y: auto;
    box-sizing: border-box;
  }

  .header {
    margin-bottom: 10px;
  }

  .header h2 {
    margin: 0;
    font-size: 18px;
    color: #333;
  }

  .success-banner {
    background: #4caf50;
    color: white;
    padding: 15px 20px;
    border-radius: 8px;
    margin-bottom: 20px;
    font-weight: 600;
    text-align: center;
    animation: slideDown 0.3s ease;
  }

  @keyframes slideDown {
    from {
      opacity: 0;
      transform: translateY(-10px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .search-section {
    background: white;
    padding: 12px;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    margin-bottom: 10px;
  }

  .search-box label {
    display: block;
    font-weight: 600;
    margin-bottom: 6px;
    color: #333;
    font-size: 13px;
  }

  .search-input-group {
    display: flex;
    gap: 10px;
  }

  .receipt-input {
    flex: 1;
    padding: 8px 12px;
    border: 2px solid #e0e0e0;
    border-radius: 6px;
    font-size: 14px;
    font-family: monospace;
    transition: all 0.3s;
  }

  .receipt-input:focus {
    outline: none;
    border-color: #667eea;
    box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
  }

  .btn-search {
    padding: 8px 16px;
    background: #667eea;
    color: white;
    border: none;
    border-radius: 6px;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }

  .btn-search:hover {
    background: #5568d3;
    transform: translateY(-2px);
    box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
  }

  .error-message {
    background: #ffebee;
    color: #c62828;
    padding: 12px;
    border-radius: 8px;
    margin-top: 10px;
    border-left: 4px solid #c62828;
  }

  .sale-details {
    background: white;
    padding: 12px;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    margin-bottom: 10px;
  }

  .details-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 10px;
  }

  .details-header h3 {
    margin: 0;
    font-size: 14px;
    color: #333;
  }

  .btn-new-search {
    padding: 8px 16px;
    background: #f5f5f5;
    color: #333;
    border: 1px solid #e0e0e0;
    border-radius: 6px;
    cursor: pointer;
    font-weight: 500;
    transition: all 0.3s;
  }

  .btn-new-search:hover {
    background: #e0e0e0;
  }

  .info-grid {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 8px;
  }

  .info-item {
    display: flex;
    justify-content: space-between;
    padding: 8px;
    background: #f8f9fa;
    border-radius: 6px;
    font-size: 12px;
  }

  .info-item .label {
    font-weight: 600;
    color: #666;
  }

  .info-item .value {
    font-weight: 500;
    color: #333;
  }

  .items-section {
    background: white;
    padding: 12px;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  }

  .items-section h3 {
    margin: 0 0 6px 0;
    font-size: 14px;
    color: #333;
  }

  .instruction {
    margin: 0 0 10px 0;
    color: #666;
    font-size: 12px;
  }

  .items-table {
    border: 1px solid #e0e0e0;
    border-radius: 8px;
    overflow: hidden;
    margin-bottom: 20px;
  }

  .table-header {
    display: grid;
    grid-template-columns: 2fr 1fr 1fr 1fr 1fr;
    background: #f8f9fa;
    font-weight: 600;
    padding: 8px;
    border-bottom: 2px solid #e0e0e0;
    font-size: 12px;
  }

  .table-row {
    display: grid;
    grid-template-columns: 2fr 1fr 1fr 1fr 1fr;
    padding: 8px;
    border-bottom: 1px solid #e0e0e0;
    align-items: center;
    font-size: 12px;
  }

  .table-row:last-child {
    border-bottom: none;
  }

  .table-row:hover {
    background: #f8f9fa;
  }

  .col {
    padding: 0 5px;
  }

  .product-name {
    display: flex;
    flex-direction: column;
  }

  .product-name small {
    color: #999;
    font-size: 12px;
    margin-top: 3px;
  }

  .refunded-info {
    display: block;
    color: #f57c00;
    font-weight: 600;
    margin-top: 5px;
  }

  .refunded-qty {
    color: #1976d2;
    font-weight: 600;
  }

  .original-price {
    color: #999;
    font-size: 10px;
    text-decoration: line-through;
  }

  .quantity-input {
    width: 60px;
    padding: 6px;
    border: 2px solid #e0e0e0;
    border-radius: 6px;
    font-size: 13px;
    text-align: center;
    font-weight: 600;
  }

  .quantity-input:focus {
    outline: none;
    border-color: #667eea;
  }

  .total {
    font-weight: 600;
    color: #4caf50;
  }

  .refund-summary {
    display: flex;
    justify-content: flex-end;
    align-items: center;
    gap: 15px;
    padding: 12px;
    background: #f8f9fa;
    border-radius: 8px;
    margin-bottom: 10px;
  }

  .summary-label {
    font-size: 14px;
    font-weight: 600;
    color: #333;
  }

  .summary-amount {
    font-size: 20px;
    font-weight: 700;
    color: #f44336;
  }

  .btn-proceed-refund {
    width: 100%;
    padding: 12px;
    background: #f44336;
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
    margin-top: 10px;
  }

  .btn-proceed-refund:hover:not(:disabled) {
    background: #d32f2f;
    transform: translateY(-2px);
    box-shadow: 0 5px 15px rgba(244, 67, 54, 0.4);
  }

  .btn-proceed-refund:disabled {
    background: #ccc;
    cursor: not-allowed;
  }

  .empty-state {
    text-align: center;
    padding: 80px 40px;
    background: white;
    border-radius: 12px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  }

  .empty-icon {
    font-size: 80px;
    margin-bottom: 20px;
  }

  .empty-state h3 {
    margin: 0 0 10px 0;
    color: #333;
    font-size: 24px;
  }

  .empty-state p {
    margin: 0;
    color: #666;
    font-size: 16px;
  }

  /* Modal Styles */
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

  .modal {
    background: white;
    border-radius: 16px;
    width: 90%;
    max-width: 600px;
    max-height: 90vh;
    overflow: auto;
  }

  .modal-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 20px;
    border-bottom: 1px solid #eee;
  }

  .modal-header h2 {
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

  .modal-body {
    padding: 20px;
  }

  .confirmation-summary {
    background: #f8f9fa;
    padding: 20px;
    border-radius: 8px;
    margin-bottom: 20px;
  }

  .confirmation-summary h3 {
    margin: 0 0 15px 0;
    font-size: 18px;
  }

  .summary-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
    margin-bottom: 15px;
  }

  .summary-item {
    display: flex;
    justify-content: space-between;
    padding: 10px;
    background: white;
    border-radius: 6px;
  }

  .refunded-items h4 {
    margin: 15px 0 10px 0;
    font-size: 16px;
  }

  .refunded-items ul {
    margin: 0;
    padding-left: 20px;
  }

  .refunded-items li {
    margin-bottom: 8px;
    color: #333;
  }

  .form-group {
    margin: 20px 0;
  }

  .form-group label {
    display: block;
    font-weight: 600;
    margin-bottom: 8px;
    color: #333;
  }

  .reason-textarea {
    width: 100%;
    padding: 12px;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    font-size: 14px;
    font-family: inherit;
    resize: vertical;
    transition: all 0.3s;
  }

  .reason-textarea:focus {
    outline: none;
    border-color: #667eea;
    box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
  }

  .modal-footer {
    padding: 20px;
    border-top: 1px solid #eee;
    display: flex;
    gap: 10px;
  }

  .btn-cancel, .btn-confirm {
    flex: 1;
    padding: 14px;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }

  .btn-cancel {
    background: #f5f5f5;
    color: #333;
  }

  .btn-cancel:hover {
    background: #e0e0e0;
  }

  .btn-confirm {
    background: #f44336;
    color: white;
  }

  .btn-confirm:hover:not(:disabled) {
    background: #d32f2f;
  }

  .btn-confirm:disabled {
    background: #ccc;
    cursor: not-allowed;
  }
</style>

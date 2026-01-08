<script>
  import { onMount } from 'svelte';
  import { stockRepo, productRepo } from '../../lib/db/database.js';
  import { user } from '../../stores/appStore.js';

  let lowStockProducts = [];
  let loading = true;

  // Admin mi kontrol et
  $: isAdmin = $user?.role === 'admin';

  onMount(async () => {
    await loadLowStockProducts();
    
    // Global refresh event listener
    const handleRefresh = () => {
      loadLowStockProducts();
    };
    window.addEventListener('refresh-screen', handleRefresh);
    
    return () => {
      window.removeEventListener('refresh-screen', handleRefresh);
    };
  });

  async function loadLowStockProducts() {
    loading = true;
    try {
      const allStocks = await stockRepo.findAll();
      const allProducts = await productRepo.findAll();
      
      lowStockProducts = allStocks
        .map(stock => {
          const product = allProducts.find(p => p.id === stock.product_id);
          if (!product || !product.is_active) return null;

          const currentStock = stock.quantity || 0;

          // 20 altında uyarı göster
          if (currentStock < 20) {
            let stockStatus;
            if (currentStock === 0) {
              stockStatus = 'critical'; // Stok yok
            } else if (currentStock < 10) {
              stockStatus = 'low'; // 10 altında - düşük
            } else {
              stockStatus = 'warning'; // 10-19 arası - uyarı
            }

            return {
              ...product,
              currentStock,
              minStock: currentStock < 10 ? 10 : 20,
              stockStatus
            };
          }
          return null;
        })
        .filter(p => p !== null)
        .sort((a, b) => a.currentStock - b.currentStock); // En azdan en çoğa
    } catch (error) {
      console.error('Stok uyarıları yükleme hatası:', error);
    } finally {
      loading = false;
    }
  }

  function getStockStatusClass(status) {
    switch (status) {
      case 'critical': return 'status-critical';
      case 'low': return 'status-low';
      case 'warning': return 'status-warning';
      default: return '';
    }
  }

  function getStockStatusText(status) {
    switch (status) {
      case 'critical': return 'Kritik';
      case 'low': return 'Düşük';
      case 'warning': return 'Uyarı';
      default: return '';
    }
  }
</script>

<div class="stock-alerts">
  <div class="header">
    <h2>⚠️ Stok Uyarıları</h2>
    <button class="btn-refresh" on:click={loadLowStockProducts} title="Yenile">
      🔄 Yenile
    </button>
  </div>

  {#if loading}
    <div class="loading-state">
      <div class="spinner"></div>
      <p>Yükleniyor...</p>
    </div>
  {:else if lowStockProducts.length === 0}
    <div class="empty-state">
      <div class="empty-icon">✅</div>
      <h3>Tüm ürünlerde yeterli stok var</h3>
      <p>Düşük stoklu ürün bulunmuyor.</p>
    </div>
  {:else}
    <div class="alerts-summary">
      <div class="summary-card critical">
        <div class="summary-icon">🔴</div>
        <div class="summary-content">
          <div class="summary-label">Kritik Stok</div>
          <div class="summary-value">{lowStockProducts.filter(p => p.stockStatus === 'critical').length}</div>
        </div>
      </div>
      <div class="summary-card low">
        <div class="summary-icon">🟠</div>
        <div class="summary-content">
          <div class="summary-label">Düşük Stok</div>
          <div class="summary-value">{lowStockProducts.filter(p => p.stockStatus === 'low').length}</div>
        </div>
      </div>
      <div class="summary-card warning">
        <div class="summary-icon">🟡</div>
        <div class="summary-content">
          <div class="summary-label">Uyarı</div>
          <div class="summary-value">{lowStockProducts.filter(p => p.stockStatus === 'warning').length}</div>
        </div>
      </div>
    </div>

    <div class="alerts-table">
      <div class="table-header">
        <div>Sıra</div>
        <div>Ürün Adı</div>
        <div>Barkod</div>
        <div>Mevcut Stok</div>
        <div>Min. Stok</div>
        <div>Durum</div>
      </div>

      {#each lowStockProducts as product, index}
        <div class="table-row {getStockStatusClass(product.stockStatus)}">
          <div class="rank">{index + 1}</div>
          <div class="product-name">{product.name}</div>
          <div class="barcode">{product.barcode}</div>
          <div class="stock-value {getStockStatusClass(product.stockStatus)}">
            {isAdmin ? product.currentStock : 'xxx'} adet
          </div>
          <div class="min-stock">{isAdmin ? product.minStock : 'xxx'} adet</div>
          <div class="status-badge {getStockStatusClass(product.stockStatus)}">
            {getStockStatusText(product.stockStatus)}
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .stock-alerts {
    padding: 20px;
    width: 100%;
    height: 100%;
    overflow-y: auto;
    background: #f5f7fa;
  }

  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 20px;
  }

  .header h2 {
    margin: 0;
    font-size: 24px;
    color: #333;
  }

  .btn-refresh {
    padding: 10px 20px;
    background: #667eea;
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }

  .btn-refresh:hover {
    background: #5568d3;
    transform: translateY(-2px);
  }

  .loading-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 60px;
  }

  .spinner {
    width: 50px;
    height: 50px;
    border: 4px solid #f3f3f3;
    border-top: 4px solid #667eea;
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin-bottom: 20px;
  }

  @keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
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

  .alerts-summary {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 15px;
    margin-bottom: 25px;
  }

  .summary-card {
    background: white;
    border-radius: 12px;
    padding: 20px;
    display: flex;
    align-items: center;
    gap: 15px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
  }

  .summary-card.critical {
    border-left: 4px solid #f44336;
  }

  .summary-card.low {
    border-left: 4px solid #ff9800;
  }

  .summary-card.warning {
    border-left: 4px solid #fbc02d;
  }

  .summary-icon {
    font-size: 40px;
  }

  .summary-content {
    flex: 1;
  }

  .summary-label {
    font-size: 13px;
    color: #666;
    margin-bottom: 5px;
  }

  .summary-value {
    font-size: 28px;
    font-weight: 700;
    color: #333;
  }

  .alerts-table {
    background: white;
    border-radius: 12px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    overflow: hidden;
  }

  .table-header {
    display: grid;
    grid-template-columns: 60px 2fr 1fr 1fr 1fr 1fr;
    background: #f8f9fa;
    font-weight: 600;
    padding: 15px;
    border-bottom: 2px solid #e0e0e0;
    color: #333;
  }

  .table-row {
    display: grid;
    grid-template-columns: 60px 2fr 1fr 1fr 1fr 1fr;
    padding: 15px;
    border-bottom: 1px solid #e0e0e0;
    align-items: center;
    transition: all 0.3s;
  }

  .table-row:hover {
    background: #f8f9fa;
  }

  .table-row.status-critical {
    background: #ffebee;
    border-left: 4px solid #f44336;
  }

  .table-row.status-low {
    background: #fff3e0;
    border-left: 4px solid #ff9800;
  }

  .table-row.status-warning {
    background: #fff9c4;
    border-left: 4px solid #fbc02d;
  }

  .rank {
    font-weight: 700;
    color: #667eea;
    font-size: 16px;
  }

  .product-name {
    font-weight: 600;
    color: #333;
  }

  .barcode {
    font-family: monospace;
    font-size: 13px;
    color: #666;
  }

  .stock-value {
    font-weight: 700;
    font-size: 16px;
  }

  .stock-value.status-critical {
    color: #f44336;
  }

  .stock-value.status-low {
    color: #ff9800;
  }

  .stock-value.status-warning {
    color: #fbc02d;
  }

  .min-stock {
    color: #666;
  }

  .status-badge {
    padding: 6px 12px;
    border-radius: 6px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    text-align: center;
    display: inline-block;
  }

  .status-badge.status-critical {
    background: #f44336;
    color: white;
  }

  .status-badge.status-low {
    background: #ff9800;
    color: white;
  }

  .status-badge.status-warning {
    background: #fbc02d;
    color: #333;
  }
</style>

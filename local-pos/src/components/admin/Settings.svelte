<script>
  import { deviceConfig } from '../../stores/appStore.js';
  import { appDataDir } from '@tauri-apps/api/path';
  import { readFile, writeFile } from '@tauri-apps/plugin-fs';
  import { save } from '@tauri-apps/plugin-dialog';
  import { onMount } from 'svelte';

  let dbPath = 'Yükleniyor...';
  let isBackingUp = false;
  let backupMessage = '';

  onMount(async () => {
    try {
      const dataDir = await appDataDir();
      dbPath = `${dataDir}pos.db`.replace(/\\/g, '\\');
    } catch (error) {
      console.error('Database path error:', error);
      dbPath = '%APPDATA%\\com.bayer.pos\\pos.db';
    }
  });

  async function backupDatabase() {
    if (isBackingUp) return;
    
    try {
      isBackingUp = true;
      backupMessage = 'Yedekleme başlatılıyor...';

      // Database dosya yolunu al
      const dataDir = await appDataDir();
      const sourcePath = `${dataDir}pos.db`;
      
      // Kullanıcıdan kayıt konumu seç
      const date = new Date();
      const dateStr = date.toISOString().split('T')[0].replace(/-/g, '');
      const timeStr = date.toTimeString().split(' ')[0].replace(/:/g, '').substring(0, 6);
      const defaultFileName = `bayer-pos-backup-${dateStr}-${timeStr}.db`;

      const filePath = await save({
        defaultPath: defaultFileName,
        filters: [{
          name: 'Database Files',
          extensions: ['db', 'sqlite', 'sqlite3']
        }]
      });

      if (!filePath) {
        backupMessage = 'Yedekleme iptal edildi.';
        setTimeout(() => backupMessage = '', 2000);
        return;
      }

      // Dosyayı oku ve yeni konuma yaz
      backupMessage = 'Database kopyalanıyor...';
      const fileData = await readFile(sourcePath);
      await writeFile(filePath, fileData);

      backupMessage = '✅ Yedekleme başarılı!';
      setTimeout(() => backupMessage = '', 3000);
    } catch (error) {
      console.error('Yedekleme hatası:', error);
      backupMessage = `❌ Hata: ${error.message || 'Bilinmeyen hata'}`;
      setTimeout(() => backupMessage = '', 5000);
    } finally {
      isBackingUp = false;
    }
  }
</script>

<div class="settings">
  <h2>⚙️ Ayarlar</h2>

  <div class="settings-section">
    <h3>Cihaz Bilgileri</h3>
    <div class="info-row"><span>Cihaz ID:</span><strong>{$deviceConfig.device_id}</strong></div>
    <div class="info-row"><span>Mağaza:</span><strong>{$deviceConfig.store_name}</strong></div>
    <div class="info-row"><span>Mağaza ID:</span><strong>{$deviceConfig.store_id}</strong></div>
    <div class="info-row"><span>API URL:</span><strong>{$deviceConfig.api_url}</strong></div>
  </div>

  <div class="settings-section">
    <h3>Uygulama</h3>
    <div class="info-row"><span>Versiyon:</span><strong>1.0.0</strong></div>
    <div class="info-row"><span>Platform:</span><strong>Tauri</strong></div>
  </div>

  <div class="settings-section important">
    <h3>📦 Database Bilgisi</h3>
    <div class="info-row"><span>Database Konumu:</span><strong class="db-path">{dbPath}</strong></div>
    <div class="warning-box">
      <strong>⚠️ ÖNEMLİ:</strong> Database bu konumda saklanır ve güncellemeler sırasında <strong>OTOMATIK KORUNUR</strong>.
      Tüm ürünler, satışlar ve veriler güvendedir.
    </div>
    
    <div class="backup-section">
      <h4>💾 Database Yedekleme</h4>
      <p class="backup-info">
        Güncelleme öncesi veya düzenli olarak database yedeği almanız önerilir.
        Yedek dosyasını USB, Cloud veya güvenli bir yere kaydedebilirsiniz.
      </p>
      <button 
        class="btn-backup" 
        on:click={backupDatabase}
        disabled={isBackingUp}
      >
        {#if isBackingUp}
          ⏳ Yedekleniyor...
        {:else}
          💾 Database Yedekle
        {/if}
      </button>
      {#if backupMessage}
        <div class="backup-message {backupMessage.includes('✅') ? 'success' : backupMessage.includes('❌') ? 'error' : 'info'}">
          {backupMessage}
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  .settings { padding: 20px; max-width: 800px; }
  .settings-section { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
  .settings-section.important { border: 2px solid #4CAF50; background: #f0f9f0; }
  .settings-section h3 { margin: 0 0 15px 0; }
  .info-row { display: flex; justify-content: space-between; padding: 10px; border-bottom: 1px solid #eee; }
  .db-path { font-size: 0.85em; word-break: break-all; color: #2196F3; }
  .warning-box { 
    margin-top: 15px; 
    padding: 15px; 
    background: #fff3cd; 
    border-left: 4px solid #ffc107; 
    border-radius: 4px;
    font-size: 0.9em;
    line-height: 1.6;
  }
  .warning-box strong { color: #856404; }
  
  .backup-section {
    margin-top: 20px;
    padding-top: 20px;
    border-top: 2px solid #4CAF50;
  }
  
  .backup-section h4 {
    margin: 0 0 10px 0;
    color: #2e7d32;
  }
  
  .backup-info {
    font-size: 0.9em;
    color: #666;
    margin-bottom: 15px;
    line-height: 1.5;
  }
  
  .btn-backup {
    background: #4CAF50;
    color: white;
    border: none;
    padding: 12px 24px;
    border-radius: 6px;
    font-size: 1em;
    font-weight: bold;
    cursor: pointer;
    transition: all 0.3s;
    width: 100%;
  }
  
  .btn-backup:hover:not(:disabled) {
    background: #45a049;
    transform: translateY(-2px);
    box-shadow: 0 4px 8px rgba(76, 175, 80, 0.3);
  }
  
  .btn-backup:disabled {
    background: #ccc;
    cursor: not-allowed;
    opacity: 0.7;
  }
  
  .backup-message {
    margin-top: 15px;
    padding: 12px;
    border-radius: 6px;
    font-weight: 500;
    text-align: center;
  }
  
  .backup-message.success {
    background: #d4edda;
    color: #155724;
    border: 1px solid #c3e6cb;
  }
  
  .backup-message.error {
    background: #f8d7da;
    color: #721c24;
    border: 1px solid #f5c6cb;
  }
  
  .backup-message.info {
    background: #d1ecf1;
    color: #0c5460;
    border: 1px solid #bee5eb;
  }
</style>

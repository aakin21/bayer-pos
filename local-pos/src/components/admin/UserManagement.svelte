<script>
  import { userRepo } from '../../lib/db/database.js';
  import { onMount } from 'svelte';

  let users = [];
  let showModal = false;
  let editingUser = null;
  let isEditingAdmin = false;
  let currentPasswordInput = '';
  let modalError = '';

  onMount(async () => {
    await loadUsers();
    
    // Global refresh event listener
    const handleRefresh = () => {
      loadUsers();
    };
    window.addEventListener('refresh-screen', handleRefresh);
    
    return () => {
      window.removeEventListener('refresh-screen', handleRefresh);
    };
  });

  async function loadUsers() {
    const allUsers = await userRepo.findAll();
    // Sadece aktif kullanıcıları göster (silinenler görünmesin)
    users = allUsers.filter(u => u.is_active === 1);
  }

  function addUser() {
    isEditingAdmin = false;
    editingUser = { username: '', password: '', full_name: '', role: 'staff', is_active: 1 };
    showModal = true;
  }

  function editAdmin(u) {
    isEditingAdmin = true;
    editingUser = { ...u, password: '' };
    currentPasswordInput = '';
    modalError = '';
    showModal = true;
  }

  async function saveUser() {
    modalError = '';
    try {
      if (isEditingAdmin) {
        if (!editingUser.full_name) { modalError = 'Ad Soyad boş olamaz'; return; }
        if (!currentPasswordInput) { modalError = 'Mevcut şifreyi girmeniz gerekiyor'; return; }
        const adminInDb = await userRepo.findByUsername(editingUser.username);
        if (!adminInDb || adminInDb.password !== currentPasswordInput) {
          modalError = 'Mevcut şifre yanlış';
          return;
        }
        const toSave = { ...editingUser };
        if (!toSave.password) delete toSave.password;
        await userRepo.upsert(toSave);
      } else {
        if (!editingUser.username || !editingUser.password || !editingUser.full_name) {
          alert('Tüm alanları doldurun'); return;
        }
        await userRepo.upsert(editingUser);
      }
      showModal = false;
      await loadUsers();
    } catch (e) {
      console.error('Kullanıcı kaydetme hatası:', e);
      alert('Kullanıcı kaydedilemedi: ' + e.message);
    }
  }

  async function deleteUser(userId, userName, userRole) {
    // Sadece staff silinebilir
    if (userRole === 'admin') {
      alert('Admin kullanıcıları silinemez!');
      return;
    }

    if (!confirm(`"${userName}" kullanıcısını silmek istediğinize emin misiniz?`)) {
      return;
    }

    try {
      // Kullanıcıyı soft delete yap (is_active = 0)
      const success = await userRepo.deactivate(userId);
      if (success) {
        await loadUsers();
        alert('Kullanıcı başarıyla silindi');
      } else {
        alert('Kullanıcı silinemedi!');
      }
    } catch (e) {
      console.error('Kullanıcı silme hatası:', e);
      alert('Kullanıcı silinemedi: ' + e.message);
    }
  }
</script>

<div class="user-management">
  <div class="header">
    <h2>👥 Kullanıcı Yönetimi</h2>
    <button class="btn-add" on:click={addUser}>+ Yeni Kullanıcı</button>
  </div>

  <div class="users-table">
    <div class="table-header">
      <div>Ad Soyad</div>
      <div>Kullanıcı Adı</div>
      <div>Rol</div>
      <div>Durum</div>
      <div>İşlemler</div>
    </div>
    {#if users.length === 0}
      <div class="empty-state">
        <p>Henüz kullanıcı bulunmuyor</p>
        <small>Yukarıdaki "+ Yeni Kullanıcı" butonuna tıklayarak ekleyin</small>
      </div>
    {:else}
      {#each users as u}
        <div class="user-row">
          <div>{u.full_name}</div>
          <div>{u.username}</div>
          <div>
            {#if u.role === 'admin'}
              <span class="badge badge-admin">Yönetici</span>
            {:else}
              <span class="badge badge-staff">Personel</span>
            {/if}
          </div>
          <div>
            {#if u.is_active}
              <span class="badge badge-active">Aktif</span>
            {:else}
              <span class="badge badge-inactive">Pasif</span>
            {/if}
          </div>
          <div class="actions-cell">
            {#if u.role === 'staff'}
              <button class="btn-delete" on:click={() => deleteUser(u.id, u.full_name, u.role)}>Sil</button>
            {:else}
              <button class="btn-edit" on:click={() => editAdmin(u)}>Düzenle</button>
            {/if}
          </div>
        </div>
      {/each}
    {/if}
  </div>
</div>

{#if showModal}
  <div class="modal-overlay">
    <div class="modal">
      <h3>{isEditingAdmin ? 'Yönetici Bilgilerini Düzenle' : 'Yeni Kullanıcı Ekle'}</h3>
      <input bind:value={editingUser.full_name} placeholder="Ad Soyad" />
      {#if !isEditingAdmin}
        <input bind:value={editingUser.username} placeholder="Kullanıcı Adı" />
      {/if}
      {#if isEditingAdmin}
        <input type="password" bind:value={currentPasswordInput} placeholder="Mevcut Şifre (zorunlu)" />
        <input type="password" bind:value={editingUser.password} placeholder="Yeni Şifre (boş bırakırsan değişmez)" />
      {:else}
        <input type="password" bind:value={editingUser.password} placeholder="Şifre" />
        <div class="info-text">
          <small>💡 Not: Sadece personel hesabı oluşturabilirsiniz</small>
        </div>
      {/if}
      {#if modalError}
        <div class="modal-error">⚠️ {modalError}</div>
      {/if}
      <button on:click={saveUser}>Kaydet</button>
      <button on:click={() => showModal = false}>İptal</button>
    </div>
  </div>
{/if}

<style>
  .user-management { padding: 20px; }
  .header { display: flex; justify-content: space-between; margin-bottom: 20px; }
  .header h2 { margin: 0; color: #333; }
  .btn-add { padding: 10px 20px; background: #4caf50; color: white; border: none; border-radius: 6px; cursor: pointer; font-weight: 600; transition: all 0.3s; }
  .btn-add:hover { background: #45a049; transform: translateY(-2px); }
  .users-table { background: white; border-radius: 8px; padding: 15px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
  .table-header { display: grid; grid-template-columns: 2fr 2fr 1fr 1fr 1fr; padding: 12px 10px; font-weight: 600; background: #f8f9fa; border-radius: 6px; margin-bottom: 10px; color: #333; }
  .user-row { display: grid; grid-template-columns: 2fr 2fr 1fr 1fr 1fr; padding: 12px 10px; border-bottom: 1px solid #eee; align-items: center; }
  .user-row:last-child { border-bottom: none; }
  .user-row:hover { background: #f8f9fa; }

  .badge { padding: 4px 12px; border-radius: 12px; font-size: 12px; font-weight: 600; display: inline-block; }
  .badge-admin { background: #ffe0b2; color: #e65100; }
  .badge-staff { background: #e3f2fd; color: #1976d2; }
  .badge-active { background: #c8e6c9; color: #2e7d32; }
  .badge-inactive { background: #ffcdd2; color: #c62828; }
  .badge-protected { background: #f5f5f5; color: #757575; font-size: 11px; }

  .actions-cell { display: flex; gap: 6px; }
  .btn-delete { padding: 6px 16px; background: #f44336; color: white; border: none; border-radius: 6px; cursor: pointer; font-size: 12px; font-weight: 600; transition: all 0.3s; }
  .btn-delete:hover { background: #d32f2f; transform: translateY(-1px); }
  .btn-edit { padding: 6px 16px; background: #ff9800; color: white; border: none; border-radius: 6px; cursor: pointer; font-size: 12px; font-weight: 600; transition: all 0.3s; }
  .btn-edit:hover { background: #f57c00; transform: translateY(-1px); }
  .empty-state { text-align: center; padding: 40px; color: #999; }
  .empty-state p { margin: 0 0 8px 0; font-size: 16px; }
  .empty-state small { color: #bbb; }
  .modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.7); display: flex; align-items: center; justify-content: center; z-index: 1000; }
  .modal { background: white; padding: 30px; border-radius: 12px; display: flex; flex-direction: column; gap: 15px; min-width: 400px; }
  .modal h3 { margin: 0 0 10px 0; color: #333; }
  .modal input, .modal select { padding: 10px; border: 2px solid #e0e0e0; border-radius: 6px; font-size: 14px; }
  .modal input:focus, .modal select:focus { outline: none; border-color: #667eea; }
  .modal button { padding: 12px; border: none; border-radius: 6px; cursor: pointer; background: #667eea; color: white; font-weight: 600; transition: all 0.3s; }
  .modal button:hover { background: #5568d3; }
  .modal button:last-child { background: #f5f5f5; color: #333; }
  .modal button:last-child:hover { background: #e0e0e0; }
  .info-text { padding: 8px; background: #e3f2fd; border-radius: 6px; }
  .info-text small { color: #1976d2; }
  .modal-error { padding: 8px 12px; background: #fee; color: #c33; border-radius: 6px; font-size: 13px; border-left: 3px solid #c33; }
</style>

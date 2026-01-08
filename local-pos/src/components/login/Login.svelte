<script>
  import { onMount } from 'svelte';
  import { login, deviceConfig } from '../../stores/appStore.js';
  import { userRepo } from '../../lib/db/database.js';
  import { v4 as uuidv4 } from 'uuid';

  let username = '';
  let password = '';
  let error = '';
  let isLoading = false;

  // Hardcoded users for single store
  const USERS = [
    {
      id: uuidv4(),
      username: 'admin',
      password: 'admin123',
      full_name: 'Admin',
      role: 'admin',
      store_id: 'BAYER-STORE',
      is_active: 1
    },
    {
      id: uuidv4(),
      username: 'calisan',
      password: 'calisan123',
      full_name: 'Çalışan',
      role: 'staff',
      store_id: 'BAYER-STORE',
      is_active: 1
    }
  ];

  onMount(async () => {
    // Ensure default users exist in database
    try {
      const existingUsers = await userRepo.findAll();

      for (const user of USERS) {
        const exists = existingUsers.find(u => u.username === user.username);
        if (!exists) {
          await userRepo.upsert({
            username: user.username,
            password: user.password,
            full_name: user.full_name,
            role: user.role,
            store_id: user.store_id,
            is_active: user.is_active
          }, true); // skipAdminCheck = true for initial setup
        }
      }
    } catch (err) {
      console.error('Failed to initialize default users:', err);
    }
  });

  async function handleLogin() {
    if (!username || !password) {
      error = 'Lütfen kullanıcı adı ve şifre girin';
      return;
    }

    isLoading = true;
    error = '';

    try {
      // Önce database'de ara
      let user = await userRepo.findByUsername(username.trim());

      // Database'de yoksa hardcoded listesinde ara
      if (!user) {
        const hardcodedUser = USERS.find(u => u.username === username.trim());
        if (hardcodedUser) {
          // Hardcoded kullanıcıyı database'e ekle
          await userRepo.upsert({
            username: hardcodedUser.username,
            password: hardcodedUser.password,
            full_name: hardcodedUser.full_name,
            role: hardcodedUser.role,
            store_id: hardcodedUser.store_id,
            is_active: hardcodedUser.is_active
          }, true); // skipAdminCheck = true for initial setup
          user = await userRepo.findByUsername(username.trim());
        }
      }

      if (!user) {
        throw new Error('Kullanıcı bulunamadı');
      }

      // Kullanıcı aktif mi kontrol et
      if (user.is_active === 0) {
        throw new Error('Bu kullanıcı hesabı devre dışı bırakılmış');
      }

      // Şifre kontrolü
      if (user.password !== password) {
        throw new Error('Şifre yanlış');
      }

      // Login successful
      login(user);
    } catch (err) {
      error = err.message || 'Giriş yapılamadı';
    } finally {
      isLoading = false;
    }
  }

  function handleKeyPress(event) {
    if (event.key === 'Enter') {
      handleLogin();
    }
  }
</script>

<div class="login-container">
  <div class="login-card">
    <div class="logo">
      <h1>🏪 Bayer POS</h1>
      <p>Satış Sistemi</p>
    </div>

    {#if $deviceConfig.store_name}
      <div class="store-info">
        <span class="store-badge">{$deviceConfig.store_name}</span>
      </div>
    {/if}

    <form on:submit|preventDefault={handleLogin}>
      <div class="form-group">
        <label for="username">Kullanıcı Adı</label>
        <input
          id="username"
          type="text"
          bind:value={username}
          on:keypress={handleKeyPress}
          placeholder="Kullanıcı adınızı girin"
          disabled={isLoading}
          autocomplete="username"
        />
      </div>

      <div class="form-group">
        <label for="password">Şifre</label>
        <input
          id="password"
          type="password"
          bind:value={password}
          on:keypress={handleKeyPress}
          placeholder="Şifrenizi girin"
          disabled={isLoading}
          autocomplete="current-password"
        />
      </div>

      {#if error}
        <div class="error-message">
          ⚠️ {error}
        </div>
      {/if}

      <button type="submit" class="btn-primary" disabled={isLoading}>
        {isLoading ? 'Giriş yapılıyor...' : 'Giriş Yap'}
      </button>
    </form>

    <div class="footer">
      <small>Offline çalışma desteği aktif</small>
    </div>
  </div>
</div>

<style>
  .login-container {
    width: 100vw;
    height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: linear-gradient(135deg, #ff6b35 0%, #f7931e 100%);
  }

  .login-card {
    background: white;
    padding: 40px;
    border-radius: 20px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
    width: 100%;
    max-width: 400px;
  }

  .logo {
    text-align: center;
    margin-bottom: 30px;
  }

  .logo h1 {
    margin: 0;
    font-size: 32px;
    color: #333;
  }

  .logo p {
    margin: 5px 0 0;
    color: #666;
    font-size: 14px;
  }

  .store-info {
    text-align: center;
    margin-bottom: 20px;
  }

  .store-badge {
    display: inline-block;
    background: #ff6b35;
    color: white;
    padding: 8px 16px;
    border-radius: 20px;
    font-size: 14px;
    font-weight: 500;
  }

  form {
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  label {
    font-weight: 500;
    color: #333;
    font-size: 14px;
  }

  input {
    padding: 12px 16px;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    font-size: 16px;
    transition: all 0.3s;
  }

  input:focus {
    outline: none;
    border-color: #ff6b35;
    box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
  }

  input:disabled {
    background: #f5f5f5;
    cursor: not-allowed;
  }

  .error-message {
    background: #fee;
    color: #c33;
    padding: 12px;
    border-radius: 8px;
    font-size: 14px;
    border-left: 4px solid #c33;
  }

  .btn-primary {
    padding: 14px;
    background: #ff6b35;
    color: white;
    border: none;
    border-radius: 8px;
    font-size: 16px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }

  .btn-primary:hover:not(:disabled) {
    background: #e55a28;
    transform: translateY(-2px);
    box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);
  }

  .btn-primary:disabled {
    background: #ccc;
    cursor: not-allowed;
  }

  .footer {
    margin-top: 20px;
    text-align: center;
    color: #999;
  }
</style>

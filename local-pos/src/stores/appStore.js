import { writable, get } from 'svelte/store';

// Auth store
export const user = writable(null);
export const authToken = writable(null);

// Device store (simplified for single store)
export const deviceConfig = writable({
  device_id: 'BAYER-POS-001',
  store_id: 'BAYER-STORE',
  store_name: 'Bayer POS',
  is_activated: true,
  auto_print_enabled: true // Otomatik fiş yazdırma (varsayılan: açık)
});

// Current shift
export const currentShift = writable(null);

// Cart for sales
export const cart = writable([]);
export const cartTotal = writable(0);
export const cartSubtotal = writable(0); // İndirim öncesi toplam
export const discount = writable({ type: null, value: 0 }); // { type: 'percentage' | 'amount' | null, value: number }
export const selectedQuantity = writable(1); // Seçili miktar (1-10)

// App view (simplified - only login and pos)
export const currentView = writable('loading'); // loading, login, pos

// Global barcode event - herhangi bir yerden barkod okutulabilir
export const globalBarcodeEvent = writable(null); // { barcode: string, timestamp: number }

// Helper functions
export function login(userData) {
  user.set(userData);
  currentView.set('pos');
  localStorage.setItem('user', JSON.stringify(userData));

  // Set user role in database module
  import('../lib/db/database.js').then(db => db.setCurrentUser(userData));
}

export function logout() {
  user.set(null);
  currentView.set('login');
  localStorage.removeItem('user');
}

export function addToCart(product, quantity = 1) {
  cart.update(items => {
    const existingItem = items.find(item => item.product_id === product.id);
    if (existingItem) {
      existingItem.quantity += quantity;
      existingItem.total_price = existingItem.quantity * existingItem.unit_price;
      return [...items];
    } else {
      return [...items, {
        product_id: product.id,
        product_name: product.name,
        barcode: product.barcode,
        quantity: quantity,
        unit_price: product.sale_price,
        purchase_price: product.purchase_price || 0,
        total_price: quantity * product.sale_price
      }];
    }
  });
  updateCartTotal();
}

// İndirim fonksiyonları
export function applyDiscount(type, value) {
  discount.set({ type, value });
  updateCartTotal();
}

export function removeDiscount() {
  discount.set({ type: null, value: 0 });
  updateCartTotal();
}

export function getDiscountAmount() {
  const currentDiscount = get(discount);
  const subtotal = get(cartSubtotal);
  
  if (currentDiscount.type === 'percentage' && currentDiscount.value > 0) {
    return (subtotal * currentDiscount.value) / 100;
  } else if (currentDiscount.type === 'amount' && currentDiscount.value > 0) {
    return Math.min(currentDiscount.value, subtotal);
  }
  
  return 0;
}

export function removeFromCart(productId) {
  cart.update(items => items.filter(item => item.product_id !== productId));
  updateCartTotal();
}

export function updateCartQuantity(productId, quantity) {
  cart.update(items => {
    const item = items.find(i => i.product_id === productId);
    if (item) {
      item.quantity = quantity;
      item.total_price = item.quantity * item.unit_price;
    }
    return [...items];
  });
  updateCartTotal();
}

export function clearCart() {
  cart.set([]);
  cartTotal.set(0);
  cartSubtotal.set(0);
  discount.set({ type: null, value: 0 });
}

function updateCartTotal() {
  const items = get(cart);
  const subtotal = items.reduce((sum, item) => sum + item.total_price, 0);
  cartSubtotal.set(subtotal);
  
  const currentDiscount = get(discount);
  let finalTotal = subtotal;
  
  if (currentDiscount.type === 'percentage' && currentDiscount.value > 0) {
    const discountAmount = (subtotal * currentDiscount.value) / 100;
    finalTotal = subtotal - discountAmount;
  } else if (currentDiscount.type === 'amount' && currentDiscount.value > 0) {
    finalTotal = Math.max(0, subtotal - currentDiscount.value);
  }
  
  cartTotal.set(finalTotal);
}

// Printer settings
export function toggleAutoPrint() {
  deviceConfig.update(config => {
    const newConfig = {
      ...config,
      auto_print_enabled: !config.auto_print_enabled
    };
    // Save to localStorage
    localStorage.setItem('printer_settings', JSON.stringify({
      auto_print_enabled: newConfig.auto_print_enabled
    }));
    return newConfig;
  });
}

export function loadPrinterSettings() {
  try {
    const savedSettings = localStorage.getItem('printer_settings');
    if (savedSettings) {
      const settings = JSON.parse(savedSettings);
      deviceConfig.update(config => ({
        ...config,
        auto_print_enabled: settings.auto_print_enabled !== undefined ? settings.auto_print_enabled : true
      }));
    }
  } catch (error) {
    console.error('Error loading printer settings:', error);
  }
}

// Initialize from localStorage on startup
export function initializeApp() {
  try {
    console.log('=== BAYER POS STARTING ===');

    // Load printer settings
    loadPrinterSettings();

    const savedUser = localStorage.getItem('user');

    if (savedUser) {
      console.log('User logged in, showing POS');
      const userData = JSON.parse(savedUser);
      user.set(userData);
      currentView.set('pos');

      // Set user role in database module
      import('../lib/db/database.js').then(db => db.setCurrentUser(userData));
    } else {
      console.log('Showing login screen');
      currentView.set('login');
    }
  } catch (error) {
    console.error('ERROR in initializeApp:', error);
    currentView.set('login');
  }
}

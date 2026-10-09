/* Service worker di Foglio: l'app si apre anche senza connessione.
 *
 * - L'involucro (pagina, script, stili, icone) si salva man mano che si usa e si serve da qui se la rete manca.
 * - La pagina si prende dalla rete se c'è (così un aggiornamento arriva subito), dalla copia salvata altrimenti.
 * - I file con l'impronta nel nome (assets/*) non cambiano mai: prima la copia salvata.
 * - Le richieste ad altri siti (Supabase: dati, accesso, allegati) NON passano di qui: non si salva nulla di privato.
 *   Fanno eccezione i caratteri di Google Fonts, che sono pubblici.
 * Tutti i percorsi sono relativi alla cartella del service worker, quindi vale anche se l'app sta in una sottocartella.
 */
const VERSION = 'foglio-v1';
const SHELL = `${VERSION}-shell`;
const ASSETS = `${VERSION}-assets`;
const FONTS = `${VERSION}-fonts`;
const ROOT = new URL('./', self.location).pathname;

const PRECACHE = ['./', 'manifest.webmanifest', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/favicon-32.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(SHELL)
      .then((cache) => cache.addAll(PRECACHE))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => ![SHELL, ASSETS, FONTS].includes(k)).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

/** Salva una copia di una risposta buona (senza toccare quella che torna al browser). */
async function remember(cacheName, request, response) {
  if (response && (response.ok || response.type === 'opaque')) {
    const cache = await caches.open(cacheName);
    await cache.put(request, response.clone());
  }
  return response;
}

/** Prima la rete; se manca, la copia salvata; in ultimo la pagina principale. */
async function networkFirstPage(request) {
  try {
    const response = await fetch(request);
    // Una sola copia della pagina (le varianti `?invite=...` non devono moltiplicarsi).
    await remember(SHELL, new Request(ROOT), response);
    return response;
  } catch {
    const cache = await caches.open(SHELL);
    return (await cache.match(new Request(ROOT))) || (await cache.match('./')) || Response.error();
  }
}

/** Prima la copia salvata; se non c'è, la rete e poi si salva. */
async function cacheFirst(cacheName, request) {
  const cache = await caches.open(cacheName);
  const hit = await cache.match(request);
  if (hit) return hit;
  return remember(cacheName, request, await fetch(request));
}

/** Copia salvata subito, e intanto si aggiorna dalla rete. */
async function staleWhileRevalidate(cacheName, request) {
  const cache = await caches.open(cacheName);
  const hit = await cache.match(request);
  const network = fetch(request)
    .then((response) => remember(cacheName, request, response))
    .catch(() => hit);
  return hit || network;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  if (url.origin !== self.location.origin) {
    if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
      event.respondWith(staleWhileRevalidate(FONTS, request));
    }
    return; // dati e allegati: sempre dalla rete, mai salvati
  }

  if (request.mode === 'navigate') {
    event.respondWith(networkFirstPage(request));
    return;
  }

  if (url.pathname.startsWith(`${ROOT}assets/`)) {
    event.respondWith(cacheFirst(ASSETS, request));
    return;
  }

  event.respondWith(staleWhileRevalidate(SHELL, request));
});

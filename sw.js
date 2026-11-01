// No offline caching in cloud version: prevent stale application and stale inventory.
self.addEventListener('install',e=>self.skipWaiting());self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));

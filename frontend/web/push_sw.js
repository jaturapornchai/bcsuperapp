// Shows chat alerts the backend pushes through FCM while the app tab is
// closed, and opens the room when one is tapped. Registered by
// bcPushGetToken in index.html under its own scope (./push/), apart from
// Flutter's files.

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {}
  const d = payload.data || payload;
  event.waitUntil(
    self.registration.showNotification(d.title || 'BC Super App', {
      body: d.body || '',
      tag: d.conversation_id || 'bcapp',
      renotify: true,
      silent: d.silent === '1',
      icon: '../icons/Icon-192.png',
      data: { conversation: d.conversation_id || '' },
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const id = event.notification.data && event.notification.data.conversation;
  const root = new URL('../', self.registration.scope).href;
  const url = id ? root + '?conversation=' + encodeURIComponent(id) : root;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      const open = list.find((c) => c.url.startsWith(root));
      if (open) {
        if (id) open.postMessage({ type: 'openConversation', conversation: id });
        return open.focus();
      }
      return self.clients.openWindow(url);
    }),
  );
});

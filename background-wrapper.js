// MV3 Service Worker polyfill for 1Password extension v4.7.5.90
// Provides compatibility shims so the original minified MV2 background script
// can run inside a Manifest V3 service worker.

self.window = self;
self.window.location = { href: 'https://localhost/' };

if (!self.navigator) {
  self.navigator = { userAgent: 'Chrome', platform: 'MacIntel' };
} else if (!self.navigator.userAgent) {
  self.navigator.userAgent = 'Chrome';
}

if (chrome.action) {
  Object.defineProperty(chrome, 'browserAction', {
    get: function () { return chrome.action; },
    configurable: true
  });
}

(function () {
  var nativeAddListener = chrome.webRequest.onBeforeRequest.addListener;
  chrome.webRequest.onBeforeRequest.addListener = function (callback, filter, extraInfoSpec) {
    if (extraInfoSpec && extraInfoSpec.indexOf('blocking') !== -1) {
      console.warn('[1P-MV3] webRequest "blocking" stripped — Go & Fill URL redirect will NOT work');
      extraInfoSpec = extraInfoSpec.filter(function (s) { return s !== 'blocking'; });
    }
    return nativeAddListener.call(chrome.webRequest.onBeforeRequest, callback, filter, extraInfoSpec || []);
  };
})();

try {
  importScripts('ext/sjcl.js', 'global.min.js');
} catch (e) {
  console.error('[1P-MV3] Failed to load original scripts:', e);
}

chrome.contextMenus.onClicked.addListener(function (info, tab) {
  if (info.menuItemId !== '1password_menu') return;
  var pageUrl = info.pageUrl;
  if (pageUrl) {
    self.OnePassword.ha('context-menu', pageUrl);
  } else {
    chrome.tabs.query({ active: true, windowId: chrome.windows.WINDOW_ID_CURRENT }, function (tabs) {
      if (tabs && tabs.length > 0 && tabs[0].url) {
        var url = tabs[0].url;
        try { if (new URL(url).hostname) self.OnePassword.ha('context-menu', url); }
        catch (_) { if (url === 'about:accounts') self.OnePassword.ha('context-menu', url); }
      }
    });
  }
});

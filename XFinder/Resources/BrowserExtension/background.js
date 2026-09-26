// XFinder Browser Helper — background.js
// Captures visible tab without browser chrome UI and sends to Native Messaging host

const NATIVE_HOST = "com.xfinder.helper";
let port = null;

function connectNativeHost() {
  try {
    port = chrome.runtime.connectNative(NATIVE_HOST);
    port.onDisconnect.addListener(() => {
      console.log("[XFinder] Native messaging host disconnected.");
      port = null;
    });
  } catch (err) {
    console.warn("[XFinder] Could not connect to native host:", err);
    port = null;
  }
}

// Listen for tab activation / updates to capture active tab
chrome.tabs.onActivated.addListener((activeInfo) => {
  captureTab(activeInfo.tabId, activeInfo.windowId);
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === "complete" && tab.active) {
    captureTab(tabId, tab.windowId);
  }
});

function captureTab(tabId, windowId) {
  chrome.tabs.captureVisibleTab(windowId, { format: "jpeg", quality: 90 }, (dataUrl) => {
    if (chrome.runtime.lastError || !dataUrl) {
      return;
    }
    chrome.tabs.get(tabId, (tab) => {
      const payload = {
        tabId: String(tabId),
        dataUrl: dataUrl,
        title: tab ? tab.title : "",
        url: tab ? tab.url : ""
      };
      sendNative(payload);
    });
  });
}

function sendNative(msg) {
  if (!port) {
    connectNativeHost();
  }
  if (port) {
    port.postMessage(msg);
  }
}

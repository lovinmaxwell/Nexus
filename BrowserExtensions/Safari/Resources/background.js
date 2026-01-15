/// Safari Web Extension background service worker.
/// Intercepts downloads and sends them to Nexus via native messaging.

const NATIVE_APP_ID = "com.nexus.app";

browser.runtime.onInstalled.addListener(() => {
  browser.contextMenus.create({
    id: "downloadWithNexus",
    title: "Download with Nexus",
    contexts: ["link", "image", "video", "audio"]
  });
});

browser.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "downloadWithNexus") {
    const url = info.linkUrl || info.srcUrl;
    if (url) {
      sendToNexus(url, tab);
    }
  }
});

browser.downloads.onCreated.addListener((downloadItem) => {
  const fileExtensions = [
    ".exe", ".msi", ".dmg", ".pkg", ".zip", ".rar", ".7z", ".tar", ".gz",
    ".iso", ".mp4", ".mkv", ".avi", ".mov", ".mp3", ".flac", ".wav",
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx"
  ];
  
  const url = downloadItem.url.toLowerCase();
  const shouldIntercept = fileExtensions.some(ext => url.includes(ext)) || 
                          (downloadItem.fileSize && downloadItem.fileSize > 10 * 1024 * 1024);
  
  if (shouldIntercept) {
    browser.downloads.cancel(downloadItem.id);
    sendToNexus(downloadItem.url, null, downloadItem.filename);
  }
});

async function sendToNexus(url, tab, filename) {
  const request = {
    action: "download",
    url: url,
    cookies: await getCookies(url),
    referrer: tab?.url || "",
    userAgent: navigator.userAgent,
    filename: filename || null
  };

  try {
    const response = await browser.runtime.sendNativeMessage(NATIVE_APP_ID, request);
    if (response.success) {
      showNotification("Download Added", `${filename || url} sent to Nexus`);
    } else {
      showNotification("Error", response.message || "Failed to add download");
    }
  } catch (error) {
    showNotification("Connection Error", "Could not connect to Nexus. Is it running?");
    console.error("Safari native messaging error:", error);
  }
}

async function getCookies(url) {
  try {
    const urlObj = new URL(url);
    const cookies = await browser.cookies.getAll({ domain: urlObj.hostname });
    return cookies.map(c => `${c.name}=${c.value}`).join("; ");
  } catch {
    return "";
  }
}

function showNotification(title, message) {
  browser.notifications.create({
    type: "basic",
    iconUrl: "images/icon-128.png",
    title: title,
    message: message
  });
}

browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === "ping") {
    browser.runtime.sendNativeMessage(NATIVE_APP_ID, { action: "ping" })
      .then(response => sendResponse({ connected: response.success }))
      .catch(() => sendResponse({ connected: false }));
    return true;
  }
  
  if (message.action === "download") {
    sendToNexus(message.url, null, message.filename)
      .then(() => sendResponse({ success: true }))
      .catch(error => sendResponse({ success: false, error: error.message }));
    return true;
  }
});

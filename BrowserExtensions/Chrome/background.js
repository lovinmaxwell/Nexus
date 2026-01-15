const NATIVE_HOST_NAME = "com.nexus.host";

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "downloadWithNexus",
    title: "Download with Nexus",
    contexts: ["link", "image", "video", "audio"]
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === "downloadWithNexus") {
    const url = info.linkUrl || info.srcUrl;
    if (url) {
      sendToNexus(url, tab);
    }
  }
});

chrome.downloads.onDeterminingFilename.addListener((downloadItem, suggest) => {
  const fileExtensions = [
    ".exe", ".msi", ".dmg", ".pkg", ".zip", ".rar", ".7z", ".tar", ".gz",
    ".iso", ".mp4", ".mkv", ".avi", ".mov", ".mp3", ".flac", ".wav",
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx"
  ];
  
  const url = downloadItem.url.toLowerCase();
  const shouldIntercept = fileExtensions.some(ext => url.includes(ext)) || 
                          downloadItem.fileSize > 10 * 1024 * 1024;
  
  if (shouldIntercept) {
    chrome.downloads.cancel(downloadItem.id);
    sendToNexus(downloadItem.url, null, downloadItem.filename);
  }
});

async function sendToNexus(url, tab, filename) {
  const request = {
    url: url,
    cookies: await getCookies(url),
    referrer: tab?.url || "",
    userAgent: navigator.userAgent,
    filename: filename || null
  };

  try {
    const response = await chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, request);
    if (response.success) {
      showNotification("Download Added", `${filename || url} sent to Nexus`);
    } else {
      showNotification("Error", response.message);
    }
  } catch (error) {
    showNotification("Connection Error", "Could not connect to Nexus. Is it running?");
    console.error("Native messaging error:", error);
  }
}

async function getCookies(url) {
  try {
    const urlObj = new URL(url);
    const cookies = await chrome.cookies.getAll({ domain: urlObj.hostname });
    return cookies.map(c => `${c.name}=${c.value}`).join("; ");
  } catch {
    return "";
  }
}

function showNotification(title, message) {
  chrome.notifications.create({
    type: "basic",
    iconUrl: "icons/icon128.png",
    title: title,
    message: message
  });
}

chrome.action.onClicked.addListener((tab) => {
  chrome.tabs.sendMessage(tab.id, { action: "showOverlay" });
});

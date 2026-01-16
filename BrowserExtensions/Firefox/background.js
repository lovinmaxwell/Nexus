const NATIVE_HOST_NAME = "com.nexus.host";

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
  // Intercept ALL browser downloads - Nexus will figure out the file extension
  // from Content-Type headers or Content-Disposition if URL doesn't have one
  browser.downloads.cancel(downloadItem.id);
  sendToNexus(downloadItem.url, null, downloadItem.filename);
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
    const response = await browser.runtime.sendNativeMessage(NATIVE_HOST_NAME, request);
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
    const cookies = await browser.cookies.getAll({ domain: urlObj.hostname });
    return cookies.map(c => `${c.name}=${c.value}`).join("; ");
  } catch {
    return "";
  }
}

function showNotification(title, message) {
  browser.notifications.create({
    type: "basic",
    iconUrl: "icons/icon128.png",
    title: title,
    message: message
  });
}

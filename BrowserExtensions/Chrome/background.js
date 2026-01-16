/**
 * Nexus Download Manager - Chrome Extension
 * 
 * IDM-style browser integration that captures:
 * - Full redirect chains (302, 301, etc.)
 * - All request headers (cookies, referer, authorization, etc.)
 * - Response headers (content-type, content-disposition, etc.)
 * 
 * This approach intercepts requests in real-time using webRequest API,
 * similar to how Internet Download Manager works.
 */

const NATIVE_HOST_NAME = "com.nexus.host";

// Store for tracking requests by their ID
// Maps requestId -> RequestRecord
const requestTracker = new Map();

// Store for pending downloads (URL -> captured data)
// Used to match downloads with their captured request data
const pendingCaptures = new Map();

// File extensions that should be intercepted for download
const DOWNLOAD_EXTENSIONS = [
  // Archives
  'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso', 'dmg',
  // Executables
  'exe', 'msi', 'deb', 'rpm', 'pkg', 'app',
  // Documents
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx',
  // Media
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v',
  'mp3', 'flac', 'wav', 'aac', 'ogg', 'm4a', 'wma',
  // Images (large)
  'psd', 'ai', 'svg', 'raw', 'tiff',
  // Other
  'torrent', 'apk', 'ipa'
];

// Content types that indicate downloadable content
const DOWNLOAD_CONTENT_TYPES = [
  'application/octet-stream',
  'application/zip',
  'application/x-rar-compressed',
  'application/x-7z-compressed',
  'application/x-tar',
  'application/gzip',
  'application/pdf',
  'application/x-msdownload',
  'application/x-apple-diskimage',
  'video/',
  'audio/',
  'application/x-bittorrent'
];

/**
 * Request record structure for tracking
 */
class RequestRecord {
  constructor(requestId, url, method) {
    this.requestId = requestId;
    this.originalUrl = url;
    this.currentUrl = url;
    this.method = method;
    this.redirectChain = [url];
    this.requestHeaders = {};
    this.responseHeaders = {};
    this.statusCode = null;
    this.contentType = null;
    this.contentLength = null;
    this.contentDisposition = null;
    this.timestamp = Date.now();
    this.tabId = null;
    this.tabUrl = null;
  }
  
  addRedirect(newUrl) {
    this.redirectChain.push(newUrl);
    this.currentUrl = newUrl;
  }
  
  toJSON() {
    return {
      originalUrl: this.originalUrl,
      finalUrl: this.currentUrl,
      redirectChain: this.redirectChain,
      requestHeaders: this.requestHeaders,
      responseHeaders: this.responseHeaders,
      statusCode: this.statusCode,
      contentType: this.contentType,
      contentLength: this.contentLength,
      contentDisposition: this.contentDisposition,
      tabUrl: this.tabUrl
    };
  }
}

// ============================================================================
// Context Menu Setup
// ============================================================================

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
      // For context menu clicks, we don't have request data yet
      // Send with tab URL as referer
      sendToNexus({
        url: url,
        originalUrl: url,
        referrer: tab?.url || "",
        tabUrl: tab?.url || ""
      });
    }
  }
});

// ============================================================================
// WebRequest API - IDM-style Request Tracking
// ============================================================================

/**
 * Capture the start of each request
 */
chrome.webRequest.onBeforeRequest.addListener(
  (details) => {
    // Only track main_frame, sub_frame, and other resource types that might be downloads
    if (details.type === 'main_frame' || details.type === 'sub_frame' || 
        details.type === 'object' || details.type === 'media' || 
        details.type === 'other' || details.type === 'xmlhttprequest') {
      
      const record = new RequestRecord(details.requestId, details.url, details.method);
      record.tabId = details.tabId;
      requestTracker.set(details.requestId, record);
      
      // Clean up old records (older than 5 minutes)
      cleanupOldRecords();
    }
  },
  { urls: ["<all_urls>"] }
);

/**
 * Capture request headers (cookies, referer, authorization, etc.)
 */
chrome.webRequest.onBeforeSendHeaders.addListener(
  (details) => {
    const record = requestTracker.get(details.requestId);
    if (record && details.requestHeaders) {
      // Store all request headers
      for (const header of details.requestHeaders) {
        record.requestHeaders[header.name.toLowerCase()] = header.value;
      }
      
      // Get tab URL for referer if not already set
      if (details.tabId > 0 && !record.tabUrl) {
        chrome.tabs.get(details.tabId, (tab) => {
          if (tab && tab.url) {
            record.tabUrl = tab.url;
          }
        });
      }
    }
  },
  { urls: ["<all_urls>"] },
  ["requestHeaders", "extraHeaders"]  // extraHeaders needed for some headers in MV3
);

/**
 * Capture redirects - this is the key for 302 handling!
 */
chrome.webRequest.onBeforeRedirect.addListener(
  (details) => {
    const record = requestTracker.get(details.requestId);
    if (record) {
      record.statusCode = details.statusCode;
      record.addRedirect(details.redirectUrl);
      
      console.log(`Nexus: Redirect detected (${details.statusCode})`);
      console.log(`  From: ${details.url}`);
      console.log(`  To: ${details.redirectUrl}`);
    }
  },
  { urls: ["<all_urls>"] }
);

/**
 * Capture response headers (content-type, content-length, content-disposition)
 */
chrome.webRequest.onHeadersReceived.addListener(
  (details) => {
    const record = requestTracker.get(details.requestId);
    if (record && details.responseHeaders) {
      record.statusCode = details.statusCode;
      
      // Store all response headers
      for (const header of details.responseHeaders) {
        const name = header.name.toLowerCase();
        record.responseHeaders[name] = header.value;
        
        // Extract important headers
        if (name === 'content-type') {
          record.contentType = header.value;
        } else if (name === 'content-length') {
          record.contentLength = parseInt(header.value, 10);
        } else if (name === 'content-disposition') {
          record.contentDisposition = header.value;
        }
      }
      
      // Check if this looks like a download based on content-type or content-disposition
      if (isDownloadableResponse(record)) {
        // Store this capture for matching with download event
        pendingCaptures.set(normalizeUrl(details.url), record);
        
        // Also store by original URL in case of redirects
        if (record.originalUrl !== details.url) {
          pendingCaptures.set(normalizeUrl(record.originalUrl), record);
        }
      }
    }
  },
  { urls: ["<all_urls>"] },
  ["responseHeaders", "extraHeaders"]
);

/**
 * Clean up when request completes
 */
chrome.webRequest.onCompleted.addListener(
  (details) => {
    const record = requestTracker.get(details.requestId);
    if (record) {
      record.statusCode = details.statusCode;
      
      // Keep the record for a bit in case download event fires
      setTimeout(() => {
        requestTracker.delete(details.requestId);
      }, 10000);  // Keep for 10 seconds
    }
  },
  { urls: ["<all_urls>"] }
);

/**
 * Clean up on error
 */
chrome.webRequest.onErrorOccurred.addListener(
  (details) => {
    requestTracker.delete(details.requestId);
  },
  { urls: ["<all_urls>"] }
);

// ============================================================================
// Download Interception
// ============================================================================

/**
 * Intercept downloads - now with full request data from webRequest tracking
 */
chrome.downloads.onDeterminingFilename.addListener((downloadItem, suggest) => {
  // Cancel the browser download - Nexus will handle it
  chrome.downloads.cancel(downloadItem.id);
  
  const downloadUrl = downloadItem.finalUrl || downloadItem.url;
  const originalUrl = downloadItem.url;
  
  console.log("Nexus: Intercepting download");
  console.log("  Original URL:", originalUrl);
  console.log("  Final URL:", downloadItem.finalUrl);
  console.log("  Filename:", downloadItem.filename);
  
  // Try to find captured request data
  let capturedData = pendingCaptures.get(normalizeUrl(downloadUrl)) ||
                     pendingCaptures.get(normalizeUrl(originalUrl));
  
  // Also search through active request records
  if (!capturedData) {
    for (const [, record] of requestTracker) {
      if (record.currentUrl === downloadUrl || record.originalUrl === originalUrl) {
        capturedData = record;
        break;
      }
    }
  }
  
  if (capturedData) {
    console.log("  Found captured request data!");
    console.log("  Redirect chain:", capturedData.redirectChain);
    console.log("  Request headers:", Object.keys(capturedData.requestHeaders));
    
    sendToNexusWithCapture(downloadItem, capturedData);
  } else {
    console.log("  No captured data found, using basic capture");
    sendToNexusBasic(downloadItem);
  }
  
  // Clean up
  pendingCaptures.delete(normalizeUrl(downloadUrl));
  pendingCaptures.delete(normalizeUrl(originalUrl));
});

// ============================================================================
// Send to Nexus Functions
// ============================================================================

/**
 * Send to Nexus with full captured request data (IDM-style)
 */
async function sendToNexusWithCapture(downloadItem, capturedData) {
  const downloadUrl = downloadItem.finalUrl || downloadItem.url;
  const originalUrl = capturedData.originalUrl || downloadItem.url;
  
  // Get cookies for all URLs in the redirect chain
  let allCookies = "";
  const seenDomains = new Set();
  
  for (const url of capturedData.redirectChain) {
    try {
      const urlObj = new URL(url);
      if (!seenDomains.has(urlObj.hostname)) {
        seenDomains.add(urlObj.hostname);
        const cookies = await getCookies(url);
        if (cookies) {
          allCookies = allCookies ? `${allCookies}; ${cookies}` : cookies;
        }
      }
    } catch (e) {
      console.error("Error getting cookies for", url, e);
    }
  }
  
  // Build comprehensive request object
  const request = {
    url: downloadUrl,
    originalUrl: originalUrl,
    filename: downloadItem.filename || null,
    
    // Full redirect chain
    redirectChain: capturedData.redirectChain,
    
    // Request headers captured from browser
    requestHeaders: capturedData.requestHeaders,
    
    // Response headers
    responseHeaders: capturedData.responseHeaders,
    
    // Cookies from all domains in redirect chain
    cookies: allCookies || capturedData.requestHeaders['cookie'] || "",
    
    // Referer - prefer captured, fall back to tab URL
    referrer: capturedData.requestHeaders['referer'] || 
              capturedData.tabUrl || 
              originalUrl,
    
    // User agent
    userAgent: capturedData.requestHeaders['user-agent'] || navigator.userAgent,
    
    // Authorization if present
    authorization: capturedData.requestHeaders['authorization'] || null,
    
    // Content info from response
    contentType: capturedData.contentType,
    contentLength: capturedData.contentLength,
    contentDisposition: capturedData.contentDisposition,
    
    // Metadata
    captureMethod: "webRequest",
    timestamp: Date.now()
  };
  
  sendToNexus(request);
}

/**
 * Basic send to Nexus (fallback when no webRequest data available)
 */
async function sendToNexusBasic(downloadItem) {
  const downloadUrl = downloadItem.finalUrl || downloadItem.url;
  const originalUrl = downloadItem.url;
  
  // Get cookies for both URLs
  let cookies = await getCookies(downloadUrl);
  if (originalUrl !== downloadUrl) {
    const originalCookies = await getCookies(originalUrl);
    if (originalCookies) {
      cookies = cookies ? `${cookies}; ${originalCookies}` : originalCookies;
    }
  }
  
  const request = {
    url: downloadUrl,
    originalUrl: originalUrl,
    filename: downloadItem.filename || null,
    cookies: cookies,
    referrer: originalUrl,
    userAgent: navigator.userAgent,
    contentType: downloadItem.mime || null,
    contentLength: downloadItem.fileSize > 0 ? downloadItem.fileSize : null,
    captureMethod: "basic",
    timestamp: Date.now()
  };
  
  sendToNexus(request);
}

/**
 * Send request to Nexus native host
 */
async function sendToNexus(request) {
  console.log("Nexus: Sending to native host", request.url);
  
  try {
    const response = await chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, request);
    if (response.success) {
      showNotification("Download Added", `${request.filename || request.url} sent to Nexus`);
    } else {
      showNotification("Error", response.message);
    }
  } catch (error) {
    showNotification("Connection Error", "Could not connect to Nexus. Is it running?");
    console.error("Native messaging error:", error);
  }
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Get cookies for a URL
 */
async function getCookies(url) {
  try {
    const urlObj = new URL(url);
    const cookies = await chrome.cookies.getAll({ domain: urlObj.hostname });
    return cookies.map(c => `${c.name}=${c.value}`).join("; ");
  } catch {
    return "";
  }
}

/**
 * Normalize URL for comparison (remove trailing slashes, etc.)
 */
function normalizeUrl(url) {
  try {
    const urlObj = new URL(url);
    return urlObj.href.replace(/\/$/, '');
  } catch {
    return url;
  }
}

/**
 * Check if a response looks like a downloadable file
 */
function isDownloadableResponse(record) {
  // Check content-disposition
  if (record.contentDisposition && record.contentDisposition.includes('attachment')) {
    return true;
  }
  
  // Check content-type
  if (record.contentType) {
    for (const type of DOWNLOAD_CONTENT_TYPES) {
      if (record.contentType.toLowerCase().includes(type)) {
        return true;
      }
    }
  }
  
  // Check URL extension
  try {
    const url = new URL(record.currentUrl);
    const path = url.pathname.toLowerCase();
    for (const ext of DOWNLOAD_EXTENSIONS) {
      if (path.endsWith('.' + ext)) {
        return true;
      }
    }
  } catch {
    // Invalid URL
  }
  
  // Check for large content-length (> 1MB might be a download)
  if (record.contentLength && record.contentLength > 1024 * 1024) {
    return true;
  }
  
  return false;
}

/**
 * Clean up old request records
 */
function cleanupOldRecords() {
  const now = Date.now();
  const maxAge = 5 * 60 * 1000;  // 5 minutes
  
  for (const [requestId, record] of requestTracker) {
    if (now - record.timestamp > maxAge) {
      requestTracker.delete(requestId);
    }
  }
  
  for (const [url, record] of pendingCaptures) {
    if (now - record.timestamp > maxAge) {
      pendingCaptures.delete(url);
    }
  }
}

/**
 * Show notification
 */
function showNotification(title, message) {
  chrome.notifications.create({
    type: "basic",
    iconUrl: "icons/icon.png",
    title: title,
    message: message
  });
}

/**
 * Handle extension icon click
 */
chrome.action.onClicked.addListener((tab) => {
  chrome.tabs.sendMessage(tab.id, { action: "showOverlay" });
});

// Clean up periodically
setInterval(cleanupOldRecords, 60000);  // Every minute

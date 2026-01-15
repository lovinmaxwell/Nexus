// Nexus Safari Extension - Background Script

console.log("Nexus Extension Loaded");

// Connect to the native application
const port = browser.runtime.connectNative("com.lovinmaxwell.nexus");

port.onMessage.addListener((response) => {
    console.log("Received response from Native App:", response);
});

port.onDisconnect.addListener(() => {
    console.log("Disconnected from Native App");
    if (browser.runtime.lastError) {
        console.error(`Connection failed: ${browser.runtime.lastError.message}`);
    }
});

// Listener for new downloads
browser.downloads.onCreated.addListener((downloadItem) => {
    console.log("Download started:", downloadItem);

    // Filter out internal downloads or blobs if strictly necessary
    if (downloadItem.url.startsWith("blob:") || downloadItem.url.startsWith("data:")) {
        return;
    }

    // Cancel the browser download
    browser.downloads.cancel(downloadItem.id).then(() => {
        console.log(`Cancelled browser download ${downloadItem.id}, handing over to Nexus`);

        // Send to Native App
        const message = {
            action: "download",
            url: downloadItem.url,
            referrer: downloadItem.referrer,
            userAgent: navigator.userAgent // Note: Service workers might not have full navigator.userAgent access same as pages
        };

        // Attempt to get cookies (requires host permissions and separate API call if needed, 
        // simplified here for initial implementation)

        port.postMessage(message);
    }, (error) => {
        console.error(`Failed to cancel download: ${error}`);
    });
});

// Context Menu
browser.contextMenus.create({
    id: "download-with-nexus",
    title: "Download with Nexus",
    contexts: ["link", "video", "audio", "image"]
});

browser.contextMenus.onClicked.addListener((info, tab) => {
    if (info.menuItemId === "download-with-nexus") {
        const url = info.linkUrl || info.srcUrl;
        if (url) {
            console.log("Context menu download:", url);
            port.postMessage({
                action: "download",
                url: url,
                referrer: tab.url
            });
        }
    }
});

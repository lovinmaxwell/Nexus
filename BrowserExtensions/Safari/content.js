// Nexus Content Script - Video Detection

console.log("Nexus Content Script Loaded");

function detectVideos() {
    const videos = document.querySelectorAll('video');
    videos.forEach(video => {
        if (!video.dataset.nexusObserved) {
            video.dataset.nexusObserved = "true";
            injectDownloadButton(video);
        }
    });
}

function injectDownloadButton(videoElement) {
    // Basic heuristics to get the source
    let src = videoElement.currentSrc || videoElement.src;
    if (!src) {
        const source = videoElement.querySelector('source');
        if (source) {
            src = source.src;
        }
    }

    if (!src || src.startsWith('blob:')) {
        // Blob URLs usually require more complex handling (XHR interception) 
        // which is out of scope for simple DOM detection. 
        // We skip unless we find a direct http/https/ftp/mms link.
        return;
    }

    // Create container for button relative to video
    // We use a simple absolute positioning approach. 
    // A more robust approach might use Shadow DOM or a separate overlay layer.

    const container = document.createElement('div');
    container.className = 'nexus-download-overlay';
    container.style.position = 'absolute';
    container.style.top = '10px';
    container.style.right = '10px';
    container.style.zIndex = '99999';
    container.style.cursor = 'pointer';
    container.title = 'Download video with Nexus';

    const button = document.createElement('div');
    button.innerText = '⬇ Nexus';
    button.style.backgroundColor = '#007AFF';
    button.style.color = 'white';
    button.style.padding = '6px 12px';
    button.style.borderRadius = '4px';
    button.style.fontFamily = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
    button.style.fontSize = '12px';
    button.style.fontWeight = 'bold';
    button.style.boxShadow = '0 2px 4px rgba(0,0,0,0.2)';
    button.style.transition = 'opacity 0.2s';

    // Hide initially, show on hover of video
    button.style.opacity = '0';

    container.appendChild(button);

    // Determine where to inject. Often directly into the video's parent is okay if relative.
    // If video is strictly part of a shadow root or complex player, this might fail or be hidden.
    // For now, we try inserting before the video and using negative margins, 
    // OR just appending to body and tracking position (complex).
    // SIMPLEST: Append to video's parentNode and position 'absolute'.
    // Ensure parent is relative/absolute.

    const parent = videoElement.parentNode;
    if (parent) {
        // Check if parent is suitable for absolute positioning
        const style = window.getComputedStyle(parent);
        if (style.position === 'static') {
            parent.style.position = 'relative';
        }
        parent.appendChild(container);

        // Hover effects
        parent.addEventListener('mouseenter', () => {
            button.style.opacity = '1';
        });
        parent.addEventListener('mouseleave', () => {
            button.style.opacity = '0';
        });

        // Handle click
        button.addEventListener('click', (e) => {
            e.stopPropagation();
            e.preventDefault();
            console.log("Nexus: Requesting download for", src);

            // Send to background script
            browser.runtime.sendMessage({
                action: "download",
                url: src,
                referrer: window.location.href
            }, (response) => {
                // Optional: Show success state on button
                button.innerText = '✓ Added';
                setTimeout(() => { button.innerText = '⬇ Nexus'; }, 2000);
            });
        });
    }
}

// Initial scan
detectVideos();

// Observe DOM for new videos (Single Page Apps, lazy loading)
const observer = new MutationObserver((mutations) => {
    detectVideos();
});

observer.observe(document.body, {
    childList: true,
    subtree: true
});

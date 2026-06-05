const extensionApi = globalThis.browser ?? globalThis.chrome;

const MEDIA_PATTERNS = [
  /\.m3u8(?:$|[?#])/i,
  /\.mp4(?:$|[?#])/i,
  /\.flv(?:$|[?#])/i,
  /\.m4v(?:$|[?#])/i,
  /\.webm(?:$|[?#])/i,
  /\.mov(?:$|[?#])/i
];

const overlayButtons = new Set();

function resolveUrl(value) {
  if (!value) {
    return null;
  }

  try {
    const resolved = new URL(value, window.location.href);
    if (!['http:', 'https:', 'ftp:', 'mms:'].includes(resolved.protocol)) {
      return null;
    }
    return resolved.href;
  } catch {
    return null;
  }
}

function mediaRank(url) {
  if (/\.m3u8(?:$|[?#])/i.test(url)) {
    return 0;
  }
  if (/\.mp4(?:$|[?#])/i.test(url)) {
    return 1;
  }
  if (/\.flv(?:$|[?#])/i.test(url)) {
    return 2;
  }
  return 3;
}

function isSupportedMediaUrl(url) {
  return MEDIA_PATTERNS.some((pattern) => pattern.test(url));
}

function getBestVideoUrl(videoElement) {
  const candidates = [];
  const seen = new Set();

  const addCandidate = (value, priority) => {
    const resolved = resolveUrl(value);
    if (!resolved || !isSupportedMediaUrl(resolved) || seen.has(resolved)) {
      return;
    }

    seen.add(resolved);
    candidates.push({ url: resolved, priority, rank: mediaRank(resolved) });
  };

  addCandidate(videoElement.currentSrc, 0);
  addCandidate(videoElement.src, 1);

  for (const source of videoElement.querySelectorAll('source')) {
    addCandidate(source.src || source.getAttribute('src'), 2);
  }

  for (const attributeName of ['src', 'data-src', 'data-video-src', 'data-hls-src', 'data-stream-src']) {
    addCandidate(videoElement.getAttribute(attributeName), 3);
  }

  candidates.sort((left, right) => left.rank - right.rank || left.priority - right.priority);
  return candidates[0]?.url ?? null;
}

function updateButtonState(button, label) {
  button.textContent = label;
}

function showButton(button, durationMs) {
  button.style.opacity = '1';

  if (durationMs) {
    window.clearTimeout(button._nexusHideTimeout);
    button._nexusHideTimeout = window.setTimeout(() => {
      button.style.opacity = '0';
    }, durationMs);
  }
}

function sendMessage(message) {
  if (globalThis.browser?.runtime?.sendMessage) {
    return globalThis.browser.runtime.sendMessage(message);
  }

  return new Promise((resolve, reject) => {
    extensionApi.runtime.sendMessage(message, (response) => {
      const runtimeError = extensionApi.runtime.lastError;
      if (runtimeError) {
        reject(new Error(runtimeError.message));
        return;
      }
      resolve(response);
    });
  });
}

function injectDownloadButton(videoElement, videoUrl) {
  if (videoElement.dataset.nexusOverlayInjected === 'true') {
    return;
  }

  const parent = videoElement.parentElement;
  if (!parent) {
    return;
  }

  const parentStyle = window.getComputedStyle(parent);
  if (parentStyle.position === 'static') {
    parent.style.position = 'relative';
  }

  const container = document.createElement('div');
  container.className = 'nexus-download-overlay';
  container.style.position = 'absolute';
  container.style.top = '10px';
  container.style.right = '10px';
  container.style.zIndex = '99999';

  const button = document.createElement('button');
  button.type = 'button';
  button.textContent = 'Download with Nexus';
  button.style.backgroundColor = '#007AFF';
  button.style.color = '#FFFFFF';
  button.style.border = 'none';
  button.style.borderRadius = '999px';
  button.style.padding = '8px 14px';
  button.style.fontFamily = '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif';
  button.style.fontSize = '12px';
  button.style.fontWeight = '600';
  button.style.cursor = 'pointer';
  button.style.boxShadow = '0 2px 8px rgba(0,0,0,0.25)';
  button.style.opacity = '0';
  button.style.transition = 'opacity 0.2s ease';

  const showOverlay = () => showButton(button);
  const hideOverlay = () => {
    window.clearTimeout(button._nexusHideTimeout);
    button.style.opacity = '0';
  };

  parent.addEventListener('mouseenter', showOverlay);
  parent.addEventListener('mouseleave', hideOverlay);

  button.addEventListener('click', async (event) => {
    event.preventDefault();
    event.stopPropagation();

    updateButtonState(button, 'Sending...');

    try {
      const response = await sendMessage({
        action: 'download',
        url: videoUrl,
        originalUrl: videoUrl,
        referrer: window.location.href,
        tabUrl: window.location.href,
        userAgent: navigator.userAgent,
        captureMethod: 'videoOverlay'
      });

      updateButtonState(button, response?.success === false ? 'Failed' : 'Added to Nexus');
    } catch {
      updateButtonState(button, 'Failed');
    }

    window.setTimeout(() => {
      updateButtonState(button, 'Download with Nexus');
    }, 2000);
  });

  container.appendChild(button);
  parent.appendChild(container);

  videoElement.dataset.nexusOverlayInjected = 'true';
  overlayButtons.add(button);
}

function detectVideos() {
  for (const videoElement of document.querySelectorAll('video')) {
    const bestVideoUrl = getBestVideoUrl(videoElement);
    if (bestVideoUrl) {
      injectDownloadButton(videoElement, bestVideoUrl);
    }
  }
}

function revealOverlays() {
  detectVideos();
  for (const button of overlayButtons) {
    showButton(button, 2000);
  }
}

detectVideos();

new MutationObserver(() => detectVideos()).observe(document.documentElement, {
  childList: true,
  subtree: true
});

extensionApi.runtime.onMessage.addListener((message) => {
  if (message.action === 'showOverlay') {
    revealOverlays();
  }
});

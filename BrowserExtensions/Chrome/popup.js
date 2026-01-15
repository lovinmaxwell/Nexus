const NATIVE_HOST_NAME = "com.nexus.host";

document.addEventListener("DOMContentLoaded", () => {
  checkConnection();
  
  document.getElementById("downloadBtn").addEventListener("click", downloadUrl);
  document.getElementById("urlInput").addEventListener("keypress", (e) => {
    if (e.key === "Enter") downloadUrl();
  });
});

async function checkConnection() {
  const statusDot = document.getElementById("statusDot");
  const statusText = document.getElementById("statusText");
  
  try {
    const response = await chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, { ping: true });
    statusDot.classList.remove("disconnected");
    statusText.textContent = "Connected to Nexus";
  } catch (error) {
    statusDot.classList.add("disconnected");
    statusText.textContent = "Nexus not running";
  }
}

async function downloadUrl() {
  const urlInput = document.getElementById("urlInput");
  const url = urlInput.value.trim();
  
  if (!url) {
    alert("Please enter a URL");
    return;
  }
  
  try {
    new URL(url);
  } catch {
    alert("Please enter a valid URL");
    return;
  }
  
  const request = {
    url: url,
    cookies: "",
    referrer: "",
    userAgent: navigator.userAgent,
    filename: null
  };
  
  try {
    const response = await chrome.runtime.sendNativeMessage(NATIVE_HOST_NAME, request);
    if (response.success) {
      urlInput.value = "";
      alert("Download added to Nexus!");
    } else {
      alert("Error: " + response.message);
    }
  } catch (error) {
    alert("Could not connect to Nexus. Is it running?");
  }
}

/// Safari Web Extension popup script.
/// Handles user interactions and communicates with the background script.

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
    const response = await browser.runtime.sendMessage({ action: "ping" });
    if (response.connected) {
      statusDot.classList.remove("disconnected");
      statusText.textContent = "Connected to Nexus";
    } else {
      statusDot.classList.add("disconnected");
      statusText.textContent = "Nexus not running";
    }
  } catch (error) {
    statusDot.classList.add("disconnected");
    statusText.textContent = "Nexus not running";
  }
}

async function downloadUrl() {
  const urlInput = document.getElementById("urlInput");
  const url = urlInput.value.trim();
  
  if (!url) {
    showAlert("Please enter a URL");
    return;
  }
  
  try {
    new URL(url);
  } catch {
    showAlert("Please enter a valid URL");
    return;
  }
  
  try {
    const response = await browser.runtime.sendMessage({
      action: "download",
      url: url,
      filename: null
    });
    
    if (response.success) {
      urlInput.value = "";
      showAlert("Download added to Nexus!");
    } else {
      showAlert("Error: " + (response.error || "Unknown error"));
    }
  } catch (error) {
    showAlert("Could not connect to Nexus. Is it running?");
  }
}

function showAlert(message) {
  alert(message);
}

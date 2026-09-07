
const textarea = document.getElementById("pairing");
const saveButton = document.getElementById("save");
const result = document.getElementById("result");
const downloadButton = document.getElementById("download-debug");
chrome.storage.local.get(["pairing"]).then((items) => {
  if (items.pairing) textarea.value = items.pairing;
});

saveButton.addEventListener("click", async () => {
  result.textContent = "Pairing…";
  result.className = "";
  const response = await chrome.runtime.sendMessage({
    type: "pair",
    pairingString: textarea.value,
  });
  if (response?.ok) {
    result.textContent = "Paired. Heartbeat started.";
    result.className = "ok";
  } else {
    result.textContent = response?.error ?? "Pairing failed.";
    result.className = "err";
  }
});

downloadButton.addEventListener("click", async () => {
  result.textContent = "Building debug bundle…";
  result.className = "";
  const response = await chrome.runtime.sendMessage({ type: "debugBundle" });
  if (!response?.ok || !response.bundle) {
    result.textContent = "Could not build debug bundle.";
    result.className = "err";
    return;
  }

  const text = JSON.stringify(response.bundle, null, 2);
  const blob = new Blob([text], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const a = document.createElement("a");
  a.href = url;
  a.download = `watchlogs-debug-${stamp}.json`;
  a.click();
  URL.revokeObjectURL(url);

  result.textContent = "Debug bundle downloaded.";
  result.className = "ok";
});


const textarea = document.getElementById("pairing");
const saveButton = document.getElementById("save");
const result = document.getElementById("result");
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

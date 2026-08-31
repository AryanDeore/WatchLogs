import { INITIAL_STATE, summarize } from "./src/state.js";

const line = document.getElementById("line");
const hint = document.getElementById("hint");

const state = (await chrome.runtime.sendMessage({ type: "getState" })) ?? INITIAL_STATE;
line.textContent = summarize(state, Date.now());

if (state.status === "needs-pairing") {
  const link = document.createElement("a");
  link.href = "#";
  link.textContent = "Open pairing settings";
  link.addEventListener("click", (event) => {
    event.preventDefault();
    chrome.runtime.openOptionsPage();
  });
  hint.appendChild(link);
}

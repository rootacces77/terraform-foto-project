/**
 * Admin static page – requires an auth token and calls POST /sign
 *
 * This implementation is designed for a browser-friendly model:
 * - You authenticate via a hosted login (e.g., Cognito Hosted UI)
 * - You receive an ID token (JWT) in the URL fragment
 * - Calls to the signer API include: Authorization: Bearer <JWT>
 *
 * Configure:
 * - AUTH_LOGIN_URL: Hosted login URL (redirect back to this page)
 * - AUTH_LOGOUT_URL: Hosted logout URL
 * - SIGNER_API_URL:  https://share.example.com/sign
 *
 * The signer Lambda should accept:
 *   { "folder": "/clients/..../", "cookie_retention_seconds": 604800 }
 * and return:
 *   { "share_url": "https://share.example.com/open?token=..." }
 */

const CONFIG = {
  AUTH_LOGIN_URL: "REPLACE_ME_LOGIN_URL",
  AUTH_LOGOUT_URL: "REPLACE_ME_LOGOUT_URL",
  SIGNER_API_URL:  "https://share.example.com/sign",
  MAX_DAYS: 14,
  MIN_DAYS: 1,
};

const el = (id) => document.getElementById(id);

const btnLogin = el("btnLogin");
const btnLogout = el("btnLogout");
const btnGenerate = el("btnGenerate");
const btnCopy = el("btnCopy");
const btnOpen = el("btnOpen");
const statusBox = el("status");
const resultBox = el("result");
const folderInput = el("folder");
const daysInput = el("days");

let shareUrl = null;

function showStatus(msg, type = "ok") {
  statusBox.style.display = "block";
  statusBox.classList.remove("ok", "err");
  statusBox.classList.add(type);
  statusBox.textContent = msg;
}

function showResult(url) {
  resultBox.style.display = "block";
  resultBox.textContent = url;
}

function setButtonsEnabled(hasUrl) {
  btnCopy.disabled = !hasUrl;
  btnOpen.disabled = !hasUrl;
}

function parseTokenFromUrl() {
  // Common hosted UI returns token in URL fragment: #id_token=...&...
  const hash = window.location.hash || "";
  if (!hash.startsWith("#")) return null;

  const params = new URLSearchParams(hash.substring(1));
  const idToken = params.get("id_token");
  return idToken || null;
}

function getToken() {
  // Persist token in sessionStorage
  let t = sessionStorage.getItem("id_token");
  if (t) return t;

  t = parseTokenFromUrl();
  if (t) {
    sessionStorage.setItem("id_token", t);
    // Clean URL fragment
    history.replaceState(null, document.title, window.location.pathname + window.location.search);
    return t;
  }
  return null;
}

function requireAuthOrRedirect() {
  const token = getToken();
  if (!token) {
    // This is the "invoke authorization when accessed"
    window.location.href = CONFIG.AUTH_LOGIN_URL;
    return null;
  }
  return token;
}

btnLogin.addEventListener("click", () => {
  window.location.href = CONFIG.AUTH_LOGIN_URL;
});

btnLogout.addEventListener("click", () => {
  sessionStorage.removeItem("id_token");
  window.location.href = CONFIG.AUTH_LOGOUT_URL;
});

btnCopy.addEventListener("click", async () => {
  if (!shareUrl) return;
  await navigator.clipboard.writeText(shareUrl);
  showStatus("Copied share link to clipboard.", "ok");
});

btnOpen.addEventListener("click", () => {
  if (!shareUrl) return;
  window.open(shareUrl, "_blank", "noopener,noreferrer");
});

function normalizeFolder(folder) {
  folder = (folder || "").trim();
  if (!folder.startsWith("/")) folder = "/" + folder;
  if (!folder.endsWith("/")) folder = folder + "/";
  return folder;
}

btnGenerate.addEventListener("click", async () => {
  shareUrl = null;
  setButtonsEnabled(false);
  resultBox.style.display = "none";
  statusBox.style.display = "none";

  const token = requireAuthOrRedirect();
  if (!token) return;

  const folder = normalizeFolder(folderInput.value);
  const days = parseInt(daysInput.value, 10);

  if (!folder.startsWith("/clients/")) {
    showStatus('Folder must start with "/clients/".', "err");
    return;
  }

  if (Number.isNaN(days) || days < CONFIG.MIN_DAYS || days > CONFIG.MAX_DAYS) {
    showStatus(`Cookie retention must be between ${CONFIG.MIN_DAYS} and ${CONFIG.MAX_DAYS} days.`, "err");
    return;
  }

  const cookie_retention_seconds = days * 24 * 60 * 60;

  btnGenerate.disabled = true;
  showStatus("Generating link…", "ok");

  try {
    const resp = await fetch(CONFIG.SIGNER_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`,
      },
      body: JSON.stringify({
        folder,
        cookie_retention_seconds,
      }),
    });

    const text = await resp.text();
    let payload;
    try { payload = JSON.parse(text); } catch { payload = { raw: text }; }

    if (!resp.ok) {
      showStatus(`Error (${resp.status}): ${payload.error || payload.message || "request_failed"}`, "err");
      return;
    }

    if (!payload.share_url) {
      showStatus("No share_url returned by API.", "err");
      return;
    }

    shareUrl = payload.share_url;
    showResult(shareUrl);
    showStatus("Share link generated.", "ok");
    setButtonsEnabled(true);

  } catch (e) {
    showStatus("Network or configuration error while calling the signer API.", "err");
  } finally {
    btnGenerate.disabled = false;
  }
});

// On load: require auth (redirect if not logged in)
requireAuthOrRedirect();
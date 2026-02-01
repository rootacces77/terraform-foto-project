/**
 * Admin static page
 * - Login/Logout via Cognito Hosted UI (Authorization Code + PKCE)
 * - Calls POST /sign with Authorization: Bearer <access_token>
 *
 * You must set these:
 * - COGNITO_DOMAIN: "https://<prefix>.auth.<region>.amazoncognito.com"
 * - COGNITO_CLIENT_ID: "<app client id>"
 * - COGNITO_REDIRECT_URI: "https://admin.example.com/"  (must match callback_urls)
 * - COGNITO_LOGOUT_URI:  "https://admin.example.com/"  (must match logout_urls)
 * - SIGNER_API_URL: "https://share.example.com/prod/sign"  (or your route URL)
 */

const CONFIG = {
  COGNITO_DOMAIN: "https://foto.auth.us-east-1.amazoncognito.com",
  COGNITO_CLIENT_ID: "3g1o5pvqlhndiufvkuc9u25t8f",
  COGNITO_REDIRECT_URI: "https://admin.project-practice.com/",
  COGNITO_LOGOUT_URI: "https://admin.project-practice.com/",

  SIGNER_API_URL: "https://eyeitiipbi.execute-api.eu-south-1.amazonaws.com/prod/sign",

  MAX_DAYS: 14,
  MIN_DAYS: 1,
};

const STORAGE = {
  accessToken: "access_token",
  idToken: "id_token",
  refreshToken: "refresh_token",
  expiresAt: "expires_at_epoch",
  pkceVerifier: "pkce_verifier",
  oauthState: "oauth_state",
};

const el = (id) => document.getElementById(id);

const btnLogin = el("btnLogin");
const btnLogout = el("btnLogout");
const btnGenerate = el("btnGenerate");
const btnCopy = el("btnCopy");
const btnOpen = el("btnOpen");

const authStatus = el("authStatus");
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

function isLoggedIn() {
  const t = sessionStorage.getItem(STORAGE.accessToken);
  const exp = parseInt(sessionStorage.getItem(STORAGE.expiresAt) || "0", 10);
  const now = Math.floor(Date.now() / 1000);
  return !!t && exp > now + 30; // 30s skew
}

function updateAuthUI() {
  const ok = isLoggedIn();
  authStatus.textContent = ok ? "Logged in" : "Not logged in";
  btnLogout.disabled = !ok;
}

btnCopy.addEventListener("click", async () => {
  if (!shareUrl) return;
  await navigator.clipboard.writeText(shareUrl);
  showStatus("Copied share link to clipboard.", "ok");
});

btnOpen.addEventListener("click", () => {
  if (!shareUrl) return;
  window.open(shareUrl, "_blank", "noopener,noreferrer");
});

function normalizeFolderPrefix(input) {
  let s = (input || "").trim();
  s = s.replace(/^\/+/, "").replace(/\/+$/, ""); // strip leading/trailing slashes
  if (!s) return null;
  return s + "/"; // make prefix
}

/** -------------------------
 * PKCE helpers
 * ------------------------*/
function base64UrlEncode(bytes) {
  const str = btoa(String.fromCharCode(...bytes));
  return str.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function randomBytes(len) {
  const arr = new Uint8Array(len);
  crypto.getRandomValues(arr);
  return arr;
}

async function sha256(text) {
  const enc = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", enc);
  return new Uint8Array(hash);
}

async function pkceChallengeFromVerifier(verifier) {
  const hashed = await sha256(verifier);
  return base64UrlEncode(hashed);
}

function buildAuthorizeUrl() {
  // state to prevent CSRF
  const state = base64UrlEncode(randomBytes(16));
  sessionStorage.setItem(STORAGE.oauthState, state);

  // PKCE verifier & challenge
  const verifier = base64UrlEncode(randomBytes(32));
  sessionStorage.setItem(STORAGE.pkceVerifier, verifier);

  const authorize = new URL(CONFIG.COGNITO_DOMAIN.replace(/\/+$/, "") + "/oauth2/authorize");
  authorize.searchParams.set("client_id", CONFIG.COGNITO_CLIENT_ID);
  authorize.searchParams.set("response_type", "code");
  authorize.searchParams.set("scope", "openid email profile");
  authorize.searchParams.set("redirect_uri", CONFIG.COGNITO_REDIRECT_URI);
  authorize.searchParams.set("state", state);
  // code_challenge added after we compute it
  return { authorize, verifier };
}

async function startLogin() {
  const { authorize, verifier } = buildAuthorizeUrl();
  const challenge = await pkceChallengeFromVerifier(verifier);
  authorize.searchParams.set("code_challenge", challenge);
  authorize.searchParams.set("code_challenge_method", "S256");
  window.location.href = authorize.toString();
}

function logout() {
  // Clear local tokens
  sessionStorage.removeItem(STORAGE.accessToken);
  sessionStorage.removeItem(STORAGE.idToken);
  sessionStorage.removeItem(STORAGE.refreshToken);
  sessionStorage.removeItem(STORAGE.expiresAt);

  // Redirect to Cognito logout
  const logoutUrl = new URL(CONFIG.COGNITO_DOMAIN.replace(/\/+$/, "") + "/logout");
  logoutUrl.searchParams.set("client_id", CONFIG.COGNITO_CLIENT_ID);
  logoutUrl.searchParams.set("logout_uri", CONFIG.COGNITO_LOGOUT_URI);

  window.location.href = logoutUrl.toString();
}

btnLogin.addEventListener("click", () => startLogin());
btnLogout.addEventListener("click", () => logout());

async function exchangeCodeForTokens(code) {
  const verifier = sessionStorage.getItem(STORAGE.pkceVerifier);
  if (!verifier) throw new Error("missing_pkce_verifier");

  const tokenUrl = CONFIG.COGNITO_DOMAIN.replace(/\/+$/, "") + "/oauth2/token";

  const body = new URLSearchParams();
  body.set("grant_type", "authorization_code");
  body.set("client_id", CONFIG.COGNITO_CLIENT_ID);
  body.set("code", code);
  body.set("redirect_uri", CONFIG.COGNITO_REDIRECT_URI);
  body.set("code_verifier", verifier);

  const resp = await fetch(tokenUrl, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: body.toString(),
  });

  const text = await resp.text();
  let payload;
  try { payload = JSON.parse(text); } catch { payload = { raw: text }; }

  if (!resp.ok) {
    throw new Error(payload.error || payload.error_description || "token_exchange_failed");
  }

  // Store tokens
  const now = Math.floor(Date.now() / 1000);
  const expiresIn = payload.expires_in || 3600;

  sessionStorage.setItem(STORAGE.accessToken, payload.access_token || "");
  sessionStorage.setItem(STORAGE.idToken, payload.id_token || "");
  if (payload.refresh_token) sessionStorage.setItem(STORAGE.refreshToken, payload.refresh_token);
  sessionStorage.setItem(STORAGE.expiresAt, String(now + expiresIn));

  // Cleanup PKCE material
  sessionStorage.removeItem(STORAGE.pkceVerifier);
}

async function handleCognitoCallbackIfPresent() {
  const url = new URL(window.location.href);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");

  if (!code) return;

  const expectedState = sessionStorage.getItem(STORAGE.oauthState);
  sessionStorage.removeItem(STORAGE.oauthState);

  if (!state || !expectedState || state !== expectedState) {
    showStatus("Login failed: invalid state.", "err");
    return;
  }

  try {
    showStatus("Completing login…", "ok");
    await exchangeCodeForTokens(code);

    // Remove code/state from URL
    url.searchParams.delete("code");
    url.searchParams.delete("state");
    window.history.replaceState({}, document.title, url.pathname + (url.search ? url.search : ""));

    showStatus("Logged in.", "ok");
  } catch (e) {
    showStatus("Login failed while exchanging code for tokens.", "err");
  } finally {
    updateAuthUI();
  }
}

function getAccessTokenOrNull() {
  if (!isLoggedIn()) return null;
  return sessionStorage.getItem(STORAGE.accessToken);
}

/** -------------------------
 * Generate
 * ------------------------*/
btnGenerate.addEventListener("click", async () => {
  shareUrl = null;
  setButtonsEnabled(false);
  resultBox.style.display = "none";
  statusBox.style.display = "none";

  const token = getAccessTokenOrNull();
  if (!token) {
    // Not logged in → start login then come back
    await startLogin();
    return;
  }

  const folderPrefix = normalizeFolderPrefix(folderInput.value);
  const days = parseInt(daysInput.value, 10);

  if (!folderPrefix) {
    showStatus("Folder is required (e.g., client123 or client123/job456).", "err");
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
        "Authorization": `Bearer ${token}`, // JWT (access token)
      },
      body: JSON.stringify({
        folder: folderPrefix,
        cookie_retention_seconds,
      }),
    });

    const text = await resp.text();
    let payload;
    try { payload = JSON.parse(text); } catch { payload = { raw: text }; }

    if (!resp.ok) {
      // If token expired or invalid, kick back to login
      if (resp.status === 401 || resp.status === 403) {
        sessionStorage.removeItem(STORAGE.accessToken);
        sessionStorage.removeItem(STORAGE.expiresAt);
        updateAuthUI();
        showStatus("Session expired. Please login again.", "err");
        return;
      }
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

// On load: handle possible Cognito callback
handleCognitoCallbackIfPresent().finally(() => updateAuthUI());

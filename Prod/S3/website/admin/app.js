const CONFIG = {
  COGNITO_DOMAIN: "https://foto.auth.eu-south-1.amazoncognito.com",
  COGNITO_CLIENT_ID: "9vj56bf1ovaub0kf82ed4kq1h",
  COGNITO_REDIRECT_URI: "https://admin.project-practice.com/",
  COGNITO_LOGOUT_URI: "https://admin.project-practice.com/",

  SIGNER_API_URL: "https://3qg8vce4tg.execute-api.eu-south-1.amazonaws.com/prod/sign",
  REVOKE_API_URL: "https://3qg8vce4tg.execute-api.eu-south-1.amazonaws.com/prod/revoke",
  ADMIN_LIST_URL: "https://3qg8vce4tg.execute-api.eu-south-1.amazonaws.com/prod/admin/links",

  MAX_DAYS: 30,
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

const btnRefresh = el("btnRefresh");
const searchInput = el("search");

const authStatus = el("authStatus");
const statusBox = el("status");
const resultBox = el("result");
const folderInput = el("folder");
const daysInput = el("days");

const linksStatus = el("linksStatus");
const foldersRoot = el("folders");

let shareUrl = null;
let lastItems = [];


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

function showLinksStatus(msg, type = "ok") {
  linksStatus.style.display = "block";
  linksStatus.classList.remove("ok", "err");
  linksStatus.classList.add(type);
  linksStatus.textContent = msg;
}

function hideLinksStatus() {
  linksStatus.style.display = "none";
  linksStatus.textContent = "";
}

function isLoggedIn() {
  const t = sessionStorage.getItem(STORAGE.accessToken);
  const exp = parseInt(sessionStorage.getItem(STORAGE.expiresAt) || "0", 10);
  const now = Math.floor(Date.now() / 1000);
  return !!t && exp > now + 30;
}

function updateAuthUI() {
  const ok = isLoggedIn();
  authStatus.textContent = ok ? "Logged in" : "Not logged in";
  btnLogout.disabled = !ok;
  btnRefresh.disabled = !ok;
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
  s = s.replace(/^\/+/, "").replace(/\/+$/, "");
  if (!s) return null;
  return s + "/";
}

function getAccessTokenOrNull() {
  if (!isLoggedIn()) return null;
  return sessionStorage.getItem(STORAGE.accessToken);
}

/** PKCE helpers */
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
  const state = base64UrlEncode(randomBytes(16));
  sessionStorage.setItem(STORAGE.oauthState, state);

  const verifier = base64UrlEncode(randomBytes(32));
  sessionStorage.setItem(STORAGE.pkceVerifier, verifier);

  const authorize = new URL(CONFIG.COGNITO_DOMAIN.replace(/\/+$/, "") + "/oauth2/authorize");
  authorize.searchParams.set("client_id", CONFIG.COGNITO_CLIENT_ID);
  authorize.searchParams.set("response_type", "code");
  authorize.searchParams.set("scope", "openid email profile");
  authorize.searchParams.set("redirect_uri", CONFIG.COGNITO_REDIRECT_URI);
  authorize.searchParams.set("state", state);
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
  sessionStorage.removeItem(STORAGE.accessToken);
  sessionStorage.removeItem(STORAGE.idToken);
  sessionStorage.removeItem(STORAGE.refreshToken);
  sessionStorage.removeItem(STORAGE.expiresAt);

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

  if (!resp.ok) throw new Error(payload.error || payload.error_description || "token_exchange_failed");

  const now = Math.floor(Date.now() / 1000);
  const expiresIn = payload.expires_in || 3600;

  sessionStorage.setItem(STORAGE.accessToken, payload.access_token || "");
  sessionStorage.setItem(STORAGE.idToken, payload.id_token || "");
  if (payload.refresh_token) sessionStorage.setItem(STORAGE.refreshToken, payload.refresh_token);
  sessionStorage.setItem(STORAGE.expiresAt, String(now + expiresIn));

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

    url.searchParams.delete("code");
    url.searchParams.delete("state");
    window.history.replaceState({}, document.title, url.pathname + (url.search ? url.search : ""));

    showStatus("Logged in.", "ok");
  } catch {
    showStatus("Login failed while exchanging code for tokens.", "err");
  } finally {
    updateAuthUI();
  }
}

/** Active links UI */
function epochToLocalString(epoch) {
  if (!epoch) return "—";
  return new Date(epoch * 1000).toLocaleString();
}

function groupByFolder(items) {
  const m = new Map();
  for (const it of items) {
    const folder = (it.folder || "").trim();
    if (!folder) continue;
    if (!m.has(folder)) m.set(folder, []);
    m.get(folder).push(it);
  }
  return Array.from(m.entries())
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([folder, links]) => ({
      folder,
      links: links.sort((x, y) => (y.link_exp || 0) - (x.link_exp || 0)),
    }));
}

function applyFilter(items) {
  const q = (searchInput.value || "").trim().toLowerCase();
  if (!q) return items;
  return items.filter((it) => (it.folder || "").toLowerCase().includes(q));
}

function clearFoldersUI() {
  foldersRoot.innerHTML = "";
}

function renderFolders(items) {
  clearFoldersUI();

  const filtered = applyFilter(items);
  const grouped = groupByFolder(filtered);

  if (grouped.length === 0) {
    const div = document.createElement("div");
    div.className = "msg";
    div.textContent = "No active links found (or filter removed them).";
    foldersRoot.appendChild(div);
    return;
  }

  for (const g of grouped) {
    const card = document.createElement("div");
    card.className = "folderCard";

    const head = document.createElement("div");
    head.className = "folderHead";

    const name = document.createElement("div");
    name.className = "folderName mono";
    name.textContent = g.folder;

    const meta = document.createElement("div");
    meta.className = "small";
    meta.textContent = `${g.links.length} link(s)`;

    head.appendChild(name);
    head.appendChild(meta);
    card.appendChild(head);

    const linksWrap = document.createElement("div");
    linksWrap.className = "links";

    for (const it of g.links) {
      const token = it.token;
      const linkExp = it.link_exp || 0;

      const shareUrl = `https://gallery.project-practice.com/open?t=${encodeURIComponent(token)}`;

      const row = document.createElement("div");
      row.className = "linkRow";

      const metaDiv = document.createElement("div");
      metaDiv.className = "linkMeta";

      const urlDiv = document.createElement("div");
      urlDiv.className = "linkUrl mono";

      const a = document.createElement("a");
      a.className = "inline";
      a.href = shareUrl;
      a.target = "_blank";
      a.rel = "noopener noreferrer";
      a.textContent = shareUrl;

      urlDiv.appendChild(a);

      const info = document.createElement("div");
      info.className = "linkInfo";
      info.innerHTML = `
        <span>Expires: <b>${epochToLocalString(linkExp)}</b></span>
        <span>Token: <span class="mono">${token.slice(0, 10)}…</span></span>
      `;

      metaDiv.appendChild(urlDiv);
      metaDiv.appendChild(info);

      const actions = document.createElement("div");
      actions.className = "actionsRow";

      const btnDisable = document.createElement("button");
      btnDisable.className = "danger";
      btnDisable.textContent = "Disable";
      btnDisable.addEventListener("click", async () => {
        await revokeToken(token, row);
      });

      actions.appendChild(btnDisable);
      row.appendChild(metaDiv);
      row.appendChild(actions);

      linksWrap.appendChild(row);
    }

    card.appendChild(linksWrap);
    foldersRoot.appendChild(card);
  }
}

async function fetchAdminLinks() {
  const jwt = getAccessTokenOrNull();
  if (!jwt) {
    await startLogin();
    return;
  }

  hideLinksStatus();
  showLinksStatus("Loading active links…", "ok");
  btnRefresh.disabled = true;

  try {
    const resp = await fetch(CONFIG.ADMIN_LIST_URL, {
      method: "GET",
      headers: { "Authorization": `Bearer ${jwt}` },
      cache: "no-store",
    });

    const text = await resp.text();
    let payload;
    try { payload = JSON.parse(text); } catch { payload = { raw: text }; }

    if (!resp.ok) {
      if (resp.status === 401 || resp.status === 403) {
        sessionStorage.removeItem(STORAGE.accessToken);
        sessionStorage.removeItem(STORAGE.expiresAt);
        updateAuthUI();
        showLinksStatus("Session expired. Please login again.", "err");
        return;
      }
      showLinksStatus(`Failed to load links (${resp.status}).`, "err");
      return;
    }

    const items = Array.isArray(payload.items) ? payload.items : [];
    lastItems = items;

    showLinksStatus(`Loaded ${items.length} active link(s).`, "ok");
    renderFolders(items);
  } catch {
    showLinksStatus("Network/config error while loading active links.", "err");
  } finally {
    btnRefresh.disabled = !isLoggedIn();
  }
}

async function revokeToken(token, rowEl) {
  const jwt = getAccessTokenOrNull();
  if (!jwt) {
    await startLogin();
    return;
  }

  const btn = rowEl.querySelector("button");
  if (btn) btn.disabled = true;

  try {
    const resp = await fetch(CONFIG.REVOKE_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${jwt}`,
      },
      body: JSON.stringify({ token }),
    });

    const text = await resp.text();
    let payload;
    try { payload = JSON.parse(text); } catch { payload = { raw: text }; }

    if (!resp.ok) {
      if (resp.status === 401 || resp.status === 403) {
        sessionStorage.removeItem(STORAGE.accessToken);
        sessionStorage.removeItem(STORAGE.expiresAt);
        updateAuthUI();
        showLinksStatus("Session expired. Please login again.", "err");
        return;
      }
      showLinksStatus(`Disable failed (${resp.status}): ${payload.error || "request_failed"}`, "err");
      if (btn) btn.disabled = false;
      return;
    }

    lastItems = lastItems.filter((x) => x.token !== token);
    renderFolders(lastItems);
    showLinksStatus("Link disabled (revoked).", "ok");
  } catch {
    showLinksStatus("Network/config error while disabling link.", "err");
    if (btn) btn.disabled = false;
  }
}

btnRefresh.addEventListener("click", () => fetchAdminLinks());
searchInput.addEventListener("input", () => renderFolders(lastItems));


/** Generate link */
btnGenerate.addEventListener("click", async () => {
  shareUrl = null;
  setButtonsEnabled(false);
  resultBox.style.display = "none";
  statusBox.style.display = "none";

  const token = getAccessTokenOrNull();
  if (!token) {
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
    showStatus(`Link TTL must be between ${CONFIG.MIN_DAYS} and ${CONFIG.MAX_DAYS} days.`, "err");
    return;
  }

  const link_ttl_seconds = days * 24 * 60 * 60;

  btnGenerate.disabled = true;
  showStatus("Generating link…", "ok");

  try {
    const resp = await fetch(CONFIG.SIGNER_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${token}`,
      },
      body: JSON.stringify({ folder: folderPrefix, link_ttl_seconds }),
    });

    const text = await resp.text();
    let payload;
    try { payload = JSON.parse(text); } catch { payload = { raw: text }; }

    if (!resp.ok) {
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

    fetchAdminLinks().catch(() => {});
  } catch {
    showStatus("Network or configuration error while calling the signer API.", "err");
  } finally {
    btnGenerate.disabled = false;
  }
});


handleCognitoCallbackIfPresent()
  .finally(() => {
    updateAuthUI();
    if (isLoggedIn()) fetchAdminLinks().catch(() => {});
  });

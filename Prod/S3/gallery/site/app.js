/* =============================
   Theme (Light default + saved toggle)
============================= */
const THEME_KEY = "gallery_theme";

function setTheme(theme) {
  document.documentElement.setAttribute("data-theme", theme);
  localStorage.setItem(THEME_KEY, theme);

  const btn = document.getElementById("themeToggle");
  if (btn) btn.textContent = theme === "dark" ? "Light mode" : "Dark mode";
}

function initTheme() {
  const saved = localStorage.getItem(THEME_KEY);
  setTheme(saved === "dark" ? "dark" : "light");
}

/* =============================
   Helpers
============================= */
function getFolderFromQuery() {
  const url = new URL(window.location.href);
  return url.searchParams.get("folder") || "";
}

function normalizeFolder(folder) {
  let f = (folder || "").trim();
  f = f.replace(/^\/+/, "");
  if (!f) return null;
  if (!f.endsWith("/")) f += "/";
  return f; // e.g. "client123/job456/"
}

function isProbablyImage(key) {
  return /\.(png|jpe?g|gif|webp|avif)$/i.test(key || "");
}

function basename(key) {
  const parts = (key || "").split("/");
  return parts[parts.length - 1] || key;
}

function safeZipName(folder) {
  return (folder || "gallery/")
    .replace(/[^A-Za-z0-9._-]/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
}

/**
 * /list returns full keys like:
 *   "gallery/client123/job456/photo 1.jpg"
 * or zip:
 *   "gallery/client123/job456/some-file.zip"
 *
 * CloudFront expects path:
 *   "/gallery/client123/job456/photo%201.jpg"
 *
 * So we MUST use the key directly and encode per path segment.
 */
function objUrlFromKey(key) {
  const clean = (key || "").replace(/^\/+/, ""); // no leading slash
  const encoded = clean.split("/").map(encodeURIComponent).join("/");
  return `/${encoded}`;
}

async function loadList(folder) {
  const resp = await fetch(`/list?folder=${encodeURIComponent(folder)}`, { cache: "no-store" });
  if (!resp.ok) throw new Error(`list failed (${resp.status})`);
  return resp.json();
}

function triggerDownloadBlob(blob, filename) {
  const a = document.createElement("a");
  const url = URL.createObjectURL(blob);
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

/* =============================
   Lightbox (slider)
============================= */
let IMAGE_KEYS = [];
let CUR = 0;
let CURRENT_FOLDER = null;

// NEW: zip key returned by /list
let ZIP_KEY = null;

function openModalAt(idx) {
  const modal = document.getElementById("modal");
  const img = document.getElementById("modalImg");
  const title = document.getElementById("modalTitle");
  const dl = document.getElementById("modalDownload");

  CUR = Math.max(0, Math.min(idx, IMAGE_KEYS.length - 1));
  const key = IMAGE_KEYS[CUR];

  const objUrl = objUrlFromKey(key);

  img.src = objUrl;
  title.textContent = basename(key);

  dl.href = objUrl;
  dl.setAttribute("download", basename(key));

  modal.classList.add("open");
}

function closeModal() {
  const modal = document.getElementById("modal");
  const img = document.getElementById("modalImg");
  img.src = "";
  modal.classList.remove("open");
}

function nextImg() {
  if (!IMAGE_KEYS.length) return;
  openModalAt((CUR + 1) % IMAGE_KEYS.length);
}

function prevImg() {
  if (!IMAGE_KEYS.length) return;
  openModalAt((CUR - 1 + IMAGE_KEYS.length) % IMAGE_KEYS.length);
}

/* Swipe support */
let TOUCH_X = null;
function onTouchStart(e) {
  if (!e.touches || e.touches.length !== 1) return;
  TOUCH_X = e.touches[0].clientX;
}
function onTouchEnd(e) {
  if (TOUCH_X == null) return;
  const x2 = (e.changedTouches && e.changedTouches[0]) ? e.changedTouches[0].clientX : null;
  if (x2 == null) { TOUCH_X = null; return; }
  const dx = x2 - TOUCH_X;
  TOUCH_X = null;

  if (Math.abs(dx) < 45) return;
  if (dx < 0) nextImg();
  else prevImg();
}

/* =============================
   Render grid (Instagram-like)
============================= */
function renderGrid(keys, folder) {
  CURRENT_FOLDER = folder;

  const grid = document.getElementById("grid");
  grid.innerHTML = "";

  IMAGE_KEYS = (keys || []).filter(isProbablyImage);

  // Status shows number of images
  document.getElementById("status").textContent = `${IMAGE_KEYS.length} image(s)`;

  // Always show Download button (requested)
  const dlFolderBtn = document.getElementById("dlFolder");
  dlFolderBtn.style.display = "inline-block";
  dlFolderBtn.disabled = false;

  IMAGE_KEYS.forEach((key, idx) => {
    const objUrl = objUrlFromKey(key);

    const tile = document.createElement("div");
    tile.className = "tile";

    const img = document.createElement("img");
    img.src = objUrl;
    img.loading = "lazy";
    img.alt = basename(key);
    img.addEventListener("click", () => openModalAt(idx));

    tile.appendChild(img);
    grid.appendChild(tile);
  });
}

/* =============================
   Download folder as ZIP (server-side ZIP stored in S3)
   - Does NOT build zip in browser
   - Uses ZIP_KEY returned by /list
============================= */
async function downloadFolderZip(folder) {
  const status = document.getElementById("status");
  const btn = document.getElementById("dlFolder");

  if (!ZIP_KEY) {
    status.textContent = "ZIP is not available yet for this folder.";
    return;
  }

  btn.disabled = true;

  try {
    const zipUrl = objUrlFromKey(ZIP_KEY);

    const resp = await fetch(zipUrl, { cache: "no-store" });
    if (!resp.ok) throw new Error(`ZIP download failed (${resp.status})`);

    const blob = await resp.blob();

    const filename = basename(ZIP_KEY) || `${safeZipName(folder)}.zip`;
    triggerDownloadBlob(blob, filename);

    status.textContent = `Downloaded ${filename}`;
  } catch (e) {
    status.textContent = `ZIP download failed: ${e.message}`;
  } finally {
    btn.disabled = false;
  }
}

/* =============================
   Main
============================= */
(async function main() {
  initTheme();

  // Theme toggle wiring
  document.getElementById("themeToggle").addEventListener("click", () => {
    const cur = document.documentElement.getAttribute("data-theme") || "light";
    setTheme(cur === "dark" ? "light" : "dark");
  });

  const status = document.getElementById("status");
  const folder = normalizeFolder(getFolderFromQuery());

  if (!folder) {
    status.textContent = "Missing ?folder=. Example: ?folder=client123/job456/";
    return;
  }

  // Lightbox wiring
  document.getElementById("modalClose").addEventListener("click", closeModal);
  document.getElementById("modalImg").addEventListener("click", closeModal);
  document.getElementById("nextBtn").addEventListener("click", nextImg);
  document.getElementById("prevBtn").addEventListener("click", prevImg);

  const stage = document.getElementById("modalStage");
  stage.addEventListener("touchstart", onTouchStart, { passive: true });
  stage.addEventListener("touchend", onTouchEnd, { passive: true });

  window.addEventListener("keydown", (e) => {
    const modalOpen = document.getElementById("modal").classList.contains("open");
    if (!modalOpen) return;

    if (e.key === "Escape") closeModal();
    if (e.key === "ArrowRight") nextImg();
    if (e.key === "ArrowLeft") prevImg();
  });

  // Folder ZIP button (always visible)
  document.getElementById("dlFolder").addEventListener("click", () => downloadFolderZip(folder));

  try {
    const data = await loadList(folder);

    // Expecting:
    // { folder: "...", files: [...], zip: "gallery/.../something.zip" }
    // OR fallback: { files: [...] } / array
    ZIP_KEY = Array.isArray(data) ? null : (data.zip || null);

    // If list response is an array, treat as files list
    const keys = Array.isArray(data) ? data : (data.files || data.keys || []);
    renderGrid(keys, folder);

    // Optional hint
    if (!ZIP_KEY) {
      status.textContent = `${IMAGE_KEYS.length} image(s) • ZIP not available yet`;
    }
  } catch (e) {
    status.textContent = `Could not load list: ${e.message}`;
    // Still keep button visible (renderGrid not called here)
    const dlFolderBtn = document.getElementById("dlFolder");
    if (dlFolderBtn) dlFolderBtn.style.display = "inline-block";
  }
})();


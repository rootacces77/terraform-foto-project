
(function () {
  function qs(id) { return document.getElementById(id); }

  function goError(code, reason) {
    const u = `/site/error.html?code=${encodeURIComponent(String(code))}&reason=${encodeURIComponent(reason || "")}`;
    window.location.replace(u);
  }

  function showToast(msg, ms = 3500) {
    const el = qs("toast");
    if (!el) return;
    el.textContent = msg;
    el.classList.add("show");
    window.clearTimeout(showToast._t);
    showToast._t = window.setTimeout(() => el.classList.remove("show"), ms);
  }

  function getFolderFromQuery() {
    const url = new URL(window.location.href);
    return url.searchParams.get("folder") || "";
  }

  function getTokenFromQuery() {
    const url = new URL(window.location.href);
    return url.searchParams.get("t") || "";
  }

  function normalizeFolder(folder) {
    let f = (folder || "").trim();
    f = f.replace(/^\/+/, "");
    f = f.replace(/\/+$/, "");
    if (!f) return null;
    return f + "/";
  }

  function encodeKeyForUrl(key) {
    return (key || "").split("/").map(encodeURIComponent).join("/");
  }

  function basename(key) {
    const parts = (key || "").split("/");
    return parts[parts.length - 1] || key;
  }

  function safeZipName(folder) {
    return (folder || "gallery/")
      .replace(/\/+$/, "")
      .replace(/[^A-Za-z0-9._-]/g, "_")
      .replace(/_+/g, "_")
      .replace(/^_+|_+$/g, "") + ".zip";
  }

  function setStatus(msg) {
    const st = qs("status");
    if (st) st.textContent = msg;
  }

  function extLower(key) {
    const m = (key || "").toLowerCase().match(/\.([a-z0-9]+)$/);
    return m ? m[1] : "";
  }

  function isVideoKey(key) {
    const e = extLower(key);
    return ["mp4", "mov", "webm", "m4v"].includes(e);
  }

  function isImageKey(key) {
    const e = extLower(key);
    return ["jpg", "jpeg", "png", "webp", "gif", "avif", "bmp"].includes(e);
  }

  async function loadList(folder, token) {
    const url = `/list?folder=${encodeURIComponent(folder)}&t=${encodeURIComponent(token)}`;
    const resp = await fetch(url, { cache: "no-store" });

    if (resp.status === 401 || resp.status === 403) { goError(403, "link_expired"); return null; }
    if (resp.status === 404) { goError(404, "not_found"); return null; }
    if (!resp.ok) { goError(500, "list_failed"); return null; }
    return resp.json();
  }

  // ---------- state ----------
  const state = {
    files: [],
    visualOrder: [],
    currentPos: -1,
    folder: "",
    token: "",
    modalReqId: 0
  };

  // ---------- modal refs ----------
  const modal = () => qs("modal");
  const modalImg = () => qs("modalImg");
  const modalTitle = () => qs("modalTitle");
  const modalDownload = () => qs("modalDownload");
  const modalClose = () => qs("modalClose");
  const prevBtn = () => qs("prevBtn");
  const nextBtn = () => qs("nextBtn");
  const modalStage = () => qs("modalStage");

  // Create / reuse a video element inside modalStage
  function ensureModalVideo() {
    const stage = modalStage();
    if (!stage) return null;
    let v = stage.querySelector("video[data-modal-video='1']");
    if (!v) {
      v = document.createElement("video");
      v.setAttribute("data-modal-video", "1");
      v.controls = true;
      v.playsInline = true;
      v.preload = "metadata";
      v.style.position = "relative";
      v.style.zIndex = "1";
      v.style.maxWidth = "min(96vw, 1800px)";
      v.style.maxHeight = "min(84vh, 900px)";
      v.style.width = "auto";
      v.style.height = "auto";
      v.style.display = "none";
      stage.appendChild(v);
    }
    return v;
  }

  function isModalOpen() {
    const m = modal();
    return !!(m && m.classList.contains("open"));
  }

  function setModalOpen(open) {
    const m = modal();
    if (!m) return;
    if (open) {
      m.classList.add("open");
      document.body.style.overflow = "hidden";
    } else {
      m.classList.remove("open");
      document.body.style.overflow = "";
      const mv = ensureModalVideo();
      if (mv) { try { mv.pause(); } catch (_) {} }
    }
  }

  function recentlyRefreshed() {
    const ts = Number(sessionStorage.getItem("cf_refresh_ts") || "0");
    return (Date.now() - ts) < 120000; // 2 min
  }

  function requestCookieRefresh(preserveVisualPos) {
    if (!state.token) return false;

    if (recentlyRefreshed()) {
      showToast("Ne mogu učitati. Ako je link istekao, otvorite ga ponovo.");
      return false;
    }

    sessionStorage.setItem("cf_refresh_ts", String(Date.now()));
    if (typeof preserveVisualPos === "number" && preserveVisualPos >= 0) {
      sessionStorage.setItem("open_pos", String(preserveVisualPos));
    }
    showToast("Osvježavam pristup…", 1500);

    window.location.replace(`/open?t=${encodeURIComponent(state.token)}`);
    return true;
  }

  function markTileBroken(tile, message) {
    tile.classList.add("broken");
    let ov = tile.querySelector(".tileOverlay");
    if (!ov) {
      ov = document.createElement("div");
      ov.className = "tileOverlay";
      tile.appendChild(ov);
    }
    ov.textContent = message || "Ne mogu učitati. Dodirni za osvježenje.";
    ov.onclick = (e) => {
      e.preventDefault();
      requestCookieRefresh(-1);
    };
  }

  /* =========================
     Masonry calculation
  ========================= */
  function resizeMasonryItem(tile) {
    const grid = qs("grid");
    if (!grid) return;
    const styles = getComputedStyle(grid);
    const rowH = parseFloat(styles.getPropertyValue("grid-auto-rows")) || 8;
    const gap = parseFloat(styles.getPropertyValue("gap")) || 6;

    const rect = tile.getBoundingClientRect();
    const height = rect.height;
    const span = Math.ceil((height + gap) / (rowH + gap));
    tile.style.gridRowEnd = `span ${span}`;
  }

  function recalcMasonryAll() {
    const grid = qs("grid");
    if (!grid) return;
    const tiles = Array.from(grid.querySelectorAll(".tile"));
    tiles.forEach(resizeMasonryItem);
    computeVisualOrder();
  }

  function computeVisualOrder() {
    const grid = qs("grid");
    if (!grid) return;

    const tiles = Array.from(grid.querySelectorAll(".tile"));
    const items = tiles.map((tile) => {
      const idx = Number(tile.getAttribute("data-idx"));
      const r = tile.getBoundingClientRect();
      return { idx, top: r.top, left: r.left };
    });

    items.sort((a, b) => (a.top - b.top) || (a.left - b.left));
    state.visualOrder = items.map(x => x.idx);
  }

  // =========================
  // THUMB mapping helpers
  // Originals: gallery/<album>/file.ext
  // Thumbs:    thumbs/<album>/thumb-of-file.jpg|png
  // =========================
  const SOURCE_PREFIX = "gallery/";
  const THUMBS_PREFIX = "thumbs/";
  const THUMB_PREFIX = "thumb-of-";

  function stripExt(name) {
    return (name || "").replace(/\.[^.]+$/, "");
  }

  function toThumbKeyWithExt(originalKey, outExtWithDot) {
    if (!originalKey || !originalKey.startsWith(SOURCE_PREFIX)) return null;

    const rel = originalKey.slice(SOURCE_PREFIX.length); // "<album>/file.ext"
    const parts = rel.split("/").filter(Boolean);
    const base = parts.pop();
    const dir = parts.join("/");
    if (!base) return null;

    const baseNoExt = stripExt(base);
    const thumbBase = `${THUMB_PREFIX}${baseNoExt}${outExtWithDot}`;

    return dir
      ? `${THUMBS_PREFIX}${dir}/${thumbBase}`
      : `${THUMBS_PREFIX}${thumbBase}`;
  }

  function thumbUrlCandidates(originalKey) {
    if (isVideoKey(originalKey)) {
      const k = toThumbKeyWithExt(originalKey, ".jpg");
      return k ? [`/${encodeKeyForUrl(k)}`] : [];
    }

    if (!isImageKey(originalKey)) return [];

    const out = [];
    const jpg = toThumbKeyWithExt(originalKey, ".jpg");
    if (jpg) out.push(`/${encodeKeyForUrl(jpg)}`);

    const png = toThumbKeyWithExt(originalKey, ".png");
    if (png) out.push(`/${encodeKeyForUrl(png)}`);

    return out;
  }

  function originalUrl(key) {
    return `/${encodeKeyForUrl(key)}`;
  }

  function setSrcFallback(el, urls, onAllFail) {
    let i = 0;
    const tried = new Set();

    function next() {
      while (i < urls.length && tried.has(urls[i])) i++;
      if (i >= urls.length) { if (onAllFail) onAllFail(); return; }
      const u = urls[i++];
      tried.add(u);
      el.src = u;
    }

    el.onerror = () => next();
    next();
  }

  function openByVisualPos(pos) {
    if (!state.visualOrder.length) return;
    const n = state.visualOrder.length;
    const p = (pos % n + n) % n;
    state.currentPos = p;

    const fileIndex = state.visualOrder[p];
    const key = state.files[fileIndex];

    const origUrl = originalUrl(key);
    const thumbCandidates = thumbUrlCandidates(key);
    const thumbBg = thumbCandidates[0] || origUrl;

    const imgEl = modalImg();
    const videoEl = ensureModalVideo();
    const titleEl = modalTitle();
    const dlEl = modalDownload();
    const stage = modalStage();

    if (titleEl) titleEl.textContent = basename(key);

    if (dlEl) {
      dlEl.href = origUrl;
      dlEl.setAttribute("download", basename(key));
      dlEl.onclick = null;
    }

    // Use thumb as blurred background (faster)
    if (stage) stage.style.setProperty("--stage-bg", `url("${thumbBg}")`);

    const reqId = ++state.modalReqId;

    if (imgEl) { imgEl.style.display = "none"; imgEl.onerror = null; imgEl.removeAttribute("src"); }
    if (videoEl) {
      try { videoEl.pause(); } catch (_) {}
      videoEl.style.display = "none";
      videoEl.onerror = null;
      videoEl.removeAttribute("src");
      try { videoEl.load(); } catch (_) {}
    }

    if (isVideoKey(key)) {
      if (!videoEl) return;
      videoEl.style.display = "block";
      videoEl.src = origUrl;
      videoEl.onerror = () => {
        if (!isModalOpen()) return;
        if (reqId !== state.modalReqId) return;
        const did = requestCookieRefresh(p);
        if (!did) showToast("Ne mogu učitati video. Otvorite link ponovo.");
      };
      return;
    }

    if (imgEl) {
      imgEl.style.display = "block";

      // Modal shows THUMB (fast). Download button still points to ORIGINAL (origUrl).
      // If you want STRICT thumbs-only, remove ", origUrl" below.
      const modalCandidates = [...thumbCandidates, origUrl];

      let i = 0;
      const tried = new Set();

      function nextCandidate() {
        if (!isModalOpen()) return;
        if (reqId !== state.modalReqId) return;

        while (i < modalCandidates.length && tried.has(modalCandidates[i])) i++;
        if (i >= modalCandidates.length) {
          const did = requestCookieRefresh(p);
          if (!did) showToast("Ne mogu učitati thumbnail. Otvorite link ponovo.");
          return;
        }

        const u = modalCandidates[i++];
        tried.add(u);
        imgEl.src = u;
      }

      imgEl.onerror = () => nextCandidate();
      nextCandidate(); // start with thumb
    }
  }

  function openModalAtFileIndex(fileIdx) {
    if (!state.visualOrder.length) computeVisualOrder();
    const pos = state.visualOrder.indexOf(fileIdx);
    setModalOpen(true);
    openByVisualPos(pos >= 0 ? pos : 0);
  }

  function closeModal() { setModalOpen(false); }
  function next() { if (isModalOpen()) openByVisualPos(state.currentPos + 1); }
  function prev() { if (isModalOpen()) openByVisualPos(state.currentPos - 1); }

  function setupModalHandlers() {
    const m = modal();
    if (!m) return;

    const c = modalClose();
    if (c) c.addEventListener("click", closeModal);

    const p = prevBtn();
    if (p) p.addEventListener("click", (e) => { e.preventDefault(); prev(); });

    const n = nextBtn();
    if (n) n.addEventListener("click", (e) => { e.preventDefault(); next(); });

    m.addEventListener("click", (e) => {
      if (e.target === m) closeModal();
    });

    const imgEl = modalImg();
    if (imgEl) imgEl.addEventListener("click", closeModal);

    window.addEventListener("keydown", (e) => {
      if (!isModalOpen()) return;
      if (e.key === "Escape") closeModal();
      else if (e.key === "ArrowRight") next();
      else if (e.key === "ArrowLeft") prev();
    });

    const stage = modalStage();
    if (stage) {
      let startX = 0;
      let startY = 0;
      let active = false;

      stage.addEventListener("touchstart", (e) => {
        if (!isModalOpen()) return;
        const t = e.touches && e.touches[0];
        if (!t) return;
        active = true;
        startX = t.clientX;
        startY = t.clientY;
      }, { passive: true });

      stage.addEventListener("touchend", (e) => {
        if (!active || !isModalOpen()) return;
        active = false;

        const t = e.changedTouches && e.changedTouches[0];
        if (!t) return;

        const dx = t.clientX - startX;
        const dy = t.clientY - startY;

        if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) {
          if (dx < 0) next();
          else prev();
        }
      }, { passive: true });
    }
  }

  function renderMedia(files) {
    const grid = qs("grid");
    if (!grid) return;

    grid.innerHTML = "";

    const onlyMedia = (files || []).filter(k => isImageKey(k) || isVideoKey(k));
    if (onlyMedia.length === 0) {
      setStatus("No media found.");
      return;
    }

    setStatus(`Loaded ${onlyMedia.length} items`);

    files.forEach((key, idx) => {
      if (!isImageKey(key) && !isVideoKey(key)) return;

      const tile = document.createElement("div");
      tile.className = "tile";
      tile.setAttribute("data-idx", String(idx));

      const origUrl = originalUrl(key);
      const thumbCandidates = thumbUrlCandidates(key);

      // Grid always uses IMG:
      // - images: thumbs -> fallback to original
      // - videos: thumb placeholder only (no fallback to video)
      const img = document.createElement("img");
      img.loading = "lazy";
      img.decoding = "async";
      img.style.width = "100%";
      img.style.height = "auto";
      img.style.display = "block";
      img.style.cursor = "zoom-in";

      const urls = isVideoKey(key) ? thumbCandidates : [...thumbCandidates, origUrl];

      setSrcFallback(img, urls, () => {
        markTileBroken(tile, isVideoKey(key)
          ? "Ne mogu učitati video thumbnail. Dodirni za osvježenje."
          : "Ne mogu učitati. Dodirni za osvježenje."
        );
        requestAnimationFrame(() => resizeMasonryItem(tile));
      });

      img.onload = () => {
        requestAnimationFrame(() => {
          resizeMasonryItem(tile);
          computeVisualOrder();
        });
      };

      img.addEventListener("click", (e) => {
        e.preventDefault();
        computeVisualOrder();
        openModalAtFileIndex(idx);
      });

      tile.appendChild(img);

      if (isVideoKey(key)) {
        const badge = document.createElement("div");
        badge.textContent = "▶";
        badge.style.position = "absolute";
        badge.style.left = "10px";
        badge.style.bottom = "10px";
        badge.style.padding = "6px 8px";
        badge.style.fontWeight = "900";
        badge.style.background = "rgba(0,0,0,0.55)";
        badge.style.color = "#fff";
        tile.appendChild(badge);
      }

      const overlay = document.createElement("div");
      overlay.className = "tileOverlay";
      overlay.textContent = "Ne mogu učitati. Dodirni za osvježenje.";
      overlay.addEventListener("click", (e) => {
        e.preventDefault();
        requestCookieRefresh(-1);
      });
      tile.appendChild(overlay);

      grid.appendChild(tile);
    });

    requestAnimationFrame(() => {
      recalcMasonryAll();
      setTimeout(recalcMasonryAll, 250);
    });
  }

  async function clientSideZipDownload(files, folder) {
    if (!window.JSZip) { goError(500, "jszip_missing"); return; }

    const onlyMedia = (files || []).filter(k => isImageKey(k) || isVideoKey(k));
    if (onlyMedia.length === 0) { setStatus("Nothing to download."); return; }

    const zip = new JSZip();
    const zipFilename = safeZipName(folder);

    const concurrency = 5;
    let i = 0;
    let done = 0;

    setStatus(`Preparing ZIP… 0/${onlyMedia.length}`);

    async function worker() {
      while (true) {
        const idx = i++;
        if (idx >= onlyMedia.length) return;

        const key = onlyMedia[idx];
        const url = originalUrl(key);

        const r = await fetch(url, { cache: "no-store" });
        if (r.status === 401 || r.status === 403) {
          showToast("Pristup je istekao. Otvorite link ponovo.");
          return;
        }
        if (!r.ok) {
          done++;
          setStatus(`Preparing ZIP… ${done}/${onlyMedia.length} (skipped 1)`);
          continue;
        }

        const blob = await r.blob();
        zip.file(basename(key), blob);

        done++;
        setStatus(`Preparing ZIP… ${done}/${onlyMedia.length}`);
      }
    }

    const workers = Array.from({ length: Math.min(concurrency, onlyMedia.length) }, () => worker());
    await Promise.all(workers);

    setStatus("Building ZIP…");
    const outBlob = await zip.generateAsync({ type: "blob" });

    const a = document.createElement("a");
    const objUrl = URL.createObjectURL(outBlob);
    a.href = objUrl;
    a.download = zipFilename;
    document.body.appendChild(a);
    a.click();
    a.remove();

    setTimeout(() => URL.revokeObjectURL(objUrl), 30_000);
    setStatus(`Downloaded ${zipFilename}`);
  }

  function setupDownloadButton(options) {
    const btn = qs("dlFolder");
    if (!btn) return;

    const zipKey = options.zipKey;
    const files = options.files || [];
    const folder = options.folder || "";

    btn.style.display = "inline-block";

    const onlyMedia = files.filter(k => isImageKey(k) || isVideoKey(k));
    if (onlyMedia.length === 0) {
      btn.disabled = true;
      btn.title = "No images/videos to download";
      btn.onclick = null;
      return;
    }

    if (zipKey) {
      btn.disabled = false;
      btn.title = "Download server-generated ZIP";
      const url = `/${encodeKeyForUrl(zipKey)}`;
      btn.onclick = () => { window.location.assign(url); };
      return;
    }

    btn.disabled = false;
    btn.title = "ZIP is not pre-generated; downloading via browser ZIP (may be slower)";
    btn.onclick = () => clientSideZipDownload(files, folder).catch(() => goError(500, "zip_failed"));
  }

  // Probe ORIGINAL media access
  async function probeMediaAccess(files) {
    const first = (files || []).find(k => isImageKey(k) || isVideoKey(k));
    if (!first) return true;

    const url = originalUrl(first);
    try {
      const r = await fetch(url, { method: "HEAD", cache: "no-store" });
      if (r.status === 403 || r.status === 401) return false;
      return true;
    } catch (_) {
      return true;
    }
  }

  async function main() {
    setupModalHandlers();

    const rawFolder = getFolderFromQuery();
    const folder = normalizeFolder(rawFolder);
    const token = (getTokenFromQuery() || "").trim();

    if (!folder) { goError(400, "missing_folder"); return; }
    if (!token) { goError(403, "missing_token"); return; }

    state.folder = folder;
    state.token = token;

    setStatus("Loading…");

    const data = await loadList(folder, token);
    if (!data) return;

    const files = Array.isArray(data.files) ? data.files : [];
    const zipKey = data.zip || data.zipKey || data.zip_key || null;

    state.files = files;

    const ok = await probeMediaAccess(files);
    if (!ok) {
      const did = requestCookieRefresh(-1);
      if (did) return;
    }

    setupDownloadButton({ zipKey, files, folder });
    renderMedia(files);

    const savedPos = sessionStorage.getItem("open_pos");
    if (savedPos != null) {
      sessionStorage.removeItem("open_pos");
      const pos = Number(savedPos);
      if (Number.isFinite(pos) && pos >= 0) {
        setTimeout(() => {
          computeVisualOrder();
          setModalOpen(true);
          openByVisualPos(pos);
        }, 150);
      }
    }

    window.addEventListener("resize", () => {
      recalcMasonryAll();
      setTimeout(recalcMasonryAll, 200);
    });
  }

  window.addEventListener("load", () => {
    main().catch(() => goError(500, "client_error"));
  });
})();
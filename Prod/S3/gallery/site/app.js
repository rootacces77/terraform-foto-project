(function () {
  function qs(id) { return document.getElementById(id); }

  function goError(code, reason) {
    const u = `/site/error.html?code=${encodeURIComponent(String(code))}&reason=${encodeURIComponent(reason || "")}`;
    window.location.replace(u);
  }

  function getFolderFromQuery() {
    const url = new URL(window.location.href);
    return url.searchParams.get("folder") || "";
  }

  function normalizeFolder(folder) {
    let f = (folder || "").trim();
    f = f.replace(/^\/+/, "");   // no leading slash
    f = f.replace(/\/+$/, "");   // no trailing slash
    if (!f) return null;
    return f + "/"; // must end with /
  }

  function encodeKeyForUrl(key) {
    // Encode each path segment but keep slashes
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

  async function loadList(folder) {
    const resp = await fetch(`/list?folder=${encodeURIComponent(folder)}`, { cache: "no-store" });

    if (resp.status === 401 || resp.status === 403) {
      goError(403, "cookies_expired");
      return null;
    }
    if (resp.status === 404) {
      goError(404, "not_found");
      return null;
    }
    if (!resp.ok) {
      goError(500, "list_failed");
      return null;
    }

    return resp.json();
  }

  // ----------------------------
  // Lightbox (Modal) logic
  // ----------------------------
  const state = {
    files: [],
    currentIndex: -1,
    folder: ""
  };

  const modal = () => qs("modal");
  const modalImg = () => qs("modalImg");
  const modalTitle = () => qs("modalTitle");
  const modalDownload = () => qs("modalDownload");
  const modalClose = () => qs("modalClose");
  const prevBtn = () => qs("prevBtn");
  const nextBtn = () => qs("nextBtn");
  const modalStage = () => qs("modalStage");

  function isModalOpen() {
    const m = modal();
    return !!(m && m.classList.contains("open"));
  }

  function setModalOpen(open) {
    const m = modal();
    if (!m) return;

    if (open) {
      m.classList.add("open");
      // prevent background scrolling
      document.body.style.overflow = "hidden";
    } else {
      m.classList.remove("open");
      document.body.style.overflow = "";
    }
  }

  function clampIndex(i) {
    const n = state.files.length;
    if (n <= 0) return -1;
    // wrap around
    return (i % n + n) % n;
  }

  function showIndex(i) {
    const n = state.files.length;
    if (n <= 0) return;

    const idx = clampIndex(i);
    state.currentIndex = idx;

    const key = state.files[idx];
    const url = `/${encodeKeyForUrl(key)}`;

    const imgEl = modalImg();
    const titleEl = modalTitle();
    const dlEl = modalDownload();

    if (titleEl) titleEl.textContent = basename(key);
    if (dlEl) {
      dlEl.href = url;
      dlEl.setAttribute("download", basename(key));
    }

    if (imgEl) {
      // If cookies expire later, images start failing -> redirect
      imgEl.onerror = () => goError(403, "cookies_expired");

      // Set src last to avoid flashing old image
      imgEl.removeAttribute("src");
      imgEl.src = url;
    }
  }

  function openModalAt(i) {
    if (!state.files || state.files.length === 0) return;
    setModalOpen(true);
    showIndex(i);
  }

  function closeModal() {
    setModalOpen(false);
  }

  function next() {
    if (!isModalOpen()) return;
    showIndex(state.currentIndex + 1);
  }

  function prev() {
    if (!isModalOpen()) return;
    showIndex(state.currentIndex - 1);
  }

  function setupModalHandlers() {
    const m = modal();
    if (!m) return;

    // Buttons
    const c = modalClose();
    if (c) c.addEventListener("click", closeModal);

    const p = prevBtn();
    if (p) p.addEventListener("click", (e) => { e.preventDefault(); prev(); });

    const n = nextBtn();
    if (n) n.addEventListener("click", (e) => { e.preventDefault(); next(); });

    // Click backdrop to close (but not when clicking inside panel/img/buttons)
    m.addEventListener("click", (e) => {
      if (e.target === m) closeModal();
    });

    // Click image to close (nice UX)
    const imgEl = modalImg();
    if (imgEl) imgEl.addEventListener("click", closeModal);

    // Keyboard
    window.addEventListener("keydown", (e) => {
      if (!isModalOpen()) return;

      if (e.key === "Escape") closeModal();
      else if (e.key === "ArrowRight") next();
      else if (e.key === "ArrowLeft") prev();
    });

    // Basic swipe on touch devices
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

        // horizontal swipe threshold
        if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy)) {
          if (dx < 0) next();
          else prev();
        }
      }, { passive: true });
    }
  }

  // ----------------------------
  // Grid render + click to open
  // ----------------------------
  function renderImages(files) {
    const grid = qs("grid");
    if (!grid) return;

    grid.innerHTML = "";

    if (!files || files.length === 0) {
      setStatus("No images found.");
      return;
    }

    setStatus(`Loaded ${files.length} images`);

    files.forEach((key, idx) => {
      const tile = document.createElement("div");
      tile.className = "tile";

      const img = document.createElement("img");
      img.loading = "lazy";
      img.decoding = "async";
      img.referrerPolicy = "no-referrer";
      img.src = `/${encodeKeyForUrl(key)}`;

      // If cookies expire later, images start failing -> redirect to error page
      img.onerror = () => goError(403, "cookies_expired");

      // OPEN LIGHTBOX ON CLICK
      img.addEventListener("click", (e) => {
        e.preventDefault();
        openModalAt(idx);
      });

      // Also allow keyboard "Enter" if user tabs to tile
      tile.tabIndex = 0;
      tile.setAttribute("role", "button");
      tile.setAttribute("aria-label", `Open ${basename(key)}`);
      tile.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          openModalAt(idx);
        }
      });

      tile.appendChild(img);
      grid.appendChild(tile);
    });
  }

  // ----------------------------
  // Download ZIP logic (unchanged)
  // ----------------------------
  async function clientSideZipDownload(files, folder) {
    // Requires JSZip loaded in HTML
    if (!window.JSZip) {
      goError(500, "jszip_missing");
      return;
    }
    if (!files || files.length === 0) {
      setStatus("Nothing to download.");
      return;
    }

    const zip = new JSZip();
    const zipFilename = safeZipName(folder);

    // Small concurrency limiter to avoid blasting the browser/network
    const concurrency = 5;
    let i = 0;
    let done = 0;

    setStatus(`Preparing ZIP… 0/${files.length}`);

    async function worker() {
      while (true) {
        const idx = i++;
        if (idx >= files.length) return;

        const key = files[idx];
        const url = `/${encodeKeyForUrl(key)}`;

        const r = await fetch(url, { cache: "no-store" });
        if (r.status === 401 || r.status === 403) {
          goError(403, "cookies_expired");
          return;
        }
        if (!r.ok) {
          done++;
          setStatus(`Preparing ZIP… ${done}/${files.length} (skipped 1)`);
          continue;
        }

        const blob = await r.blob();
        zip.file(basename(key), blob);

        done++;
        setStatus(`Preparing ZIP… ${done}/${files.length}`);
      }
    }

    const workers = Array.from({ length: Math.min(concurrency, files.length) }, () => worker());
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

    // NEVER hide the button anymore
    btn.style.display = "inline-block";

    // If nothing to download, keep visible but disabled
    if (!files || files.length === 0) {
      btn.disabled = true;
      btn.title = "No images to download";
      btn.onclick = null;
      return;
    }

    // If server ZIP exists, prefer it
    if (zipKey) {
      btn.disabled = false;
      btn.title = "Download server-generated ZIP";

      const url = `/${encodeKeyForUrl(zipKey)}`;
      btn.onclick = () => window.open(url, "_blank", "noopener,noreferrer");
      return;
    }

    // Fallback: client-side ZIP using JSZip
    btn.disabled = false;
    btn.title = "ZIP is not pre-generated; downloading via browser ZIP (may be slower)";
    btn.onclick = () => clientSideZipDownload(files, folder).catch(() => goError(500, "zip_failed"));
  }

  function setupThemeToggle() {
    const btn = qs("themeToggle");
    if (!btn) return;

    btn.addEventListener("click", () => {
      const html = document.documentElement;
      const cur = html.getAttribute("data-theme") || "light";
      const next = cur === "dark" ? "light" : "dark";
      html.setAttribute("data-theme", next);
      btn.textContent = next === "dark" ? "Light mode" : "Dark mode";
    });
  }

  async function main() {
    setupThemeToggle();
    setupModalHandlers();

    const rawFolder = getFolderFromQuery();
    const folder = normalizeFolder(rawFolder);

    if (!folder) {
      goError(400, "missing_folder");
      return;
    }

    state.folder = folder;

    setStatus("Loading…");

    const data = await loadList(folder);
    if (!data) return;

    const files = Array.isArray(data.files) ? data.files : [];
    const zipKey = data.zip || data.zipKey || data.zip_key || null;

    state.files = files;

    setupDownloadButton({ zipKey, files, folder });
    renderImages(files);
  }

  window.addEventListener("load", () => {
    main().catch(() => goError(500, "client_error"));
  });
})();

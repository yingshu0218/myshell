const $ = (selector) => document.querySelector(selector);
const state = {
  csrf: "",
  username: "",
  vault: null,
  health: new Map(),
  terminals: new Map(),
  activeTerminal: null,
  statusTimer: null,
};

const terminalThemes = {
  midnight: { background: "#061017", foreground: "#edf3f6", cursor: "#edf3f6", selectionBackground: "#29485a", black: "#071017", red: "#ff6269", green: "#69d469", yellow: "#f2bd4a", blue: "#4db9ef", magenta: "#d29cf6", cyan: "#72d5f4", white: "#dce5e9" },
  paper: { background: "#ffffff", foreground: "#16222a", cursor: "#16222a", selectionBackground: "#b9ddec", black: "#16222a", red: "#c6353d", green: "#258a45", yellow: "#9b6713", blue: "#007db6", magenta: "#8a4da8", cyan: "#087f8d", white: "#e5eaed" },
  solarized: { background: "#002b36", foreground: "#eee8d5", cursor: "#eee8d5", selectionBackground: "#1c5965", black: "#073642", red: "#dc322f", green: "#859900", yellow: "#b58900", blue: "#268bd2", magenta: "#d33682", cyan: "#2aa198", white: "#eee8d5" },
  nord: { background: "#242933", foreground: "#eceff4", cursor: "#eceff4", selectionBackground: "#4c566a", black: "#2e3440", red: "#bf616a", green: "#a3be8c", yellow: "#ebcb8b", blue: "#81a1c1", magenta: "#b48ead", cyan: "#88c0d0", white: "#eceff4" },
  contrast: { background: "#000000", foreground: "#ffffff", cursor: "#ffffff", selectionBackground: "#006080", black: "#000000", red: "#ff5b5b", green: "#45ff61", yellow: "#ffdf3b", blue: "#00c8ff", magenta: "#ff7bff", cyan: "#00ffff", white: "#ffffff" },
};

async function api(path, options = {}) {
  const headers = new Headers(options.headers || {});
  if (options.body && typeof options.body !== "string") {
    headers.set("Content-Type", "application/json");
    options.body = JSON.stringify(options.body);
  }
  if (state.csrf && (options.method || "GET") !== "GET") {
    headers.set("X-CSRF-Token", state.csrf);
  }
  const response = await fetch(path, { ...options, headers });
  if (response.status === 204) return null;
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    if (response.status === 401 && !path.includes("/login")) showAuth(false);
    const error = new Error(payload.error?.message || `请求失败（${response.status}）`);
    error.code = payload.error?.code;
    error.payload = payload;
    throw error;
  }
  return payload;
}

async function bootstrap() {
  bindEvents();
  highlightPreview();
  try {
    const session = await api("/api/session");
    if (!session.initialized) {
      showAuth(true);
    } else if (!session.authenticated) {
      showAuth(false);
    } else {
      await enterApp(session);
    }
  } catch {
    showAuth(false);
    $("#auth-error").textContent = "无法连接 MyShell 服务。";
  }
}

function showAuth(setup) {
  $("#auth-view").hidden = false;
  $("#app-view").hidden = true;
  $("#auth-title").textContent = setup ? "初始化 MyShell" : "登录你的终端";
  $("#auth-copy").textContent = setup ? "创建这台 VPS 上唯一的管理员账号。" : "使用 VPS 上唯一的 MyShell 账号继续。";
  $("#auth-form button").textContent = setup ? "创建账号" : "登录";
  $("#auth-form").dataset.mode = setup ? "setup" : "login";
  $("#password").autocomplete = setup ? "new-password" : "current-password";
}

async function enterApp(session) {
  state.csrf = session.csrfToken;
  state.username = session.username;
  $("#account-name").textContent = session.username;
  state.vault = await api("/api/v1/vault");
  $("#auth-view").hidden = true;
  $("#app-view").hidden = false;
  applyPreferences();
  renderConnections();
  await refreshStatus();
  configureStatusRefresh();
}

function bindEvents() {
  $("#auth-form").addEventListener("submit", handleAuth);
  $("#local-shell").addEventListener("click", () => createTerminal("shell"));
  $("#new-shell").addEventListener("click", () => createTerminal("shell"));
  $("#empty-shell").addEventListener("click", () => createTerminal("shell"));
  $("#add-connection").addEventListener("click", () => openConnectionDialog());
  $("#connection-search").addEventListener("input", renderConnections);
  $("#connection-form").addEventListener("submit", saveConnection);
  document.querySelectorAll("[data-close-connection]").forEach((button) => {
    button.addEventListener("click", () => $("#connection-dialog").close());
  });
  $("#delete-connection").addEventListener("click", deleteConnection);
  $("#theme-button").addEventListener("click", toggleThemeMenu);
  document.addEventListener("click", (event) => {
    if (!event.target.closest("#theme-menu, #theme-button")) closeThemeMenu();
  });
  document.querySelectorAll("[data-theme-choice]").forEach((button) => {
    button.addEventListener("click", () => setTheme(button.dataset.themeChoice, true));
  });
  $("#toggle-preview").addEventListener("click", () => setPreview(false, true));
  $("#open-settings").addEventListener("click", openSettings);
  $("#settings-theme").addEventListener("change", (event) => setTheme(event.target.value, false));
  $("#settings-preview").addEventListener("change", (event) => setPreview(event.target.checked, false));
  $("#save-settings").addEventListener("click", saveSettings);
  $("#run-backup").addEventListener("click", runBackup);
  $("#refresh-backups").addEventListener("click", refreshBackups);
  $("#logout-button").addEventListener("click", logout);
  $("#check-status").addEventListener("click", checkAll);
  $("#mobile-menu").addEventListener("click", () => $(".sidebar").classList.add("open"));
  $("#mobile-close").addEventListener("click", () => $(".sidebar").classList.remove("open"));
  window.addEventListener("resize", debounce(() => {
    const current = state.terminals.get(state.activeTerminal);
    if (current) fitTerminal(current);
  }, 120));
}

async function handleAuth(event) {
  event.preventDefault();
  const submit = event.submitter;
  submit.disabled = true;
  $("#auth-error").textContent = "";
  try {
    const mode = event.currentTarget.dataset.mode;
    const payload = await api(`/api/${mode}`, {
      method: "POST",
      body: { username: $("#username").value, password: $("#password").value },
    });
    const session = await api("/api/session");
    session.csrfToken ||= payload.csrfToken;
    $("#password").value = "";
    await enterApp(session);
  } catch (error) {
    $("#auth-error").textContent = error.code === "rate_limited" ? "失败次数过多，请稍后再试。" : error.message;
  } finally {
    submit.disabled = false;
  }
}

function renderConnections() {
  const list = $("#connection-list");
  if (!state.vault) return;
  const query = $("#connection-search").value.trim().toLowerCase();
  const connections = state.vault.connections.filter((item) => !item.deleted && [item.name, item.host, item.group].join(" ").toLowerCase().includes(query));
  const groups = new Map();
  for (const connection of connections) {
    const group = connection.group || "未分组";
    if (!groups.has(group)) groups.set(group, []);
    groups.get(group).push(connection);
  }
  list.replaceChildren();
  for (const [group, items] of groups) {
    const section = document.createElement("section");
    section.className = "connection-group";
    const title = document.createElement("h3");
    title.textContent = group;
    section.append(title);
    for (const connection of items) {
      const row = document.createElement("button");
      row.className = "connection-row";
      row.type = "button";
      row.dataset.id = connection.id;
      const health = state.health.get(connection.id);
      const dotClass = health ? (health.online ? "online" : "offline") : "";
      row.innerHTML = `<span class="status-dot ${dotClass}"></span><span class="name"></span><span class="connection-edit" role="button" tabindex="0" aria-label="编辑连接">•••</span>`;
      row.querySelector(".name").textContent = connection.name;
      row.title = `${connection.credential?.username ? `${connection.credential.username}@` : ""}${connection.host}:${connection.port}`;
      row.addEventListener("click", (event) => {
        if (event.target.closest(".status-dot")) {
          event.stopPropagation();
          checkOne(connection.id);
        } else if (event.target.closest(".connection-edit")) {
          openConnectionDialog(connection);
        } else {
          createTerminal("ssh", connection.id);
          $(".sidebar").classList.remove("open");
        }
      });
      row.querySelector(".connection-edit").addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") openConnectionDialog(connection);
      });
      section.append(row);
    }
    list.append(section);
  }
  if (!connections.length) {
    const empty = document.createElement("p");
    empty.className = "form-hint";
    empty.style.padding = "8px 12px";
    empty.textContent = query ? "没有匹配的连接。" : "还没有 SSH 连接。";
    list.append(empty);
  }
}

function openConnectionDialog(connection = null) {
  $("#connection-dialog-title").textContent = connection ? "编辑 SSH 连接" : "新增 SSH 连接";
  $("#connection-id").value = connection?.id || "";
  $("#connection-name").value = connection?.name || "";
  $("#connection-group").value = connection?.group || "";
  $("#connection-host").value = connection?.host || "";
  $("#connection-port").value = connection?.port || 22;
  $("#connection-username").value = connection?.credential?.username || "";
  $("#connection-password").value = "";
  $("#connection-period").value = connection?.healthPeriod || 0;
  $("#connection-error").textContent = "";
  $("#delete-connection").hidden = !connection;
  $("#connection-dialog").showModal();
  $("#connection-name").focus();
}

async function saveConnection(event) {
  event.preventDefault();
  const id = $("#connection-id").value || crypto.randomUUID();
  const old = state.vault.connections.find((item) => item.id === id);
  const connection = {
    id,
    name: $("#connection-name").value.trim(),
    group: $("#connection-group").value.trim(),
    host: $("#connection-host").value.trim(),
    port: Number($("#connection-port").value),
    credential: {
      username: $("#connection-username").value.trim(),
      password: $("#connection-password").value || old?.credential?.password || "",
    },
    healthPeriod: Number($("#connection-period").value),
    updatedAt: new Date().toISOString(),
  };
  const connections = old ? state.vault.connections.map((item) => item.id === id ? connection : item) : [...state.vault.connections, connection];
  try {
    await updateVault({ ...state.vault, connections });
    $("#connection-dialog").close();
    renderConnections();
    toast("连接已安全保存。");
  } catch (error) {
    $("#connection-error").textContent = error.message;
  }
}

async function deleteConnection() {
  const id = $("#connection-id").value;
  const current = state.vault.connections.find((item) => item.id === id);
  if (!current || !confirm(`删除连接“${current.name}”？`)) return;
  const connections = state.vault.connections.map((item) => item.id === id ? { ...item, deleted: true, updatedAt: new Date().toISOString() } : item);
  try {
    await updateVault({ ...state.vault, connections });
    $("#connection-dialog").close();
    renderConnections();
    toast("连接已删除。");
  } catch (error) {
    $("#connection-error").textContent = error.message;
  }
}

async function updateVault(data) {
  $("#sync-status").textContent = "同步中…";
  try {
    state.vault = await api("/api/v1/vault", {
      method: "PUT",
      body: { expectedVersion: state.vault.version, data },
    });
  } catch (error) {
    if (error.code === "version_conflict") {
      state.vault = error.payload.current;
      renderConnections();
      throw new Error("数据已在其他页面修改，请检查后重试。");
    }
    throw error;
  } finally {
    $("#sync-status").textContent = "已同步";
  }
  configureStatusRefresh();
}

async function createTerminal(kind, connectionId = "") {
  try {
    if (kind === "ssh") {
      const hostKey = await api(`/api/v1/connections/${encodeURIComponent(connectionId)}/host-key`);
      if (!hostKey.trusted) {
        const accepted = confirm(`首次连接需要确认服务器指纹：\n\n${hostKey.algorithm || "SSH"}\n${hostKey.fingerprint}\n\n请与服务器管理员提供的指纹核对。确认信任吗？`);
        if (!accepted) return;
        await api(`/api/v1/connections/${encodeURIComponent(connectionId)}/host-key/trust`, {
          method: "POST", body: { fingerprint: hostKey.fingerprint },
        });
      }
    }
    const session = await api("/api/v1/terminals", { method: "POST", body: { kind, connectionId } });
    mountTerminal(session);
  } catch (error) {
    toast(error.message, true);
  }
}

function mountTerminal(session) {
  $("#empty-terminal").hidden = true;
  const host = document.createElement("div");
  host.className = "terminal-host";
  host.dataset.terminalId = session.id;
  host.hidden = true;
  $("#terminal-stack").append(host);

  const terminal = new Terminal({
    allowProposedApi: false,
    cursorBlink: true,
    convertEol: false,
    fontFamily: '"SFMono-Regular", Consolas, "Liberation Mono", monospace',
    fontSize: 14,
    lineHeight: 1.28,
    scrollback: 10000,
    theme: terminalThemes[state.vault.preferences.theme] || terminalThemes.midnight,
  });
  const fit = new FitAddon.FitAddon();
  terminal.loadAddon(fit);
  terminal.open(host);

  const protocol = location.protocol === "https:" ? "wss:" : "ws:";
  const socket = new WebSocket(`${protocol}//${location.host}/api/v1/terminals/${session.id}/stream`);
  socket.binaryType = "arraybuffer";
  const record = { session, terminal, fit, socket, host, resizeTimer: null };
  state.terminals.set(session.id, record);

  socket.addEventListener("open", () => {
    terminal.focus();
    fitTerminal(record);
    toast(`${session.label} 已连接。`);
  });
  socket.addEventListener("message", (event) => terminal.write(new Uint8Array(event.data)));
  socket.addEventListener("close", () => {
    record.closed = true;
    terminal.write("\r\n\x1b[33m[连接已关闭]\x1b[0m\r\n");
    renderTabs();
  });
  socket.addEventListener("error", () => toast(`${session.label} 连接中断。`, true));
  terminal.onData((data) => {
    if (socket.readyState === WebSocket.OPEN) socket.send(new TextEncoder().encode(data));
  });
  terminal.onResize(({ rows, cols }) => scheduleResize(record, rows, cols));
  activateTerminal(session.id);
  renderTabs();
}

function renderTabs() {
  const tabs = $("#terminal-tabs");
  tabs.replaceChildren();
  for (const [id, record] of state.terminals) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `terminal-tab${state.activeTerminal === id ? " active" : ""}`;
    button.role = "tab";
    button.ariaSelected = String(state.activeTerminal === id);
    const icon = record.session.kind === "ssh" ? "⌁" : ">_";
    button.innerHTML = `<span>${icon}</span><span></span><span class="close-tab" role="button" aria-label="关闭终端">×</span>`;
    button.querySelector("span:nth-child(2)").textContent = record.session.label;
    button.addEventListener("click", (event) => {
      if (event.target.closest(".close-tab")) closeTerminal(id);
      else activateTerminal(id);
    });
    tabs.append(button);
  }
  const active = [...state.terminals.values()].filter((record) => !record.closed).length;
  $("#session-count").textContent = `${active} 个活动终端`;
}

function activateTerminal(id) {
  state.activeTerminal = id;
  for (const [terminalId, record] of state.terminals) record.host.hidden = terminalId !== id;
  const record = state.terminals.get(id);
  if (record) requestAnimationFrame(() => {
    fitTerminal(record);
    record.terminal.focus();
  });
  renderTabs();
}

async function closeTerminal(id) {
  const record = state.terminals.get(id);
  if (!record) return;
  try {
    await api(`/api/v1/terminals/${id}`, { method: "DELETE" });
  } catch {
    // The process may already have exited.
  }
  record.socket.close();
  record.terminal.dispose();
  record.host.remove();
  state.terminals.delete(id);
  if (state.activeTerminal === id) {
    state.activeTerminal = [...state.terminals.keys()].at(-1) || null;
  }
  if (state.activeTerminal) activateTerminal(state.activeTerminal);
  $("#empty-terminal").hidden = state.terminals.size > 0;
  renderTabs();
}

function fitTerminal(record) {
  if (record.host.hidden) return;
  try { record.fit.fit(); } catch { /* hidden/layout transition */ }
}

function scheduleResize(record, rows, cols) {
  clearTimeout(record.resizeTimer);
  record.resizeTimer = setTimeout(() => {
    api(`/api/v1/terminals/${record.session.id}/resize`, { method: "POST", body: { rows, cols } }).catch(() => {});
  }, 100);
}

function applyPreferences() {
  const preferences = state.vault.preferences || { theme: "midnight", codePreview: true };
  setTheme(preferences.theme || "midnight", false);
  setPreview(preferences.codePreview !== false, false);
  $("#settings-theme").value = preferences.theme || "midnight";
  $("#settings-preview").checked = preferences.codePreview !== false;
}

function setTheme(theme, persist) {
  if (!terminalThemes[theme]) theme = "midnight";
  document.body.dataset.theme = theme;
  $("#settings-theme").value = theme;
  document.querySelectorAll("[data-theme-choice]").forEach((button) => button.classList.toggle("selected", button.dataset.themeChoice === theme));
  for (const record of state.terminals.values()) record.terminal.options.theme = terminalThemes[theme];
  closeThemeMenu();
  if (persist && state.vault) {
    updateVault({ ...state.vault, preferences: { ...state.vault.preferences, theme } }).catch((error) => toast(error.message, true));
  }
}

function setPreview(visible, persist) {
  $("#code-preview").hidden = !visible;
  $(".content-grid").classList.toggle("preview-hidden", !visible);
  $("#settings-preview").checked = visible;
  const current = state.terminals.get(state.activeTerminal);
  if (current) requestAnimationFrame(() => fitTerminal(current));
  if (persist && state.vault) {
    updateVault({ ...state.vault, preferences: { ...state.vault.preferences, codePreview: visible } }).catch((error) => toast(error.message, true));
  }
}

function toggleThemeMenu() {
  const menu = $("#theme-menu");
  menu.hidden = !menu.hidden;
  $("#theme-button").ariaExpanded = String(!menu.hidden);
}

function closeThemeMenu() {
  $("#theme-menu").hidden = true;
  $("#theme-button").ariaExpanded = "false";
}

function openSettings() {
  const backup = state.vault.backup || {};
  $("#backup-enabled").checked = Boolean(backup.enabled);
  $("#backup-provider").value = backup.provider || "github";
  $("#backup-api").value = backup.apiBase || "";
  $("#backup-owner").value = backup.owner || "";
  $("#backup-repo").value = backup.repo || "";
  $("#backup-branch").value = backup.branch || "main";
  $("#backup-schedule").value = backup.schedule || "";
  $("#settings-message").textContent = "";
  $("#settings-dialog").showModal();
  if (backup.enabled) refreshBackups();
}

async function saveSettings() {
  const button = $("#save-settings");
  button.disabled = true;
  const preferences = {
    theme: $("#settings-theme").value,
    codePreview: $("#settings-preview").checked,
  };
  const backup = {
    enabled: $("#backup-enabled").checked,
    provider: $("#backup-provider").value,
    apiBase: $("#backup-api").value.trim(),
    owner: $("#backup-owner").value.trim(),
    repo: $("#backup-repo").value.trim(),
    branch: $("#backup-branch").value.trim() || "main",
    schedule: $("#backup-schedule").value,
  };
  try {
    await updateVault({ ...state.vault, preferences, backup });
    applyPreferences();
    $("#settings-message").textContent = "设置已保存并同步。";
  } catch (error) {
    $("#settings-message").textContent = error.message;
  } finally {
    button.disabled = false;
  }
}

async function runBackup() {
  const button = $("#run-backup");
  button.disabled = true;
  $("#settings-message").textContent = "正在创建加密备份…";
  try {
    const item = await api("/api/v1/backups", { method: "POST" });
    $("#settings-message").textContent = `备份完成：${item.name}`;
    await refreshBackups();
  } catch (error) {
    $("#settings-message").textContent = error.message;
  } finally {
    button.disabled = false;
  }
}

async function refreshBackups() {
  const list = $("#backup-list");
  list.innerHTML = '<p class="form-hint">正在读取备份…</p>';
  try {
    const items = await api("/api/v1/backups");
    list.replaceChildren();
    if (!items.length) {
      list.innerHTML = '<p class="form-hint">还没有可恢复的备份。</p>';
      return;
    }
    for (const item of [...items].reverse()) {
      const row = document.createElement("div");
      row.className = "backup-row";
      const name = document.createElement("span");
      name.textContent = item.name;
      name.title = item.path;
      const restore = document.createElement("button");
      restore.type = "button";
      restore.textContent = "恢复";
      restore.addEventListener("click", () => restoreBackup(item));
      row.append(name, restore);
      list.append(row);
    }
  } catch (error) {
    list.innerHTML = "";
    const message = document.createElement("p");
    message.className = "form-error";
    message.textContent = error.message;
    list.append(message);
  }
}

async function restoreBackup(item) {
  try {
    const preview = await api("/api/v1/backups/preview", { method: "POST", body: { path: item.path } });
    const names = preview.connectionNames?.length ? `\n连接：${preview.connectionNames.join("、")}` : "";
    const confirmation = prompt(`备份“${item.name}”完整性验证通过。\n版本：${preview.version}\n连接数量：${preview.connectionCount}\n更新时间：${preview.updatedAt}${names}\n\n恢复将替换当前保险库，请输入 RESTORE 确认：`);
    if (confirmation !== "RESTORE") return;
    state.vault = await api("/api/v1/backups/restore", {
      method: "POST",
      body: { path: item.path, expectedVersion: state.vault.version, confirm: confirmation },
    });
    applyPreferences();
    renderConnections();
    $("#settings-message").textContent = `已从 ${item.name} 恢复，并创建了新的本地版本。`;
  } catch (error) {
    $("#settings-message").textContent = error.message;
  }
}

async function refreshStatus() {
  const started = performance.now();
  try {
    const status = await api("/api/v1/status");
    $("#latency-status").textContent = `${Math.max(1, Math.round(performance.now() - started))} ms`;
    for (const result of status.targets || []) {
      const previous = state.health.get(result.id);
      state.health.set(result.id, result);
      if (previous && previous.online !== result.online) {
        const connection = state.vault?.connections.find((item) => item.id === result.id);
        toast(`${connection?.name || result.id} 已${result.online ? "恢复在线" : "离线"}。`, !result.online);
      }
    }
    renderConnections();
  } catch {
    $("#check-status").innerHTML = '<span class="status-dot offline"></span>中转服务异常';
  }
}

function configureStatusRefresh() {
  clearInterval(state.statusTimer);
  state.statusTimer = null;
  if (!state.vault) return;
  const periods = state.vault.connections.filter((item) => !item.deleted && item.healthPeriod > 0).map((item) => item.healthPeriod);
  if (!periods.length) return;
  const milliseconds = Math.min(...periods) * 60_000;
  state.statusTimer = setInterval(() => {
    if (document.visibilityState === "visible") refreshStatus();
  }, milliseconds);
}

async function checkAll() {
  const button = $("#check-status");
  button.disabled = true;
  button.innerHTML = '<span class="status-dot checking"></span>正在检查';
  try {
    const results = await api("/api/v1/status/check", { method: "POST", body: {} });
    for (const result of results) state.health.set(result.id, result);
    button.innerHTML = '<span class="status-dot online"></span>中转服务正常';
    $("#latency-status").textContent = results.length ? `已检查 ${results.length} 台` : "没有服务器";
    renderConnections();
  } catch (error) {
    button.innerHTML = '<span class="status-dot offline"></span>检查失败';
    toast(error.message, true);
  } finally {
    button.disabled = false;
  }
}

async function checkOne(connectionId) {
  const dot = document.querySelector(`.connection-row[data-id="${CSS.escape(connectionId)}"] .status-dot`);
  dot?.classList.add("checking");
  try {
    const results = await api("/api/v1/status/check", { method: "POST", body: { connectionId } });
    for (const result of results) state.health.set(result.id, result);
    renderConnections();
  } catch (error) {
    toast(error.message, true);
  }
}

async function logout() {
  try { await api("/api/logout", { method: "POST" }); } catch { /* local reset */ }
  for (const id of [...state.terminals.keys()]) await closeTerminal(id);
  state.csrf = "";
  state.vault = null;
  clearInterval(state.statusTimer);
  state.statusTimer = null;
  $("#settings-dialog").close();
  showAuth(false);
}

function highlightPreview() {
  if (globalThis.Prism) Prism.highlightElement($("#preview-code"));
}

function toast(message, error = false) {
  const element = document.createElement("div");
  element.className = `toast${error ? " error" : ""}`;
  element.textContent = message;
  $("#toast-region").append(element);
  setTimeout(() => element.remove(), 4200);
}

function debounce(callback, delay) {
  let timer;
  return (...arguments_) => {
    clearTimeout(timer);
    timer = setTimeout(() => callback(...arguments_), delay);
  };
}

bootstrap();

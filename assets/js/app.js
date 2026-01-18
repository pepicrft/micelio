// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import { hooks as colocatedHooks } from "phoenix-colocated/micelio";
import topbar from "../vendor/topbar";
import "../css/app.css";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { ...colocatedHooks },
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// Project handle auto-generation
function slugify(str) {
  return str
    .toLowerCase()
    .trim()
    .replace(/[^\w\s-]/g, '') // Remove special characters
    .replace(/\s+/g, '-')     // Replace spaces with hyphens
    .replace(/-+/g, '-');     // Replace multiple hyphens with single hyphen
}

function setupProjectHandleGeneration() {
  const nameInput = document.getElementById('project_name');
  const handleInput = document.getElementById('project_handle');
  
  if (nameInput && handleInput) {
    let handleModified = false;
    
    // Check if handle was manually modified
    handleInput.addEventListener('input', () => {
      handleModified = true;
    });
    
    // Auto-generate handle from name
    nameInput.addEventListener('input', (e) => {
      if (!handleModified) {
        handleInput.value = slugify(e.target.value);
      }
    });
  }
}

// Setup project handle generation when DOM is ready
document.addEventListener('DOMContentLoaded', setupProjectHandleGeneration);

function base64UrlEncode(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.length; i += 1) {
    binary += String.fromCharCode(bytes[i]);
  }

  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded =
    normalized.length % 4 === 0
      ? normalized
      : normalized + "=".repeat(4 - (normalized.length % 4));
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function csrfTokenHeader() {
  return document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");
}

function setStatus(target, message, isError = false) {
  if (!target) return;
  target.textContent = message;
  target.hidden = false;
  target.dataset.state = isError ? "error" : "ok";
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  const data = await response.json();
  return { response, data };
}

function supportsPasskeys() {
  return (
    window.PublicKeyCredential &&
    typeof window.PublicKeyCredential === "function" &&
    navigator.credentials
  );
}

function setupPasskeyLogin() {
  const button = document.getElementById("auth-passkey-button");
  const status = document.getElementById("auth-passkey-status");
  if (!button) return;

  if (!supportsPasskeys()) {
    button.setAttribute("hidden", "");
    return;
  }

  button.addEventListener("click", async () => {
    button.disabled = true;
    setStatus(status, "Waiting for your passkey...");

    try {
      const { response, data } = await fetchJson("/auth/passkey/options", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": csrfTokenHeader(),
        },
        body: "{}",
      });

      if (!response.ok) {
        throw new Error(data.error || "Unable to start passkey login.");
      }

      const options = data;
      options.challenge = base64UrlDecode(options.challenge);
      if (options.allowCredentials) {
        options.allowCredentials = options.allowCredentials.map((cred) => ({
          ...cred,
          id: base64UrlDecode(cred.id),
        }));
      }

      const credential = await navigator.credentials.get({
        publicKey: options,
      });

      const payload = {
        id: credential.id,
        rawId: base64UrlEncode(credential.rawId),
        type: credential.type,
        response: {
          clientDataJSON: base64UrlEncode(credential.response.clientDataJSON),
          authenticatorData: base64UrlEncode(
            credential.response.authenticatorData,
          ),
          signature: base64UrlEncode(credential.response.signature),
          userHandle: credential.response.userHandle
            ? base64UrlEncode(credential.response.userHandle)
            : null,
        },
      };

      const verify = await fetchJson("/auth/passkey/authenticate", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": csrfTokenHeader(),
        },
        body: JSON.stringify(payload),
      });

      if (!verify.response.ok) {
        throw new Error(verify.data.error || "Passkey login failed.");
      }

      window.location = verify.data.redirect_to || "/";
    } catch (error) {
      setStatus(status, error.message || "Passkey login failed.", true);
      button.disabled = false;
    }
  });
}

function setupPasskeyRegistration() {
  const button = document.getElementById("account-passkey-add");
  const status = document.getElementById("account-passkey-status");
  if (!button) return;

  if (!supportsPasskeys()) {
    button.setAttribute("hidden", "");
    return;
  }

  button.addEventListener("click", async () => {
    button.disabled = true;
    setStatus(status, "Registering your passkey...");

    try {
      const { response, data } = await fetchJson("/account/passkeys/options", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": csrfTokenHeader(),
        },
        body: "{}",
      });

      if (!response.ok) {
        throw new Error(data.error || "Unable to start passkey registration.");
      }

      const options = data;
      options.challenge = base64UrlDecode(options.challenge);
      options.user.id = base64UrlDecode(options.user.id);

      const credential = await navigator.credentials.create({
        publicKey: options,
      });

      const payload = {
        id: credential.id,
        rawId: base64UrlEncode(credential.rawId),
        type: credential.type,
        response: {
          attestationObject: base64UrlEncode(
            credential.response.attestationObject,
          ),
          clientDataJSON: base64UrlEncode(credential.response.clientDataJSON),
        },
      };

      const register = await fetchJson("/account/passkeys", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-csrf-token": csrfTokenHeader(),
        },
        body: JSON.stringify(payload),
      });

      if (!register.response.ok) {
        throw new Error(register.data.error || "Passkey registration failed.");
      }

      window.location.reload();
    } catch (error) {
      setStatus(status, error.message || "Passkey registration failed.", true);
      button.disabled = false;
    }
  });
}

function setupPasskeyRemoval() {
  const buttons = document.querySelectorAll("[data-passkey-id]");
  if (buttons.length === 0) return;

  buttons.forEach((button) => {
    button.addEventListener("click", async () => {
      const passkeyId = button.getAttribute("data-passkey-id");
      if (!passkeyId) return;
      button.disabled = true;

      try {
        const { response, data } = await fetchJson(`/account/passkeys/${passkeyId}`, {
          method: "DELETE",
          headers: {
            "content-type": "application/json",
            "x-csrf-token": csrfTokenHeader(),
          },
        });

        if (!response.ok) {
          throw new Error(data.error || "Unable to remove passkey.");
        }

        const row = document.getElementById(`passkey-${passkeyId}`);
        if (row) {
          row.remove();
        }
      } catch (_error) {
        button.disabled = false;
      }
    });
  });
}

function setupPasskeys() {
  setupPasskeyLogin();
  setupPasskeyRegistration();
  setupPasskeyRemoval();
}

function getPreferredTheme() {
  try {
    const stored = localStorage.getItem("micelio:theme");
    if (stored === "light" || stored === "dark") return stored;
  } catch (_e) {}

  return "system";
}

function getEffectiveTheme() {
  const explicit = document.documentElement.getAttribute("data-theme");
  if (explicit === "light" || explicit === "dark") return explicit;

  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function applyThemePreference(preference) {
  if (preference === "light" || preference === "dark") {
    document.documentElement.setAttribute("data-theme", preference);
  } else {
    document.documentElement.removeAttribute("data-theme");
  }

  const toggle = document.getElementById("theme-toggle");
  if (toggle) {
    const effective = getEffectiveTheme();
    toggle.textContent = effective === "dark" ? "light" : "dark";
    toggle.setAttribute(
      "aria-label",
      effective === "dark" ? "Switch to light mode" : "Switch to dark mode",
    );
  }
}

function persistThemePreference(preference) {
  try {
    if (preference === "light" || preference === "dark") {
      localStorage.setItem("micelio:theme", preference);
    } else {
      localStorage.removeItem("micelio:theme");
    }
  } catch (_e) {}
}

function initTheme() {
  const preference = getPreferredTheme();
  applyThemePreference(preference);

  window
    .matchMedia("(prefers-color-scheme: dark)")
    .addEventListener("change", () => {
      if (getPreferredTheme() === "system") applyThemePreference("system");
    });
}

function setupThemeToggle() {
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;
    if (target.id !== "theme-toggle") return;

    if (event.altKey || event.metaKey) {
      persistThemePreference("system");
      applyThemePreference("system");
      return;
    }

    const next = getEffectiveTheme() === "dark" ? "light" : "dark";
    persistThemePreference(next);
    applyThemePreference(next);
  });

  window.addEventListener("phx:page-loading-stop", () => {
    applyThemePreference(getPreferredTheme());
  });
}

function setupFlashDismiss() {
  document.addEventListener("click", (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const dismissButton = target.closest("button[data-flash-dismiss]");
    if (!(dismissButton instanceof HTMLButtonElement)) return;

    const targetId = dismissButton.getAttribute("data-flash-target");
    const flashBar = targetId
      ? document.getElementById(targetId)
      : dismissButton.closest(".flash-bar");

    if (flashBar) {
      flashBar.setAttribute("hidden", "");
    }
  });
}

initTheme();
setupThemeToggle();
setupFlashDismiss();
setupPasskeys();
window.addEventListener("phx:page-loading-stop", setupPasskeys);

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (_e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}

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

// Feature modules
import { setupPasskeys } from "./auth/passkeys";
import { initTheme, setupThemeToggle } from "./ui/theme";
import { setupFlashDismiss } from "./ui/flash";
import { setupDropdown } from "./ui/dropdown";
import { setupProjectHandleGeneration } from "./forms/project-handle";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");
const MAX_SESSION_EVENTS = 200;

function capitalize(text) {
  if (!text || typeof text !== "string") return "";
  return text.charAt(0).toUpperCase() + text.slice(1);
}

function truncateText(text, maxLength = 140) {
  if (!text || typeof text !== "string") return "";
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength)}...`;
}

function formatTimestamp(value) {
  if (!value || typeof value !== "string") return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString();
}

function formatSummary(event) {
  if (!event || typeof event !== "object") return "";
  const payload = event.payload || {};

  switch (event.type) {
    case "status": {
      const parts = [];
      if (payload.state) parts.push(payload.state);
      if (payload.message) parts.push(payload.message);
      if (payload.percent != null) parts.push(`${payload.percent}%`);
      return parts.join(" - ");
    }
    case "progress": {
      const parts = [];
      if (payload.percent != null) {
        parts.push(`${payload.percent}%`);
      } else if (payload.current != null && payload.total != null) {
        parts.push(
          `${payload.current}/${payload.total} ${payload.unit || ""}`.trim()
        );
      }
      if (payload.message) parts.push(payload.message);
      return parts.join(" - ");
    }
    case "output":
      return truncateText(payload.text || "");
    case "error":
      return payload.message || "";
    case "artifact":
      return payload.name || payload.uri || "";
    default:
      return "";
  }
}

function progressPercent(payload) {
  if (!payload || typeof payload !== "object") return null;
  let percent = null;
  if (typeof payload.percent === "number") {
    percent = payload.percent;
  } else if (
    typeof payload.current === "number" &&
    typeof payload.total === "number" &&
    payload.total > 0
  ) {
    percent = (payload.current / payload.total) * 100;
  }

  if (typeof percent === "number" && Number.isFinite(percent)) {
    return Math.max(0, Math.min(100, percent));
  }

  return null;
}

function formatPercentValue(value) {
  if (typeof value !== "number" || !Number.isFinite(value)) return "";
  return Number.isInteger(value) ? `${value}%` : `${value.toFixed(1)}%`;
}

function outputOpen(text) {
  if (!text || typeof text !== "string") return false;
  return text.length <= 240;
}

function isImageArtifact(payload) {
  if (!payload || typeof payload !== "object") return false;
  const kind = payload.kind;
  const contentType = payload.content_type;
  const uri = payload.uri || "";

  if (kind === "image") return true;
  if (contentType && contentType.startsWith("image/")) return true;

  return [".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg"].some((ext) =>
    uri.toLowerCase().endsWith(ext)
  );
}

function artifactLabel(payload) {
  if (!payload || typeof payload !== "object") return "Artifact";
  return payload.name || payload.uri || "Artifact";
}

function artifactDetail(payload) {
  if (!payload || typeof payload !== "object") return "";
  const parts = [];
  if (payload.kind) parts.push(payload.kind);
  if (typeof payload.size_bytes === "number") {
    const size = formatFileSize(payload.size_bytes);
    if (size) parts.push(size);
  }
  return parts.join(" - ");
}

function formatFileSize(bytes) {
  if (typeof bytes !== "number" || !Number.isFinite(bytes)) return "";
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`;
}

function formatSourceLabel(source) {
  if (!source || typeof source !== "object") return "System";
  if (source.label) return source.label;
  if (source.kind) return capitalize(source.kind);
  return "System";
}

function eventTypeIcon(type) {
  switch (type) {
    case "status":
      return "S";
    case "progress":
      return "P";
    case "output":
      return "O";
    case "error":
      return "E";
    case "artifact":
      return "A";
    default:
      return "?";
  }
}

function createElement(tag, className, text) {
  const el = document.createElement(tag);
  if (className) el.className = className;
  if (text) el.textContent = text;
  return el;
}
const hooks = {
  ...colocatedHooks,
  CopyToClipboard: {
    mounted() {
      this.onClick = async () => {
        const targetId = this.el.dataset.copyTarget;
        if (!targetId) return;
        const target = document.getElementById(targetId);
        if (!target) return;
        const text = target.value || target.innerText || "";

        try {
          if (navigator.clipboard) {
            await navigator.clipboard.writeText(text);
          } else {
            const range = document.createRange();
            range.selectNodeContents(target);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            document.execCommand("copy");
            selection.removeAllRanges();
          }
          this.el.dataset.copyState = "copied";
        } catch (_error) {
          this.el.dataset.copyState = "error";
        }
      };

      this.el.addEventListener("click", this.onClick);
    },
    destroyed() {
      if (this.onClick) {
        this.el.removeEventListener("click", this.onClick);
      }
    },
  },
  SessionEventViewer: {
    mounted() {
      this.eventsUrl = this.el.dataset.eventsUrl;
      if (!this.eventsUrl) return;

      this.list = this.el.querySelector("[data-role='event-list']");
      this.empty = this.el.querySelector("[data-role='event-empty']");
      this.status = this.el.querySelector("[data-role='event-status']");
      this.initialAfter = this.el.dataset.after || null;
      this.filters = Array.from(
        this.el.querySelectorAll("input[name='event-types']")
      );
      this.maxEvents = Number(this.el.dataset.maxEvents) || MAX_SESSION_EVENTS;
      this.onFilterChange = () => {
        this.applyFilters();
      };

      this.filters.forEach((filter) =>
        filter.addEventListener("change", this.onFilterChange)
      );

      this.connectStream();
      this.applyFilters();
    },
    destroyed() {
      this.teardown();
    },
    teardown() {
      if (this.filters && this.onFilterChange) {
        this.filters.forEach((filter) =>
          filter.removeEventListener("change", this.onFilterChange)
        );
      }
      if (this.eventSource) {
        this.eventSource.close();
        this.eventSource = null;
      }
    },
    setStatus(message, state) {
      if (!this.status) return;
      this.status.textContent = message;
      this.status.dataset.state = state;
    },
    selectedTypes() {
      return this.filters
        .filter((filter) => filter.checked)
        .map((filter) => filter.value);
    },
    applyFilters() {
      if (!this.list) return;
      const selected = new Set(this.selectedTypes());
      const cards = Array.from(this.list.children);
      let visibleCount = 0;

      cards.forEach((card) => {
        const type = card.dataset.type || "";
        const show = selected.size > 0 && selected.has(type);
        card.hidden = !show;
        if (show) visibleCount += 1;
      });

      this.updateEmptyState(visibleCount, cards.length, selected.size);
    },
    updateEmptyState(visibleCount, totalCount, selectedCount) {
      if (!this.empty) return;
      let message = "No events yet.";

      if (selectedCount === 0) {
        message = "Select at least one event type.";
      } else if (totalCount > 0 && visibleCount === 0) {
        message = "No events match the selected filters.";
      }

      this.empty.textContent = message;
      this.empty.hidden = visibleCount > 0;
    },
    connectStream() {
      if (this.eventSource) {
        this.eventSource.close();
      }

      const url = new URL(this.eventsUrl, window.location.origin);
      url.searchParams.set("follow", "true");
      url.searchParams.set("limit", String(this.maxEvents));
      if (this.initialAfter) {
        url.searchParams.set("after", this.initialAfter);
      }

      this.setStatus("Connecting...", "connecting");

      this.eventSource = new EventSource(url.toString());
      this.initialAfter = null;
      this.eventSource.onopen = () => {
        this.setStatus("Live", "live");
      };
      this.eventSource.onerror = () => {
        this.setStatus("Reconnecting...", "warning");
      };
      this.eventSource.addEventListener("session_event", (event) => {
        try {
          const parsed = JSON.parse(event.data);
          this.appendEvent(parsed);
        } catch (_error) {
          this.setStatus("Stream error", "error");
        }
      });
    },
    appendEvent(event) {
      if (!this.list) return;
      const card = this.buildEventCard(event);
      if (!card) return;

      this.list.appendChild(card);

      while (this.list.children.length > this.maxEvents) {
        this.list.removeChild(this.list.firstChild);
      }

      this.applyFilters();
    },
    buildEventCard(event) {
      if (!event || typeof event !== "object") return null;
      const type = event.type || "unknown";
      const payload = event.payload || {};

      const card = createElement(
        "article",
        `session-event-card session-event-${type}`
      );
      card.dataset.type = type;

      const header = createElement("div", "session-event-card-header");
      const typeBadge = createElement(
        "span",
        `session-event-type session-event-type-${type}`
      );
      const typeIcon = createElement(
        "span",
        `session-event-icon session-event-icon-${type}`,
        eventTypeIcon(type)
      );
      typeIcon.setAttribute("aria-hidden", "true");
      typeBadge.appendChild(typeIcon);
      typeBadge.appendChild(document.createTextNode(capitalize(type)));
      header.appendChild(typeBadge);

      const timestamp = formatTimestamp(event.timestamp);
      if (timestamp) {
        const timeEl = createElement("time", "session-event-time", timestamp);
        if (event.timestamp) {
          const parsedDate = new Date(event.timestamp);
          if (!Number.isNaN(parsedDate.getTime())) {
            timeEl.dateTime = parsedDate.toISOString();
          }
        }
        header.appendChild(timeEl);
      }

      const sourceLabel = formatSourceLabel(event.source);
      const sourceEl = createElement(
        "span",
        "session-event-source",
        sourceLabel
      );
      header.appendChild(sourceEl);
      card.appendChild(header);

      const summaryText = formatSummary(event);
      if (summaryText) {
        const summaryEl = createElement(
          "div",
          "session-event-summary",
          summaryText
        );
        card.appendChild(summaryEl);
      }

      const percent = progressPercent(payload);
      if (percent != null) {
        const progress = createElement("div", "session-event-progress");
        progress.setAttribute("role", "progressbar");
        progress.setAttribute("aria-valuemin", "0");
        progress.setAttribute("aria-valuemax", "100");
        progress.setAttribute("aria-valuenow", String(percent));
        const track = createElement("div", "session-event-progress-track");
        const bar = createElement("div", "session-event-progress-bar");
        bar.style.width = `${percent}%`;
        const label = createElement(
          "span",
          "session-event-progress-label",
          formatPercentValue(percent)
        );
        track.appendChild(bar);
        progress.appendChild(track);
        progress.appendChild(label);
        card.appendChild(progress);
      }

      if (type === "artifact" && payload.uri) {
        const artifact = createElement("div", "session-event-artifact");
        if (isImageArtifact(payload)) {
          const link = createElement("a", "session-event-artifact-link");
          link.href = payload.uri;
          link.target = "_blank";
          link.rel = "noopener";
          const img = createElement("img", "session-event-artifact-image");
          img.src = payload.uri;
          img.alt = artifactLabel(payload);
          img.loading = "lazy";
          link.appendChild(img);
          artifact.appendChild(link);
        } else {
          const link = createElement(
            "a",
            "session-event-artifact-link",
            artifactLabel(payload)
          );
          link.href = payload.uri;
          link.target = "_blank";
          link.rel = "noopener";
          artifact.appendChild(link);
        }

        const detail = artifactDetail(payload);
        if (detail) {
          const meta = createElement(
            "div",
            "session-event-artifact-meta",
            detail
          );
          artifact.appendChild(meta);
        }
        card.appendChild(artifact);
      }

      if (type === "output" && payload.text) {
        const details = createElement("details", "session-event-output-block");
        if (outputOpen(payload.text)) {
          details.open = true;
        }
        const summary = createElement("summary", null, "Output");
        if (payload.stream) {
          summary.appendChild(document.createTextNode(" "));
          const stream = createElement(
            "span",
            "session-event-output-stream",
            String(payload.stream).toUpperCase()
          );
          summary.appendChild(stream);
        }
        const outputEl = createElement("pre", "session-event-output");
        outputEl.textContent = payload.text;
        details.appendChild(summary);
        details.appendChild(outputEl);
        card.appendChild(details);
      }

      const details = createElement("details", "session-event-details");
      details.dataset.role = "event-details";
      const summary = createElement("summary", null, "Details");
      const pre = createElement("pre", "session-event-payload");
      const code = createElement("code");
      code.textContent = JSON.stringify(event, null, 2);
      pre.appendChild(code);
      details.appendChild(summary);
      details.appendChild(pre);
      card.appendChild(details);

      return card;
    },
  },
};

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks,
});

// Show progress bar on live navigation and form submits
// Get theme primary color from CSS variables
function getThemePrimaryColor() {
  return getComputedStyle(document.documentElement)
    .getPropertyValue("--theme-ui-colors-primary")
    .trim() || "#2f7c4c";
}

// Configure topbar with theme color
function configureTopbar() {
  const primaryColor = getThemePrimaryColor();
  topbar.config({ barColors: { 0: primaryColor }, shadowColor: "rgba(0, 0, 0, .3)" });
}

// Initial configuration
configureTopbar();

// Reconfigure when theme changes
window.addEventListener("theme-changed", configureTopbar);

window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// Initialize features
initTheme();
setupThemeToggle();
setupFlashDismiss();
setupDropdown();
setupPasskeys();
document.addEventListener("DOMContentLoaded", setupProjectHandleGeneration);
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

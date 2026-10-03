import {
  escapeHtml,
  glyph,
  priority,
  signError,
  stageClass,
} from "./graph.mjs";
import { renderMarkdown } from "./markdown.mjs";

const el = (id) => document.getElementById(id);
const relative = (time) => {
  const seconds = Math.max(
    0,
    Math.round((Date.now() - Date.parse(time)) / 1000),
  );
  return seconds < 60
    ? "just now"
    : seconds < 3600
      ? `${Math.floor(seconds / 60)}m ago`
      : `${Math.floor(seconds / 3600)}h ago`;
};
const section = (name, content, open = false) =>
  `<details class="drawer-section" data-section="${name}" ${sessionStorage.getItem(`keep-section-${name}`) === "open" || (open && sessionStorage.getItem(`keep-section-${name}`) !== "closed") ? "open" : ""}><summary>${name}</summary>${content}</details>`;
const dependencies = (bead) => {
  const labels = {
    blocks: "Blocks",
    blockedBy: "Blocked by",
    parent: "Parent",
    children: "Children",
    discoveredFrom: "Discovered from",
    supersedes: "Supersedes",
  };
  return (
    Object.entries(labels)
      .map(([type, name]) => {
        const ids = bead.dependencyGroups?.[type] ?? [];
        return ids.length
          ? `<p><b>${name}</b> <span class="dependency-chips">${ids.map((id) => `<button class="chip dependency" data-id="${escapeHtml(id)}">${escapeHtml(id)}</button>`).join("")}</span></p>`
          : "";
      })
      .join("") || "<p>None.</p>"
  );
};
const optionsFrom = (bead) =>
  [
    ...`${bead.description ?? ""}\n${bead.acceptance_criteria ?? ""}`.matchAll(
      /^OPTION ([A-Z]):\s*(.+)$/gm,
    ),
  ].map((match) => ({ id: match[1], text: match[2] }));
const signingDesk = (bead) => {
  const options = optionsFrom(bead);
  const choices = options.length
    ? `<fieldset class="sign-options"><legend>Decision option</legend>${options.map((option) => `<label><input type="radio" name="sign-option" value="${escapeHtml(option.id)}"> OPTION ${escapeHtml(option.id)}: ${escapeHtml(option.text)}</label>`).join("")}</fieldset>`
    : "<p>No OPTION A: lines found on this bead.</p>";
  const saved = localStorage.getItem(tokenKey);
  const tokenControl = `<label>Signing token${saved ? " (leave blank to use the saved token)" : ""} <input id="sign-token" type="password" autocomplete="off"></label>`;
  const question = bead.needsYou.detail
    ? `<p class="notice">${escapeHtml(bead.needsYou.detail)}${bead.needsYou.ts ? ` <time>${escapeHtml(bead.needsYou.ts)}</time>` : ""}</p>`
    : "";
  return `<div class="signing-desk">${question}<p class="notice">${escapeHtml(bead.needsYou.why)}</p>${choices}<label>Note <textarea id="sign-note" rows="4"></textarea></label>${tokenControl}<div class="sign-actions"><button data-sign-action="approve">${approveLabel(bead, false)}</button><button data-sign-action="decline">Decline</button><button data-sign-action="decide" ${options.length ? "" : "disabled"}>Decide-option</button></div><output id="sign-result" aria-live="polite"></output></div>`;
};
const inFlight = new Set();
// CIV KEEP: one token for the unified desk, separate from Proofdelve's own Keep.
const tokenKey = "civ-keep-signing-token";
// A plain fort has no fleet, so every approval goes to its Mayor.
const approveLabel = (bead, noted) =>
  bead.fortMode === "fleet" && !noted ? "Approve → Fleet" : "Approve → Mayor";
const commentDesk = () =>
  `<div class="signing-desk"><label>Comment <textarea id="comment-note" rows="3"></textarea></label><p class="muted">Posted on the bead as an OVERSEER comment. No labels change and no event is emitted.</p>${localStorage.getItem(tokenKey) ? "" : '<label>Signing token <input id="comment-token" type="password" autocomplete="off"></label>'}<div class="sign-actions"><button id="comment-send">Post comment</button></div><output id="comment-result" aria-live="polite"></output></div>`;
async function post(body, token) {
  const response = await fetch("/api/sign", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(body),
  });
  const result = await response.json();
  if (response.status === 401) localStorage.removeItem(tokenKey);
  return { response, result };
}
function bindCommentDesk(bead, reopen) {
  const send = el("comment-send");
  if (!send) return;
  send.addEventListener("click", async () => {
    const text = el("comment-note").value.trim();
    if (!text) {
      el("comment-result").textContent = "Write a comment first.";
      return;
    }
    const token =
      el("comment-token")?.value.trim() || localStorage.getItem(tokenKey);
    if (!token) {
      el("comment-result").textContent = "Enter the signing token.";
      return;
    }
    localStorage.setItem(tokenKey, token);
    send.disabled = true;
    el("comment-result").textContent = "Posting…";
    try {
      const { response, result } = await post(
        { id: bead.id, fort: bead.fort, action: "comment", text },
        token,
      );
      el("comment-result").textContent = response.ok
        ? "Comment posted."
        : signError(response.status, result);
      if (response.ok) await reopen(bead.id);
    } catch (error) {
      el("comment-result").textContent = `Comment failed: ${error.message}`;
    } finally {
      send.disabled = false;
    }
  });
}
function bindSigningDesk(bead, reopen) {
  const signingButtons = document.querySelectorAll("[data-sign-action]");
  const approve = [...signingButtons].find(
    (button) => button.dataset.signAction === "approve",
  );
  el("sign-note").addEventListener("input", () => {
    approve.textContent = approveLabel(
      bead,
      Boolean(el("sign-note").value.trim()),
    );
  });
  signingButtons.forEach((button) =>
    button.addEventListener("click", async () => {
      if (inFlight.has(bead.id)) return;
      const action = button.dataset.signAction;
      const text = el("sign-note").value.trim();
      const option =
        document.querySelector('input[name="sign-option"]:checked')?.value ??
        null;
      if ((action === "decline" || action === "decide") && !text) {
        el("sign-result").textContent =
          "A note is required for Decline and Decide.";
        return;
      }
      if (action === "decide" && !option) {
        el("sign-result").textContent = "Choose an option.";
        return;
      }
      const token =
        el("sign-token").value.trim() || localStorage.getItem(tokenKey);
      if (!token) {
        el("sign-result").textContent = "Enter the signing token.";
        return;
      }
      const choice = action === "decide" ? ` OPTION ${option}` : "";
      if (
        !window.confirm(
          `${bead.fortName ?? ""} ${bead.id}: ${action.toUpperCase()}${choice}\n\n${text}`,
        )
      )
        return;
      localStorage.setItem(tokenKey, token);
      el("sign-result").textContent = "Recording decision…";
      inFlight.add(bead.id);
      button.disabled = true;
      try {
        const { response, result } = await post(
          { id: bead.id, fort: bead.fort, action, option, text },
          token,
        );
        el("sign-result").textContent = response.ok
          ? "Decision recorded."
          : signError(response.status, result);
        if (response.ok) await reopen(bead.id);
      } catch (error) {
        el("sign-result").textContent = `Signing failed: ${error.message}`;
      } finally {
        inFlight.delete(bead.id);
        button.disabled = false;
      }
    }),
  );
}

export async function openDrawer(
  id,
  {
    onNavigate,
    onClose,
    updateHash = true,
    notice = "",
    bead: suppliedBead,
  } = {},
) {
  let bead = suppliedBead;
  if (!bead) {
    const response = await fetch(`/api/bead/${encodeURIComponent(id)}`);
    if (!response.ok) return;
    bead = await response.json();
  }
  const header = `<div class="drawer-header"><div><span class="chip fort-chip">${escapeHtml(bead.fortName ?? "")}${bead.civilization && bead.civilization !== "Justin" ? ` · ${escapeHtml(bead.civilization)}` : ""}</span> <code>${escapeHtml(bead.id)}</code><h2>${escapeHtml(bead.title)}</h2><div class="meta"><span class="stage-chip ${stageClass(bead.stage)}">${escapeHtml(bead.stage)}</span><span>${escapeHtml(priority(bead))} · ${glyph(bead.issue_type)}</span>${(bead.labels ?? []).map((label) => `<span class="chip">${escapeHtml(label)}</span>`).join("")}<span>${escapeHtml(bead.assignee ?? "Unassigned")}</span><time title="${escapeHtml(bead.created_at)}">Created ${relative(bead.created_at)}</time><time title="${escapeHtml(bead.updated_at)}">Updated ${relative(bead.updated_at)}</time></div></div><button id="drawer-close">Back</button></div>`;
  const comments =
    (bead.comments ?? [])
      .map(
        (comment) =>
          `<article class="comment"><b>${escapeHtml(comment.author ?? "Unknown")}</b> <time title="${escapeHtml(comment.created_at)}">${relative(comment.created_at)}</time><div class="pasted">${renderMarkdown(comment.text)}</div></article>`,
      )
      .join("") || "<p>None.</p>";
  el("drawer").innerHTML =
    `${header}${notice ? `<p class="notice">${escapeHtml(notice)}</p>` : ""}${bead.needsYou ? section("Needs you", signingDesk(bead), true) : ""}${section("Description", renderMarkdown(bead.description), true)}${section("Acceptance criteria", renderMarkdown(bead.acceptance_criteria))}${section("Notes", renderMarkdown(bead.notes))}${section("Comments", comments + commentDesk(), Boolean(bead.comments?.length))}${section("Close reason", renderMarkdown(bead.close_reason))}${section("Dependencies", dependencies(bead))}`;
  el("drawer").hidden = false;
  if (updateHash) window.location.hash = encodeURIComponent(id);
  el("drawer-close").addEventListener("click", () => {
    if (onClose) onClose();
    else {
      window.location.hash = "";
      el("drawer").hidden = true;
    }
  });
  const reopen = (target) =>
    openDrawer(target, { onNavigate, onClose, updateHash });
  if (bead.needsYou) bindSigningDesk(bead, reopen);
  bindCommentDesk(bead, reopen);
  document.querySelectorAll(".drawer-section").forEach((item) =>
    item.addEventListener("toggle", () => {
      sessionStorage.setItem(
        `keep-section-${item.dataset.section}`,
        item.open ? "open" : "closed",
      );
    }),
  );
  document.querySelectorAll(".dependency").forEach((item) =>
    item.addEventListener("click", async () => {
      const result = await onNavigate?.(item.dataset.id);
      if (result)
        await openDrawer(result.id, {
          onNavigate,
          onClose,
          updateHash,
          notice: result.notice,
          bead: result.bead,
        });
    }),
  );
  return bead;
}

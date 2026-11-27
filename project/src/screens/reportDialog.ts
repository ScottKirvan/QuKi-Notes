import type { BackDismissStack } from "../backDismissStack";
import { formatBuildString, type BuildInfo } from "../buildInfo";
import type { FailureLogView } from "../failureLog";
import {
  PRIVACY_URL,
  REPORT_EMAIL,
  TITLE_MAX,
  relayRequest,
  reportIssueUrl,
  reportMailtoUrl,
  reportText,
  sendReport,
  tailLines,
  type RelaySender,
  type ReportInput,
  type ReportType,
} from "../reportProblem";
import type { ShowToast } from "./toast";

export interface ReportFormOptions {
  version: string;
  buildInfo: BuildInfo;
  /** "win32", "linux", "android" or "web". */
  platform: string;
  /** The local failure log, or null when this device keeps none. Read only if the user ticks "Include recent log". */
  failureLog: () => FailureLogView | null;
  /** Delivers Send's request to the relay; main.ts passes the platform's own (reportSender.ts). */
  send: RelaySender;
  showToast: ShowToast;
  backDismiss?: BackDismissStack;
}

/** Lines of the failure log offered when the user ticks "Include recent log". */
const LOG_LINES = 80;

const TYPE_LABELS: Array<[ReportType, string]> = [
  ["bug", "Bug"],
  ["feature", "Feature request"],
  ["feedback", "Feedback"],
];

const PLACEHOLDER: Record<ReportType, string> = {
  bug: "What went wrong? What did you expect to happen?\n\nSteps to reproduce:\n1. \n2. \n3. ",
  feature: "What would you like QuKi Notes to do?",
  feedback: "What is on your mind?",
};

const TITLE_PLACEHOLDER: Record<ReportType, string> = {
  bug: "A short summary of the problem",
  feature: "A short summary of the idea",
  feedback: "A short summary",
};

let opener: (() => void) | null = null;

/**
 * Opens the "Report a problem" form. Settings -> Diagnostics calls this; a Help
 * or About row can call it too. Does nothing before `createReportForm` ran.
 */
export function openReportForm(): void {
  opener?.();
}

/**
 * "Report a problem": everything pre-filled, everything that could hold
 * personal data editable, and nothing sent until the user taps Send. Open on
 * GitHub, Copy report and Email instead stay available at all times, so a
 * failed Send never loses a report. QuKi text is never put in a report
 * automatically.
 */
export function createReportForm(container: HTMLElement, options: ReportFormOptions): void {
  const overlay = document.createElement("div");
  overlay.className = "report-overlay";
  overlay.hidden = true;
  container.appendChild(overlay);

  let unregisterBack = (): void => {};
  let returnFocus: Element | null = null;
  let generation = 0;

  const close = (): void => {
    if (overlay.hidden) return;
    generation++;
    overlay.hidden = true;
    overlay.replaceChildren();
    unregisterBack();
    document.removeEventListener("keydown", onKeyDown);
    if (returnFocus instanceof HTMLElement) returnFocus.focus();
    returnFocus = null;
  };

  const onKeyDown = (e: KeyboardEvent): void => {
    if (e.key === "Escape") {
      e.preventDefault();
      close();
      return;
    }
    if (e.key !== "Tab") return;
    const focusable = Array.from(
      overlay.querySelectorAll<HTMLElement>("a[href], button:not([disabled]), input:not([disabled]), select, textarea"),
    ).filter((node) => !node.hidden);
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (!first || !last) return;
    const active = document.activeElement;
    if (e.shiftKey && (active === first || !overlay.contains(active))) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && (active === last || !overlay.contains(active))) {
      e.preventDefault();
      first.focus();
    }
  };

  const el = <K extends keyof HTMLElementTagNameMap>(tag: K, className?: string, text?: string): HTMLElementTagNameMap[K] => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };

  const field = (parent: HTMLElement, label: string, control: HTMLElement, hint?: string): void => {
    const wrap = el("div", "report-field");
    const labelEl = el("label", "report-label");
    labelEl.appendChild(el("span", undefined, label));
    if (hint) labelEl.appendChild(el("span", "report-hint", hint));
    labelEl.appendChild(control);
    wrap.appendChild(labelEl);
    parent.appendChild(wrap);
  };

  const link = (text: string, href: string, className: string): HTMLAnchorElement => {
    const a = el("a", className, text);
    a.href = href;
    a.target = "_blank";
    a.rel = "noopener noreferrer";
    return a;
  };

  const build = (): void => {
    overlay.replaceChildren();
    const dialog = el("div", "confirm-dialog report-dialog");
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    dialog.setAttribute("aria-labelledby", "report-title");
    const heading = el("h2", "confirm-title", "Report a problem");
    heading.id = "report-title";
    dialog.appendChild(heading);

    let type: ReportType = "bug";
    const typeSelect = el("select", "report-input report-type");
    for (const [value, label] of TYPE_LABELS) typeSelect.appendChild(new Option(label, value, false, value === type));
    field(dialog, "Type", typeSelect);

    const title = el("input", "report-input report-title-input");
    title.type = "text";
    title.maxLength = TITLE_MAX;
    title.placeholder = TITLE_PLACEHOLDER[type];
    field(dialog, "Title", title);

    const description = el("textarea", "report-input report-description");
    description.rows = 5;
    description.placeholder = PLACEHOLDER[type];
    field(dialog, "Description", description);

    typeSelect.addEventListener("change", () => {
      type = typeSelect.value as ReportType;
      title.placeholder = TITLE_PLACEHOLDER[type];
      description.placeholder = PLACEHOLDER[type];
    });

    const details = el("textarea", "report-input report-mono report-details");
    details.rows = 3;
    details.value = `${formatBuildString(options.version, options.buildInfo)}\nPlatform: ${options.platform}`;
    field(dialog, "Details", details, "Filled in for you. Edit or remove anything you would rather not share.");

    const logWrap = el("div", "report-field");
    const logLabel = el("label", "report-check");
    const logCheck = el("input", "report-log-check");
    logCheck.type = "checkbox";
    logLabel.append(logCheck, el("span", undefined, "Include recent log"));
    logWrap.appendChild(logLabel);
    const logHint = el("div", "report-hint");
    const logText = el("textarea", "report-input report-mono report-log");
    logText.rows = 6;
    logText.hidden = true;
    const logAvailable = options.failureLog() !== null;
    logHint.textContent = logAvailable
      ? "The failure log kept on this device. It holds error types, codes and times, never QuKi text or file names, but check it: logs can hold personal details. Edit it before sending."
      : "This device keeps no failure log.";
    logCheck.disabled = !logAvailable;
    logWrap.append(logHint, logText);
    dialog.appendChild(logWrap);
    logCheck.addEventListener("change", () => {
      logText.hidden = !logCheck.checked;
      if (!logCheck.checked || logText.value) return;
      const view = options.failureLog();
      if (!view) return;
      view.readText().then(
        (text) => {
          logText.value = tailLines(text, LOG_LINES);
        },
        () => {
          logText.value = "";
        },
      );
    });

    const notice = el("p", "report-notice");
    notice.append(
      "Send files your report as a public GitHub issue, so anyone can read it. You do not need a GitHub account. Do not include anything private. For private matters, use Email instead. ",
      link("Privacy policy", PRIVACY_URL, "report-privacy-link"),
    );
    dialog.appendChild(notice);

    const message = el("p", "report-message");
    message.setAttribute("role", "alert");
    message.hidden = true;
    dialog.appendChild(message);

    const current = (): ReportInput => ({
      type,
      title: title.value,
      description: description.value,
      details: details.value,
      log: logCheck.checked ? logText.value : undefined,
    });

    const showMessage = (text: string): void => {
      message.textContent = text;
      message.hidden = false;
    };

    /** Send and Open on GitHub need a title and a description; Copy and Email take whatever is there. */
    const incomplete = (): boolean => {
      const missing = !title.value.trim() ? title : !description.value.trim() ? description : null;
      if (!missing) return false;
      showMessage(missing === title ? "Add a title first." : "Add a description first.");
      missing.focus();
      return true;
    };

    let sending = false;
    const actions = el("div", "report-actions");
    const sendBtn = el("button", "report-send", "Send");
    sendBtn.type = "button";
    const githubLink = link("Open on GitHub", "#", "report-button report-github");
    const copyBtn = el("button", "report-copy", "Copy report");
    copyBtn.type = "button";
    const emailLink = el("a", "report-button report-email", "Email instead (private)");
    emailLink.href = `mailto:${REPORT_EMAIL}`;
    emailLink.title = `Opens your email app, addressed to ${REPORT_EMAIL}`;
    const closeBtn = el("button", "report-close", "Close");
    closeBtn.type = "button";
    actions.append(sendBtn, githubLink, copyBtn, emailLink, closeBtn);
    dialog.appendChild(actions);

    githubLink.addEventListener("click", (e) => {
      if (incomplete()) {
        e.preventDefault();
        return;
      }
      githubLink.href = reportIssueUrl(current());
    });
    emailLink.addEventListener("click", () => {
      emailLink.href = reportMailtoUrl(current());
    });
    copyBtn.addEventListener("click", () => {
      void navigator.clipboard.writeText(reportText(current())).then(
        () => options.showToast("Report copied. Paste it wherever you want to send it.", 3000),
        () => options.showToast("Could not copy the report.", 3000),
      );
    });
    closeBtn.addEventListener("click", close);

    sendBtn.addEventListener("click", () => {
      if (sending || incomplete()) return;
      message.hidden = true;
      actions.classList.remove("report-actions-failed");
      const input = current();
      const { truncated } = relayRequest(input);
      sending = true;
      const mine = generation;
      sendBtn.disabled = true;
      sendBtn.textContent = "Sending…";
      void sendReport(options.send, input).then((result) => {
        sending = false;
        if (mine !== generation) return;
        if (result.ok) {
          showSent(result.url, result.number, truncated);
          return;
        }
        sendBtn.disabled = false;
        sendBtn.textContent = "Send";
        actions.classList.add("report-actions-failed");
        showMessage(result.message);
      });
    });

    overlay.appendChild(dialog);
    title.focus();
  };

  const showSent = (url: string, issueNumber: number, truncated: "none" | "log-dropped" | "cut"): void => {
    overlay.replaceChildren();
    const dialog = el("div", "confirm-dialog report-dialog report-sent");
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    dialog.appendChild(el("h2", "confirm-title", "Sent. Thank you!"));
    const p = el("p", "report-notice");
    p.append(
      "Your report is now ",
      link(issueNumber ? `issue #${issueNumber}` : "a GitHub issue", url, "report-issue-link"),
      ". Anyone can read it there; follow it to see replies.",
    );
    dialog.appendChild(p);
    if (truncated !== "none") {
      dialog.appendChild(
        el("p", "report-notice", truncated === "log-dropped" ? "The failure log was too long and was left out." : "The report was too long and was cut to fit."),
      );
    }
    const actions = el("div", "report-actions");
    const closeBtn = el("button", "report-close", "Close");
    closeBtn.type = "button";
    closeBtn.addEventListener("click", close);
    actions.appendChild(closeBtn);
    dialog.appendChild(actions);
    overlay.appendChild(dialog);
    closeBtn.focus();
  };

  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) close();
  });

  opener = () => {
    if (!overlay.hidden) return;
    returnFocus = document.activeElement;
    build();
    overlay.hidden = false;
    document.addEventListener("keydown", onKeyDown);
    unregisterBack();
    unregisterBack = options.backDismiss?.push(close) ?? ((): void => {});
    overlay.querySelector<HTMLElement>(".report-title-input")?.focus();
  };
}

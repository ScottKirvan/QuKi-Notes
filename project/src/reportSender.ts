/**
 * How Send reaches the report relay on each platform (the relay sends CORS
 * headers only for the web origin, so a WebView's fetch cannot be used there):
 *  - Electron: the main process posts it with net.fetch, over IPC (the window
 *    never talks to the relay itself, and the main process owns the address);
 *  - Android: Capacitor's native HTTP, which is not subject to CORS;
 *  - web: plain fetch.
 */
import { Capacitor, CapacitorHttp } from "@capacitor/core";

import { RELAY_URL, type RelayReply, type RelaySender } from "./reportProblem";

export interface ElectronReportApi {
  /** Posts the JSON text to the relay from the main process. Rejects when the relay is unreachable. */
  send(body: string): Promise<RelayReply>;
}

declare global {
  interface Window {
    /** Present only inside the Electron wrapper (see preload.ts). */
    electronReportAPI?: ElectronReportApi;
  }
}

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

export const fetchSender: RelaySender = async (body, signal) => {
  const response = await fetch(RELAY_URL, { method: "POST", headers: { "content-type": "application/json" }, body, signal });
  return { status: response.status, json: parseJson(await response.text()) };
};

export const capacitorSender: RelaySender = async (body) => {
  const response = await CapacitorHttp.request({
    url: RELAY_URL,
    method: "POST",
    headers: { "content-type": "application/json" },
    data: parseJson(body),
    responseType: "text",
    connectTimeout: 20000,
    readTimeout: 20000,
  });
  const data: unknown = response.data;
  return { status: response.status, json: typeof data === "string" ? parseJson(data) : data };
};

export function electronSender(api: ElectronReportApi): RelaySender {
  return (body) => api.send(body);
}

export function platformRelaySender(): RelaySender {
  if (window.electronReportAPI) return electronSender(window.electronReportAPI);
  if (Capacitor.isNativePlatform()) return capacitorSender;
  return fetchSender;
}

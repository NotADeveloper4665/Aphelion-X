import { invoke as tauriInvoke } from "@tauri-apps/api/core";
import { openUrl as tauriOpenUrl } from "@tauri-apps/plugin-opener";
import { isAllowedMicrosoftVerificationUri } from './device-login-flow';

interface XjausBridge {
  invoke<T>(command: string, args?: Record<string, unknown>): Promise<T>;
  openExternal(url: string): Promise<void>;
  openMicrosoftVerification(url: string): Promise<void>;
  copyText(text: string): Promise<void>;
  reportStreamState?(active: boolean): void;
}
declare global {
  interface Window {
    xjaus?: XjausBridge;
    __XJAUS_QT_BRIDGE__?: boolean;
    __XJAUS_QT_BRIDGE_READY__?: boolean;
  }
}

let qtBridgePromise: Promise<XjausBridge> | undefined;
async function nativeBridge(): Promise<XjausBridge | undefined> {
  if (window.xjaus) return window.xjaus;
  if (!window.__XJAUS_QT_BRIDGE__) return undefined;
  qtBridgePromise ??= new Promise<XjausBridge>((resolve, reject) => {
    if (window.xjaus && window.__XJAUS_QT_BRIDGE_READY__) {
      resolve(window.xjaus);
      return;
    }
    const timeout = window.setTimeout(() => {
      window.removeEventListener('xjaus:bridge-ready', ready);
      reject(new Error('KDE backend bridge did not become ready'));
    }, 10_000);
    const ready = () => {
      window.clearTimeout(timeout);
      window.removeEventListener('xjaus:bridge-ready', ready);
      if (window.xjaus) resolve(window.xjaus);
      else reject(new Error('KDE backend bridge is unavailable'));
    };
    window.addEventListener('xjaus:bridge-ready', ready, { once: true });
  });
  return qtBridgePromise;
}

const ownedStreamCommands = new Set([
  'begin_connection', 'wake_console', 'start_stream', 'provision_stream', 'submit_stream_offer', 'poll_stream_answer',
  'exchange_stream_ice', 'stream_keepalive', 'stop_stream', 'cancel_connection',
]);
export async function invokeBackend<T>(command: string, args?: Record<string, unknown>): Promise<T> {
  if (ownedStreamCommands.has(command) && (typeof args?.attemptId !== 'string' || !args.attemptId)) {
    throw new Error('Missing connection attempt identifier');
  }
  if (command !== 'begin_connection' && ownedStreamCommands.has(command) && (typeof args?.generation !== 'string' || !args.generation)) {
    throw new Error('Missing connection generation');
  }
  const bridge = await nativeBridge();
  if (bridge) return bridge.invoke<T>(command, args);
  return tauriInvoke<T>(command, args);
}
export async function openExternalUrl(url: string): Promise<void> {
  const bridge = await nativeBridge();
  if (bridge) return bridge.openExternal(url);
  return tauriOpenUrl(url);
}

export async function openMicrosoftVerificationUrl(url: string): Promise<void> {
  if (!isAllowedMicrosoftVerificationUri(url)) throw new Error('Microsoft verification URL not permitted');
  const bridge = await nativeBridge();
  if (bridge) return bridge.openMicrosoftVerification(url);
  return tauriOpenUrl(url);
}

export async function copyToClipboard(text: string): Promise<void> {
  const userCode = /^[A-Za-z0-9-]{1,64}$/.test(text);
  if (typeof text !== 'string' || text.length > 512 || (!userCode && !isAllowedMicrosoftVerificationUri(text))) {
    throw new Error('Clipboard value not permitted');
  }
  const bridge = await nativeBridge();
  if (bridge) return bridge.copyText(text);
  if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
  await navigator.clipboard.writeText(text);
}

export async function reportNativeStreamState(active: boolean): Promise<void> {
  const bridge = await nativeBridge();
  bridge?.reportStreamState?.(active);
}

/**
 * Versioned host <-> editor bridge protocol.
 *
 * The same wire format works over WKWebView (`window.webkit.messageHandlers`)
 * and WebKitGTK (which exposes the identical `window.webkit.messageHandlers`
 * API to JavaScript). The host pushes messages in by evaluating
 * `window.topdrawerEditor.handleMessage(json)`; the editor pushes out via the
 * `topdrawer` message handler. In the standalone harness there is no native
 * host, so a fallback transport records traffic for inspection.
 *
 * Data-safety rule: `changed` may only carry *local user edits*. Loading or
 * replacing a document must never serialize and re-emit the original string.
 */

export const PROTOCOL_VERSION = 1;

export type Theme = 'light' | 'dark';
export type Platform = 'macos' | 'linux' | 'harness';

/** host -> editor */
export type HostMessage =
  | { type: 'initialize'; markdown: string; theme: Theme; platform: Platform; revision: number }
  | { type: 'replaceDocument'; markdown: string; revision: number }
  | { type: 'focus' }
  | { type: 'command'; name: 'toggleMode' | 'undo' | 'redo' }
  | { type: 'setTheme'; theme: Theme };

/** editor -> host */
export type EditorMessage =
  | { type: 'ready'; protocolVersion: number }
  | { type: 'changed'; markdown: string; editorRevision: number }
  | { type: 'openLink'; url: string }
  | { type: 'focusChanged'; isFocused: boolean }
  | { type: 'diagnostic'; code: string; detail?: string };

export interface Transport {
  send(message: EditorMessage): void;
}

interface WebkitMessageHandlers {
  topdrawer?: { postMessage(message: unknown): void };
}

declare global {
  interface Window {
    webkit?: { messageHandlers?: WebkitMessageHandlers };
    topdrawerEditor?: { handleMessage(raw: string): void };
    topdrawerHarness?: { log(direction: 'in' | 'out', message: unknown): void };
  }
}

/** Real host transport (WKWebView / WebKitGTK). */
export class WebkitTransport implements Transport {
  send(message: EditorMessage): void {
    window.webkit?.messageHandlers?.topdrawer?.postMessage(message);
  }
}

/** Fallback transport for the browser harness: records every message. */
export class HarnessTransport implements Transport {
  constructor(private sink?: (message: EditorMessage) => void) {}
  send(message: EditorMessage): void {
    this.sink?.(message);
    window.topdrawerHarness?.log('out', message);
  }
}

export function detectTransport(sink?: (message: EditorMessage) => void): Transport {
  if (window.webkit?.messageHandlers?.topdrawer) return new WebkitTransport();
  return new HarnessTransport(sink);
}

/** Validates an incoming raw host message. Returns null when malformed. */
export function parseHostMessage(raw: unknown): HostMessage | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const msg = raw as Record<string, unknown>;
  switch (msg.type) {
    case 'initialize':
      if (typeof msg.markdown !== 'string' || typeof msg.revision !== 'number') return null;
      return {
        type: 'initialize',
        markdown: msg.markdown,
        theme: msg.theme === 'dark' ? 'dark' : 'light',
        platform:
          msg.platform === 'macos' || msg.platform === 'linux' ? msg.platform : 'harness',
        revision: msg.revision,
      };
    case 'replaceDocument':
      if (typeof msg.markdown !== 'string' || typeof msg.revision !== 'number') return null;
      return { type: 'replaceDocument', markdown: msg.markdown, revision: msg.revision };
    case 'focus':
      return { type: 'focus' };
    case 'command':
      if (msg.name === 'toggleMode' || msg.name === 'undo' || msg.name === 'redo') {
        return { type: 'command', name: msg.name };
      }
      return null;
    case 'setTheme':
      return { type: 'setTheme', theme: msg.theme === 'dark' ? 'dark' : 'light' };
    default:
      return null;
  }
}

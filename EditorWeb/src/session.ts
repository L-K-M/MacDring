import {
  PROTOCOL_VERSION,
  detectTransport,
  parseHostMessage,
  type EditorMessage,
  type HostMessage,
  type Theme,
  type Transport,
} from './bridge';
import { RichEditor } from './editor';
import { SourceEditor } from './source';

const PLACEHOLDER = 'Write a note…';

/** Coalescing window for `changed` traffic while typing (ms). */
export const CHANGE_DEBOUNCE_MS = 200;

type Mode = 'rich' | 'source';

/**
 * Owns one note-editing session: the two editor modes, revision discipline,
 * and debounced change reporting.
 *
 * Invariants:
 * - `changed` is emitted only after a local user edit (`dirty`), so a
 *   view-only open/close never normalizes or re-emits the source.
 * - Host `replaceDocument` messages with a revision older than the last
 *   applied one are stale (a late flush from a previous tab) and are dropped.
 * - Only one mode is alive at a time; switching destroys the other editor.
 */
export class EditorSession {
  private transport: Transport;
  private rich: RichEditor | null = null;
  private source: SourceEditor | null = null;
  private mode: Mode = 'rich';
  private theme: Theme = 'light';

  /** Revision last assigned by the host (monotonic). */
  private hostRevision = -1;
  /** Revision of the editor's own change stream; echoed to the host. */
  private editorRevision = 0;
  /** Markdown as loaded by the host — the source of truth until a local edit. */
  private loadedMarkdown = '';
  private dirty = false;
  private pendingMarkdown: string | null = null;
  private debounceTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private container: HTMLElement,
    transport?: Transport,
  ) {
    this.transport = transport ?? detectTransport();
  }

  start(): void {
    window.topdrawerEditor = {
      handleMessage: (raw: string) => {
        let parsed: unknown;
        try {
          parsed = JSON.parse(raw);
        } catch {
          this.diagnostic('bad-message', 'host message is not valid JSON');
          return;
        }
        const message = parseHostMessage(parsed);
        if (!message) {
          this.diagnostic('bad-message', 'host message failed validation');
          return;
        }
        window.topdrawerHarness?.log('in', message);
        void this.handleHostMessage(message);
      },
    };
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'hidden') this.flush();
    });
    this.send({ type: 'ready', protocolVersion: PROTOCOL_VERSION });
  }

  private async handleHostMessage(message: HostMessage): Promise<void> {
    switch (message.type) {
      case 'initialize':
        this.theme = message.theme;
        this.applyTheme();
        await this.loadDocument(message.markdown, message.revision);
        break;
      case 'replaceDocument':
        await this.loadDocument(message.markdown, message.revision);
        break;
      case 'focus':
        this.activeEditorFocus();
        break;
      case 'command':
        await this.handleCommand(message.name);
        break;
      case 'setTheme':
        this.theme = message.theme;
        this.applyTheme();
        break;
    }
  }

  private async loadDocument(markdown: string, revision: number): Promise<void> {
    if (revision < this.hostRevision) {
      this.diagnostic('stale-replace', `dropped revision ${revision}`);
      return;
    }
    // A replace for a document we have local edits on means the host
    // overrode us (e.g. external change); our pending edit is discarded.
    this.hostRevision = revision;
    this.loadedMarkdown = markdown;
    this.dirty = false;
    this.pendingMarkdown = null;
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    await this.rebuildEditor();
  }

  private async rebuildEditor(): Promise<void> {
    await this.destroyEditors();
    if (this.mode === 'rich') {
      this.rich = await RichEditor.mount(this.container, {
        markdown: this.loadedMarkdown,
        placeholder: PLACEHOLDER,
        onChange: (md) => this.localChange(md),
        onOpenLink: (url) => this.openLink(url),
        onFocusChanged: (focused) => this.focusChanged(focused),
      });
    } else {
      this.source = new SourceEditor(this.container, {
        markdown: this.loadedMarkdown,
        placeholder: PLACEHOLDER,
        theme: this.theme,
        onChange: (md) => this.localChange(md),
        onFocusChanged: (focused) => this.focusChanged(focused),
      });
    }
  }

  private async destroyEditors(): Promise<void> {
    if (this.rich) {
      await this.rich.destroy();
      this.rich = null;
    }
    if (this.source) {
      this.source.destroy();
      this.source = null;
    }
  }

  private async handleCommand(name: 'toggleMode' | 'undo' | 'redo'): Promise<void> {
    switch (name) {
      case 'toggleMode':
        await this.toggleMode();
        break;
      // undo/redo stay inside the active editor's own history; the host only
      // forwards the keystroke as a command when the web view has focus.
      case 'undo':
      case 'redo':
        document.execCommand(name);
        break;
    }
  }

  private async toggleMode(): Promise<void> {
    // Serialize once at the boundary so both modes always agree on the text.
    const current = this.currentMarkdown();
    this.mode = this.mode === 'rich' ? 'source' : 'rich';
    this.loadedMarkdown = current;
    await this.rebuildEditor();
  }

  private currentMarkdown(): string {
    if (this.pendingMarkdown !== null) return this.pendingMarkdown;
    if (this.rich) return this.rich.getMarkdown();
    if (this.source) return this.source.getMarkdown();
    return this.loadedMarkdown;
  }

  private localChange(markdown: string): void {
    this.dirty = true;
    this.pendingMarkdown = markdown;
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    this.debounceTimer = setTimeout(() => this.flush(), CHANGE_DEBOUNCE_MS);
  }

  /** Sends any pending local edit immediately (blur, drawer close, terminate). */
  flush(): void {
    if (this.debounceTimer) clearTimeout(this.debounceTimer);
    this.debounceTimer = null;
    if (!this.dirty || this.pendingMarkdown === null) return;
    this.editorRevision += 1;
    this.send({
      type: 'changed',
      markdown: this.pendingMarkdown,
      editorRevision: this.editorRevision,
    });
    this.loadedMarkdown = this.pendingMarkdown;
    this.pendingMarkdown = null;
    this.dirty = false;
  }

  private openLink(url: string): void {
    // Only web links leave the app; every other scheme stays inert.
    if (/^https?:\/\//i.test(url)) {
      this.send({ type: 'openLink', url });
    } else {
      this.diagnostic('blocked-link', url);
    }
  }

  private focusChanged(isFocused: boolean): void {
    if (!isFocused) this.flush();
    this.send({ type: 'focusChanged', isFocused });
  }

  private activeEditorFocus(): void {
    if (this.rich) this.rich.focus();
    else this.source?.focus();
  }

  private applyTheme(): void {
    document.documentElement.dataset.tdTheme = this.theme;
  }

  private diagnostic(code: string, detail?: string): void {
    this.send({ type: 'diagnostic', code, detail });
  }

  private send(message: EditorMessage): void {
    this.transport.send(message);
  }
}

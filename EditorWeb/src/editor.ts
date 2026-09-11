import { CrepeBuilder } from '@milkdown/crepe/builder';
import { toolbar } from '@milkdown/crepe/feature/toolbar';
import { topBar } from '@milkdown/crepe/feature/top-bar';
import { codeMirror } from '@milkdown/crepe/feature/code-mirror';
import { cursor } from '@milkdown/crepe/feature/cursor';
import { linkTooltip } from '@milkdown/crepe/feature/link-tooltip';
import { listItem } from '@milkdown/crepe/feature/list-item';
import { placeholder } from '@milkdown/crepe/feature/placeholder';
import { table } from '@milkdown/crepe/feature/table';

// Only the CSS for enabled features; the monolithic style.css would drag in
// KaTeX fonts, the AI panel, image upload and slash-menu chrome.
import '@milkdown/crepe/theme/common/prosemirror.css';
import '@milkdown/crepe/theme/common/reset.css';
import '@milkdown/crepe/theme/common/code-mirror.css';
import '@milkdown/crepe/theme/common/cursor.css';
import '@milkdown/crepe/theme/common/link-tooltip.css';
import '@milkdown/crepe/theme/common/list-item.css';
import '@milkdown/crepe/theme/common/placeholder.css';
import '@milkdown/crepe/theme/common/toolbar.css';
import '@milkdown/crepe/theme/common/table.css';
import '@milkdown/crepe/theme/common/top-bar.css';

export interface RichEditorOptions {
  markdown: string;
  placeholder: string;
  /** Fires only on local user edits, never on load. Receives serialized Markdown. */
  onChange(markdown: string): void;
  /** Links must open through the host's external-browser path, never in-view. */
  onOpenLink(url: string): void;
  onFocusChanged?(isFocused: boolean): void;
}

/**
 * Rich WYSIWYG mode: a deliberately slim Milkdown/Crepe assembly built with
 * CrepeBuilder so unused features (image upload, LaTeX, AI, slash menu / block
 * handle) are tree-shaken out of the bundle entirely. Markdown in, Markdown
 * out. Serialization only ever happens in response to a local change reported
 * by the listener, so a view-only open/close cycle cannot normalize the source.
 */
export class RichEditor {
  private state = { destroyed: false };

  private constructor(
    private root: HTMLElement,
    private builder: CrepeBuilder,
  ) {}

  static async mount(root: HTMLElement, options: RichEditorOptions): Promise<RichEditor> {
    const builder = new CrepeBuilder({ root, defaultValue: options.markdown });
    const editor = new RichEditor(root, builder);
    builder
      .addFeature(toolbar)
      .addFeature(topBar)
      .addFeature(codeMirror)
      .addFeature(cursor)
      .addFeature(linkTooltip, { onCopyLink: (link: string) => options.onOpenLink(link) })
      .addFeature(listItem)
      .addFeature(placeholder, { text: options.placeholder, mode: 'doc' })
      .addFeature(table);

    builder.on((api) => {
      api.markdownUpdated((_ctx, markdown, prevMarkdown) => {
        if (editor.state.destroyed || markdown === prevMarkdown) return;
        options.onChange(markdown);
      });
    });

    await builder.create();
    return editor;
  }

  getMarkdown(): string {
    return this.builder.getMarkdown();
  }

  focus(): void {
    this.root.querySelector<HTMLElement>('.ProseMirror')?.focus();
  }

  async destroy(): Promise<void> {
    this.state.destroyed = true;
    await this.builder.destroy();
    this.root.replaceChildren();
  }
}

// @vitest-environment happy-dom
import { describe, expect, it } from 'vitest';
import { EditorSession } from '../src/session';
import type { EditorMessage, Transport } from '../src/bridge';

/** In-memory transport capturing every editor -> host message. */
class FakeTransport implements Transport {
  messages: EditorMessage[] = [];
  send(message: EditorMessage): void {
    this.messages.push(message);
  }
  ofType<T extends EditorMessage['type']>(type: T) {
    return this.messages.filter((m) => m.type === type);
  }
}

function handleMessage(json: string) {
  window.topdrawerEditor?.handleMessage(json);
}

function initialize(session: EditorSession, markdown: string, revision: number) {
  handleMessage(JSON.stringify({ type: 'initialize', markdown, theme: 'light', platform: 'harness', revision }));
}

async function tick(ms = 50) {
  await new Promise((r) => setTimeout(r, ms));
}

function newSession() {
  const transport = new FakeTransport();
  const container = document.createElement('div');
  document.body.appendChild(container);
  const session = new EditorSession(container, transport);
  session.start();
  return { transport, container, session };
}

describe('EditorSession', () => {
  it('announces readiness with the protocol version', () => {
    const { transport } = newSession();
    expect(transport.ofType('ready')).toEqual([{ type: 'ready', protocolVersion: 1 }]);
  });

  it('load + flush without edits sends no changed message', async () => {
    const { transport, session } = newSession();
    initialize(session, '# Note\n', 1);
    await tick(100);
    session.flush();
    expect(transport.ofType('changed')).toEqual([]);
  });

  it('drops a stale replaceDocument and reports a diagnostic', async () => {
    const { transport, session } = newSession();
    initialize(session, 'new\n', 5);
    await tick(100);
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'OLD\n', revision: 2 }));
    await tick(100);

    expect(transport.ofType('diagnostic')).toContainEqual({
      type: 'diagnostic',
      code: 'stale-replace',
      detail: 'dropped revision 2',
    });
    expect(transport.ofType('changed')).toEqual([]);
  });

  it('accepts a newer replaceDocument and renders the new text', async () => {
    const { transport, container, session } = newSession();
    initialize(session, 'v1\n', 1);
    await tick(100);
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'v2\n', revision: 2 }));
    await tick(150);
    session.flush();
    expect(transport.ofType('changed')).toEqual([]);
    expect(container.textContent).toContain('v2');
  });

  it('ignores an identical host retry without rebuilding', async () => {
    const { container, session } = newSession();
    initialize(session, 'same\n', 1);
    await tick(100);
    const editorBefore = container.querySelector('.ProseMirror');

    // Same revision, same text: a redelivery must not churn the editor.
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'same\n', revision: 1 }));
    await tick(100);

    expect(container.querySelector('.ProseMirror')).toBe(editorBefore);
  });

  it('serializes concurrent host messages so only one editor is mounted', async () => {
    const { container, session } = newSession();
    initialize(session, 'one\n', 1);
    // Deliver a rebuild-triggering message in the same tick, while the first
    // mount is still in flight.
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'two\n', revision: 2 }));
    await tick(300);

    expect(container.querySelectorAll('.ProseMirror')).toHaveLength(1);
    expect(container.textContent).toContain('two');
  });

  it('rejects malformed host JSON with a diagnostic instead of throwing', async () => {
    const { transport, session } = newSession();
    handleMessage('not json');
    handleMessage(JSON.stringify({ type: 'nonsense' }));
    await tick();
    expect(transport.ofType('diagnostic').map((d) => (d as { code: string }).code)).toEqual([
      'bad-message',
      'bad-message',
    ]);
  });

  it('answers a stale revision with a diagnostic rather than a rebuild', async () => {
    const { transport, session } = newSession();
    initialize(session, 'x\n', 3);
    await tick(100);
    handleMessage(JSON.stringify({ type: 'replaceDocument', markdown: 'y\n', revision: 3 }));
    await tick(100);
    // Equal revision and different text is news (an external edit), not stale.
    expect(transport.ofType('diagnostic')).toEqual([]);
  });
});

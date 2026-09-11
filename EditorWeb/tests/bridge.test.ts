import { describe, expect, it } from 'vitest';
import { parseHostMessage, PROTOCOL_VERSION } from '../src/bridge';

describe('parseHostMessage', () => {
  it('accepts a well-formed initialize', () => {
    expect(
      parseHostMessage({ type: 'initialize', markdown: '# Hi', theme: 'dark', platform: 'macos', revision: 3 }),
    ).toEqual({ type: 'initialize', markdown: '# Hi', theme: 'dark', platform: 'macos', revision: 3 });
  });

  it('rejects non-objects and missing fields', () => {
    expect(parseHostMessage(null)).toBeNull();
    expect(parseHostMessage('initialize')).toBeNull();
    expect(parseHostMessage({ type: 'initialize', markdown: 1, revision: 1 })).toBeNull();
    expect(parseHostMessage({ type: 'replaceDocument', markdown: 'x' })).toBeNull();
  });

  it('defaults unknown theme/platform to safe values', () => {
    expect(parseHostMessage({ type: 'setTheme', theme: 'purple' })).toEqual({
      type: 'setTheme',
      theme: 'light',
    });
    expect(
      parseHostMessage({ type: 'initialize', markdown: '', theme: 'light', platform: 'plan9', revision: 0 }),
    ).toMatchObject({ platform: 'harness' });
  });

  it('rejects unknown commands', () => {
    expect(parseHostMessage({ type: 'command', name: 'rm -rf' })).toBeNull();
    expect(parseHostMessage({ type: 'command', name: 'toggleMode' })).toEqual({
      type: 'command',
      name: 'toggleMode',
    });
  });

  it('protocol version is pinned at 1', () => {
    expect(PROTOCOL_VERSION).toBe(1);
  });
});

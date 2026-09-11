import './theme.css';
import { EditorSession } from './session';

const container = document.getElementById('editor');
if (!container) throw new Error('missing #editor container');

const session = new EditorSession(container);
session.start();

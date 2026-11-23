const WebSocket = require('ws');
const {spawn} = require('node:child_process');
const {mkdtempSync, readFileSync, rmSync} = require('node:fs');
const {tmpdir} = require('node:os');
const path = require('node:path');
const cloud = require('./cloud');
const uuid = require('./manifest.json').UUID;
const helper = path.join(__dirname, 'bin/helper');
const [address, port] = process.argv.slice(2);
let socket, session, configuring = false;
const instances = new Map();

function send(data) {
  if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(data));
}
function title(id, text) {
  const context = instances.get(id);
  if (context?.active) send({cmd:'setTitle', param:{uuid:context.uuid, key:context.key, actionid:id, text}});
}
function native(args) {
  const child = spawn(helper, args, {stdio:'pipe'});
  let output = '', error = '';
  child.stdout.on('data', chunk => output += chunk);
  child.stderr.on('data', chunk => error += chunk);
  child.stdin.on('error', () => {}); // The helper may refuse permission before release.
  const result = new Promise((resolve, reject) => {
    child.once('error', () => reject(Error('辅助程序启动失败')));
    child.once('close', code => code === 0 ? resolve(output.trim()) : reject(Error(error.slice(0,60) || '操作已取消')));
  });
  return {child, result};
}
function cancel() {
  const current = session;
  if (!current) return;
  current.abort.abort();
  current.child?.kill();
  current.release();
}
async function dictate(id) {
  let release;
  const released = new Promise(resolve => { release = resolve; });
  const current = {id, release, abort:new AbortController()};
  session = current;
  const timer = setTimeout(cancel, 180000);
  let dir;
  try {
    const key = native(['credential']);
    current.child = key.child;
    const token = await key.result;
    if (current.ended || current.abort.signal.aborted) return title(id, '请按久一点');
    dir = mkdtempSync(path.join(tmpdir(), 'openless-'));
    const wav = path.join(dir, 'recording.wav');
    const recorder = native(['record', wav]);
    current.child = recorder.child;
    recorder.child.stdout.once('data', () => title(id, '录音中'));
    released.then(() => recorder.child.stdin.end('\n'));
    const target = await recorder.result;
    if (!/^\d+$/.test(target)) throw Error('录音失败');
    current.abort.signal.throwIfAborted();
    const audio = readFileSync(wav);
    if (audio.length < 5000) throw Error('录音太短');
    title(id, '识别中');
    const raw = await cloud.transcribe(audio, token, current.abort.signal);
    title(id, '润色中');
    let text = raw, degraded = false;
    try { text = await cloud.polish(raw, token, current.abort.signal); }
    catch { degraded = true; }
    current.abort.signal.throwIfAborted();
    const insertion = native(['paste', target]);
    current.child = insertion.child;
    insertion.child.stdin.end(text);
    const status = await insertion.result;
    title(id, (degraded ? '原文 · ' : '') + status);
  } catch (error) {
    title(id, current.abort.signal.aborted ? '已取消' : error.message);
  } finally {
    clearTimeout(timer);
    if (dir) rmSync(dir, {recursive:true, force:true});
    if (session === current) session = undefined;
  }
}
function receive(m) {
  if (m.cmdType === 'NOTIFY' || (m.code !== undefined && m.cmdType !== 'REQUEST')) return;
  if (['add','clear','keydown','keyup','run','setactive','sendToPlugin'].includes(m.cmd)) {
    const {cmdType, ...response} = m;
    send({...response, code:0});
  }
  if (m.cmd === 'clear') {
    for (const item of m.param || []) {
      instances.delete(item.actionid);
      if (session?.id === item.actionid) cancel();
    }
    return;
  }
  if (m.uuid !== uuid + '.dictate' || !m.actionid) return;
  const id = m.actionid;
  if (m.cmd === 'add' || m.cmd === 'setactive' || !instances.has(id)) {
    instances.set(id, {uuid:m.uuid, key:m.key, active:m.active !== false});
  }
  if (m.cmd === 'setactive' && !m.active && session?.id === id) cancel();
  if (m.cmd === 'keydown' && !session && !configuring && !m.isInMultiAction) void dictate(id);
  if (m.cmd === 'keyup' && session?.id === id) { session.ended = true; session.release(); }
  if (m.cmd === 'sendToPlugin' && m.payload?.action === 'configure' && !configuring && !session) {
    configuring = true;
    native(['configure']).result.then(msg => title(id,msg || '按住听写'), e => title(id,e.message))
      .finally(() => configuring = false);
  }
}
function connect() {
  socket = new WebSocket('ws://' + address + ':' + port);
  socket.on('open', () => send({cmd:'connected', code:0, uuid}));
  socket.on('message', bytes => { try { receive(JSON.parse(bytes)); } catch {} });
  socket.on('error', () => {});
  socket.on('close', () => { instances.clear(); cancel(); setTimeout(connect, 1000); });
}
connect();

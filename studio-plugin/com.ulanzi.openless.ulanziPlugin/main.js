const WebSocket = require('ws');
const {spawn} = require('node:child_process');
const {mkdtempSync, readFileSync, rmSync, mkdirSync, writeFileSync, renameSync} = require('node:fs');
const {homedir, tmpdir} = require('node:os');
const path = require('node:path');
const cloud = require('./cloud');
const {record} = require('./record');
const uuid = require('./manifest.json').UUID;
const helper = path.join(__dirname, 'bin/helper');
const [address, port] = process.argv.slice(2);
const {seal, unseal} = require('./credentials');
let pendingSettings;
function readSettings(id) {
  return new Promise((resolve, reject) => {
    if (pendingSettings || socket.readyState !== WebSocket.OPEN) return reject(Error('全局设置暂不可用'));
    const timer = setTimeout(() => finish(undefined, Error('读取全局设置超时')), 3000);
    function finish(settings, error) {
      clearTimeout(timer);
      pendingSettings = undefined;
      if (error) reject(error); else resolve(settings);
    }
    pendingSettings = {id, finish};
    send({cmd:'getGlobalSettings', uuid, actionid:id});
  });
}
async function configure(id) {
  // Keep plaintext off Studio's WebSocket and therefore out of host protocol logs.
  const value = await native(['configure']).result;
  if (!value) return;
  const settings = await readSettings(id);
  const box = seal(value);
  send({cmd:'setGlobalSettings', uuid, settings:{...settings, openaiCredential:box}});
  const saved = await readSettings(id);
  if (unseal(saved.openaiCredential) !== value) throw Error('保存全局设置失败');
  title(id,'已保存');
}
let overlay, overlayTimer;
let socket, session, configuring = false;
const instances = new Map();

// Keep only the latest attempt. Audio, transcripts, credentials and target names are excluded.
const diagnosticDir = path.join(homedir(), 'Library/Logs/OpenLessStudio');
function checkpoint(current, stage, value = true) {
  current.stages[stage] = value;
  try {
    mkdirSync(diagnosticDir, {recursive:true, mode:0o700});
    const file = path.join(diagnosticDir, 'last-session.json');
    writeFileSync(file + '.tmp', JSON.stringify(current.stages), {mode:0o600});
    renameSync(file + '.tmp', file);
  } catch { /* Diagnostics must never interrupt dictation. */ }
}
function send(data) {
  if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(data));
}
// Share one panel across consecutive presses so a previous result cannot cover a new recording.
function displayStatus(text) {
  clearTimeout(overlayTimer);
  if (!overlay) {
    const child = spawn(path.join(__dirname, 'bin/overlay'), [], {stdio:['pipe','ignore','ignore']});
    overlay = child;
    child.stdin.on('error', () => {});
    const reset = () => { if (overlay === child) overlay = undefined; };
    child.on('error', reset);
    child.on('close', reset);
  }
  overlay.stdin.write(text.replace(/[\r\n]/g, ' ') + '\n');
}
function dismissStatus() {
  overlayTimer = setTimeout(() => {
    overlay?.stdin.end();
    overlay = undefined;
  }, 2400);
}
function title(id, text) {
  if (session?.id === id) displayStatus(text);
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
async function dictate(id, mode) {
  let release;
  const released = new Promise(resolve => { release = resolve; });
  const current = {id, mode, release, abort:new AbortController(), stages:{startedAt:new Date().toISOString()}};
  session = current;
  checkpoint(current, 'keydown');
  displayStatus('准备录音');
  const timer = setTimeout(cancel, 180000);
  let dir;
  try {
    const token = unseal((await readSettings(id)).openaiCredential);
    if (current.ended || current.abort.signal.aborted) return title(id, '录音尚未开始');
    dir = mkdtempSync(path.join(tmpdir(), 'openless-'));
    const wav = path.join(dir, 'recording.wav');
    const target = await record(dir, released, current.abort.signal, status => {
      if (status === '录音中') checkpoint(current, 'recording');
      title(id, status === '录音中' && mode === 'toggle' ? '录音中 · 再按结束' : status);
    });
    current.abort.signal.throwIfAborted();
    const audio = readFileSync(wav);
    checkpoint(current, 'wavBytes', audio.length);
    if (audio.length < 5000) throw Error('录音太短');
    title(id, '识别中');
    const raw = await cloud.transcribe(audio, token, current.abort.signal);
    checkpoint(current, 'transcribed');
    title(id, '润色中');
    let text = raw, degraded = false;
    try { text = await cloud.polish(raw, token, current.abort.signal); }
    catch { degraded = true; }
    checkpoint(current, 'polished', !degraded);
    current.abort.signal.throwIfAborted();
    const insertion = native(['paste', target]);
    current.child = insertion.child;
    insertion.child.stdin.end(text);
    const status = await insertion.result;
    checkpoint(current, 'output', status === '已发送粘贴' ? 'paste-dispatched' : 'clipboard');
    title(id, (degraded ? '原文 · ' : '') + status);
  } catch (error) {
    checkpoint(current, 'failure', /^服务错误 [0-9]{3}/.test(error.message) ? error.message : 'stage-failed');
    title(id, current.abort.signal.aborted ? '已取消' : error.message);
  } finally {
    clearTimeout(timer);
    dismissStatus();
    if (dir) rmSync(dir, {recursive:true, force:true});
    if (session === current) session = undefined;
  }
}
function receive(m) {
  if (m.cmd === 'didReceiveGlobalSettings' && m.uuid === uuid && pendingSettings &&
      m.actionid === pendingSettings.id && m.settings && typeof m.settings === 'object') {
    pendingSettings.finish(m.settings);
    return;
  }
  if (m.cmd === 'didReceiveSettings' && m.uuid === uuid + '.dictate' && m.actionid && m.settings) {
    const instance = instances.get(m.actionid);
    if (instance) instance.mode = m.settings.dictationMode === 'hold' ? 'hold' : 'toggle';
    return;
  }
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
  let instance = instances.get(id);
  if (!instance) {
    instance = {uuid:m.uuid, key:m.key, active:true, down:false, mode:'toggle'};
    instances.set(id, instance);
  }
  if (m.cmd === 'add' || m.cmd === 'setactive') {
    instance.active = m.active !== false;
    instance.down = false;
    if (m.param) instance.mode = m.param.dictationMode === 'hold' ? 'hold' : 'toggle';
  }
  if (m.cmd === 'setactive' && !m.active && session?.id === id) cancel();
  if (m.cmd === 'keydown' && instance.active && !instance.down && !m.isInMultiAction) {
    instance.down = true;
    if (!session && !configuring) void dictate(id, instance.mode);
    else if (session?.id === id && session.mode === 'toggle' && !session.ended) {
      session.ended = true;
      session.release();
    }
  }
  if (m.cmd === 'keyup') {
    instance.down = false;
    if (session?.id === id && session.mode === 'hold' && !session.ended) {
      checkpoint(session, 'keyup');
      session.ended = true;
      session.release();
    }
  }
  if (m.cmd === 'sendToPlugin' && m.payload?.action === 'configure' && !configuring && !session) {
    configuring = true;
    configure(id).catch(e => title(id, e.message))
      .finally(() => configuring = false);
  }
}
function connect() {
  socket = new WebSocket('ws://' + address + ':' + port);
  socket.on('open', () => send({cmd:'connected', code:0, uuid}));
  socket.on('message', bytes => { try { receive(JSON.parse(bytes)); } catch {} });
  socket.on('error', () => {});
  socket.on('close', () => { pendingSettings?.finish(undefined, Error('Studio 已断开')); instances.clear(); cancel(); setTimeout(connect, 1000); });
}
connect();

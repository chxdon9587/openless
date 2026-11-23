const net = require('node:net');
const path = require('node:path');
const {spawn} = require('node:child_process');
const {createInterface} = require('node:readline');
const app = path.join(__dirname, 'bin/OpenLess Recorder.app');

exports.record = async function record(dir, release, signal, update) {
  const endpoint = path.join(dir, 'mic.sock');
  let peer, launcher, released = false;
  const server = net.createServer();
  const abort = () => peer?.destroy();
  signal.addEventListener('abort', abort);
  release.then(() => { released = true; peer?.write('\n'); });
  try {
    return await new Promise((resolve, reject) => {
      const fail = () => reject(Error('录音程序已退出'));
      signal.addEventListener('abort', fail, {once:true});
      server.on('error', fail);
      server.once('connection', socket => {
        peer = socket;
        if (released) socket.write('\n');
        let target;
        socket.on('error', fail);
        socket.on('close', fail);
        createInterface({input:socket}).on('line', line => {
          if (line === 'permission') update('请允许 OpenLess Recorder 录音');
          else if (/^ready [0-9]+$/.test(line)) { target = line.slice(6); update('录音中'); }
          else if (line === 'done' && target) resolve(target);
          else if (line === 'released') reject(Error('请重新按住设备键'));
          else if (line === 'denied') reject(Error('请开启 OpenLess Recorder 麦克风'));
          else reject(Error('麦克风启动失败'));
        });
      });
      server.listen(endpoint, () => {
        if (signal.aborted) return fail();
        launcher = spawn('/usr/bin/open', ['-g','-n','-W','-a',app,'--args',endpoint,path.join(dir,'recording.wav')], {stdio:'ignore'});
        launcher.once('error', fail);
        launcher.once('close', () => { if (!peer) fail(); });
      });
    });
  } finally {
    signal.removeEventListener('abort', abort);
    peer?.destroy();
    server.close();
    launcher?.kill();
  }
};

// Doubao V3 uses binary WebSocket frames, including a negative sequence on the final packet.
const WebSocket = require('ws');
const {randomUUID} = require('node:crypto');
const {gzipSync, gunzipSync} = require('node:zlib');

function frame(type, flags, format, seq, bytes) {
  const payload = gzipSync(bytes);
  const header = Buffer.from([0x11, type << 4 | flags, format << 4 | 1, 0]);
  const fields = Buffer.alloc(8);
  fields.writeInt32BE(seq);
  fields.writeUInt32BE(payload.length, 4);
  return Buffer.concat([header, fields, payload]);
}
function response(bytes) {
  if (bytes.length < 8 || bytes[0] >>> 4 !== 1) throw Error('豆包语音返回格式异常');
  const type = bytes[1] >>> 4, flags = bytes[1] & 15;
  let at = (bytes[0] & 15) * 4;
  if (type === 15) throw Error('豆包语音服务错误 ' + bytes.readUInt32BE(at));
  if (type !== 9) throw Error('豆包语音返回未知消息');
  if (flags & 1) at += 4;
  const size = bytes.readUInt32BE(at);
  const payload = bytes.subarray(at + 4);
  if (size !== payload.length) throw Error('豆包语音响应不完整');
  const body = JSON.parse((bytes[2] & 15) === 1 ? gunzipSync(payload, {maxOutputLength:4*1024*1024}) : payload);
  return {final:Boolean(flags & 2), text:body.result?.text};
}

exports.transcribe = function transcribe(wav, key, signal, agent) {
  signal.throwIfAborted();
  return new Promise((resolve, reject) => {
    const socket = new WebSocket('wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async', {
      agent, handshakeTimeout:10000, maxPayload:4*1024*1024, perMessageDeflate:false,
      headers:{'X-Api-Key':key, 'X-Api-Resource-Id':'volc.seedasr.sauc.duration', 'X-Api-Connect-Id':randomUUID()}
    });
    let offset = 0, seq = 1, latest = '', pump, deadline, done = false;
    function finish(error) {
      if (done) return;
      done = true;
      clearTimeout(pump);
      clearTimeout(deadline);
      signal.removeEventListener('abort', abort);
      socket.terminate();
      if (error) reject(error);
      else if (latest.trim()) resolve(latest.trim());
      else reject(Error('未识别到语音'));
    }
    function abort() { finish(Error('已取消')); }
    function sendAudio() {
      if (done) return;
      // Native recorder produces a mono 16 kHz / 16-bit WAV. Keep its header in the first chunk.
      const end = Math.min(offset + 6400, wav.length);
      const last = end === wav.length;
      seq++;
      socket.send(frame(2, last ? 3 : 1, 0, last ? -seq : seq, wav.subarray(offset, end)));
      offset = end;
      if (!last) pump = setTimeout(sendAudio, 200);
      else deadline = setTimeout(() => finish(Error('豆包语音识别超时')), 30000);
    }
    signal.addEventListener('abort', abort, {once:true});
    socket.on('error', error => {
      const code = error.message.match(/Unexpected server response: (\d{3})/)?.[1];
      finish(Error(code ? '豆包语音连接失败 ' + code : '无法连接豆包语音'));
    });
    socket.on('close', () => finish(Error('豆包语音连接已断开')));
    socket.on('message', bytes => {
      try {
        const result = response(bytes);
        if (result.text) latest = result.text;
        if (result.final) finish();
      } catch (error) { finish(error); }
    });
    socket.on('open', () => {
      if (done) return;
      const config = {user:{uid:'openless'}, audio:{format:'wav', codec:'raw', rate:16000, bits:16, channel:1},
        request:{model_name:'bigmodel', enable_itn:true, enable_punc:true, result_type:'full'}};
      socket.send(frame(1, 1, 1, seq, Buffer.from(JSON.stringify(config))));
      sendAudio();
    });
  });
};

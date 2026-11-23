const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');
const {homedir} = require('node:os');

const directory = path.join(homedir(), 'Library/Application Support/OpenLessStudio');
const keyPath = path.join(directory, 'global-settings.key');
const aad = key => Buffer.from('com.ulanzi.ulanzistudio.openless:' + (key === 'openaiCredential' ? 'openai' : key) + ':v1');

function localKey(create) {
  if (create && !fs.existsSync(keyPath)) {
    fs.mkdirSync(directory, {recursive:true, mode:0o700});
    // Publish a fully written key atomically if two Studio processes start together.
    const temp = path.join(directory, crypto.randomUUID());
    fs.writeFileSync(temp, crypto.randomBytes(32), {flag:'wx', mode:0o600});
    try { fs.linkSync(temp, keyPath); }
    catch (e) { if (e.code !== 'EEXIST') throw e; }
    finally { fs.unlinkSync(temp); }
  }
  return fs.readFileSync(keyPath);
}
exports.seal = (value, key = 'openaiCredential') => {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', localKey(true), iv);
  cipher.setAAD(aad(key));
  const data = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return {v:1, iv:iv.toString('base64'), data:data.toString('base64'), tag:cipher.getAuthTag().toString('base64')};
};
exports.unseal = (box, key = 'openaiCredential') => {
  if (!box) throw Error('请先配置 API Key');
  try {
    if (box.v !== 1) throw Error();
    const tag = Buffer.from(box.tag,'base64');
    const iv = Buffer.from(box.iv,'base64');
    if (tag.length !== 16 || iv.length !== 12) throw Error();
    const cipher = crypto.createDecipheriv('aes-256-gcm',localKey(false),iv,{authTagLength:16});
    cipher.setAAD(aad(key));
    cipher.setAuthTag(tag);
    return Buffer.concat([cipher.update(Buffer.from(box.data,'base64')),cipher.final()]).toString('utf8');
  } catch { throw Error('无法解密，请重新配置 API Key'); }
};

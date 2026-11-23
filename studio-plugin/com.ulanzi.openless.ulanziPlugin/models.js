// Shared by the property inspector and Node so the displayed route matches the request.
const openAI = {id:'openai', name:'OpenAI', keyUrl:'https://platform.openai.com/api-keys', key:'openaiCredential', root:'https://api.openai.com/v1/', polish:'gpt-6-luna'};
const siliconFlow = {id:'siliconflow', name:'硅基流动', keyUrl:'https://cloud.siliconflow.cn/account/ak', key:'siliconFlowCredential', root:'https://api.siliconflow.cn/v1/', polish:'deepseek-ai/DeepSeek-V4-Flash'};
const volc = {id:'volc', name:'火山引擎', key:'volcSpeechCredential', keyUrl:'https://console.volcengine.com/speech/new/setting/apikeys',
  polishKey:'volcArkCredential', polishUrl:'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey',
  root:'https://ark.cn-beijing.volces.com/api/v3/', polish:'doubao-seed-2-1-lite-260915', fallback:'doubao-seed-2-0-lite-260428'};
const speechModels = {
  whisper:{service:openAI, asr:'whisper-1', hint:'已有 OpenAI 密钥可继续使用这个默认模型。'},
  sensevoice:{service:siliconFlow, asr:'FunAudioLLM/SenseVoiceSmall', hint:'适合普通话、粤语、英语、日语和韩语听写。'},
  doubao:{service:volc, asr:'豆包流式语音识别 2.0', hint:'先在豆包语音开通流式语音识别 2.0（小时版），再在北京区火山方舟开通所用润色模型。两个控制台各创建一把密钥。'},
  telespeech:{service:siliconFlow, asr:'TeleAI/TeleSpeechASR', hint:'可与 SenseVoiceSmall 对比同一句话的识别效果，两者共用硅基流动密钥。'}
};
function speechModel(id) {
  if (id == null) return speechModels.whisper; // Existing actions predate model selection.
  if (!Object.hasOwn(speechModels, id)) throw Error('请重新选择语音模型');
  return speechModels[id];
}
function customPolishModel(service, overrides) {
  const id = overrides?.[service.id];
  return typeof id === 'string' ? id.trim() : '';
}
if (typeof module !== 'undefined') module.exports = {speechModel, customPolishModel};

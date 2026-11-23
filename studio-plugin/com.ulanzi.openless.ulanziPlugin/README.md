# OpenLess 听写 0.1.1

Apple 芯片 Mac，macOS 13+，Ulanzi Studio 3.3+。将「OpenLess 听写 → 按住听写」拖到普通按键，在属性面板点「配置 OpenAI API Key」。所有听写按键共用本机钥匙串中的密钥。账户需要能调用 whisper-1 和 gpt-4o-mini，服务费用计入自己的 OpenAI 账户。

先将光标置于目标输入框。按住按键说话，松开后等待识别、润色及粘贴。首次使用时允许麦克风，再次按住开始录音。macOS「隐私与安全性 → 辅助功能」中允许负责粘贴的进程；未授权或前台应用发生变化时，请手动粘贴。每次输出会覆盖当前剪贴板。请保持目标输入框的焦点。

录音临时文件在正常结束、取消或出错时清理。录音发往 api.openai.com，识别文本发送至同一服务润色。润色失败会保留原文，转写失败时按键显示错误。401 需更新密钥，429 请检查账户额度或稍后重试。一个插件同一时间处理一次听写，最长三分钟（含等待服务时间）。

基于 Open-Less/openless fork，图标来自上游 src-tauri/icons；许可见 LICENSE。WebSocket 库的许可见 node_modules/ws/LICENSE。源码在 https://github.com/chxdon9587/openless/tree/feat/ulanzi-mac-dictation/studio-plugin 。从源码构建时在插件目录运行 npm ci --omit=dev，在上级目录运行 bash build-helper.sh。

# OpenLess 听写 0.1.7

Apple 芯片 Mac，macOS 13+，Ulanzi Studio 3.3+。将「OpenLess 听写 → 按住听写」拖到普通按键，在属性面板点「配置 OpenAI API Key」。所有听写按键共用 Studio 全局设置中以 AES-256-GCM 加密的凭据。加密用的随机密钥单独保存在当前 macOS 用户目录（权限 0600）。换机、丢失本机加密密钥或从钥匙串版本升级时，请重新输入 API Key。账户需要能调用 whisper-1 和 gpt-4o-mini，服务费用计入自己的 OpenAI 账户。

先将光标置于目标输入框。按住按键说话，松开后等待识别、润色及粘贴。首次看到 OpenLess Recorder 请求麦克风权限时点击允许；若仍按住，录音继续。若已松开，重新按住再说。若看到「请在系统设置允许麦克风」，打开「系统设置 → 隐私与安全性 → 麦克风」开启 OpenLess Recorder 的权限。macOS「隐私与安全性 → 辅助功能」中允许负责粘贴的进程；未授权或前台应用发生变化时，请手动粘贴。每次输出会覆盖当前剪贴板。请保持目标输入框的焦点。

录音临时文件在正常结束、取消或出错时清理。录音发往 api.openai.com，识别文本发送至同一服务润色。润色失败会保留原文，转写失败时按键显示错误。401 需更新密钥，429 请检查账户额度或稍后重试。一个插件同一时间处理一次听写，最长三分钟（含等待服务时间）。

基于 Open-Less/openless fork，图标来自上游 src-tauri/icons；许可见 LICENSE。WebSocket 库的许可见 node_modules/ws/LICENSE。源码在 https://github.com/chxdon9587/openless/tree/feat/ulanzi-mac-dictation/studio-plugin 。从源码构建时在插件目录运行 npm ci --omit=dev，在上级目录运行 bash build-helper.sh。

设备键按下后，屏幕底部显示状态浮窗。看到红色麦克风和计时即可说话；松开后依次显示转写、润色与结果，最后自动收起。

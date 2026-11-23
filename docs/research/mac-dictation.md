# macOS 按住听写插件可行性

核对基线为 OpenLess 的 `670a44a` 和 Studio JS 插件协议 V3.1.0。首版建议由 Studio 的 Node 主服务接收按键，随包提供一个 macOS 原生辅助程序收音、访问钥匙串和投递文本。使用者无需安装或启动 OpenLess。以下为设计建议，尚未完成集成或真机验收。

## 从按下到写入

1. 使用 Keypad 动作。按 `keydown` 为该 `actionid` 创建一次录音，按匹配的 `keyup` 停止并提交一次。忽略重复按下和迟到的松开，设备断线、宿主退出或录音超时时取消。避免再用 `run` 启动同一动作。使用 `setTitle` 提示录音、处理、权限错误时，宿主最低版本设为 3.3.0。[Studio 协议](https://github.com/UlanziTechnology/ulanzi-plugin-skill/blob/main/skills/ulanzi-plugin/references/js-plugin-protocol-V3.1.0.md) · [版本说明](https://github.com/UlanziTechnology/ulanzi-plugin-skill/blob/main/skills/ulanzi-plugin/references/protocol-v3.1-notes.md)
2. 参考上游 cpal 录音线程及下混、重采样算法，输出 16 kHz 单声道有符号 16 位 PCM。桌面录音器包含宿主诊断和设备管理依赖，迁移时仅取需要的部分。已有批量 ASR 客户端可作为适配入口，结束时将 PCM 编为 WAV。首版宜限制时长并在取消或完成时释放缓冲区。[录音器](../../openless-all/app/src-tauri/src/recorder.rs) · [Whisper 客户端](../../openless-all/app/crates/openless-core/src/asr/whisper.rs) · [WAV 编码](../../openless-all/app/crates/openless-core/src/asr/wav.rs)
3. 云端首选一条可单独验证的路径。用户提供 OpenAI API key，松开后以 multipart 将 WAV 发至 `POST /v1/audio/transcriptions`（例如 `whisper-1`），再将转写正文发送到 `POST /v1/chat/completions`，使用该账户已开通的文本模型纠正口误和标点。参考上游提示词对口述内容进行数据封装，保留原意，禁止执行口述中的指令。ASR 失败或返回空串时停止；润色失败、超时或返回空串时使用原始转写并提示降级。联网、模型可用性及中文效果仍需实测。[转写 API](https://developers.openai.com/api/docs/guides/speech-to-text) · [文本 API](https://platform.openai.com/docs/api-reference/chat/create) · [上游润色客户端](../../openless-all/app/crates/openless-core/src/polish.rs) · [提示词边界](../../openless-all/app/crates/openless-core/src/prompts.rs)
4. 辅助程序在开始时记住前台应用和焦点，写入前复核。可复用上游 macOS 插入流程：检查辅助功能与安全输入，写入剪贴板，使用 CoreGraphics 投递 ⌘V，再有条件地恢复原剪贴板。事件已投递只表明系统收到了按键；目标控件可能拒绝粘贴。焦点改变、密码框或安全输入开启时停止自动粘贴，允许用户主动复制。拒绝授予麦克风权限时不启动录音。[插入实现](../../openless-all/app/src-tauri/src/insertion.rs) · [上游权限指南](../../USAGE.zh.md)

## 凭据和分发

建议由辅助程序在独立的插件 Keychain service 下保存用户密钥，通过原生设置窗口录入；主服务和属性面板只读取配置状态。Studio 全局配置可存模型名称。只向所选供应商发送录音和转写，日志仅记阶段和错误类别。上游使用自己的 service `com.openless.app`，插件应建立自己的凭据项。[上游凭据说明](../../USAGE.zh.md) · [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain-services)

当前源码按 AGPL-3.0-only 发布。若复制、修改或分发受其覆盖的实现，应保留版权与许可声明，按许可证要求提供对应源码；另核对组件许可及修改说明。若项目需采用其他分发许可，可独立实现协议和系统接口，或向权利人取得授权。旧版 1.x 的 MIT 声明仅对应旧版本。[项目许可说明](../../README.zh.md#许可证) · [许可证第 4–6、13 节](../../LICENSE) · [组件署名](../ATTRIBUTION.md)

## 待验收

在实际 Studio 安装目录内运行签名插件，记录 Studio 版本、Mac 架构、macOS 版本和设备型号。检查首次授权时 TCC 显示的责任进程及重启后授权是否生效；分别在 TextEdit、浏览器和 Electron 编辑器验证中文选区替换、原剪贴板恢复及焦点改变；再覆盖拒权、快速连按、拔设备、切页、断网、无效 key 和润色超时。记录实际文字与按键提示，特别核对每次手势仅录一次、仅写入一次。调研未使用用户凭据，也未验证签名包、权限归属、云端调用或真机行为。[Studio 生命周期](https://github.com/UlanziTechnology/ulanzi-plugin-skill/blob/main/skills/ulanzi-plugin/references/plugin-workflow.md) · [上游使用指南](../../USAGE.zh.md)

# xj-AI 架构

## 数据流

```text
麦克风 ── AVAudioEngine ─┐       ┌─ Apple Speech（设备端累计文本）
                         ├─ PCM ─┼─ whisper.cpp（本机固定分段） ─ 原文 ─ AIProviderStore ─ 译文
系统/应用 ─ ScreenCaptureKit ┘       └─ LAN ASR（OpenAI / whisper.cpp）       │
                                                                           │
                                                                SessionStore
                                                        │
                                              SessionPersistence
                                      JSON / CAF / SRT / VTT / TXT / MP3 / WAV
```

## 模块

- `MicrophoneCaptureService`：在用户开始录音后才创建 AVAudioEngine；把 PCM 同时送给本地识别与 CAF 写入器；
- `SystemAudioCaptureService`：使用 SCStream 的 audio output，不安装音频驱动；可以过滤到指定运行应用；
- `SpeechRecognitionService`：使用 `SFSpeechAudioBufferRecognitionRequest`，要求 `requiresOnDeviceRecognition = true`；
- `SpeechRecognitionStore`：持久化 Apple / 本地 Whisper / 局域网 ASR 选择，管理小模型下载、删除、测试和局域网凭据；
- `ChunkedSpeechRecognitionService`：把麦克风或系统音频持续转换为 16 kHz 单声道，按 2–8 秒配置串行提交，保持分段顺序；
- `LocalWhisperTranscriber`：调用 App 内静态 whisper.cpp helper，以 Accelerate/CPU 离线识别 GGML Q5 模型；
- `LANTranscriptionClient`：发送 WAV multipart 到 OpenAI `/v1/audio/transcriptions` 或 whisper.cpp `/inference`；
- `RecordingStore`：控制权限、录音阶段、计时、识别引擎路由、翻译请求、波形和导出状态；
- `AIProviderStore`：持久化 Provider、当前模型、目标语言与提示词，协调模型发现和翻译；
- `OpenAICompatibleClient`：调用 `/v1/models` 与 `/v1/chat/completions`，兼容 OpenAI、DeepSeek、Ollama、llama.cpp 和自定义服务；
- `KeychainStore`：用 macOS Keychain 保存每个 Provider 的 API Key；
- `SessionStore`：持有内存会话并将更改交给持久化层；
- `SessionPersistence`：原子写 JSON、CAF 文件命名；按原文、译文或双语导出 TXT/VTT/SRT，并将录音转换为 MP3/WAV；
- `SubtitleWindowController`：用可移动、可缩放的 AppKit `NSPanel` 承载 SwiftUI 实时字幕，并管理弹出、置顶、位置记忆和还原；
- `ContentView`：组合标题栏、侧栏、控制轨、时间轴、字幕画布、检查器与状态栏；窄窗口时控制轨换行，检查器切换为覆盖层。

## 权限时机

- App 启动：不申请麦克风、语音识别或屏幕录制权限；
- 选择“指定应用”：枚举可采集应用，macOS 可能检查屏幕录制权限；
- Apple Speech + 麦克风：申请语音识别与麦克风；
- 本地 Whisper / 局域网 ASR + 麦克风：只申请麦克风；
- 系统/应用音频：申请屏幕/系统音频录制；只有选择 Apple Speech 时另外申请语音识别。

失败的权限请求不会创建历史会话。只有识别与音频采集均成功启动后，才会建立会话记录。

## 识别切片

Apple Speech 会持续返回累计文本，而且可能修订前文用词或标点；系统音频流的识别时间戳还可能回退或重新起算。`RecordingStore` 保存最近已提交词语的规范化文本尾部，并用时间戳辅助选择重叠锚点。每约 3 秒从锚点之后切出一个 `TranscriptSegment`，带开始/结束时间并异步送给当前 AI Provider；完全没有文本重叠时按全新话语处理。识别最终结果会立即触发一次剩余文本提交。这样既不会重发累计全文，也不会因时间戳回退而停止输出。

本地 Whisper 与局域网 ASR 不使用累计文本。`SpeechPCMConverter` 在整次录音中复用同一个重采样器，将输入稳定转换为 16 kHz 单声道；`ChunkPipeline` 按用户选择的固定时长串行识别，每个结果直接形成一个独立时间轴片段，因此不会在后续重新提交或合并整段历史。

## 数据与隐私

- App 未启用 App Sandbox，方便本机开发阶段使用用户选择的保存目录；
- 默认翻译地址是 loopback `127.0.0.1`；
- 没有分析 SDK、遥测、账号或广告；云端 API Key 只存在 macOS 钥匙串；
- 用户选择局域网 ASR 时，音频分段会发送到用户配置的地址；选择局域网或云端翻译 Provider 时，原文会发送到相应地址，责任边界见 `PRIVACY.md`。

## 构建

工程是 SwiftPM GUI executable。`script/build_and_run.sh` 固定使用完整 Xcode 的匹配 Swift/SDK，关闭 SwiftPM 子沙箱，把缓存放到项目 `.build`，随后构造标准 `.app` bundle、写入 Info.plist、复制图标和静态 whisper.cpp helper，并进行 ad-hoc 深度签名。

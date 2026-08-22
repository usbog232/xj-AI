# AI Hear 实机调研与 xj-AI 重构依据

调研日期：2026-08-22

本次不是只阅读网页。已实际打开本机 `/Applications/AIHear.app`（AIHear 2.0.0），完成首次向导、内容库、实时字幕 HUD、文件转录入口和设置后台逐页点击。调研截图保存在项目外部，不随源码仓库上传：

```text
../aihear-research/screenshots/
```

## 实际确认的页面

### 首次向导

1. 转录模型：Qwen3 ASR 0.6B、Apple Speech Streaming、Qwen3 ASR 1.7B；
2. 内置样本验证，不用麦克风；本机测试 Apple Speech 时出现了 `Failed to create a new whisper context`；
3. 按用途组合权限：麦克风、系统音（屏幕录制权限）、跨应用听写；
4. 翻译与 AI：明确区分本机处理和联网服务。

### 内容库与实时字幕

- 内容库顶部有搜索、记录筛选、新建、设置、深色模式和界面语言；
- 新建包含“实时字幕”和“转录文件”；文件入口接受音频/视频；
- 实时字幕 HUD 可以切换麦克风、系统音源、转录模型、翻译语言和字幕显示；
- 翻译快捷菜单有关闭、润色、常用语言和更多语言；
- 字幕显示可调字号、背景不透明度，并明确提供原文、译文、双语三种模式。

### 设置后台

实际侧栏包含：

- 账户 / 升级；
- 音频 / 混音；
- 听写；
- AI Provider；
- 翻译；
- AI 功能；
- 本地模型；
- 高级；
- 关于。

AI Provider 是翻译与 AI 功能的共同底座，实际添加菜单包括 OpenAI、DeepSeek、MoonShot、OpenRouter、Groq、SiliconFlow、Ollama 和自定义。每个 Provider 具有 API Key、Base URL、模型发现、手动模型 ID、保存与测试。

翻译页并不直接保存 API Key，而是在 Provider 之上选择 Provider + 模型，再设置目标语言和 `{{targetLang}}` / `{{text}}` 提示词。这个分层是本次 xj-AI 重构的核心依据。

本地模型页同时管理 ASR 模型和内置 llama.cpp 翻译模型；实机展示的本地翻译模型为 Qwen3 4B Instruct。高级页包含本地 AI 空闲释放、VAD、性能追踪、代理和数据目录。

## xj-AI 采用的结构

- 保留现有 macOS 原生采音、Apple 设备端识别、时间轴和本地会话；
- 主窗口右上角增加明确齿轮，打开完整应用内设置后台；
- Provider 与翻译配置分层；
- Provider 模板：OpenAI、DeepSeek、Ollama、llama.cpp、自定义；
- 本机或局域网 llama.cpp 通过 OpenAI 兼容 `/v1` 地址接入；
- 云端 API Key 保存到 macOS Keychain；
- 模型列表支持服务端发现和手动输入；
- 翻译提示词可编辑并可直接测试。

## 有意保留的差异

- xj-AI 已加入独立实现的 Whisper Tiny/Base/Small Q5 下载、选择、测试和删除；暂未加入 AI Hear 的 Qwen3 ASR、SenseVoice 与 Parakeet 引擎；
- xj-AI 不复制 AI Hear 的代码、品牌、订阅或 15 分钟限制；
- xj-AI 当前接入外部 llama.cpp/Ollama 服务，不在 App 内嵌 llama.cpp 可执行文件与 GGUF 下载器；
- AI Hear 的公开 GitHub 仓库是文档站，不是桌面应用源码。

## 参考

- [AI Hear 官网](https://hear.thucydides.net/zh-cn/)
- [AI Hear 公开文档仓库](https://github.com/lwtlab/hear)

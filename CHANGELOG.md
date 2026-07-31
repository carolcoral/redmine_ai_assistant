# Changelog

All notable changes to the Redmine AI Assistant project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] — 2026-07-31

### Added (新增)

#### AI 能力核心枢纽 (AI Capability Hub)

- **模块级公开 API (`AiAssistant`)** — 一行调用即可完成 AI 对话，自动解析服务商、处理认证与错误。
  - `AiAssistant.chat` / `AiAssistant.chat_stream` / `AiAssistant.chat_messages`
  - `AiAssistant.enabled?` / `AiAssistant.ready?` / `AiAssistant.available_providers` / `AiAssistant.default_provider`
- **Mixin 混入模块 (`AiAssistant::Mixins::AiCapable`)** — 其他 Redmine 插件通过 `include` 即可零配置获得 AI 能力。
  - 提供 `ai_chat` / `ai_chat_messages` / `ai_chat_stream` / `ai_ready?` 方法
- **流式响应支持 (SSE)** — 基于 Server-Sent Events 的 `chat_stream` 回调接口
- **向后兼容** — 保留原始 `AiClient` 类作为薄封装

#### 端点用户功能 (End-User Features)

- **悬浮聊天组件** — 右下角可拖拽的 AI 对话气泡
  - Markdown 渲染、语法高亮、表格支持
  - 对话历史持久化，可配置上下文窗口大小
  - 快捷提问模板（一键发送常用查询）
- **工作报告生成** — 一键生成日报 / 周报 / 月报
  - 基于真实活动数据：工时记录、任务变更、评论、Wiki 更新
  - AI 总结为结构化 Markdown 文档
- **智能数据注入** — 自动检测任务/报告类查询，将真实 Redmine Issue 数据作为上下文注入
  - 支持 `#123` 任务编号引用
  - 关键词触发（任务、问题、状态、优先级等）

#### 管理员功能 (Admin Features)

- **多服务商管理** — 配置多个 AI 后端
  - 支持 `tdp`（TDP 平台集成）和 `custom`（任意 OpenAI 兼容接口）
  - 兼容 OpenAI、DeepSeek、Ollama、vLLM 等
  - 一键自动获取可用模型列表
- **只读守卫提示 (`GuardPrompt`)** — 涉及业务数据时自动限制 AI 为只读分析模式
- **自定义系统提示词** — 定义组织级 AI 行为规范
- **用量统计仪表板** — 按用户统计 Token 消耗量和调用次数
  - CSV / PDF 导出功能
- **API 密钥加密** — 采用 AES-256-CBC 加密存储服务商凭证

#### REST API 接口

| 模块 | 接口 | 说明 |
|------|------|------|
| 聊天 | `POST /ai_assistant/chat/send_message` | 发送消息 |
| 聊天 | `GET /ai_assistant/chat/history` | 获取对话历史 |
| 聊天 | `GET /ai_assistant/chat/clear` | 清除会话 |
| 报告 | `GET /ai_assistant/reports/daily` | 今日日报 |
| 报告 | `GET /ai_assistant/reports/weekly` | 本周周报 |
| 报告 | `GET /ai_assistant/reports/monthly` | 本月月报 |
| 报告 | `POST /ai_assistant/reports/generate` | 自定义报告 |
| 统计 | `GET /ai_assistant/stats` | 用量统计仪表板 |
| 统计 | `GET /ai_assistant/stats/export` | 导出统计 |

#### 数据库

- `ai_providers` — AI 服务商配置表（名称、标识、类型、API 地址、加密密钥、模型列表等）
- `ai_messages` — AI 消息持久化表（用户、会话、角色、内容、Token 消耗量等）

#### 国际化

- 中文 (`zh.yml`) 和 English (`en.yml`) 完整本地化支持

#### CI/CD

- `.cnb.yml` — CNB 流水线配置（GitHub 同步推送）
- `.cnb/web_trigger.yml` — 分支详情页「推送到 GitHub」按钮

### Requirements (环境要求)

- Redmine >= 6.1.0
- Ruby >= 3.2.0
- 至少一个 OpenAI 兼容的 AI 服务商

---

[1.1.0]: https://cnb.cool/xindu.site/redmine_ai_assistant/-/tags/v1.1.0

# Changelog

本文件记录 **Redmine AI Assistant** 的版本变更历史。

- 格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)
- 版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)
- 版本分类：`Added` 新增 / `Changed` 变更 / `Fixed` 修复 / `Removed` 移除

## [1.1.1] - 2026-08-17

### Added
- **支持按指定指派人统计任务**：`统计<姓名/工号>...` 语法（兼容全角 `＜＞`）
  - 管理员可统计任意用户的任务；普通用户仅可统计本人
  - 非管理员查询他人时，AI 按权限策略礼貌拒绝并引导联系管理员
  - 新增权限拒绝强制中文回复模板与 FOCUS RULE，杜绝 AI 越权输出数据或编造统计
- 新增 i18n 文案：`error_ai_not_configured_for_user`、`hint_ai_send_btn_disabled`

### Changed
- 用户消息改为纯文本渲染（保留尖括号语法原文），不再走完整 Markdown 渲染
- 前端错误消息不再写入 localStorage，避免旧错误残留到下次会话
- 发送按钮在 AI 未就绪时禁用并显示提示（`data-ai-ready` 前端兜底 + 服务端 503 预检双保险）

### Fixed
- **修复 AI 返回无关用户名（历史对话"串台"）**：Permission Denied 文案中字符串插值写法错误（`{target_user.name}` 未插值），导致 AI 用历史对话中的其他名字填补
- **修复普通用户显示「内部错误: API key not configured」**：服务端预检 + 友好提示「请联系管理员」，职责分离
- **修复 `<姓名/工号>` 尖括号语法在消息气泡中被吞掉**：`renderMarkdown` 把 `<admin>` 当未知 HTML 标签处理
- **修复视图模板 `uninitialized constant AiProvider`**：改用完整命名空间 `AiAssistant::AiProvider`
- **修复聊天头像渲染崩坏（HTML 属性转义）**：`ActiveSupport::SafeBuffer` 需先 `.to_str` 再转义，并改用 `<template>` 传递
- **修复编辑 AI 服务商时 API Key 被清空**：编辑页不再回显密钥明文（安全），留空则保留原值；保存时空密钥不再覆盖已存密钥；「自动获取模型」在编辑时留空密钥也能回退使用已保存的密钥

## [1.1.0] - 2026-07-30

### Added
- **统一 AI 能力层（AI Capability Hub）**：
  - 模块级 API：`AiAssistant.chat` / `AiAssistant.chat_messages` / `AiAssistant.chat_stream` / `AiAssistant.ready?`
  - 面向其他插件的 Mixin 模块：`AiAssistant::Mixins::AiCapable`（提供 `ai_chat` / `ai_chat_stream` 等）
  - 客户端实例 API：provider 指定、温度、超时、`linkify` 等高级选项
- 多个审计日志字段（记录消息归属的服务商快照等）
- 任务上下文时间范围统计增强（支持按周期/时间段聚合）

### Changed
- 保留 `AiClient` 作为向后兼容的薄封装

## [1.0.0] - 2026-07-23

### Added
- 初始发布
- **悬浮聊天组件**：右下角可拖拽 AI 对话气泡，支持 Markdown 渲染、语法高亮、表格
- **工作报告生成**：基于真实活动数据（工时、任务变更、评论、Wiki 更新）一键生成日报 / 周报 / 月报
- **智能数据注入**：自动检测任务 / 报告类查询并注入真实 Redmine 数据
- **对话历史**：持久化聊天记录，可配置上下文窗口（1–50 条）
- **多服务商管理**：支持 OpenAI、DeepSeek、Ollama、vLLM 等任意 OpenAI 兼容接口
- **API 密钥加密**：AES-256-CBC 静态加密存储
- **只读守卫提示**：涉及业务数据时限制 AI 为只读分析模式
- **用量统计**：按用户统计 Token 消耗与调用次数，支持 CSV/PDF 导出
- **模型自动获取**：一键从 `/models` 接口拉取可用模型列表
- **自定义提示词**：组织级系统提示词 + 插件级自定义头像 / 图标

<div align="center">

# 🤖 Redmine AI 助手

**Redmine 统一 AI 能力核心枢纽** — 为整个 Redmine 系统提供标准化 AI 接口，允许任何插件零配置接入 AI 功能。

![Version](https://img.shields.io/badge/Version-1.1.1-2ea44f)
![Redmine](https://img.shields.io/badge/Redmine-%3E%3D%206.1.0-4a90d9)
![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.2.0-e4405f)
![Plugin](https://img.shields.io/badge/Plugin-OpenAI%20Compatible-8c8c8c)

> :us: [English Documentation](README.md)

</div>

---

## 📑 目录

- [✨ 功能特性](#-功能特性)
- [📌 环境要求](#-环境要求)
- [🚀 快速开始](#-快速开始)
- [⚙️ 配置](#️-配置)
- [💡 使用指南](#-使用指南)
- [🏗️ 技术架构](#️-技术架构)
- [🔌 API 接口](#-api-接口)
- [🗄️ 数据库表结构](#️-数据库表结构)
- [🛠️ 开发指南](#️-开发指南)
- [📄 开源许可](#-开源许可)

---

## ✨ 功能特性

### 👤 面向最终用户

| 能力 | 说明 |
|---|---|
| 💬 **悬浮聊天组件** | 右下角可拖拽的 AI 对话气泡，支持 Markdown 渲染、语法高亮和表格 |
| 📊 **工作报告生成** | 一键生成日报 / 周报 / 月报，基于真实活动数据（工时、任务变更、评论、Wiki 更新） |
| 🧠 **智能数据注入** | 自动检测任务 / 报告类查询，将真实 Redmine 数据作为上下文注入 |
| 🕘 **对话历史** | 持久化的聊天记录，可配置上下文窗口大小 |
| ⚡ **快捷提问模板** | 常用查询一键发送 |

### 🛡️ 面向管理员

| 能力 | 说明 |
|---|---|
| 🏢 **多服务商管理** | 配置多个 AI 后端（OpenAI、DeepSeek、Ollama、vLLM 等任意 OpenAI 兼容接口） |
| 🔒 **只读守卫提示** | 涉及业务数据时自动限制 AI 为只读分析模式 |
| 🧾 **自定义系统提示词** | 定义组织级的 AI 行为规范 |
| 📈 **用量统计** | 按用户统计 Token 消耗量和调用次数，支持 CSV / PDF 导出 |
| 🔐 **API 密钥加密** | 采用 AES-256-CBC 加密存储服务商凭证 |

### 🧩 面向开发者（AI 能力枢纽）

| 能力 | 说明 |
|---|---|
| ⚙️ **模块级 API** | 一行调用：`AiAssistant.chat("你好")` |
| 🔌 **Mixin 混入** | `include AiAssistant::Mixins::AiCapable` 即可获得 `ai_chat` / `ai_chat_stream` 等能力 |
| 🎯 **深度封装** | 服务商选择、认证、错误处理、链接转换对调用方完全透明 |
| 🌊 **流式支持** | 基于 SSE 的 `chat_stream` 回调接口 |
| 🧳 **向后兼容** | 保留原始 `AiClient` 类作为薄封装 |

---

## 📌 环境要求

| 组件 | 要求 |
|---|---|
| Redmine | `>= 6.1.0` |
| Ruby | `>= 3.2.0` |
| AI 服务 | 至少一个 OpenAI 兼容接口的服务商 |

---

## 🚀 快速开始

1. **复制插件目录**

   将插件目录放置到 `plugins/redmine_ai_assistant`

2. **运行数据库迁移**

   ```bash
   bundle exec rake redmine:plugins:migrate RAILS_ENV=production
   ```

3. **重启 Redmine**

4. **启用插件**

   进入 **管理 → 插件 → Redmine AI Assistant → 配置** 启用

---

## ⚙️ 配置

### 🛠️ 插件设置

进入 **管理 → 插件 → Redmine AI Assistant → 配置**：

| 设置项 | 默认值 | 说明 |
|---|---|---|
| 启用 AI 助手 | 关闭 | 为已登录用户启用悬浮聊天组件 |
| 默认 AI 服务商 | (无) | 聊天和报告使用的默认 AI 服务商 |
| 启用只读守卫提示 | 开启 | 涉及业务数据时将 AI 限制为只读分析模式 |
| 自定义系统提示词 | (空) | 每次 AI 调用前注入的自定义提示词 |
| 最大历史消息数 | 20 | 对话上下文中保留的历史消息数量（1–50） |
| 报告时区 | (空) | 报告周期计算的时区（如 `Asia/Shanghai`） |
| 自定义图标 URL | (空) | 自定义悬浮图标地址（PNG / JPG / GIF / APNG / WebP / SVG） |
| 图标大小 | 60 | 悬浮按钮尺寸（像素，40–120） |

### 🏢 AI 服务商管理

进入 **管理 → AI 服务商配置** 配置 AI 后端。

**服务商类型**：

- `tdp` — TDP 平台集成服务商
- `custom` — 任意 OpenAI 兼容接口（OpenAI、DeepSeek、Ollama、vLLM、通过代理的 Anthropic 等）

**必填字段**：

| 字段 | 说明 |
|---|---|
| 名称 | 展示名称 |
| 标识 | 唯一标识符（小写字母、数字、连字符、下划线） |
| 服务商类型 | `tdp` 或 `custom` |
| API 地址 | 完整基础 URL（如 `https://api.openai.com/v1`） |
| API 密钥 | 认证密钥（加密存储） |
| 默认模型 | 模型名称（如 `gpt-4o-mini`） |

**可选字段**：

| 字段 | 说明 |
|---|---|
| 可用模型列表 | JSON 数组 — 点击「自动获取」按钮从 API 拉取 |
| 扩展配置 | JSON 对象，服务商特定参数（如 `top_p`、`frequency_penalty`） |
| 排序 | 服务商列表排序权重 |

### 🔑 权限

| 权限 | 角色 | 说明 |
|---|---|---|
| 管理 AI 服务商 | 仅管理员 | 增删改查和启停 AI 服务商 |
| 使用 AI 聊天 | 已登录用户 | 使用悬浮聊天组件 |
| 生成 AI 报告 | 已登录用户 | 生成工作报告 |
| 查看 AI 统计 | 仅管理员 | 查看用量统计仪表板 |

---

## 💡 使用指南

### 💬 AI 聊天

1. 点击右下角悬浮图标打开聊天面板
2. 询问有关项目、任务或工时的问题
3. 使用任务相关关键词时，助手会自动注入真实的 Redmine 数据
4. 使用快捷按钮一键获取摘要

> **触发关键词**（需命中 2 个以上才会触发数据注入）：任务、问题、状态、优先级、进度、版本、截止、逾期、task、issue、status、priority 等。

也可以直接引用任务编号：`#123`、`#456`。

### 👥 统计指定指派人的任务

管理员可使用 `<姓名/工号>` 语法统计任意用户的全部任务，例如：

| 示例 | 说明 |
|---|---|
| `统计<邹悦>今年内的所有任务并生成报告` | 统计邹悦今年内的全部任务 |
| `统计<zhangwei>本月指派给他的任务` | 统计 zhangwei 本月的指派任务 |
| `统计<李娜>近30天的任务汇总` | 统计李娜近 30 天的任务 |

> **权限说明**：普通用户只能统计自己的任务；若尝试查询其他用户，助手会礼貌地拒绝并提示联系管理员。

统计包含**所有状态**（打开 / 已关闭）的任务，并输出按状态、项目、类型分布以及每月创建趋势的汇总数据。

### 📊 工作报告

通过 API 接口或聊天组件生成报告。生成器收集以下数据：

| 数据源 | 说明 |
|---|---|
| ⏱️ 工时记录 | 带项目、任务和活动详情的工时日志 |
| 📋 新分配任务 | 报告周期内新指派的任务 |
| 🔄 任务变更历史 | 完整的状态 / 优先级 / 指派人变更时间线 |
| ✅ 已关闭任务 | 周期内完成的任务 |
| 📌 状态汇总 | 未关闭任务按状态分布统计 |
| ⚠️ 逾期任务 | 超过截止日期但未关闭的任务 |
| 💬 评论记录 | 任务、Wiki、文档上的备注 |
| 📝 Wiki 更新 | 周期内编辑的 Wiki 页面 |

报告以 Markdown 格式生成，由 AI 总结为易读的结构化文档。

---

## 🏗️ 技术架构

```
redmine_ai_assistant/
├── init.rb                              # 插件注册、权限、设置
├── config/
│   ├── routes.rb                        # API 路由
│   └── locales/                         # 国际化（zh.yml, en.yml）
├── app/
│   ├── controllers/ai_assistant/
│   │   ├── chat_controller.rb           # 聊天 API
│   │   ├── providers_controller.rb      # 服务商管理（管理员）
│   │   ├── reports_controller.rb        # 报告生成 API
│   │   └── stats_controller.rb          # 用量统计仪表板（管理员）
│   ├── models/ai_assistant/
│   │   ├── ai_provider.rb               # 服务商模型（CRUD + 加密）
│   │   └── ai_message.rb                # 消息持久化
│   └── views/ai_assistant/              # ERB 模板
├── assets/
│   ├── javascripts/ai_assistant/
│   │   └── chat_widget_controller.js    # 原生 JS 聊天组件
│   └── stylesheets/ai_assistant/
│       ├── chat_widget.css              # 聊天组件样式
│       ├── providers.css                # 服务商表单样式
│       └── stats.css                    # 统计页样式
├── lib/ai_assistant/                    # ← AI 能力核心枢纽
│   ├── client.rb                        # 核心 AI 客户端（HTTP / SSL / 解析 / 流式）
│   ├── ai_client.rb                     # 向后兼容包装
│   ├── guard_prompt.rb                  # 只读守卫提示注入
│   ├── hooks.rb                         # Redmine 视图钩子
│   ├── report_generator.rb              # 工作报告引擎
│   └── mixins/
│       └── ai_capable.rb                # 给其他插件使用的 Mixin 模块
└── db/migrate/                          # 数据库迁移
```

### ⚙️ AI 能力枢纽 — 公开 API

```ruby
# === 模块级 API（推荐使用） ===

# 状态检查
AiAssistant.enabled?            # 插件是否在设置中启用
AiAssistant.ready?              # 已启用且有可用服务商
AiAssistant.available_providers # 可用服务商列表
AiAssistant.default_provider    # 默认服务商实例

# 简单对话（自动解析服务商）
result = AiAssistant.chat("分析问题 #123")
# => { content: "...", role: "assistant", model: "gpt-4o", tokens_used: 1234 }

# 带选项的调用
result = AiAssistant.chat("你好",
  provider:    "deepseek",      # 服务商标识或 ID
  model:       "deepseek-chat",
  temperature: 0.3,             # 采样温度（默认 0.7）
  max_tokens:  2048,            # 最大 token 数（默认 4096）
  system:      "你是一位代码审查员。"  # 系统提示词
)

# 多轮消息（原始格式）
AiAssistant.chat_messages([
  { role: "system", content: "你是一位乐于助人的助手。" },
  { role: "user",   content: "什么是敏捷开发？" }
])

# 流式对话
AiAssistant.chat_stream("写一首五言绝句") do |chunk|
  if chunk[:done]
    puts "\n--- 生成完成 ---"
  else
    print chunk[:content]
  end
end

# 错误处理
result = AiAssistant.chat("你好")
if result[:error]
  puts "AI 错误: #{result[:error]}"
else
  puts result[:content]
end
```

### 🧰 Client 实例 API（高级用法）

```ruby
client = AiAssistant.client(
  provider:    my_provider_instance,
  model:       "gpt-4",
  temperature: 0.5,             # 默认 0.7
  max_tokens:  4096,            # 默认 4096
  timeout:     120,             # 读取超时（秒），默认 120
  linkify:     true             # 自动将 #ID 转为 issue 链接，默认 true
)

result = client.chat(messages)
client.chat_stream(messages) { |chunk| ... }
```

### 🔌 给其他插件使用的 Mixin

```ruby
# 在你的插件中：
require 'ai_assistant/mixins/ai_capable'

class MyFeatureController < ApplicationController
  include AiAssistant::Mixins::AiCapable

  def analyze
    # 自动使用系统默认服务商
    result = ai_chat("分析 #{Issue.find(params[:id]).subject}")

    if result[:error]
      flash[:error] = result[:error]
      redirect_back fallback_location: home_path
    else
      @analysis = result[:content]
    end
  end

  def translate_stream
    # 流式响应给客户端
    ai_chat_stream("翻译：#{params[:text]}") do |chunk|
      ActionCable.server.broadcast("stream_#{current_user.id}", chunk)
    end
  end
end
```

> **Mixin 提供的方法**：`ai_chat`、`ai_chat_messages`、`ai_chat_stream`、`ai_ready?`

---

## 🔌 API 接口

> 所有接口需要认证（会话或 API Key）。

### 💬 聊天

| 方法 | 接口 | 说明 |
|---|---|---|
| POST | `/ai_assistant/chat/send_message` | 发送消息，获取 AI 回复 |
| GET | `/ai_assistant/chat/history` | 获取对话历史 |
| GET | `/ai_assistant/chat/clear` | 清除会话 |

**发送消息 — 请求体：**

```json
{
  "message": "我今天有哪些任务？",
  "conversation_id": "可选-uuid"
}
```

**发送消息 — 响应：**

```json
{
  "conversation_id": "abc-123",
  "message": {
    "id": 42,
    "role": "assistant",
    "content": "你今天有 3 个待办任务：\n\n- [#101](/issues/101) ...",
    "tokens_used": 1234
  }
}
```

### 📊 报告

| 方法 | 接口 | 说明 |
|---|---|---|
| GET | `/ai_assistant/reports/daily` | 今日日报 |
| GET | `/ai_assistant/reports/weekly` | 本周周报 |
| GET | `/ai_assistant/reports/monthly` | 本月月报 |
| POST | `/ai_assistant/reports/generate` | 自定义报告 |

**生成报告 — 请求体：**

```json
{
  "report_type": "weekly",
  "period_offset": "-1",
  "provider_id": "可选-服务商-id"
}
```

> `period_offset`：`0` = 当前周期，`-1` = 上一周期（昨日 / 上周 / 上月）。

### 📈 管理统计

| 方法 | 接口 | 说明 |
|---|---|---|
| GET | `/ai_assistant/stats` | 用量统计仪表板（HTML） |
| GET | `/ai_assistant/stats/export` | 导出统计（CSV 或 PDF） |

---

## 🗄️ 数据库表结构

### `ai_providers`（AI 服务商）

| 列名 | 类型 | 说明 |
|---|---|---|
| `name` | string | 服务商展示名称 |
| `slug` | string | 唯一标识 |
| `provider_type` | string | 类型：`tdp` 或 `custom` |
| `api_url` | string | API 基础地址 |
| `api_key` | text | AES-256-CBC 加密密钥 |
| `default_model` | string | 默认模型名称 |
| `available_models` | text | 可用模型列表（JSON 数组） |
| `settings` | text | 扩展配置（JSON） |
| `is_enabled` | boolean | 启用状态 |
| `is_builtin` | boolean | 是否内置 |
| `position` | integer | 排序权重 |

### `ai_messages`（AI 消息）

| 列名 | 类型 | 说明 |
|---|---|---|
| `user_id` | integer | 用户外键 |
| `ai_provider_id` | integer | 服务商外键 |
| `conversation_id` | string | 会话分组 UUID |
| `role` | string | 角色：`user` 或 `assistant` |
| `content` | text | 消息内容 |
| `model` | string | 使用的 AI 模型 |
| `tokens_used` | integer | Token 消耗量 |
| `report_type` | string | 报告类型：`daily` / `weekly` / `monthly` |
| `ai_provider` | string | 服务商名称快照 |

---

## 🛠️ 开发指南

### 🏢 添加新的 AI 服务商

1. 进入 **管理 → AI 服务商配置 → 新建服务商**
2. 填写任意 OpenAI 兼容接口的 API 地址和密钥
3. 可选：点击「自动获取」按钮获取可用模型列表
4. 需要在插件设置中设为默认服务商

### 📊 扩展报告数据

`ReportGenerator#collect_data` 方法返回完整数据哈希。要添加新数据源：

1. 在 `report_generator.rb` 中添加 `fetch_*` 方法
2. 在 `collect_data` 中注册新的 key
3. 在 `build_user_prompt` 中追加对应数据段
4. 在 `build_system_prompt` 中更新格式化指引

### 🧩 从其他插件调用 AI 能力

```ruby
# 零配置：使用系统默认服务商
result = AiAssistant.chat("总结项目状态")

# 指定服务商
result = AiAssistant.chat("你好", provider: "deepseek")

# 使用 Mixin（推荐用于控制器 / 模型）
include AiAssistant::Mixins::AiCapable
result = ai_chat("你好")
```

### 🧾 自定义提示词

在插件配置中使用「自定义系统提示词」设置。它会注入到每次 AI 调用中，可用于：

- 限定 AI 回答领域
- 定义输出格式规范
- 执行公司特定策略

---

## 📄 开源许可

本项目属于 Redmine 生态。详见主项目许可证。

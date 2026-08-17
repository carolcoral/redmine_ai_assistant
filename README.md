<div align="center">

# 🤖 Redmine AI Assistant

**Unified AI Capability Hub for Redmine** — provides a standardized AI interface for the entire system, allowing any Redmine plugin to integrate AI features with zero configuration.

![Version](https://img.shields.io/badge/Version-1.1.1-2ea44f)
![Redmine](https://img.shields.io/badge/Redmine-%3E%3D%206.1.0-4a90d9)
![Ruby](https://img.shields.io/badge/Ruby-%3E%3D%203.2.0-e4405f)
![Plugin](https://img.shields.io/badge/Plugin-OpenAI%20Compatible-8c8c8c)

> :cn: [中文文档](README.zh.md)

</div>

---

## 📑 Table of Contents

- [✨ Features](#-features)
- [📌 Requirements](#-requirements)
- [🚀 Quick Start](#-quick-start)
- [⚙️ Configuration](#️-configuration)
- [💡 Usage](#-usage)
- [🏗️ Architecture](#️-architecture)
- [🔌 API Reference](#-api-reference)
- [🗄️ Database Schema](#️-database-schema)
- [🛠️ Development](#️-development)
- [📄 License](#-license)

---

## ✨ Features

### 👤 For End Users

| Capability | Description |
|---|---|
| 💬 **Floating Chat Widget** | Draggable AI chat bubble in the bottom-right corner with Markdown rendering, syntax highlighting, and table support |
| 📊 **Work Report Generation** | One-click daily / weekly / monthly reports based on real activity data (time entries, issue changes, comments, wiki updates) |
| 🧠 **Smart Data Injection** | Automatically detects task / report queries and injects real Redmine issue data as context |
| 🕘 **Conversation History** | Persistent chat history with a configurable context window |
| ⚡ **Quick-Action Templates** | Common queries available as one-click buttons |

### 🛡️ For Admins

| Capability | Description |
|---|---|
| 🏢 **Multi-Provider Management** | Configure multiple AI backends (OpenAI, DeepSeek, Ollama, vLLM, or any OpenAI-compatible API) |
| 🔒 **Read-Only Guard Prompt** | Automatically restricts AI to analysis-only mode when business data is involved |
| 🧾 **Custom System Prompts** | Define organization-wide AI behavior rules |
| 📈 **Usage Statistics** | Token consumption and call frequency per user, with CSV / PDF export |
| 🔐 **Encrypted API Keys** | AES-256-CBC encryption at rest for provider credentials |

### 🧩 For Developers (as AI Hub)

| Capability | Description |
|---|---|
| ⚙️ **Module-Level API** | One-line calls: `AiAssistant.chat("Hello")` |
| 🔌 **Mixin Module** | `include AiAssistant::Mixins::AiCapable` gives any class `ai_chat` / `ai_chat_stream` methods |
| 🎯 **Deep Encapsulation** | Provider selection, authentication, error handling, and linkification are hidden from callers |
| 🌊 **Streaming Support** | SSE-based `chat_stream` with callback blocks |
| 🧳 **Backward Compatible** | The original `AiClient` class is preserved as a thin wrapper |

---

## 📌 Requirements

| Component | Requirement |
|---|---|
| Redmine | `>= 6.1.0` |
| Ruby | `>= 3.2.0` |
| AI Service | At least one OpenAI-compatible provider |

---

## 🚀 Quick Start

1. **Copy the plugin directory**

   Place the plugin into `plugins/redmine_ai_assistant`

2. **Run database migrations**

   ```bash
   bundle exec rake redmine:plugins:migrate RAILS_ENV=production
   ```

3. **Restart Redmine**

4. **Enable the plugin**

   Go to **Administration → Plugins → Redmine AI Assistant → Configure**

---

## ⚙️ Configuration

### 🛠️ Plugin Settings

Go to **Administration → Plugins → Redmine AI Assistant → Configure**:

| Setting | Default | Description |
|---|---|---|
| Enable AI Assistant | Off | Enables the floating chat widget for logged-in users |
| Default AI Provider | (None) | The default AI provider for chat and reports |
| Enable Read-Only Guard Prompt | On | Restricts AI to analysis-only when business data is involved |
| Custom System Prompt | (Empty) | Custom prompt injected before every AI call |
| Max History Messages | 20 | Previous messages to keep in conversation context (1–50) |
| Report Timezone | (Empty) | Timezone for report period calculation (e.g. `Asia/Shanghai`) |
| Custom Pet Image URL | (Empty) | Custom floating icon URL (PNG / JPG / GIF / APNG / WebP / SVG) |
| Icon Size | 60 | Floating button size in pixels (40–120) |

### 🏢 AI Service Providers

Go to **Administration → AI Service Providers** to configure AI backends.

**Provider Types**:

- `tdp` — TDP platform integrated provider
- `custom` — Any OpenAI-compatible API (OpenAI, DeepSeek, Ollama, vLLM, Anthropic via proxy, etc.)

**Required Fields**:

| Field | Description |
|---|---|
| Name | Display name |
| Slug | Unique identifier (lowercase, digits, hyphens, underscores) |
| Provider Type | `tdp` or `custom` |
| API URL | Full base URL (e.g. `https://api.openai.com/v1`) |
| API Key | Authentication key (encrypted at rest) |
| Default Model | Model name (e.g. `gpt-4o-mini`) |

**Optional Fields**:

| Field | Description |
|---|---|
| Available Models | JSON array — use the **Auto Fetch** button to retrieve from `/models` endpoint |
| Extra Settings | JSON object for provider-specific parameters (e.g. `top_p`, `frequency_penalty`) |
| Position | Sort order for provider list |

### 🔑 Permissions

| Permission | Access | Description |
|---|---|---|
| Manage AI Providers | Admin only | CRUD and enable / disable AI providers |
| Use AI Chat | Logged-in users | Access the floating chat widget |
| Generate AI Reports | Logged-in users | Generate work reports |
| View AI Stats | Admin only | View usage statistics dashboard |

---

## 💡 Usage

### 💬 AI Chat

1. Click the floating icon (bottom-right corner) to open the chat panel
2. Ask questions about your projects, tasks, or time entries
3. The assistant automatically injects real Redmine data when you use task-related keywords
4. Use quick-action buttons for one-click summaries

> **Trigger keywords** (at least 2 needed to trigger data injection): task, issue, status, priority, progress, version, due date, overdue, 任务, 项目, etc.

You can also reference issues directly by ID: `#123`, `#456`.

### 👥 Statistics for a Specific Assignee

Administrators can use the `<name/employee ID>` syntax to generate statistics for any user's tasks:

| Example | Description |
|---|---|
| `统计<邹悦>今年内的所有任务并生成报告` | All tasks assigned to 邹悦 this year |
| `统计<zhangwei>本月指派给他的任务` | Tasks assigned to zhangwei this month |
| `统计<李娜>近30天的任务汇总` | Task summary for 李娜 over the last 30 days |

> **Permission note**: Regular users can only generate statistics for themselves; when they try to query another user, the assistant will politely decline and suggest contacting an administrator.

Statistics cover tasks in **all statuses** (open and closed) and include a summary with distributions by status, project, tracker, plus a monthly creation trend.

### 📊 Work Reports

Reports are generated via API endpoints or from the chat widget. The generator collects:

| Data Source | Description |
|---|---|
| ⏱️ Time Entries | Hours logged with project, issue, and activity details |
| 📋 Issues Assigned | New tasks assigned during the report period |
| 🔄 Issue Change History | Full timeline of status / priority / assignee changes |
| ✅ Issues Closed | Tasks completed during the period |
| 📌 Status Summary | Distribution of open issues by status |
| ⚠️ Overdue Issues | Tasks past due date but not closed |
| 💬 Comments | Notes on issues, wiki pages, documents |
| 📝 Wiki Updates | Pages edited during the period |

Reports are generated in Markdown with structured sections, summarized by AI.

---

## 🏗️ Architecture

```
redmine_ai_assistant/
├── init.rb                              # Plugin registration, permissions, settings
├── config/
│   ├── routes.rb                        # API routes
│   └── locales/                         # zh.yml, en.yml
├── app/
│   ├── controllers/ai_assistant/
│   │   ├── chat_controller.rb           # Chat API
│   │   ├── providers_controller.rb      # Provider CRUD (admin)
│   │   ├── reports_controller.rb        # Report generation API
│   │   └── stats_controller.rb          # Usage stats dashboard (admin)
│   ├── models/ai_assistant/
│   │   ├── ai_provider.rb               # Provider model (CRUD + encryption)
│   │   └── ai_message.rb                # Message persistence
│   └── views/ai_assistant/              # ERB templates
├── assets/
│   ├── javascripts/ai_assistant/
│   │   └── chat_widget_controller.js    # Vanilla JS chat widget
│   └── stylesheets/ai_assistant/
│       ├── chat_widget.css              # Chat widget styles
│       ├── providers.css                # Provider form styles
│       └── stats.css                    # Stats dashboard styles
├── lib/ai_assistant/                    # ← AI Capability Hub
│   ├── client.rb                        # Core AI client (HTTP / SSL / parsing / streaming)
│   ├── ai_client.rb                     # Backward-compatible wrapper
│   ├── guard_prompt.rb                  # Read-only guard prompt injection
│   ├── hooks.rb                         # Redmine view hooks
│   ├── report_generator.rb              # Work report engine
│   └── mixins/
│       └── ai_capable.rb                # Mixin module for other plugins
└── db/migrate/                          # Schema migrations
```

### ⚙️ AI Capability Hub — Public API

```ruby
# === Module-Level API (recommended) ===

# Check readiness
AiAssistant.enabled?            # Plugin enabled in settings?
AiAssistant.ready?              # Enabled + has an active provider?
AiAssistant.available_providers # List of enabled AiProvider records
AiAssistant.default_provider    # The default provider instance

# Simple chat (auto-resolves provider)
result = AiAssistant.chat("Analyze issue #123")
# => { content: "...", role: "assistant", model: "gpt-4o", tokens_used: 1234 }

# With options
result = AiAssistant.chat("Hello",
  provider:    "openai",        # provider slug or ID
  model:       "gpt-4",
  temperature: 0.3,             # sampling temperature (default: 0.7)
  max_tokens:  2048,            # max tokens (default: 4096)
  system:      "You are a code reviewer."  # system prompt
)

# Multi-turn messages (raw format)
AiAssistant.chat_messages([
  { role: "system", content: "You are a helpful assistant." },
  { role: "user",   content: "What is Agile?" }
])

# Streaming
AiAssistant.chat_stream("Write a haiku") do |chunk|
  if chunk[:done]
    puts "\n--- finished ---"
  else
    print chunk[:content]
  end
end

# Error handling
result = AiAssistant.chat("Hello")
if result[:error]
  puts "AI error: #{result[:error]}"
else
  puts result[:content]
end
```

### 🧰 Client Instance API (Advanced)

```ruby
client = AiAssistant.client(
  provider:    my_provider_instance,
  model:       "gpt-4",
  temperature: 0.5,             # (default: 0.7)
  max_tokens:  4096,            # (default: 4096)
  timeout:     120,             # read timeout in seconds (default: 120)
  linkify:     true             # auto-link #ID to issue URLs (default: true)
)

result = client.chat(messages)
client.chat_stream(messages) { |chunk| ... }
```

### 🔌 Mixin for Other Plugins

```ruby
# In your plugin:
require 'ai_assistant/mixins/ai_capable'

class MyFeatureController < ApplicationController
  include AiAssistant::Mixins::AiCapable

  def analyze
    # Uses the system default provider automatically
    result = ai_chat("Analyze #{Issue.find(params[:id]).subject}")

    if result[:error]
      flash[:error] = result[:error]
      redirect_back fallback_location: home_path
    else
      @analysis = result[:content]
    end
  end

  def translate_stream
    # Streaming response to the client
    ai_chat_stream("Translate: #{params[:text]}") do |chunk|
      ActionCable.server.broadcast("stream_#{current_user.id}", chunk)
    end
  end
end
```

> **Mixin provides**: `ai_chat`, `ai_chat_messages`, `ai_chat_stream`, `ai_ready?`

---

## 🔌 API Reference

> All endpoints require authentication (session or API key).

### 💬 Chat

| Method | Endpoint | Description |
|---|---|---|
| POST | `/ai_assistant/chat/send_message` | Send message, get AI response |
| GET | `/ai_assistant/chat/history` | Get conversation history |
| GET | `/ai_assistant/chat/clear` | Clear a conversation |

**Send Message — request:**

```json
{
  "message": "What are my tasks today?",
  "conversation_id": "optional-uuid"
}
```

**Send Message — response:**

```json
{
  "conversation_id": "abc-123",
  "message": {
    "id": 42,
    "role": "assistant",
    "content": "Here are your tasks today:\n\n- [#101](/issues/101) ...",
    "tokens_used": 1234
  }
}
```

### 📊 Reports

| Method | Endpoint | Description |
|---|---|---|
| GET | `/ai_assistant/reports/daily` | Today's daily report |
| GET | `/ai_assistant/reports/weekly` | This week's weekly report |
| GET | `/ai_assistant/reports/monthly` | This month's monthly report |
| POST | `/ai_assistant/reports/generate` | Custom report |

**Generate Report — request:**

```json
{
  "report_type": "weekly",
  "period_offset": "-1",
  "provider_id": "optional-provider-id"
}
```

> `period_offset`: `0` = current period, `-1` = previous period (yesterday / last week / last month).

### 📈 Admin Stats

| Method | Endpoint | Description |
|---|---|---|
| GET | `/ai_assistant/stats` | Usage statistics dashboard (HTML) |
| GET | `/ai_assistant/stats/export` | Export stats as CSV or PDF |

---

## 🗄️ Database Schema

### `ai_providers`

| Column | Type | Description |
|---|---|---|
| `name` | string | Provider display name |
| `slug` | string | Unique identifier |
| `provider_type` | string | `tdp` or `custom` |
| `api_url` | string | API base URL |
| `api_key` | text | AES-256-CBC encrypted API key |
| `default_model` | string | Default model name |
| `available_models` | text | JSON array of model names |
| `settings` | text | JSON extra configuration |
| `is_enabled` | boolean | Enabled status |
| `is_builtin` | boolean | Built-in provider flag |
| `position` | integer | Sort order |

### `ai_messages`

| Column | Type | Description |
|---|---|---|
| `user_id` | integer | User FK |
| `ai_provider_id` | integer | Provider FK |
| `conversation_id` | string | Conversation group UUID |
| `role` | string | `user` or `assistant` |
| `content` | text | Message content |
| `model` | string | AI model used |
| `tokens_used` | integer | Token consumption |
| `report_type` | string | `daily`, `weekly`, `monthly` |
| `ai_provider` | string | Provider name snapshot |

---

## 🛠️ Development

### 🏢 Adding a New AI Provider

1. Go to **Administration → AI Service Providers → New Provider**
2. Fill in the API URL and key for any OpenAI-compatible service
3. Optionally use **Auto Fetch** to retrieve available model names
4. Set as default in Plugin Settings if desired

### 📊 Extending Report Data

The `ReportGenerator#collect_data` method returns a hash. To add new data sources:

1. Add a `fetch_*` method in `report_generator.rb`
2. Include the new key in `collect_data`
3. Add the corresponding section in `build_user_prompt`
4. Update `build_system_prompt` with formatting guidelines

### 🧩 Using the AI Hub from Other Plugins

```ruby
# Zero-config: uses the system's default provider
result = AiAssistant.chat("Summarize project status")

# With explicit provider selection
result = AiAssistant.chat("Hello", provider: "deepseek")

# With Mixin (preferred for controllers / models)
include AiAssistant::Mixins::AiCapable
result = ai_chat("Hello")
```

### 🧾 Customizing System Prompts

Use the **Custom System Prompt** setting in plugin configuration. It is prepended to every AI call, allowing you to:

- Restrict AI to specific domains
- Define output format conventions
- Enforce company policies

---

## 📄 License

This project is part of the Redmine ecosystem. See the main project license for details.

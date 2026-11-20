# 第三方 API 供应商与额度窗实验报告

- 日期：2026-11-19
- 分支：`joseph/dev`
- 版本：`0.8.2-dev.2`
- 后续验收：2026-11-20，用户确认模型摘要与第三方额度窗通过 P0 验收。[验收归档](../todo.md#p0-核心窗口与双通道交互回归)

## 实验结论

### Codex 基础指令与桌宠人设

在本轮任务模式实验中，Codex 按模型基础指令执行代码任务和工具调用。桌宠通过 app-server 的 `developerInstructions` 设置面向用户的回复语气。

### DeepSeek 余额查询

早期原型通过 `GET /user/balance` 取得余额。该接口使用 `Authorization: Bearer <API_KEY>` 认证，请求方需在运行内存 (RAM) 中持有明文 Key。本轮开发采用本机 Token 统计和官方平台入口。

实验也考察了由 DeepSeek Harness（DSH）代查余额的方案。DSH 提供凭据服务和本地插件，同一 macOS 用户下的进程可以读取其本地凭据文件。插件初始化失败会中止所属 profile 的启动。实验提出使用独立、固定版本的 sidecar profile 承载插件，进度停在方案阶段。

## 本轮实现

### DeepSeek 峰谷定价

- Codex 当前供应商为 DeepSeek 时，在本机今日 Token 用量下方显示当前时段与下一次切换时间。
- 北京时间工作日 9:00–12:00、14:00–18:00 为高峰，显示红色。其余时段、周末和中国法定节假日为空闲，显示绿色。
- 本版收录 2026、2027 年国务院放假安排。其他年份显示“时段未提供”。
- 峰谷切换和午夜更新取本机时间。气泡打开期间，时段变化只刷新显示。

### 供应商区域拆分

| 供应商 | 完整显示名 | 模型摘要短名 | 区域识别 |
| --- | --- | --- | --- |
| OpenAI | OpenAI | OpenAI | `api.openai.com` |
| DeepSeek | DeepSeek | DeepSeek | `api.deepseek.com` |
| xAI | xAI | xAI | `api.x.ai` |
| Mistral | Mistral AI | Mistral | `api.mistral.ai` |
| Kimi 中国站 | Kimi（中国站） | Kimi CN | `api.moonshot.cn` |
| Kimi 国际站 | Kimi（国际站） | Kimi Global | `api.moonshot.ai` |
| 智谱中国站 | 智谱 GLM（中国站） | 智谱 GLM | `open.bigmodel.cn` |
| Z.AI 国际站 | Z.AI GLM（国际站） | Z.AI | `api.z.ai` |
| 阿里云百炼北京 | 阿里云百炼（北京） | 百炼 CN | `{WorkspaceId}.cn-beijing.maas.aliyuncs.com` |
| 阿里云百炼新加坡 | 阿里云百炼（新加坡） | 百炼 SG | `{WorkspaceId}.ap-southeast-1.maas.aliyuncs.com` |
| OpenRouter | OpenRouter | OpenRouter | `openrouter.ai` |
| Groq | Groq | Groq | `api.groq.com` |
| Amazon Bedrock | Amazon Bedrock | Bedrock | AWS provider |
| Google Cloud Vertex AI | Google Cloud Vertex AI | Vertex AI | Google Cloud provider |

区域共用品牌图标，各自显示完整名称和官方账户入口。运行时供应商图标统一为 PNG；OpenRouter、Groq、Amazon Bedrock、Google Cloud Vertex AI 与阿里云百炼使用 LobeHub `lobe-icons` 社区重绘。

本机 Token 仍按原始 `model_provider` 值统计。需要区分区域历史用量时，Codex 配置应使用不同 provider ID，例如 `kimi-cn` 与 `kimi-global`、`zhipu-cn` 与 `zai-global`。

### 官方开放平台入口

额度气泡底栏的「打开供应商开放平台」指向目录收录的官方用量、充值、账户或计费页面。有官方地址时显示按钮。

供应商目录优先匹配 `base_url` 的主机。主机必须与目录域名相同，或以点号加目录域名结尾。主机未命中时按 provider ID、别名或完整名称回退。

| 第三方配置 | 气泡顶部名称 | 开放平台按钮 |
| --- | --- | --- |
| ID、名称、主机均未命中目录，例如 `my-proxy` 配合 `api.proxy.example.com` | Codex 配置名称，未填则显示原始 ID | 隐藏 |
| 自定义反代复用了已知 ID、别名或完整名称，例如 `deepseek` 配合 `proxy.example.com` | DeepSeek 等目录名称 | 有官方页面时显示。DeepSeek 打开官方用量页 |
| 使用已知官方主机，例如 `api.deepseek.com` | 主机对应的目录名称 | 有官方页面时显示 |

通用 `kimi` 在主机未命中区域时显示 Kimi，开放平台按钮隐藏。表中的链接均来自应用内目录，打开按钮和查询本机用量都不会向配置的反代主机发起请求。

| 供应商 | 当前官方入口 | 页面类型 |
| --- | --- | --- |
| DeepSeek | `https://platform.deepseek.com/usage` | 用量 |
| xAI | `https://console.x.ai/team/default/billing` | API 计费／点数 |
| Mistral AI | `https://admin.mistral.ai/organization/billing` | 组织计费 |
| Kimi 中国站 | `https://platform.kimi.com/console/pay` | 充值 |
| Kimi 国际站 | `https://platform.kimi.ai/console/account` | 用户账户 |
| 智谱 BigModel | `https://bigmodel.cn/finance-center/bill/expensebill/list` | 账单明细 |
| Z.AI 国际站 | `https://z.ai/manage-apikey/billing` | 计费 |
| 阿里云百炼北京 | `https://bailian.console.aliyun.com/` | 百炼控制台 |
| 阿里云百炼新加坡 | `https://modelstudio.console.alibabacloud.com/` | Model Studio 控制台 |
| OpenRouter | `https://openrouter.ai/settings/credits` | Credits |
| Groq | `https://console.groq.com/settings/billing` | 计费 |

### 模型摘要与状态宽度

- 模型摘要在右侧状态需要显示时，先为完整状态预留宽度。
- 状态最多使用可用宽度的 55%，模型至少保留 45%。
- 空间不足时摘要先截断；仍放不下时完整状态移到下一行。
- 状态文本不截断，模型摘要悬停显示完整供应商、模型、档位和速度信息。
- 模型摘要使用短供应商名；完整区域名称保留在额度气泡和悬停帮助中。
- “额度查询缓存”同时覆盖第三方视图：同一供应商、同缓存代次、同一天内的成功本机用量结果在有效期内复用；关闭缓存或点击“立即刷新”时重新扫描 Token 日志。

## 验证

通过：

- 全源码 `swiftc -typecheck`
- `DeepSeekPricingRegression`
- `APIProviderQuotaRegression`
- `ModelSummaryLayoutRegression`
- `APIProviderUsageCacheRegression`
- `git diff --check`

覆盖内容：

- 峰谷边界、周末、法定节假日、跨年、未知年份和自动刷新时间。
- DeepSeek 之外不显示峰谷定价。
- Kimi／智谱／阿里云百炼区域名称、摘要短名、图标族和官方入口。
- 右侧状态优先的模型摘要宽度预算与状态换行。
- 第三方本机用量缓存的供应商、代次、日期、有效期和失败结果边界。
- 全部供应商图标资源存在，xAI 与 Kimi 保持非模板显示，运行时图标统一为 36×36 PNG。
- 离线核对了未知反代、已知 ID 与完整名称回退、官方主机优先及域名边界；通用 Kimi 在区域未识别时无官方入口。
- 拆分供应商图标后，复核了 `2026-11-10` 开发素材包。35 段动画在内的 44 个运行文件与 r3 逐字节一致，继续沿用已有素材包。[开发资源获取](开发资源获取.md)

2026-11-19 的验证使用本地配置和用量样例。旧 `ModelSelectionRegression` 引用已移除的接口，模型摘要布局由 `ModelSummaryLayoutRegression` 验证。

## 当前源码入口

- `Sources/BailongPet/Infrastructure/DeepSeekPricing.swift`
- `Sources/BailongPet/Codex/APIProviderDirectory.swift`
- `Sources/BailongPet/UI/Shared/Presentation.swift`
- [额度正文](../Sources/BailongPet/UI/Bubble/QuotaBubbleBody.swift) 与[查询协调器](../Sources/BailongPet/Conversation/QuotaCoordinator.swift)
- `Sources/BailongPet/UI/Chat/ModelPresentation.swift`
- `Sources/BailongPet/UI/Chat/ChatComposer.swift`
- [模型配置](../Sources/BailongPet/Codex/ModelSelection.swift) 与[模型选择器](../Sources/BailongPet/UI/Chat/ModelSelector.swift)

## 官方资料

- Kimi 区域与 Key 隔离：<https://platform.kimi.com/docs/guide/troubleshooting>
- BigModel API：<https://docs.bigmodel.cn/cn/api/introduction>
- Z.AI API：<https://docs.z.ai/guides/develop/http/introduction.md>
- DeepSeek 余额接口：<https://api-docs.deepseek.com/zh-cn/api/get-user-balance/>
- DeepSeek 定价：<https://api-docs.deepseek.com/zh-cn/quick_start/pricing/>

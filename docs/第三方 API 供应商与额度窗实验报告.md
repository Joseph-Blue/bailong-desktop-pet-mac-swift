# 第三方 API 供应商与额度窗实验报告

- 日期：2026-11-19
- 分支：`joseph/dev`
- 版本：`0.8.2-dev.2`
- 状态：功能已进入开发线，真实第三方 API 与界面验收待完成
- 边界：未读取或保存任何 API Key，未访问真实第三方 API，未构建或启动应用

## 摘要

本轮实验确认了两条独立边界：

1. Codex 的模型基础指令高于桌宠通过 `developerInstructions` 注入的人设。人设只能塑造表达层，不能覆盖基础任务、工具和权限规则。
2. 第三方余额查询不能脱离凭证持有者完成。DeepSeek 余额接口要求 Bearer API Key；让桌宠重新收集 Key 不是合理产品方案。可行方向是由已经持有 provider 凭证的受信层代查。

本轮没有实现 Key 输入或余额代查，而是完成了一个不依赖 Key 的可用子集：DeepSeek 峰谷定价、供应商区域识别、固定开放平台入口，以及模型摘要与右侧状态的空间分配。

## 背景

桌宠支持通过 Codex 自定义 provider 接入多个第三方 API。不同供应商存在不同账户体系、端点、计费入口和区域隔离，不能只按品牌名称合并。

此前实验通过 API Key 直接请求 DeepSeek `/user/balance`。该实现可以工作，但要求主应用持有明文 Key，因此本轮决定不把这条路径作为正式功能。

## 关键结论

### Codex 基础指令与桌宠人设

- `models.json` 的模型基础指令位于更高层。
- 桌宠 `persona` 通过 app-server `developerInstructions` 注入，不能覆盖基础身份和任务规则。
- 在任务模式中继续要求桌宠执行代码、调用工具时，基础 Codex 行为会优先保留；人设适合作为面向用户正文的语气层。

### 余额查询与凭据

- DeepSeek 余额接口：`GET https://api.deepseek.com/user/balance`
- 认证方式：`Authorization: Bearer <API_KEY>`
- 请求方必须在内存中取得明文 Key，才能构造认证头。
- “只存运行内存 (RAM)”可以避免磁盘持久化，但不能让主应用完全不接触 Key。
- 不读取明文 Key 且保留结构化余额，需要受信凭据代理或上游 provider 能力。

### DSH 代查边界

DeepSeek Harness 已具备凭据服务和本地插件机制，适合作为个人场景的凭据代理原型，但存在发布风险：

- 插件初始化失败会拒绝整个 DSH profile 启动，而不是只禁用该插件。
- 把余额插件安装进主 `web`／desktop profile，会让一个小功能影响整个 DSH 启动。
- DSH 本地凭据文件只隔离其他 OS 用户，不能隔离同一 macOS 用户下的 agent 或工具进程。

若继续验证，应使用独立、固定版本的 sidecar profile，而不是修改用户主 DSH profile。该 sidecar 尚未实现。

### 余额入口不统一

第三方开放平台并不都提供可直接打开的“余额查询”页面。现有页面可能是用量、充值、账户、点数或计费页。因此按钮不写具体供应商名，也不宣称统一余额接口。

## 本轮实现

### DeepSeek 峰谷定价

- 仅在 Codex 当前 `model_provider` 识别为 DeepSeek 时显示。
- 在本机今日 Token 用量后补充“峰谷定价”和“下一时段”。
- 工作日北京时间 `9:00–12:00`、`14:00–18:00` 为高峰，其余时间、周末和中国法定节假日为空闲。
- 高峰使用红色，空闲使用绿色；下一时段按北京时间显示。
- 已维护 2026／2027 年国务院放假安排；未知年份显示“时段未提供”。
- 气泡可见期间只在峰谷边界或午夜重新排版，不重新查询额度、Token 或模型。

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

额度气泡底栏使用地球图标和强调色文字「打开供应商开放平台」。按钮采用目录中的官方页面地址，仅在有对应地址时显示。

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

入口涵盖用量、充值、账户和计费页面。Token 统计仍按 Codex 配置的原始 provider ID 归属。

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
- 本地开发素材包 `2026-11-19-r2` 已解压并通过项目资源检查，包含全部 11 个供应商图标。远端素材发布状态见[开发资源获取](开发资源获取.md)。

未执行：

- App 构建、启动和视觉验收。
- 真实 Kimi／智谱／DeepSeek API 请求。
- 13 英寸 M1 MacBook Air 实机验收。
- DSH sidecar 插件或凭据代理。

本地旧 `ModelSelectionRegression` 仍引用当前源码中不存在的接口，因此未作为本轮验证结果。

## 后续

- 正式版不恢复主应用 API Key 输入。
- 若重新研究结构化余额，优先推动 provider／Codex 上游能力，或实现隔离的 DSH sidecar。
- 区域 provider 需要用户配置不同原始 ID，才能分别统计历史 Token。
- 本轮界面改动仍需在真实输入窗与额度气泡中做视觉和交互验收。

## 相关代码

- `Sources/BailongPet/Infrastructure/DeepSeekPricing.swift`
- `Sources/BailongPet/Codex/APIProviderDirectory.swift`
- `Sources/BailongPet/UI/Shared/Presentation.swift`
- `Sources/BailongPet/UI/Bubble/Bubble.swift`
- `Sources/BailongPet/UI/Chat/ModelPresentation.swift`
- `Sources/BailongPet/UI/Chat/ChatComposer.swift`
- `Sources/BailongPet/Codex/ModelSelection.swift`

## 官方资料

- Kimi 区域与 Key 隔离：<https://platform.kimi.com/docs/guide/troubleshooting>
- BigModel API：<https://docs.bigmodel.cn/cn/api/introduction>
- Z.AI API：<https://docs.z.ai/guides/develop/http/introduction.md>
- DeepSeek 余额接口：<https://api-docs.deepseek.com/zh-cn/api/get-user-balance/>
- DeepSeek 定价：<https://api-docs.deepseek.com/zh-cn/quick_start/pricing/>

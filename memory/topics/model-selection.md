# 模型选型：Qwen 方向与待验证边界

## 目标约束

- 需要覆盖中国大陆与海外，但网络可达性、模型可用性和合规不能只靠厂商品牌推断。
- 回应包含图像，因此 provider 必须同时支持视觉理解与图像生成，或由两个可替换模型组合完成。
- 所有模型隐藏在 `OracleProvider` / `OracleRouter` 后，避免供应商锁定。

## 当前方向

- **视觉理解**：Qwen 视觉模型读取用户涂鸦。
- **图像回应**：Qwen 图像模型生成适合抽骨架的干净线稿。
- **本地 StrokeEngine**：负责骨架、笔顺、压感/收笔/速度/抖动和逐笔重播；不依赖模型直接输出最终手感。
- **可选升级**：Gemini/FLUX 等仅作为同一接口后的替换 provider。
- **自部署托底**：使用哪个具体开源版本前，必须重新核对许可证、权重能力、硬件成本和安全运维，不把“可自部署”当作零成本方案。

## API Key 与区域（2026-07-23 已核对官方说明）

1. 用户登录阿里云并开通 Model Studio；需要时完成账号身份验证。
2. 按 [Qwen 首次 API 调用指南](https://help.aliyun.com/en/model-studio/first-api-call-to-qwen) 进入 API Key 页面并创建。
3. Key 按区域区分；北京、新加坡、东京、法兰克福等部分区域调用还需把 Workspace ID 放入 Base URL。接入时以实际账号和模型页面为准。
4. 永久 Key 不进入可分发 iOS App。本地非分发 DEBUG 实验可放 gitignored 配置，并限制权限/额度/模型范围、监控异常。
5. 移动端正式调用经安全后端。官方 [临时 API Key 指南](https://help.aliyun.com/en/model-studio/application-obtain-temporary-authentication-token) 建议由安全后端为不可信环境签发临时 Key；默认 60 秒，可配置 1–1800 秒，并继承签发 Key 权限。

Content was rephrased for compliance with licensing restrictions.

## 未核实项（决定区域/签约/实现前必须复核）

- 最终所需 Qwen 视觉与图像模型在各区域的实时可用性、配额和价格。
- 中国大陆设备到所选端点的真实网络可达性与延迟。
- 供应商对请求、日志、备份、训练、删除与支持访问的处理条款。
- “数据不出境”是否有合同与全链路实现证据；备案状态本身不足以证明。
- 自部署模型版本的许可证、能力、推理成本和安全维护责任。

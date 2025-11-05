-- 转发规则配置文件
-- 支持多个渠道和关键词匹配
-- channel: 转发渠道 (wecom, feishu, dingding, custom_post)
-- keyword: 关键词匹配 ("all" 表示匹配所有消息)
-- webhook: 接收地址
-- secret: 签名密钥 (可选，用于dingding)
-- content_type: 内容类型 (可选，用于custom_post)
-- post_body: POST内容模板 (可选，用于custom_post)

--[[
========== 各渠道配置示例 ==========

企业微信 (wecom):
{
    channel = "wecom",
    keyword = "all",
    webhook = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=your-webhook-key"
}

飞书 (feishu):
{
    channel = "feishu",
    keyword = "all",
    webhook = "https://open.feishu.cn/open-apis/bot/v2/hook/your-webhook-id"
}

钉钉 (dingding):
{
    channel = "dingding",
    keyword = "all",
    webhook = "https://oapi.dingtalk.com/robot/send?access_token=your-access-token",
    secret = "your-secret"  -- 可选，用于签名验证
}

自定义POST (custom_post):
{
    channel = "custom_post",
    keyword = "all",
    webhook = "https://your-api-endpoint.com/webhook",
    content_type = "application/json",
    post_body = {
        title = "通知标题",
        desp = "通知内容: {msg}"  -- {msg} 会被替换为实际消息内容
    }
}

======================================
]]

return {
    {
        channel = "wecom",
        keyword = "all",
        webhook = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=your-webhook-id"
    },
    {
        channel = "feishu",
        keyword = "test",
        webhook = "https://open.feishu.cn/open-apis/bot/v2/hook/your-webhook-id"
    },
    {
        channel = "dingding",
        keyword = "阿里云",
        webhook = "https://oapi.dingtalk.com/robot/send?access_token=your-access-token",
        secret = "your-secret"
    },
    {
        channel = "custom_post",
        keyword = "百度",
        webhook = "https://your-api-endpoint.com/webhook",
        content_type = "application/json",
        post_body = {
            title = "通知标题",
            desp = "通知内容: {msg}"
        }
    }
}
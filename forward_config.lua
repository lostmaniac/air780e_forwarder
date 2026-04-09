-- 转发规则配置文件
-- 支持多个渠道，关键词匹配和正则匹配
-- channel: 转发渠道 (wecom, feishu, dingding, custom_post)
-- keyword: 关键词匹配，部分匹配不区分大小写 ("all" 表示匹配所有消息)
-- regular: Lua正则模式匹配，区分大小写 (与keyword二选一)
-- webhook: 接收地址
-- secret: 签名密钥 (可选，用于dingding)
-- content_type: 内容类型 (可选，用于custom_post)
-- post_body: POST内容模板 (可选，用于custom_post)

--[[
========== 各渠道配置示例 ==========

企业微信 - 关键词匹配:
{
    channel = "wecom",
    keyword = "all",
    webhook = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=your-webhook-key"
}

飞书 - 关键词匹配:
{
    channel = "feishu",
    keyword = "all",
    webhook = "https://open.feishu.cn/open-apis/bot/v2/hook/your-webhook-id"
}

钉钉 - 关键词匹配:
{
    channel = "dingding",
    keyword = "all",
    webhook = "https://oapi.dingtalk.com/robot/send?access_token=your-access-token",
    secret = "your-secret"  -- 可选，用于签名验证
}

自定义POST - 关键词匹配:
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

========== 正则模式匹配示例 ==========

匹配验证码（4-6位连续数字）:
{
    channel = "wecom",
    regular = "%d%d%d%d%d?%d?",
    webhook = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=your-key"
}

匹配以"验证码"开头的消息:
{
    channel = "feishu",
    regular = "^验证码",
    webhook = "https://open.feishu.cn/open-apis/bot/v2/hook/your-id"
}

注意：Lua pattern 不支持 | 语法，匹配多个不同关键词请分别建规则：
{
    channel = "dingding",
    regular = "腾讯云",
    webhook = "https://oapi.dingtalk.com/robot/send?access_token=your-token"
}
{
    channel = "dingding",
    regular = "阿里云",
    webhook = "https://oapi.dingtalk.com/robot/send?access_token=your-token"
}

匹配包含"订单"后跟数字的消息:
{
    channel = "feishu",
    regular = "订单%d+",
    webhook = "https://open.feishu.cn/open-apis/bot/v2/hook/your-id"
}

========== Lua pattern 常用语法 ==========
-- %d  数字          %a  字母          %w  字母数字
-- %s  空白          %l  小写字母      %u  大写字母
-- .   任意字符      *   0次或多次     +   1次或多次
-- ?   0次或1次      ^   开头          $   结尾
-- [set] 字符集      %   转义特殊字符

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

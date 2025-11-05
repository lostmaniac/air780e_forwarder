local util_notify = require "util_notify"
local util_http = require "util_http"
local forward_config = require "forward_config"

local util_forward = {}

-- 转发规则配置
local forward_rules = forward_config

-- 初始化转发规则
local function initForwardRules()
    log.info("util_forward", "初始化转发规则", "规则数量", #forward_rules)

    -- 打印所有规则用于调试
    for i, rule in ipairs(forward_rules) do
        log.info("util_forward", "规则" .. i, "渠道", rule.channel, "关键词", rule.keyword, "webhook", rule.webhook and "已配置" or "未配置")
    end

    return true
end

-- 关键词匹配函数
local function matchKeyword(content, keyword)
    if keyword == "all" then
        return true
    end

    if not content or not keyword then
        return false
    end

    -- 支持部分匹配，不区分大小写
    return string.find(string.lower(content), string.lower(keyword)) ~= nil
end

-- 企业微信转发函数
local function sendToWeCom(msg, webhook)
    if not webhook or webhook == "" then
        log.error("util_forward", "企业微信webhook为空")
        return false
    end

    local header = { ["Content-Type"] = "application/json; charset=utf-8" }
    local body = { msgtype = "text", text = { content = msg } }

    log.info("util_forward", "发送到企业微信", "webhook", webhook)
    local code, headers, response = util_http.fetch(nil, "POST", webhook, header, json.encode(body))

    if code and code >= 200 and code < 300 then
        log.info("util_forward", "企业微信发送成功", "状态码", code)
        return true
    else
        log.error("util_forward", "企业微信发送失败", "状态码", code, "响应", response)
        return false
    end
end

-- 飞书转发函数（简化版，无签名验证）
local function sendToFeishu(msg, webhook, secret)
    if not webhook or webhook == "" then
        log.error("util_forward", "飞书webhook为空")
        return false
    end

    local header = { ["Content-Type"] = "application/json; charset=utf-8" }
    local body = { msg_type = "text", content = { text = msg } }

    log.info("util_forward", "发送到飞书（无签名模式）", "webhook", webhook)
    local code, headers, response = util_http.fetch(nil, "POST", webhook, header, json.encode(body))

    if code and code >= 200 and code < 300 then
        log.info("util_forward", "飞书发送成功", "状态码", code)
        return true
    else
        log.error("util_forward", "飞书发送失败", "状态码", code, "响应", response)
        return false
    end
end

-- 钉钉转发函数
local function sendToDingding(msg, webhook, secret)
    if not webhook or webhook == "" then
        log.error("util_forward", "钉钉webhook为空")
        return false
    end

    local url = webhook

    -- 如果配置了密钥，需要签名
    if secret and secret ~= "" then
        local timestamp = tostring(os.time()) .. "000"
        local sign = crypto.hmac_sha256(timestamp .. "\n" .. secret, secret):fromHex():toBase64():urlEncode()
        url = url .. "&timestamp=" .. timestamp .. "&sign=" .. sign
    end

    local header = { ["Content-Type"] = "application/json; charset=utf-8" }
    local body = { msgtype = "text", text = { content = msg } }

    log.info("util_forward", "发送到钉钉", "url", url)
    local code, headers, response = util_http.fetch(nil, "POST", url, header, json.encode(body))

    if code and code >= 200 and code < 300 then
        log.info("util_forward", "钉钉发送成功", "状态码", code)
        return true
    else
        log.error("util_forward", "钉钉发送失败", "状态码", code, "响应", response)
        return false
    end
end

-- 自定义POST转发函数
local function sendToCustomPost(msg, webhook, content_type, post_body)
    if not webhook or webhook == "" then
        log.error("util_forward", "自定义POST webhook为空")
        return false
    end

    local header = { ["content-type"] = content_type or "application/json" }
    local body = post_body or { title = "消息通知", desp = msg }

    -- 替换消息占位符
    local function replacePlaceholders(obj)
        for k, v in pairs(obj) do
            if type(v) == "string" then
                obj[k] = string.gsub(v, "{msg}", msg)
            elseif type(v) == "table" then
                replacePlaceholders(v)
            end
        end
    end

    replacePlaceholders(body)

    local body_json = json.encode(body)

    log.info("util_forward", "发送自定义POST", "url", webhook, "content-type", content_type)
    local code, headers, response = util_http.fetch(nil, "POST", webhook, header, body_json)

    if code and code >= 200 and code < 300 then
        log.info("util_forward", "自定义POST发送成功", "状态码", code)
        return true
    else
        log.error("util_forward", "自定义POST发送失败", "状态码", code, "响应", response)
        return false
    end
end

-- 根据渠道发送消息
local function sendByChannel(msg, channel, rule)
    if not msg or msg == "" then
        log.error("util_forward", "消息内容为空")
        return false
    end

    log.info("util_forward", "根据渠道发送消息", "渠道", channel, "消息", msg)

    local success = false

    if channel == "wecom" then
        success = sendToWeCom(msg, rule.webhook)
    elseif channel == "feishu" then
        success = sendToFeishu(msg, rule.webhook, rule.secret)
    elseif channel == "dingding" then
        success = sendToDingding(msg, rule.webhook, rule.secret)
    elseif channel == "custom_post" then
        success = sendToCustomPost(msg, rule.webhook, rule.content_type, rule.post_body)
    else
        log.error("util_forward", "不支持的转发渠道", channel)
        return false
    end

    return success
end

--- 通用消息转发函数（异步版本）
-- @param msg 消息内容
-- @param msg_type 消息类型 (可选)
function util_forward.forwardMessage(msg, msg_type)
    if not forward_rules or #forward_rules == 0 then
        log.warn("util_forward", "没有配置转发规则，跳过转发")
        return false
    end

    log.info("util_forward", "开始转发消息", "类型", msg_type or "未知", "内容", msg)

    local matched_rules = {}

    -- 循环匹配所有规则
    for i, rule in ipairs(forward_rules) do
        if matchKeyword(msg, rule.keyword) then
            table.insert(matched_rules, rule)
            log.info("util_forward", "匹配到规则", "索引", i, "渠道", rule.channel, "关键词", rule.keyword)
        end
    end

    if #matched_rules == 0 then
        log.warn("util_forward", "没有匹配到任何转发规则")
        return false
    end

    log.info("util_forward", "匹配到规则数量", #matched_rules)

    -- 启动异步任务执行转发
    sys.taskInit(function()
        local success_count = 0
        for i, rule in ipairs(matched_rules) do
            log.info("util_forward", "执行转发规则", i .. "/" .. #matched_rules, "渠道", rule.channel)

            local success = sendByChannel(msg, rule.channel, rule)
            if success then
                success_count = success_count + 1
                log.info("util_forward", "转发成功", "渠道", rule.channel)
            else
                log.error("util_forward", "转发失败", "渠道", rule.channel)
            end

            -- 避免请求过于频繁
            if i < #matched_rules then
                sys.wait(1000)  -- 等待1秒
            end
        end

        log.info("util_forward", "转发完成", "成功", success_count, "总计", #matched_rules)
    end)

    return true  -- 表示任务已启动
end

--- 主要的转发函数
-- @param msg 消息内容
-- @param sender_number 发件人号码
-- @param time 接收时间
function util_forward.forwardSms(msg, sender_number, time)
    if not forward_rules or #forward_rules == 0 then
        log.warn("util_forward", "没有配置转发规则，使用默认转发")
        -- 使用默认转发方式
        util_notify.add({ msg, "", "发件号码: " .. sender_number, "发件时间: " .. time, "#SMS" })
        return
    end

    log.info("util_forward", "开始转发短信", "发件人", sender_number, "内容", msg, "时间", time)

    local full_msg = { msg, "", "发件号码: " .. sender_number, "发件时间: " .. time, "#SMS" }
    local content = table.concat(full_msg, "\n")

    -- 添加设备信息（如果配置启用）
    if config.NOTIFY_APPEND_MORE_INFO and not string.find(msg, "开机时长:") then
        content = content .. util_mobile.appendDeviceInfo()
    end

    local matched_rules = {}

    -- 循环匹配所有规则
    for i, rule in ipairs(forward_rules) do
        if matchKeyword(msg, rule.keyword) then
            table.insert(matched_rules, rule)
            log.info("util_forward", "匹配到规则", "索引", i, "渠道", rule.channel, "关键词", rule.keyword)
        end
    end

    if #matched_rules == 0 then
        log.warn("util_forward", "没有匹配到任何转发规则")
        return
    end

    log.info("util_forward", "匹配到规则数量", #matched_rules)

    -- 启动异步任务执行转发
    sys.taskInit(function()
        local success_count = 0
        for i, rule in ipairs(matched_rules) do
            log.info("util_forward", "执行转发规则", i .. "/" .. #matched_rules, "渠道", rule.channel)

            local success = sendByChannel(content, rule.channel, rule)
            if success then
                success_count = success_count + 1
                log.info("util_forward", "转发成功", "渠道", rule.channel)
            else
                log.error("util_forward", "转发失败", "渠道", rule.channel)
            end

            -- 避免请求过于频繁
            if i < #matched_rules then
                sys.wait(1000)  -- 等待1秒
            end
        end

        log.info("util_forward", "转发完成", "成功", success_count, "总计", #matched_rules)
    end)
end

--- 重新加载转发规则
function util_forward.reloadRules()
    log.info("util_forward", "重新加载转发规则")
    return initForwardRules()
end

--- 获取当前转发规则
function util_forward.getRules()
    return forward_rules
end

--- 初始化转发模块
function util_forward.init()
    log.info("util_forward", "初始化转发模块")
    return initForwardRules()
end

return util_forward
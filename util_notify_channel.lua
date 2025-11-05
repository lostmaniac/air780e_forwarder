
local function urlencodeTab(params)
    local msg = {}
    for k, v in pairs(params) do
        table.insert(msg, string.urlEncode(k) .. "=" .. string.urlEncode(v))
        table.insert(msg, "&")
    end
    table.remove(msg)
    return table.concat(msg)
end

return {
    -- 发送到 custom_post
    ["custom_post"] = function(msg)
        if config.CUSTOM_POST_URL == nil or config.CUSTOM_POST_URL == "" then
            log.error("util_notify", "未配置 `config.CUSTOM_POST_URL`")
            return
        end
        if type(config.CUSTOM_POST_BODY_TABLE) ~= "table" then
            log.error("util_notify", "未配置 `config.CUSTOM_POST_BODY_TABLE`")
            return
        end

        local header = { ["content-type"] = config.CUSTOM_POST_CONTENT_TYPE }
        local body = json.decode(json.encode(config.CUSTOM_POST_BODY_TABLE))
        -- 遍历并替换其中的变量
        local function traverse_and_replace(t)
            for k, v in pairs(t) do
                if type(v) == "table" then
                    traverse_and_replace(v)
                elseif type(v) == "string" then
                    t[k] = string.gsub(v, "{msg}", msg)
                end
            end
        end
        traverse_and_replace(body)

        -- 根据 content-type 进行编码, 默认为 application/x-www-form-urlencoded
        if string.find(config.CUSTOM_POST_CONTENT_TYPE, "json") then
            body = json.encode(body)
        else
            body = urlencodeTab(body)
        end

        log.info("util_notify", "POST", config.CUSTOM_POST_URL, config.CUSTOM_POST_CONTENT_TYPE, body)
        return util_http.fetch(nil, "POST", config.CUSTOM_POST_URL, header, body)
    end,
        -- 发送到 dingtalk
    ["dingtalk"] = function(msg)
        if config.DINGTALK_WEBHOOK == nil or config.DINGTALK_WEBHOOK == "" then
            log.error("util_notify", "未配置 `config.DINGTALK_WEBHOOK`")
            return
        end

        local url = config.DINGTALK_WEBHOOK
        -- 如果配置了 config.DINGTALK_SECRET 则需要签名(加签), 没配置则为自定义关键词
        if (config.DINGTALK_SECRET and config.DINGTALK_SECRET ~= "") then
            -- 时间异常则等待同步，增加重试机制
            local max_retries = 3
            local retry_count = 0
            local sync_success = false

            while retry_count < max_retries and not sync_success do
                if os.time() < 1714500000 then
                    log.info("util_notify", "时间同步中", "重试次数", retry_count + 1)
                    socket.sntp()
                    sync_success = sys.waitUntil("NTP_UPDATE", 1000 * 15)

                    if not sync_success then
                        retry_count = retry_count + 1
                        if retry_count < max_retries then
                            log.warn("util_notify", "时间同步失败，等待重试", retry_count, "/", max_retries)
                            sys.wait(5000)  -- 等待5秒后重试
                        end
                    end
                else
                    sync_success = true
                    break
                end
            end

            if not sync_success then
                log.error("util_notify", "时间同步失败，已达到最大重试次数", max_retries)
                -- 继续执行，但可能会签名失败
            end
            local timestamp = tostring(os.time()) .. "000"
            local sign = crypto.hmac_sha256(timestamp .. "\n" .. config.DINGTALK_SECRET, config.DINGTALK_SECRET):fromHex():toBase64():urlEncode()
            url = url .. "&timestamp=" .. timestamp .. "&sign=" .. sign
        end

        local header = { ["Content-Type"] = "application/json; charset=utf-8" }
        local body = { msgtype = "text", text = { content = msg } }
        body = json.encode(body)

        log.info("util_notify", "POST", url)
        local res_code, res_headers, res_body = util_http.fetch(nil, "POST", url, header, body)

        -- 处理响应
        -- https://open.dingtalk.com/document/orgapp/custom-robots-send-group-messages
        if res_code == 200 and res_body and res_body ~= "" then
            local res_data = json.decode(res_body)
            local res_errcode = res_data.errcode or 0
            local res_errmsg = res_data.errmsg or ""
            -- 系统繁忙 / 发送速度太快而限流
            if res_errcode == -1 or res_errcode == 410100 then
                return 500, res_headers, res_body
            end
            -- timestamp 无效
            if res_errcode == 310000 and (string.find(res_errmsg, "timestamp") or string.find(res_errmsg, "过期")) then
                socket.sntp()
                return 500, res_headers, res_body
            end
        end
        return res_code, res_headers, res_body
    end,
    -- 发送到 feishu
    ["feishu"] = function(msg)
        log.info("util_notify", "飞书通知开始", "消息内容", msg)

        if config.FEISHU_WEBHOOK == nil or config.FEISHU_WEBHOOK == "" then
            log.error("util_notify", "未配置 `config.FEISHU_WEBHOOK`")
            return
        end

        log.info("util_notify", "飞书Webhook配置", config.FEISHU_WEBHOOK)

        local url = config.FEISHU_WEBHOOK
        local header = { ["Content-Type"] = "application/json; charset=utf-8" }
        local body = { msg_type = "text", content = { text = msg } }

        -- 如果配置了密钥，需要签名
        if config.FEISHU_SECRET and config.FEISHU_SECRET ~= "" then
            local timestamp = tostring(os.time())
            -- 根据飞书文档：签名字符串 = timestamp + "\n" + secret
            -- 签名算法 = HmacSHA256(timestamp + "\n" + secret, secret)
            local string_to_sign = timestamp .. "\n" .. config.FEISHU_SECRET
            local sign = crypto.hmac_sha256(string_to_sign, config.FEISHU_SECRET):fromHex():toBase64():urlEncode()

            -- 将timestamp和sign添加到请求体中
            body.timestamp = timestamp
            body.sign = sign

            log.info("util_notify", "飞书签名配置", "timestamp", timestamp, "sign", sign)
        end

        local body_json = json.encode(body)
        log.info("util_notify", "飞书请求体", body_json)

        local res_code, res_headers, res_body = util_http.fetch(nil, "POST", url, header, body_json)

        log.info("util_notify", "飞书响应", "状态码", res_code, "响应体", res_body)
        return res_code, res_headers, res_body
    end,
    -- 发送到 wecom
    ["wecom"] = function(msg)
        if config.WECOM_WEBHOOK == nil or config.WECOM_WEBHOOK == "" then
            log.error("util_notify", "未配置 `config.WECOM_WEBHOOK`")
            return
        end

        local header = { ["Content-Type"] = "application/json; charset=utf-8" }
        local body = { msgtype = "text", text = { content = msg } }

        log.info("util_notify", "POST", config.WECOM_WEBHOOK)
        local res_code, res_headers, res_body = util_http.fetch(nil, "POST", config.WECOM_WEBHOOK, header, json.encode(body))

        -- 处理响应
        -- https://developer.work.weixin.qq.com/document/path/90313
        if res_code == 200 and res_body and res_body ~= "" then
            local res_data = json.decode(res_body)
            local res_errcode = res_data.errcode or 0
            -- 系统繁忙 / 接口调用超过限制
            if res_errcode == -1 or res_errcode == 45009 then
                return 500, res_headers, res_body
            end
        end
        return res_code, res_headers, res_body
    end,
        
    
    -- 发送到 serial
    ["serial"] = function(msg)
        uart.write(1, msg)
        log.info("util_notify", "serial", "消息已转发到串口")
        sys.wait(1000)
        return 200
    end,
}

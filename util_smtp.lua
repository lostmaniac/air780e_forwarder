local util_smtp = {}
local libnet = require "libnet"

-- SMTP超时配置(毫秒)
local SMTP_TIMEOUT = 10000
local SMTP_CONNECT_TIMEOUT = 15000

--- 从socket读取SMTP响应
-- @param netc socket控制对象
-- @param taskName 任务名称
-- @param timeout 超时时间(毫秒)
-- @return 响应字符串 or nil
local function readResponse(netc, taskName, timeout)
    timeout = timeout or SMTP_TIMEOUT
    socket.rx(netc, 1024)
    libnet.wait(taskName, timeout, netc)
    return socket.read(netc, 1024)
end

--- 发送SMTP命令并读取响应
-- @param netc socket控制对象
-- @param taskName 任务名称
-- @param cmd SMTP命令
-- @param timeout 超时时间(毫秒)
-- @return 响应字符串 or nil
local function sendCommand(netc, taskName, cmd, timeout)
    log.debug("util_smtp", "发送:", (cmd or ""):gsub("\r\n$", ""))
    socket.tx(netc, cmd)
    libnet.wait(taskName, timeout or SMTP_TIMEOUT, netc)
    socket.rx(netc, 1024)
    libnet.wait(taskName, timeout or SMTP_TIMEOUT, netc)
    return socket.read(netc, 1024)
end

--- 检查SMTP响应码
-- @param resp SMTP响应
-- @param expected 期望的响应码(如250, 220, 235)
-- @return true if matches
local function checkCode(resp, expected)
    if not resp then return false end
    return tonumber(resp:match("^(%d+)")) == expected
end

--- 构建邮件内容(含邮件头)
-- @param from 发件人
-- @param to 收件人
-- @param subject 主题
-- @param body 正文
-- @return 格式化的邮件内容
local function buildEmail(from, to, subject, body)
    local b64_subject = crypto.base64_encode(subject) or ""
    local b64_body = crypto.base64_encode(body) or ""
    return table.concat({
        "From: <" .. from .. ">",
        "To: <" .. to .. ">",
        "Subject: =?UTF-8?B?" .. b64_subject .. "?=",
        "Content-Type: text/plain; charset=utf-8",
        "Content-Transfer-Encoding: base64",
        "",
        b64_body,
    }, "\r\n")
end

--- 安全关闭socket
local function closeSocket(netc)
    if netc then
        socket.close(netc)
        socket.release(netc)
    end
end

--- 通过SMTP发送邮件
-- @param rule 转发规则(含SMTP配置)
-- @param msg 消息内容
-- @return true成功, false失败
function util_smtp.send(rule, msg)
    -- 回收内存
    collectgarbage("collect")

    -- 校验配置
    if not rule.smtp_server or not rule.smtp_username or not rule.smtp_password
        or not rule.email_from or not rule.email_to then
        log.error("util_smtp", "SMTP配置不完整")
        return false
    end

    local ssl = rule.smtp_ssl ~= false
    local port = rule.smtp_port or (ssl and 465 or 25)
    local taskName = "smtp_" .. os.time()

    log.info("util_smtp", "连接SMTP", rule.smtp_server, port, ssl and "SSL" or "明文")

    -- 创建socket
    local netc = socket.create(taskName, function() return true end)
    if not netc then
        log.error("util_smtp", "创建socket失败")
        return false
    end

    -- 配置SSL
    socket.config(netc, nil, nil, ssl)

    -- 连接服务器
    if not libnet.connect(taskName, SMTP_CONNECT_TIMEOUT, netc, rule.smtp_server, port) then
        log.error("util_smtp", "连接SMTP服务器失败")
        closeSocket(netc)
        return false
    end

    -- SMTP协议步骤封装
    local function step(cmd, expected, err_msg)
        local resp = sendCommand(netc, taskName, cmd)
        if not checkCode(resp, expected) then
            log.error("util_smtp", err_msg, resp)
            socket.tx(netc, "QUIT\r\n")
            libnet.wait(taskName, 3000, netc)
            closeSocket(netc)
            return false
        end
        return true
    end

    -- 1. 读取服务器问候
    local resp = readResponse(netc, taskName)
    if not checkCode(resp, 220) then
        log.error("util_smtp", "SMTP问候失败", resp)
        closeSocket(netc)
        return false
    end

    -- 2. EHLO
    if not step("EHLO air780e\r\n", 250, "EHLO失败") then return false end

    -- 3. AUTH LOGIN
    if not step("AUTH LOGIN\r\n", 334, "AUTH LOGIN失败") then return false end

    -- 4. 用户名
    local user_b64 = crypto.base64_encode(rule.smtp_username) or ""
    if not step(user_b64 .. "\r\n", 334, "用户名验证失败") then return false end

    -- 5. 密码
    local pass_b64 = crypto.base64_encode(rule.smtp_password) or ""
    if not step(pass_b64 .. "\r\n", 235, "密码验证失败") then return false end

    -- 6. MAIL FROM
    if not step("MAIL FROM:<" .. rule.email_from .. ">\r\n", 250, "MAIL FROM失败") then return false end

    -- 7. RCPT TO
    if not step("RCPT TO:<" .. rule.email_to .. ">\r\n", 250, "RCPT TO失败") then return false end

    -- 8. DATA
    if not step("DATA\r\n", 354, "DATA失败") then return false end

    -- 9. 邮件内容 + 结束标记
    local email = buildEmail(rule.email_from, rule.email_to, "短信转发通知", msg)
    if not step(email .. "\r\n.\r\n", 250, "邮件发送失败") then return false end

    log.info("util_smtp", "邮件发送成功", rule.email_to)

    -- 10. QUIT
    socket.tx(netc, "QUIT\r\n")
    libnet.wait(taskName, 3000, netc)
    closeSocket(netc)

    collectgarbage("collect")
    return true
end

return util_smtp

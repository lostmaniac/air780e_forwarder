PROJECT = "air780epv_forwarder"
VERSION = "2.0.0"

log.setLevel("DEBUG")
log.info("main", PROJECT, VERSION)
log.info("main", "开机原因", pm.lastReson())

sys = require "sys"
sysplus = require "sysplus"

-- 添加硬狗防止程序卡死
wdt.init(9000)
sys.timerLoopStart(wdt.feed, 3000)


-- 在这里加上回收内存的代码
sys.timerLoopStart(function()
       log.info("回收一次内存")
       collectgarbage("collect")
end,3600000) -- 每小时回收一次内存


-- 设置 DNS
socket.setDNS(nil, 1, "119.29.29.29")
socket.setDNS(nil, 2, "223.5.5.5")

-- SIM 自动恢复, 周期性获取小区信息, 网络遇到严重故障时尝试自动恢复等功能
mobile.setAuto(10000, 300000, 8, true, 120000)


-- 初始化 fskv
log.info("main", "fskv.init", fskv.init())

-- POWERKEY
local rtos_bsp = rtos.bsp()
local pin_table = { ["EC618"] = 35, ["EC718P"] = 46 }
local powerkey_pin = pin_table[rtos_bsp]

if powerkey_pin then
    local button_last_press_time, button_last_release_time = 0, 0
    gpio.setup(powerkey_pin, function()
        local current_time = mcu.ticks()
        -- 按下
        if gpio.get(powerkey_pin) == 0 then
            button_last_press_time = current_time -- 记录最后一次按下时间
            return
        end
        -- 释放
        if button_last_press_time == 0 then -- 开机前已经按下, 开机后释放
            return
        end
        if current_time - button_last_release_time < 250 then -- 防止连按
            return
        end
        local duration = current_time - button_last_press_time -- 按键持续时间
        button_last_release_time = current_time -- 记录最后一次释放时间
        if duration > 2000 then
            log.debug("EVENT.POWERKEY_LONG_PRESS", duration)
            sys.publish("POWERKEY_LONG_PRESS", duration)
        elseif duration > 50 then
            log.debug("EVENT.POWERKEY_SHORT_PRESS", duration)
            sys.publish("POWERKEY_SHORT_PRESS", duration)
        end
    end, gpio.PULLUP)
end

-- 加载模块
config = require "config"
util_http = require "util_http"
util_netled = require "util_netled"
util_mobile = require "util_mobile"
util_location = require "util_location"
util_notify = require "util_notify"
util_forward = require "util_forward"
TaskManager = require "task_manager"



if config.ROLE == "SLAVE" then
    -- 串口配置
    uart.setup(1, 115200, 8, 1, uart.NONE)
    -- 串口接收回调
    uart.on(1, "receive", function(id, len)
        -- 限制单次读取最大数据量，防止内存溢出
        local max_read_len = 1024  -- 最大1KB
        if len > max_read_len then
            len = max_read_len
            log.warn("uart", "数据量过大，截断处理", len)
        end

        local data = uart.read(id, len)
        if not data or data == "" then
            return
        end

        log.info("uart read:", id, len, data)
        if config.ROLE == "MASTER" then
            -- 主机, 通过队列发送数据
            util_notify.add(data)
        else
            -- 从机, 通过串口发送数据
            uart.write(1, data)
        end
    end)
end

-- 短信接收回调
sms.setNewSmsCb(function(sender_number, sms_content, m)
    local time = string.format("%d/%02d/%02d %02d:%02d:%02d", m.year + 2000, m.mon, m.day, m.hour, m.min, m.sec)
    log.info("smsCallback", time, sender_number, sms_content)

    -- 短信控制
    local is_sms_ctrl = false
    -- 改进的正则表达式，支持国际号码格式
    local receiver_number, sms_content_to_be_sent = sms_content:match("^SMS,([%+]?%d%d%d%d%d%d?%d?%d?%d?%d?%d?%d?%d?%d?),(.+)$")
    receiver_number, sms_content_to_be_sent = receiver_number or "", sms_content_to_be_sent or ""

    -- 增强号码验证
    if sms_content_to_be_sent ~= "" and receiver_number ~= "" then
        -- 去除可能的空格和分隔符
        receiver_number = receiver_number:gsub("[%s%-]", "")

        -- 验证号码格式（5-20位数字，可含+号开头）
        if string.match(receiver_number, "^%+?%d%d%d%d%d%d?%d?%d?%d?%d?%d?%d?%d?%d?$") and
           #receiver_number >= 5 and #receiver_number <= 20 then
            sms.send(receiver_number, sms_content_to_be_sent)
            is_sms_ctrl = true
            log.info("smsCtrl", "发送短信", receiver_number, sms_content_to_be_sent)
        else
            log.warn("smsCtrl", "号码格式无效", receiver_number)
        end
    end

    -- 使用转发模块处理短信
    local msg_with_tag = sms_content .. (is_sms_ctrl and " #CTRL" or "")
    util_forward.forwardSms(msg_with_tag, sender_number, time)
end)

sys.taskInit(function()
    -- 等待网络环境准备就绪
    sys.waitUntil("IP_READY", config.NETWORK_TIMEOUT_LONG)

    util_netled.init()

    -- 初始化转发模块
    if util_forward.init() then
        log.info("main", "转发模块初始化成功")
    else
        log.error("main", "转发模块初始化失败")
    end

    -- 开机通知
    if config.BOOT_NOTIFY then
        local boot_reason = pm.lastReson()
        local boot_msg = "#BOOT_" .. boot_reason

        -- 添加设备信息到开机通知
        if config.NOTIFY_APPEND_MORE_INFO then
            boot_msg = boot_msg .. util_mobile.appendDeviceInfo()
        end

        log.info("main", "准备发送开机通知", "BOOT_NOTIFY", config.BOOT_NOTIFY, "开机原因", boot_reason, "消息", boot_msg)

        local timer_id = sys.timerStart(function()
            log.info("main", "定时器触发，开始发送开机通知", "消息", boot_msg, "定时器ID", timer_id)

            -- 尝试使用转发规则发送开机通知
            local forward_success = util_forward.forwardMessage(boot_msg, "BOOT")
            if forward_success then
                log.info("main", "开机通知通过转发规则发送成功")
            else
                log.info("main", "转发规则发送失败或无规则，使用默认通知方式")
                local result = util_notify.add(boot_msg)
                log.info("main", "开机通知发送结果", result)
            end
        end, 1000 * 5)

        log.info("main", "定时器已启动", "ID", timer_id, "延迟", 5000, "毫秒")
    else
        log.info("main", "开机通知已禁用", "BOOT_NOTIFY", config.BOOT_NOTIFY)
    end

    -- 定时同步时间
    if os.time() < 1714500000 then
        socket.sntp()
    end
    if type(config.SNTP_INTERVAL) == "number" and config.SNTP_INTERVAL >= 1000 * 60 then
        sys.timerLoopStart(socket.sntp, config.SNTP_INTERVAL)
    end

    -- 定时查询流量
    if type(config.QUERY_TRAFFIC_INTERVAL) == "number" and config.QUERY_TRAFFIC_INTERVAL >= 1000 * 60 then
        sys.timerLoopStart(util_mobile.queryTraffic, config.QUERY_TRAFFIC_INTERVAL)
    end

    -- 定时基站定位
    if type(config.LOCATION_INTERVAL) == "number" and config.LOCATION_INTERVAL >= 1000 * 60 then
        util_location.refresh(nil, true)
        sys.timerLoopStart(util_location.refresh, config.LOCATION_INTERVAL)
    end

    -- 定时上报
    if type(config.REPORT_INTERVAL) == "number" and config.REPORT_INTERVAL >= 1000 * 60 then
        sys.timerLoopStart(function() util_notify.add("#ALIVE_REPORT") end, config.REPORT_INTERVAL)
    end

    -- 设备重启管理（增加状态检查）
    local restart_enabled = true  -- 可配置的重启开关
    local restart_interval = 2 * 60 * 60 * 1000  -- 2小时

    if restart_enabled then
        sys.timerLoopStart(function()
            log.info("main", "准备重启设备", "重启间隔", restart_interval / 1000 / 60, "分钟")

            -- 检查是否有正在进行的操作
            local task_list = TaskManager.list()
            if #task_list > 0 then
                log.info("main", "发现活跃任务，延迟重启", "任务数量", #task_list)
                for _, task_name in ipairs(task_list) do
                    log.info("main", "活跃任务", task_name)
                end
                -- 等待1分钟后再尝试
                sys.timerStart(function()
                    log.info("main", "延迟重启设备")
                    cleanupAllTasks()
                    sys.wait(2000)  -- 等待任务清理完成
                    rtos.restart()
                end, 60000)
            else
                -- 没有活跃任务，直接重启
                log.info("main", "无活跃任务，立即重启设备")
                cleanupAllTasks()
                sys.wait(1000)  -- 等待清理完成
                rtos.restart()
            end
        end, restart_interval)
    else
        log.info("main", "设备自动重启已禁用")
    end

    -- 电源键处理（合并短按和双击功能）
    local last_short_press = 0
    sys.subscribe("POWERKEY_SHORT_PRESS", function()
        local current_time = mcu.ticks()

        -- 检测双击
        if current_time - last_short_press < 500 then  -- 500ms内双击
            log.info("main", "检测到双击，发送开机通知测试")
            local boot_test_msg = "#BOOT_TEST_" .. pm.lastReson()
            local forward_success = util_forward.forwardMessage(boot_test_msg, "BOOT_TEST")
            if forward_success then
                log.info("main", "开机测试通知通过转发规则发送成功")
            else
                log.info("main", "转发规则发送失败，使用默认通知方式")
                util_notify.add(boot_test_msg)
            end
        else
            -- 短按发送测试通知
            log.info("main", "短按电源键，发送测试通知")
            local test_msg = "#ALIVE"
            local forward_success = util_forward.forwardMessage(test_msg, "TEST")
            if forward_success then
                log.info("main", "测试通知通过转发规则发送成功")
            else
                log.info("main", "转发规则发送失败，使用默认通知方式")
                util_notify.add(test_msg)
            end
        end

        last_short_press = current_time
    end)
    -- 电源键长按查询流量
    sys.subscribe("POWERKEY_LONG_PRESS", util_mobile.queryTraffic)
end)

sys.taskInit(function()
    if type(config.PIN_CODE) ~= "string" or config.PIN_CODE == "" then
        return
    end
    -- 开机等待短时间仍未联网, 再进行 pin 验证
    if not sys.waitUntil("IP_READY", config.NETWORK_TIMEOUT_SHORT) then
        util_mobile.pinVerify(config.PIN_CODE)
    end
end)

-- 定时开关飞行模式
if type(config.FLYMODE_INTERVAL) == "number" and config.FLYMODE_INTERVAL >= 1000 * 60 then
    sys.timerLoopStart(function()
        mobile.flymode(0, true)
        mobile.flymode(0, false)
    end, config.FLYMODE_INTERVAL)
end

-- 通话相关
local is_calling = false

sys.subscribe("CC_IND", function(status)
    if cc == nil then return end

    if status == "INCOMINGCALL" then
        -- 来电事件, 期间会重复触发
        if is_calling then return end
        is_calling = true

        log.info("cc_status", "INCOMINGCALL", "来电事件", cc.lastNum())

        -- 发送通知
        util_notify.add({ "来电号码: " .. cc.lastNum(), "来电时间: " .. os.date("%Y-%m-%d %H:%M:%S"), "#CALL #CALL_IN" })
        return
    end

    if status == "DISCONNECTED" then
        -- 挂断事件
        is_calling = false
        log.info("cc_status", "DISCONNECTED", "挂断事件", cc.lastNum())

        -- 发送通知
        util_notify.add({ "来电号码: " .. cc.lastNum(), "挂断时间: " .. os.date("%Y-%m-%d %H:%M:%S"), "#CALL #CALL_DISCONNECTED" })
        return
    end

    log.info("cc_status", status)
end)

-- 全局任务清理函数
function cleanupAllTasks()
    log.info("main", "开始清理所有任务")

    -- 清理各模块任务
    if util_notify.cleanup then
        util_notify.cleanup()
    end
    if util_location.cleanup then
        util_location.cleanup()
    end
    if util_netled.cleanup then
        util_netled.cleanup()
    end

    -- 清理任务管理器中的所有任务
    TaskManager.cleanup()

    log.info("main", "所有任务清理完成")
end

-- 设置调试模式
TaskManager.setDebug(false)  -- 可设置为true查看详细日志

sys.run()

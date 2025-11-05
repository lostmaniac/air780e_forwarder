local util_mobile = {}
--- 获取本机号码，支持多种方法和重试机制
-- @param max_retries number, 最大重试次数，默认3次
-- @param retry_delay number, 重试间隔毫秒，默认2000毫秒
-- @return string|nil, 获取到的号码或nil
function util_mobile.getLocalNumber(max_retries, retry_delay)
    max_retries = max_retries or 3
    retry_delay = retry_delay or 2000
    local sim_id = mobile.simid()
    local network_status = mobile.status()
    log.info("util_mobile.getLocalNumber", "开始获取本机号码",
             "SIMID:", sim_id, "网络状态:", network_status, "最大重试:", max_retries)

    -- 简化版本：不使用sys.wait，避免在非协程环境中出错
    for retry = 1, max_retries do
        -- 检查网络状态
        if network_status == 1 then
            -- 方法1: 直接获取号码
            local number = mobile.number(sim_id)
            if number and number ~= "" and number ~= "00000000000" then
                log.info("util_mobile.getLocalNumber", "方法1获取成功", "号码:", number, "重试次数:", retry)
                return number
            end
            -- 方法2: 通过IMSI推断（部分运营商可以从IMSI推断号码段）
            local imsi = mobile.imsi(sim_id)
            log.info("util_mobile.getLocalNumber", "尝试方法2: IMSI分析", "IMSI:", imsi)
            -- 方法3: 通过ICCID分析SIM卡信息
            local iccid = mobile.iccid(sim_id)
            log.info("util_mobile.getLocalNumber", "尝试方法3: ICCID分析", "ICCID:", iccid)
        else
            log.warn("util_mobile.getLocalNumber", "网络未注册", "状态:", network_status, "重试:", retry)
        end

        log.warn("util_mobile.getLocalNumber", "获取失败", "重试:", retry)
        -- 在非协程环境中不能使用sys.wait，所以直接重试
        if retry < max_retries then
            network_status = mobile.status()
        end
    end

    log.error("util_mobile.getLocalNumber", "获取失败，已达到最大重试次数")
    return nil
end
--- 获取设备唯一标识符（用于替代号码显示）
-- @return table, 包含各种设备标识
function util_mobile.getDeviceIdentifiers()
    local identifiers = {}
    -- IMEI
    local imei = mobile.imei()
    if imei and imei ~= "" then
        identifiers.imei = imei
    end
    -- IMSI
    local imsi = mobile.imsi()
    if imsi and imsi ~= "" then
        identifiers.imsi = imsi
        -- 从IMSI提取运营商信息和部分号码信息
        if #imsi >= 15 then
            identifiers.mcc = imsi:sub(1, 3)  -- 移动国家代码
            identifiers.mnc = imsi:sub(4, 5)  -- 移动网络代码
            identifiers.msin = imsi:sub(6)   -- 用户标识
        end
    end
    -- ICCID
    local iccid = mobile.iccid()
    if iccid and iccid ~= "" then
        identifiers.iccid = iccid
    end
    -- SIM卡ID
    local simid = mobile.simid()
    identifiers.simid = simid
    log.info("util_mobile.getDeviceIdentifiers", "设备标识符", json.encode(identifiers))
    return identifiers
end
--- 生成设备标识文本（用于通知显示）
-- @return string, 设备标识文本
function util_mobile.getDeviceIdentityText()
    local identifiers = util_mobile.getDeviceIdentifiers()
    local text = ""
    if identifiers.imei then
        text = text .. "IMEI: " .. identifiers.imei .. "\n"
    end
    if identifiers.imsi then
        -- 完整显示IMSI
        text = text .. "IMSI: " .. identifiers.imsi .. "\n"
    end
    if identifiers.iccid then
        -- 完整显示ICCID
        text = text .. "SIM卡: " .. identifiers.iccid
    end
    return text
end
--- 验证 pin 码
-- @param pin_code string, pin 码
function util_mobile.pinVerify(pin_code)
    local sim_id = mobile.simid()
    pin_code = tostring(pin_code or "")
    if #pin_code < 4 or #pin_code > 8 then
        log.warn("util_mobile.pinVerify", "pin 码长度不正确")
        return
    end
    local cpin_is_ready = mobile.simPin(sim_id)
    if cpin_is_ready then
        log.info("util_mobile.pinVerify", "无需验证 pin 码")
        return
    end
    cpin_is_ready = mobile.simPin(sim_id, mobile.PIN_VERIFY, pin_code)
    log.info("util_mobile.pinVerify", "验证 pin 码" .. (cpin_is_ready and "成功" or "失败"))
end
-- 运营商数据
local oper_data = {
    -- 中国移动
    ["46000"] = { "CM", "中国移动", { "10086", "CXLL" } },
    ["46002"] = { "CM", "中国移动", { "10086", "CXLL" } },
    ["46007"] = { "CM", "中国移动", { "10086", "CXLL" } },
    ["46008"] = { "CM", "中国移动", { "10086", "CXLL" } },
    -- 中国联通
    ["46001"] = { "CU", "中国联通", { "10010", "2082" } },
    ["46006"] = { "CU", "中国联通", { "10010", "2082" } },
    ["46009"] = { "CU", "中国联通", { "10010", "2082" } },
    ["46010"] = { "CU", "中国联通", { "10010", "2082" } },
    -- 中国电信
    ["46003"] = { "CT", "中国电信", { "10001", "108" } },
    ["46005"] = { "CT", "中国电信", { "10001", "108" } },
    ["46011"] = { "CT", "中国电信", { "10001", "108" } },
    ["46012"] = { "CT", "中国电信", { "10001", "108" } },
    -- 中国广电
    ["46015"] = { "CB", "中国广电" },
}
--- 获取 MCC 和 MNC
-- @return MCC or -1
-- @return MNC or -1
function util_mobile.getMccMnc()
    local imsi = mobile.imsi(mobile.simid()) or ""
    return string.sub(imsi, 1, 3) or -1, string.sub(imsi, 4, 5) or -1
end
--- 获取 Band
-- @return Band or -1
function util_mobile.getBand()
    local info = mobile.getCellInfo()[1] or {}
    return info.band or -1
end
--- 获取运营商
-- @param is_zh 是否返回中文
-- @return 运营商 or ""
function util_mobile.getOper(is_zh)
    local imsi = mobile.imsi(mobile.simid()) or ""
    local mcc, mnc = string.sub(imsi, 1, 3), string.sub(imsi, 4, 5)
    local mcc_mnc = mcc .. mnc
    local oper = oper_data[mcc_mnc]
    if oper then
        return is_zh and oper[2] or oper[1]
    else
        return mcc_mnc
    end
end
--- 发送查询流量短信
function util_mobile.queryTraffic()
    local imsi = mobile.imsi(mobile.simid()) or ""
    local mcc_mnc = string.sub(imsi, 1, 5)
    local oper = oper_data[mcc_mnc]
    if oper and oper[3] then
        sms.send(oper[3][1], oper[3][2])
    else
        log.warn("util_mobile.queryTraffic", "查询流量代码未配置")
    end
end
--- 获取网络状态
-- @return 网络状态
function util_mobile.status()
    local codes = {
        [0] = "网络未注册",
        [1] = "网络已注册",
        [2] = "网络搜索中",
        [3] = "网络注册被拒绝",
        [4] = "网络状态未知",
        [5] = "网络已注册,漫游",
        [6] = "网络已注册,仅SMS",
        [7] = "网络已注册,漫游,仅SMS",
        [8] = "网络已注册,紧急服务",
        [9] = "网络已注册,非主要服务",
        [10] = "网络已注册,非主要服务,漫游",
    }
    local mobile_status = mobile.status()
    if mobile_status and mobile_status >= 0 and mobile_status <= 10 then
        return codes[mobile_status] or "未知网络状态"
    end
    return "未知网络状态"
end
--- 追加设备信息
--- @return string
function util_mobile.appendDeviceInfo()
    local msg = "\n"
    -- 本机号码
    local number = util_mobile.getLocalNumber(2, 1000)  -- 减少重试次数和延迟，避免阻塞
    local number_source = ""
    if number and number ~= "" then
        number_source = "(系统获取)"
    elseif config.FALLBACK_LOCAL_NUMBER and config.FALLBACK_LOCAL_NUMBER ~= "" then
        number = config.FALLBACK_LOCAL_NUMBER
        number_source = "(备用号码)"
    end
    if number and number ~= "" then
        msg = msg .. "\n本机号码: " .. number .. " " .. number_source
        log.info("util_mobile", "本机号码获取成功", number, number_source)
    else
        log.warn("util_mobile", "无法获取本机号码，系统接口返回空，备用号码未配置")
        -- 添加设备标识信息作为替代
        local identity_text = util_mobile.getDeviceIdentityText()
        if identity_text ~= "" then
            msg = msg .. "\n设备标识:\n" .. identity_text
        end
    end
    -- 开机时长
    local ms = mcu.ticks()
    local seconds = math.floor(ms / 1000)
    local minutes = math.floor(seconds / 60)
    local hours = math.floor(minutes / 60)
    seconds = seconds % 60
    minutes = minutes % 60
    local boot_time = string.format("%02d:%02d:%02d", hours, minutes, seconds)
    if ms >= 0 then
        msg = msg .. "\n开机时长: " .. boot_time
    end
    -- 运营商
    local oper = util_mobile.getOper(true)
    if oper ~= "" then
        msg = msg .. "\n运营商: " .. oper
    end
    -- 信号强度
    local rsrp = mobile.rsrp()
    local csq = mobile.csq()
    if rsrp and rsrp ~= 0 then
        msg = msg .. "\n信号强度: " .. rsrp .. "dBm (RSRP)"
        if csq and csq >= 0 and csq <= 31 then
            msg = msg .. " CSQ:" .. csq
        end
    else
        msg = msg .. "\n信号强度: 获取失败"
    end
    -- 位置
    local _, _, map_link = util_location.get()
    if map_link ~= "" then
        msg = msg .. "\n位置: " .. map_link
    end
    return msg
end
return util_mobile

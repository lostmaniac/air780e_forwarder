## 项目概述

基于LuatOS的Air780E设备SMS转发器，根据关键词匹配规则智能转发短信到多个渠道（企业微信、飞书、钉钉、自定义webhook）。

## 系统架构详解

### 核心文件及功能说明

**主程序入口：main.lua**
- `PROJECT = "air780e_forwarder"` - 项目定义和版本
- `sms.setNewSmsCb()` - 短信接收回调函数注册（第115行）
- `sys.subscribe()` - 电源键事件订阅（短按/长按/双击）
- `sys.taskInit()` - 主协程启动，处理网络就绪后的初始化
- 包含定时器：内存回收、飞行模式、SNTP时间同步

**配置系统：**
- **config.lua** - 系统级配置（网络超时、定时任务、设备行为）
  - `ROLE = "MASTER/SLAVE"` - 主从机角色设定
  - `BOOT_NOTIFY = true` - 开机通知开关
  - `NOTIFY_APPEND_MORE_INFO = true` - 是否追加设备信息
  - 各种超时配置：`NETWORK_TIMEOUT_DEFAULT/LONG/SHORT`
- **forward_config.lua** - 业务逻辑配置（25条转发规则）
  - 每条规则包含：`channel`、`keyword`、`webhook`、可选`secret/post_body`
  - 支持4种渠道：`wecom`、`feishu`、`dingding`、`custom_post`
  - 关键词`"all"`表示匹配所有消息

**核心转发引擎：util_forward.lua**
- `forwardSms(msg, sender, time)` - 短信转发主函数（第233行）
  - 调用`matchKeyword()`进行关键词匹配
  - 启动异步协程执行多渠道转发
- `forwardMessage(msg, msg_type)` - 通用消息转发（第178行）
  - 用于开机通知、测试通知等
- `sendByChannel(msg, channel, rule)` - 根据渠道分发消息（第149行）
  - 内部调用具体的渠道实现函数

**通知系统：util_notify.lua**
- `add(msg, channels)` - 添加通知到队列（第68行）
  - 默认渠道：`{"feishu"}`（备用通知）
  - 调用`util_notify_channel.lua`中的具体实现
- `send()` - 实际发送逻辑，包含重试机制
- `cleanup()` - 清理定时器和资源

**渠道实现：util_notify_channel.lua**
- `custom_post` - 自定义POST请求（支持JSON/form-encoded）
- `dingtalk` - 钉钉机器人（支持HMAC-SHA256签名验证）
- `feishu` - 飞书机器人（简化版，无签名验证）
- `wecom` - 企业微信机器人
- `serial` - 串口转发（UART1，115200波特率）

**工具模块：**
- **util_mobile.lua** - 移动网络工具
  - `getLocalNumber()` - 获取本机号码（最大重试3次）
  - `appendDeviceInfo()` - 追加设备信息到消息（信号强度、运营商、位置等）
  - `getDeviceIdentityText()` - 获取设备标识文本（IMEI/IMSI/ICCID）
  - `pinVerify(pin_code)` - SIM卡PIN码验证
- **util_http.lua** - HTTP客户端封装
  - `fetch(timeout, method, url, headers, body)` - 统一HTTP请求接口
  - 自动处理重试和超时
- **util_location.lua** - 基站定位
  - `get()` - 获取位置信息（经纬度、地图链接）
  - `refresh()` - 刷新位置信息
- **util_netled.lua** - 网络状态LED指示
- **task_manager.lua** - 任务管理器
  - `create(name, func, callback)` - 创建命名任务
  - `cleanup()` - 清理所有任务

### 详细消息流程

```
SMS接收 → main.lua:115 sms.setNewSmsCb()
    ↓
消息预处理（添加发件人、时间、控制标记）
    ↓
util_forward.forwardSms() - 第233行
    ↓
遍历forward_config.lua中的25条规则
    ↓
matchKeyword() - 关键词匹配（不区分大小写，支持部分匹配）
    ↓
sys.taskInit() - 启动异步转发协程 - 第269行
    ↓
sendByChannel() - 按渠道分发 - 第274行
    ↓
具体渠道实现 → HTTP POST请求
    ↓
成功/失败日志记录
```

**备用通知流程：**
```
转发失败 → util_notify.add() → 默认飞书渠道
```

**开机通知流程：**
```
设备启动 → 等待IP_READY → util_forward.forwardMessage("#BOOT_xxx")
    ↓
转发失败 → util_notify.add() → 备用通知
```

### 核心技术细节

**LuatOS协程使用规范：**
- 所有异步操作必须使用`sys.taskInit()`包装
- 严禁在回调函数中使用`sys.wait()`
- HTTP请求必须在协程中执行
- 内存管理：每小时执行`collectgarbage("collect")`

**信号强度处理（util_mobile.lua:230-240行）：**
```lua
local rsrp = mobile.rsrp()  -- 主要指标：-44到-140 dBm
local csq = mobile.csq()    -- 参考指标：0-31
if rsrp and rsrp ~= 0 then
    msg = msg .. "\n信号强度: " .. rsrp .. "dBm (RSRP)"
    if csq and csq >= 0 and csq <= 31 then
        msg = msg .. " CSQ:" .. csq
    end
end
```

**设备信息获取：**
- 完整IMSI显示：15位移动用户识别码
- 完整ICCID显示：SIM卡唯一序列号
- 运营商信息：从IMSI提取MCC（国家代码）和MNC（网络代码）
- 开机时长：格式化为`HH:MM:SS`

**关键词匹配算法：**
```lua
function matchKeyword(content, keyword)
    if keyword == "all" then return true end
    return string.find(string.lower(content), string.lower(keyword)) ~= nil
end
```

**HTTP请求处理：**
- 超时配置：短超时10秒，默认1分钟，长超时5分钟
- 自动重试机制：网络失败时的重连逻辑
- 内容编码：支持JSON和表单编码

### 开发调试指南

**添加新通知渠道步骤：**
1. 在`util_notify_channel.lua`中实现渠道函数
2. 在`util_forward.lua`的`sendByChannel()`中添加channel判断
3. 在`forward_config.lua`头部添加配置示例

**常见调试命令：**
```lua
-- 发送测试消息
util_forward.forwardMessage("#TEST_MESSAGE", "TEST")

-- 查看信号强度
local rsrp, csq = mobile.rsrp(), mobile.csq()
log.info("signal", "RSRP:", rsrp, "CSQ:", csq)

-- 获取设备信息
local device_info = util_mobile.getDeviceIdentityText()
log.info("device", device_info)
```

**错误处理机制：**
- 网络自动恢复：`mobile.setAuto(10000, 300000, 8, true, 120000)`
- 看门狗定时器：`wdt.init(9000)`，每3秒喂狗
- 任务管理器捕获协程异常
- HTTP请求失败时的降级处理

### 硬件相关配置

**移动网络配置：**
- DNS设置：119.29.29.29（主），223.5.5.5（备）
- 自动重连机制：周期性获取小区信息
- 飞行模式：定时重启网络连接

**电源管理：**
- 硬看门狗：9秒超时重启
- 内存管理：定时垃圾回收
- 设备重启：2小时定时重启（检查活跃任务）

### 系统启动流程

1. **基础初始化**：日志级别、看门狗、内存回收定时器
2. **网络配置**：DNS设置、移动网络自动恢复
3. **硬件初始化**：FSKV存储、电源键GPIO配置
4. **模块加载**：加载所有工具模块和转发模块
5. **串口配置**：如果ROLE="SLAVE"，配置UART串口通信
6. **主协程启动**：等待网络就绪，执行各种初始化任务
7. **定时任务启动**：时间同步、流量查询、定位、设备重启等
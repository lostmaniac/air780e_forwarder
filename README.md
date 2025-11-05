# Air780E SMS转发器

基于LuatOS的智能短信转发系统，支持根据关键词匹配规则将短信转发到多个渠道（企业微信、飞书、钉钉、自定义webhook）。

## 功能特性

- 📱 **多渠道转发**：支持企业微信、飞书、钉钉、自定义POST等4种转发渠道
- 🎯 **智能匹配**：支持关键词匹配，可配置多条转发规则
- 🔄 **异步处理**：采用协程机制，支持并发转发多个渠道
- 📊 **设备信息**：自动附加信号强度、运营商、位置等设备信息
- 🛡️ **容错机制**：网络异常自动恢复，转发失败备用通知
- ⚡ **低功耗**：定时内存回收，看门狗保护，设备自动重启

## 硬件要求

[推荐淘宝购买链接](https://item.taobao.com/item.htm?id=989345949846)

- **设备型号**：Air780E（支持Air780EPV芯片）
- **网络**：4G移动网络（需要SIM卡）
- **存储**：至少64KB Flash空间
- **电源**：3.3V-4.2V供电

## 快速开始

### 1. 硬件连接

```
Air780E开发板
├── SIM卡槽 → 插入4G SIM卡
├── 天线接口 → 连接4G天线
└── USB接口 → 连接电脑（供电和调试）
```

### 2. 配置文件修改

#### 系统配置 (`config.lua`)

```lua
return {
    -- 主从机角色
    ROLE = "MASTER",  -- MASTER: 主机, SLAVE: 从机

    -- 开机通知
    BOOT_NOTIFY = true,

    -- 是否追加设备信息
    NOTIFY_APPEND_MORE_INFO = true,

    -- 网络超时配置
    NETWORK_TIMEOUT_DEFAULT = 60 * 1000,  -- 1分钟
    NETWORK_TIMEOUT_LONG = 5 * 60 * 1000, -- 5分钟

    -- 其他配置...
}
```

#### 转发规则配置 (`forward_config.lua`)

```lua
return {
    -- 匹配所有消息，转发到企业微信
    {
        channel = "wecom",
        keyword = "all",
        webhook = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=your-key"
    },

    -- 匹配包含"验证码"的消息，转发到飞书
    {
        channel = "feishu",
        keyword = "验证码",
        webhook = "https://open.feishu.cn/open-apis/bot/v2/hook/your-id"
    },

    -- 更多规则...
}
```

### 3. 下载工具

1. [下载烧录工具](https://luatos.com/luatools/download/last)
2. 下载本项目

### 4. 烧录固件

根据自己开发板型号选择对应的固件目前支持Air780E和Air780EPV，都在rom目录里

![烧录方法](/doc/imgs/image.png)

## 配置详解

### 支持的转发渠道

#### 1. 企业微信 (wecom)
```lua
{
    channel = "wecom",
    keyword = "all",
    webhook = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=your-webhook-key"
}
```

#### 2. 飞书 (feishu)
```lua
{
    channel = "feishu",
    keyword = "all",
    webhook = "https://open.feishu.cn/open-apis/bot/v2/hook/your-webhook-id"
}
```

#### 3. 钉钉 (dingding)
```lua
{
    channel = "dingding",
    keyword = "all",
    webhook = "https://oapi.dingtalk.com/robot/send?access_token=your-token",
    secret = "your-secret"  -- 可选，签名验证
}
```

#### 4. 自定义POST (custom_post)
```lua
{
    channel = "custom_post",
    keyword = "all",
    webhook = "https://your-api.com/webhook",
    content_type = "application/json",
    post_body = {
        title = "短信通知",
        desp = "内容: {msg}"  -- {msg}会被替换为实际消息
    }
}
```

### 关键词匹配规则

- `"all"`：匹配所有消息
- 部分匹配：不区分大小写，包含关键词即匹配
- 多规则：一条消息可匹配多条规则，同时转发到多个渠道

## 使用示例

### 短信控制指令

设备支持短信控制指令格式：`SMS,接收号码,短信内容`

```
示例：SMS,13800138000,这是一条测试短信
```

### 电源键操作

- **短按**：发送测试消息 `#ALIVE`
- **双击**：发送开机测试消息 `#BOOT_TEST_xxx`
- **长按**：查询流量信息

### 设备信息显示

系统会自动在通知中附加以下信息：

```
本机号码: 13800138000 (系统获取)
开机时长: 02:30:15
运营商: 中国移动
信号强度: -85dBm (RSRP) CSQ:20
位置: https://maps.google.com/?q=39.9042,116.4074
```

## 状态监控

### 信号强度指标

- **RSRP**：-44到-140 dBm（主要指标）
  - -50 ~ -80：信号优秀
  - -80 ~ -90：信号良好
  - -90 ~ -100：信号一般
  - < -100：信号较差
- **CSQ**：0-31（参考指标）

### 日志查看

设备启动后可通过串口查看详细日志：

```
[INFO] main: air780e_forwarder 1.0.0
[INFO] main: 开机原因 0
[INFO] util_forward: 初始化转发模块
[INFO] util_forward: 规则数量 25
[INFO] main: 转发模块初始化成功
[INFO] main: 准备发送开机通知
```

## 故障排除

### 常见问题

1. **无法接收短信**
   - 检查SIM卡是否正常插入
   - 确认4G网络信号强度
   - 查看是否注册到网络

2. **转发失败**
   - 检查webhook URL是否正确
   - 确认网络连接正常
   - 查看目标渠道是否正常

3. **设备频繁重启**
   - 检查电源供电是否稳定
   - 查看是否有内存不足
   - 确认看门狗配置

### 调试命令

```lua
-- 查看网络状态
local status = mobile.status()
log.info("network", status)

-- 查看信号强度
local rsrp = mobile.rsrp()
local csq = mobile.csq()
log.info("signal", "RSRP:", rsrp, "CSQ:", csq)

-- 发送测试消息
util_forward.forwardMessage("#TEST_MESSAGE", "TEST")
```

## 开发说明

### 添加新渠道

1. 在 `util_notify_channel.lua` 中实现渠道函数
2. 在 `util_forward.lua` 的 `sendByChannel()` 中添加判断
3. 在 `forward_config.lua` 中添加配置示例

### 自定义消息处理

可修改 `main.lua` 中的短信回调函数实现自定义消息处理逻辑：

```lua
sms.setNewSmsCb(function(sender_number, sms_content, m)
    -- 自定义处理逻辑
    local time = os.date("%Y-%m-%d %H:%M:%S")
    -- 调用转发
    util_forward.forwardSms(sms_content, sender_number, time)
end)
```

## 许可证

本项目基于MIT许可证开源。

## 技术支持

如有问题或建议，请通过以下方式联系：

- 提交Issue：[GitHub Issues](https://github.com/lostmaniac/air780e_forwarder/issues)
- 技术文档：查看项目根目录下的 `CLAUDE.md`
- 开发指南：参考代码注释和配置文件示例

---

**注意**：请确保在合法合规的前提下使用本设备，遵守相关法律法规。
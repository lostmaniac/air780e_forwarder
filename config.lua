return {
    -- 角色类型, 用于区分主从机, 仅当使用串口转发时才需要配置
    -- MASTER: 主机, 可主动联网; SLAVE: 从机, 不可主动联网, 通过串口发送数据
    ROLE = "MASTER",

    -- 设备自动重启配置
    RESTART_ENABLED = true,                    -- 是否启用自动重启
    RESTART_INTERVAL = 72 * 60 * 60 * 1000,    -- 重启间隔，72小时
    
    -- 定时查询流量间隔, 单位毫秒, 设置为 0 关闭
    QUERY_TRAFFIC_INTERVAL = 0,

    -- 定时基站定位间隔, 单位毫秒, 设置为 0 关闭
    LOCATION_INTERVAL = 0,

    -- 定时开关飞行模式间隔, 单位毫秒, 设置为 0 关闭
    FLYMODE_INTERVAL = 1000 * 60 * 60 * 12,

    -- 定时同步时间间隔, 单位毫秒, 设置为 0 关闭
    SNTP_INTERVAL = 1000 * 60 * 60 * 6,

    -- 定时上报间隔, 单位毫秒, 设置为 0 关闭
    REPORT_INTERVAL = 0,

    -- 开机通知 (会消耗流量)
    BOOT_NOTIFY = true,

    -- 是否过滤上线通知 (设置为false可以收到开机通知)
    FILTER_BOOT_NOTIFY = false,

    -- 通知内容追加更多信息 (通知内容增加会导致流量消耗增加)
    NOTIFY_APPEND_MORE_INFO = true,

    -- 通知最大重发次数
    NOTIFY_RETRY_MAX = 20,

    -- 本机号码, 优先使用 mobile.number() 接口获取, 如果获取不到则使用此号码
    FALLBACK_LOCAL_NUMBER = "",

    -- SIM 卡 pin 码
    PIN_CODE = "",

    -- 网络超时配置 (单位: 毫秒)
    NETWORK_TIMEOUT_DEFAULT = 1000 * 60,      -- 默认1分钟
    NETWORK_TIMEOUT_LONG = 1000 * 60 * 5,     -- 长超时5分钟
    NETWORK_TIMEOUT_SHORT = 1000 * 10,        -- 短超时10秒
    NETWORK_TIMEOUT_LOCATION = 1000 * 30,     -- 定位服务30秒

    -- 网络恢复配置
    FLYMODE_THRESHOLD = 4,                     -- 连续失败多少次才开启飞行模式
    FLYMODE_ENABLE = true,                     -- 是否启用飞行模式自动恢复
}

--[[
任务管理器
用于统一管理LuatOS中的任务创建、删除和生命周期
]]

local TaskManager = {
    tasks = {},
    debug = false
}

--[[
创建命名任务
@param name string 任务名称
@param func function 任务函数
@param callback function 错误回调函数
@return 任务对象
]]
function TaskManager.create(name, func, callback)
    if TaskManager.debug then
        log.info("TaskManager", "creating task:", name)
    end

    -- 删除已存在的同名任务
    TaskManager.delete(name)

    local task = sysplus.taskInitEx(function()
        local success, err = pcall(func)
        if not success then
            log.error("TaskManager", name, "task error:", err)
            if callback then callback(false, err) end
        else
            if TaskManager.debug then
                log.info("TaskManager", name, "task completed successfully")
            end
            if callback then callback(true, nil) end
        end
        TaskManager.tasks[name] = nil
    end, name, function(err)
        log.error("TaskManager", name, "init error:", err)
        TaskManager.tasks[name] = nil
        if callback then callback(false, err) end
    end)

    TaskManager.tasks[name] = task
    return task
end

--[[
删除指定任务
@param name string 任务名称
@return boolean 是否删除成功
]]
function TaskManager.delete(name)
    if TaskManager.tasks[name] then
        if TaskManager.debug then
            log.info("TaskManager", "deleting task:", name)
        end
        sysplus.taskDel(name)
        TaskManager.tasks[name] = nil
        return true
    end
    return false
end

--[[
检查任务是否存在
@param name string 任务名称
@return boolean 任务是否存在
]]
function TaskManager.exists(name)
    return TaskManager.tasks[name] ~= nil
end

--[[
获取所有活跃任务列表
@return table 任务名称列表
]]
function TaskManager.list()
    local list = {}
    for name, _ in pairs(TaskManager.tasks) do
        table.insert(list, name)
    end
    return list
end

--[[
清理所有任务
]]
function TaskManager.cleanup()
    if TaskManager.debug then
        log.info("TaskManager", "cleaning up all tasks")
    end

    for name, _ in pairs(TaskManager.tasks) do
        TaskManager.delete(name)
    end
end

--[[
设置调试模式
@param enable boolean 是否开启调试
]]
function TaskManager.setDebug(enable)
    TaskManager.debug = enable
end

--[[
创建循环任务（带退出机制）
@param name string 任务名称
@param func function 循环执行的函数
@param interval number 循环间隔（毫秒）
@param callback function 错误回调函数
@return 任务对象
]]
function TaskManager.createLoop(name, func, interval, callback)
    if not interval or interval <= 0 then
        interval = 1000  -- 默认1秒
    end

    local should_stop = false

    local task_func = function()
        while not should_stop do
            local success, err = pcall(func)
            if not success then
                log.error("TaskManager", name, "loop error:", err)
                if callback then callback(false, err) end
            end

            -- 检查是否应该停止
            if should_stop then
                break
            end

            sys.wait(interval)
        end
        if TaskManager.debug then
            log.info("TaskManager", name, "loop task stopped")
        end
    end

    local task = TaskManager.create(name, task_func, callback)

    -- 返回停止函数
    return task, function()
        should_stop = true
    end
end

--[[
停止循环任务
@param name string 任务名称
]]
function TaskManager.stopLoop(name)
    -- 通过删除任务来停止循环
    TaskManager.delete(name)
end

return TaskManager
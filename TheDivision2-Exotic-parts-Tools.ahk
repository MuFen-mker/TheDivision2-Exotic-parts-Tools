#Requires AutoHotkey v2.0
#UseHook
#SingleInstance Force

if !A_IsAdmin {
    Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
    ExitApp
}

;=======全局变量=========
;EDRSilencer路径
global windowstite := "TheDivision2-Exotic-parts-Tools-1.0.5"
global pbPath := A_ScriptDir "\EDRSilencer\EDRSilencer.exe"
global stopLoop := false
global TheDivision2Path := IniRead(A_ScriptDir "\config.ini", "Game", "TheDivision2Path", "")
;检测网络连接
global adapter := IniRead(A_ScriptDir "\config.ini", "Network", "Adapter", "")
SplitPath(TheDivision2Path, &fileName)  ; 提取文件名
global gamefile := fileName
; 断网方式常量
global NET_FIREWALL := 1      ; 防火墙规则
global NET_ADAPTER := 2       ; 禁用网卡
global NET_PROXYBRIDGE := 3   ; EDRSilencer
global configFile := A_ScriptDir "\config.ini"
global NetMethod := NET_FIREWALL
;运行状态显示
global iterationCount := 0
global numberOfErrors := 0
global netError := 0
global logBuffer := []          ; 存储最近的操作记录
global maxLogLines := 100       ; 最多保留 100 条记录
; 检查文件是否存在，不存在则释放
if !FileExist(pbPath) {
    ; 确保目标目录存在
    targetDir := A_ScriptDir "\EDRSilencer"
    if !DirExist(targetDir)
        DirCreate(targetDir)
    ; 尝试释放文件
    try {
        FileInstall "EDRSilencer\EDRSilencer.exe", pbPath, 1
    } catch as e {
        MsgBox "程序无法读写所在目录，请尝试使用管理员权限运行，或将程序移动到其他目录下"
        ExitApp
    }
}

if !FileExist(pbPath){
    MsgBox "程序异常退出,原因:`nEDRSilencer 未找到,请确认脚本目录下EDRSilencer/EDRSilencer.exe是否存在"
    ExitApp
}

; ========== 获取网卡列表 ==========
GetNetworkAdapters() {
    adapters := []
    try {
        wmi := ComObject("WbemScripting.SWbemLocator").ConnectServer("", "root\cimv2")
        query := "SELECT * FROM Win32_NetworkAdapter WHERE PhysicalAdapter=True AND NetEnabled=True"
        for adapter in wmi.ExecQuery(query) {
            if (adapter.NetConnectionID)
                adapters.Push(adapter.NetConnectionID)
        }
    }
    return adapters
}

; ========== GUI 回调函数 ==========
BrowseFile(*) {
    global editPath
    selected := FileSelect("3", , "选择 TheDivision2.exe", "可执行文件 (*.exe)")
    if selected != ""
        editPath.Value := selected
}

RefreshAdapterList() {
    global comboAdapter, savedAdapter
    adapters := GetNetworkAdapters()
    comboAdapter.Delete()
    for ad in adapters
        comboAdapter.Add([ad])
    if adapters.Length = 0
        comboAdapter.Add(["未检测到可用网卡"])

    ; 恢复之前保存的适配器
    if savedAdapter {
        for i, ad in adapters {
            if ad = savedAdapter {
                comboAdapter.Choose(i)
                break
            }
        }
    }
}

; 检查并关闭窗口（如果配置有效）
CheckAndClose() {
    global editPath, comboAdapter, configFile, TheDivision2Path, NetworkAdapter,gamefile,NetMethod
    global comboNetMethod
    path := Trim(editPath.Value)
    adapter := Trim(comboAdapter.Text)
    if path = "" {
        MsgBox "请先选择游戏路径！", "提示", 0x40
        return false
    }
    if adapter = "" || adapter = "未检测到可用网卡" {
        MsgBox "请先选择一个有效的网络适配器！", "提示", 0x40
        return false
    }
    ; 保存配置
    IniWrite path, configFile, "Game", "TheDivision2Path"
    IniWrite adapter, configFile, "Network", "Adapter"
    ; 保存断网方式
    IniWrite comboNetMethod.Value, configFile, "Settings", "NetMethod"
    ; 更新全局变量
    TheDivision2Path := path
    NetworkAdapter := adapter
    NetMethod := comboNetMethod.Value
    SplitPath(TheDivision2Path, &fileName)  ; 提取文件名
    gamefile := fileName
    return true
}

; 窗口关闭事件（右上角 X）
GuiClose(*) {
    if CheckAndClose() {
        mainGui.Destroy()
    }
    return true
}

; ========== GUI ==========
global mainGui, editPath, comboAdapter, savedAdapter
global TheDivision2Path, NetworkAdapter   ; 主脚本使用的全局变量

mainGui := Gui()
mainGui.Title := windowstite
mainGui.SetFont("s10")
; ========== 说明文本 ==========
mainGui.Add("Text", "x10 y260 w480 h30", "网线和WIFI使用其中一个，保存后F10运行，F12强制停止程序")
; 游戏路径区域
mainGui.Add("Text", "x10 y10 w300 h30", "请选择《全境封锁2》的主程序路径：")
editPath := mainGui.Add("Edit", "x10 y50 w400 h25 ReadOnly")
btnBrowse := mainGui.Add("Button", "x420 y49 w80 h27", "浏览")

; 网卡选择区域
mainGui.Add("Text", "x10 y110 w300 h30", "选择当前连接的网络适配器：")
comboAdapter := mainGui.Add("ComboBox", "x10 y150 w300 h200 Choose1")
btnRefresh := mainGui.Add("Button", "x320 y148 w80 h27", "刷新")

; 关闭按钮
btnCancel := mainGui.Add("Button", "x10 y200 w80 h30", "保存并关闭窗口")

mainGui.Add("Text", "x10 y280 w300 h30", "选择断网方式：")
comboNetMethod := mainGui.Add("ComboBox", "x10 y310 w400 h200 Choose1", ["防火墙规则（裸连网络稳定，响应快）", "禁用网卡（暴力断网，需选择网络适配器）", "EDRSilencer（WFP过滤，可使用加速器）"])

; 加载已保存的选项，确保是有效整数
savedMethod := IniRead(configFile, "Settings", "NetMethod", NET_FIREWALL)
savedMethod := savedMethod + 0   ; 转换为整数
if (savedMethod < 1 || savedMethod > 3)
    savedMethod := NET_FIREWALL
comboNetMethod.Choose(savedMethod)

; 加载已有配置（仅用于显示）
savedPath := IniRead(configFile, "Game", "TheDivision2Path", "")
if savedPath
    editPath.Value := savedPath

savedAdapter := IniRead(configFile, "Network", "Adapter", "")
RefreshAdapterList()   ; 填充网卡列表

; 绑定事件
btnBrowse.OnEvent("Click", BrowseFile)
btnRefresh.OnEvent("Click", (*) => RefreshAdapterList())
btnCancel.OnEvent("Click", (*) => CheckAndClose() && mainGui.Destroy())
mainGui.OnEvent("Close", GuiClose)   ; 处理右上角 X

; 显示窗口
mainGui.Show()

; 等待用户关闭窗口
WinWaitClose windowstite

; ========== 窗口关闭后，从配置文件读取配置 ==========
TheDivision2Path := IniRead(configFile, "Game", "TheDivision2Path", "")
NetworkAdapter := IniRead(configFile, "Network", "Adapter", "")
; 读取断网方式，默认为防火墙规则
NetMethod := IniRead(configFile, "Settings", "NetMethod", NET_FIREWALL)

; 颜色检测函数（支持重试，使用 DllCall 获取颜色）
; 参数：
;   hwnd        - 窗口句柄
;   percentX, percentY - 相对于窗口左上角的偏移百分比
;   targetColor - 期望的颜色（十六进制，如 0x136AFF）
;   variation   - 容差（0~255），推荐 10~30，默认 20
;   maxRetries  - 最大重试次数，默认 20
;   retryDelay  - 重试间隔（毫秒），默认 200
;   debug       - 是否显示F10调试信息，默认 false
; 返回：匹配返回 true，否则 false
CheckColorWithRetry(hwnd, percentX, percentY, targetColor, variation := 20, maxRetries := 20, retryDelay := 200, debug := false) {
        ; 检查窗口句柄是否有效
        loop maxRetries {
            if !WinExist("ahk_id " hwnd){
                return false
            }
        WinGetPos(&winX, &winY, &winW, &winH, hwnd)
        ; 将百分比转换为绝对坐标
        screenX := winW * percentX
        screenY := winH * percentY

        if debug {
            ToolTip "检查颜色位置: " screenX "," screenY "`n预期: " Format("{:06X}", targetColor)
            SetTimer () => ToolTip(), -1000
        } 

        ; 使用 DllCall 获取颜色
        hDC := DllCall("GetDC", "Ptr", 0, "Ptr")
        actualColor := DllCall("GetPixel", "Ptr", hDC, "Int", screenX, "Int", screenY, "UInt")
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hDC)

        if debug {
            ToolTip "实际颜色: " Format("{:06X}", actualColor)
            SetTimer () => ToolTip(), -1000
        }

        if ColorsMatch(actualColor, targetColor, variation) {
            return true
        }

        if (A_Index < maxRetries)
            Sleep retryDelay
    }
    return false
}


; 颜色匹配辅助函数（保持不变）
ColorsMatch(color1, color2, variation) {
    r1 := (color1 >> 16) & 0xFF
    g1 := (color1 >> 8) & 0xFF
    b1 := color1 & 0xFF
    r2 := (color2 >> 16) & 0xFF
    g2 := (color2 >> 8) & 0xFF
    b2 := color2 & 0xFF
    return (Abs(r1 - r2) <= variation && Abs(g1 - g2) <= variation && Abs(b1 - b2) <= variation)
}

; 强制关闭指定进程的所有 TCP 连接
CloseTCPConnections(pid) {
    try {
        shell := ComObject("WScript.Shell")
        exec := shell.Exec('netstat -ano | findstr "' pid '"')
        output := exec.StdOut.ReadAll()
        
        lines := StrSplit(Trim(output), "`n", "`r")
        for line in lines {
            if !InStr(line, "TCP") || InStr(line, "LISTENING")
                continue
                
            ; 解析格式: TCP  192.168.1.100:12345  1.2.3.4:80  ESTABLISHED  1234
            parts := StrSplit(Trim(line), " ", "`t")
            cleanParts := []
            for p in parts {
                if p != ""
                    cleanParts.Push(p)
            }
            if cleanParts.Length < 5
                continue
                
            localAddr := cleanParts[2]
            remoteAddr := cleanParts[3]
            
            localParts := StrSplit(localAddr, ":")
            remoteParts := StrSplit(remoteAddr, ":")
            if localParts.Length < 2 || remoteParts.Length < 2
                continue
                
            localIP := localParts[1]
            localPort := localParts[2]
            remoteIP := remoteParts[1]
            remotePort := remoteParts[2]
            
            ; 构造 MIB_TCPROW
            row := Buffer(20, 0)
            ; 状态: 12 = MIB_TCP_STATE_DELETE_TCB
            NumPut("UInt", 12, row, 0)
            
            ; 本地地址（网络字节序）
            ipParts := StrSplit(localIP, ".")
            localAddrBin := (ipParts[1] << 24) | (ipParts[2] << 16) | (ipParts[3] << 8) | ipParts[4]
            NumPut("UInt", localAddrBin, row, 4)
            
            ; 本地端口（网络字节序）
            NumPut("UInt", (localPort << 8) | (localPort >> 8), row, 8)
            
            ; 远程地址
            ipParts := StrSplit(remoteIP, ".")
            remoteAddrBin := (ipParts[1] << 24) | (ipParts[2] << 16) | (ipParts[3] << 8) | ipParts[4]
            NumPut("UInt", remoteAddrBin, row, 12)
            
            ; 远程端口
            NumPut("UInt", (remotePort << 8) | (remotePort >> 8), row, 16)
            
            ; 调用 SetTcpEntry
            DllCall("iphlpapi\SetTcpEntry", "Ptr", row)
        }
        return true
    } catch {
        return false
    }
}

;==断网==
DisableAdapter(adapterName) {
    global NetMethod, TheDivision2Path, pbPath
    if (NetMethod = NET_FIREWALL) {
        ; 防火墙规则
        RunWait 'netsh advfirewall firewall add rule name="BlockGame_Out" dir=out action=block program="' TheDivision2Path '" enable=yes', , "Hide"
        RunWait 'netsh advfirewall firewall add rule name="BlockGame_In" dir=in action=block program="' TheDivision2Path '" enable=yes', , "Hide"
        ToolTip "已断开网络(防火墙规则)"
        SetTimer () => ToolTip(), -2000
    } else if (NetMethod = NET_ADAPTER) {
        ; 禁用网卡
        RunWait 'netsh interface set interface "' adapterName '" admin=disable', , "Hide"
        ToolTip "已断开网络(禁用网卡)"
        SetTimer () => ToolTip(), -2000
    } else if (NetMethod = NET_PROXYBRIDGE) {
        ; EDRSilencer
        RunWait '*RunAs "' pbPath '" block "' TheDivision2Path '"', , "Hide"
         ; 2. 获取游戏进程 PID
        SplitPath(TheDivision2Path, &gameExe)
        ; 3. 强制关闭所有现有 TCP 连接（可选）
        if ProcessExist(gameExe) {
            pid := WinGetPID("ahk_exe " gameExe)
            if pid {
                CloseTCPConnections(pid)
            }
        } else {
            ; 游戏未运行，跳过或提示
            ToolTip "游戏未运行，跳过关闭旧的TCP连接"
        }
        ToolTip "已断开网络(WFP过滤)"
        SetTimer () => ToolTip(), -2000
    }
}
;========

;==恢复网络==
EnableAdapter(adapterName) {
    global NetMethod, pbPath
    if (NetMethod = NET_FIREWALL) {
        ; 删除防火墙规则
        RunWait 'netsh advfirewall firewall delete rule name="BlockGame_Out"', , "Hide"
        RunWait 'netsh advfirewall firewall delete rule name="BlockGame_In"', , "Hide"
    } else if (NetMethod = NET_ADAPTER) {
        ; 启用网卡
        RunWait 'netsh interface set interface "' adapterName '" admin=enable', , "Hide"
    } else if (NetMethod = NET_PROXYBRIDGE) {
        ; 删除 EDRSilencer 规则
        RunWait '*RunAs "' pbPath '" unblockall', , "Hide"
    }
}
;===========

; 创建悬浮窗
FloatingWindow := Gui("+AlwaysOnTop +ToolWindow -Caption +LastFound")
FloatingWindow.BackColor := "000000"
WinSetTransparent 180, FloatingWindow
WinSetExStyle "+0x20", FloatingWindow

; 添加多行文本控件，手动指定位置和宽度（确保足够宽）
textCtrl := FloatingWindow.Add("Text", "cWhite x10 y10 w200 h100", "循环次数:0`n错误重置次数:0`n掉线重连次数:0")
textCtrl.SetFont("s12", "微软雅黑")

; 手动设定窗口大小（请根据实际显示效果调整）
winWidth := 220   ; 宽度比文本宽度稍宽
winHeight := 100   ; 高度足够显示三行文字（若下半部分不显示，请增加此值，例如 100、110）

; 窗口位置（屏幕右上角，距右边缘 10 像素，距上边缘 10 像素）
xPos := A_ScreenWidth - winWidth - 10
yPos := 10

; 显示窗口
FloatingWindow.Show("x" xPos " y" yPos " w" winWidth " h" winHeight " NoActivate")

; 定时更新显示
SetTimer(UpdateDisplay, 1000)

UpdateDisplay() {
    global iterationCount, numberOfErrors, netError
    iter := IsSet(iterationCount) ? iterationCount : 0
    err := IsSet(numberOfErrors) ? numberOfErrors : 0
    net := IsSet(netError) ? netError : 0
    textCtrl.Value := "循环次数:" iter "`n错误重置次数:" err "`n掉线重连次数:" net
}

LogStep(stepDesc) {
    global logBuffer, maxLogLines
    timestamp := FormatTime("yyyy-MM-dd HH:mm:ss")
    logBuffer.Push(timestamp " - " stepDesc)
    if logBuffer.Length > maxLogLines
        logBuffer.RemoveAt(1)
}

; 保存日志到脚本目录下的 log.txt
SaveLogToFile() {
    global logBuffer
    logFilePath := A_ScriptDir "\log.txt"
    content := ""
    for line in logBuffer
        content .= line "`n"
    FileOpen(logFilePath, "w").Write(content)
    ToolTip "日志已保存到 " logFilePath
    SetTimer () => ToolTip(), -2000
}

;===========启动重置脚本============
reboot(){
    ToolTip "重置进程执行中..."
    SetTimer () => ToolTip(), -2000
    global adapter
    global gamefile
    global numberOfErrors
    global netError
    global TheDivision2Path
    EnableAdapter(adapter)
    SaveLogToFile()
    gamghwd := WinExist("ahk_exe" gamefile)
    Sleep 500
    ;检测是否掉线
    lopNbr := 0
    if gamghwd{
        loop 10{
            networkerror := CheckColorWithRetry(gamghwd,0.431640625,0.55625,0x3C3A93,20,10,500,false)
            if networkerror{
                SendInput "{Space down}"
                Sleep 100
                SendInput "{Space up}"
                Sleep 100
                SendInput "{Space down}"
                Sleep 100
                SendInput "{Space up}"
                Sleep 500
                mainObj := CheckColorWithRetry(gamghwd,0.50234375,0.936,0x136AFF,5,150,1000,false)
                if mainObj{
                    Sleep 1000
                    Loop "已恢复，守护进程退出"
                    SetTimer () => ToolTip(), -1500
                    netError += 1
                    RunAutomation()
                    return
                }else{
                    Sleep 10000
                }
            }
            lopNbr += 1
            ToolTip "掉线检测重试：" lopNbr "/10"
            Sleep 3000
        }
        ToolTip
    }else{
        ToolTip "游戏崩溃，执行重启步骤"
        SetTimer () => ToolTip(), -1500
    }
    Sleep 5000
    re:
    if WinExist("ahk_exe" gamefile) {
        ToolTip "游戏窗口存在,杀死游戏进程"
        SetTimer () => ToolTip(), -1500
        RunWait 'taskkill /f /im ' gamefile, , "Hide"
    } else {
        ToolTip "未检测到游戏窗口，检测游戏进程中"
        SetTimer () => ToolTip(), -1500
        if ProcessExist(gamefile) {
            ToolTip "游戏正在运行,终止游戏进程中"
            SetTimer () => ToolTip(), -1500
            RunWait 'taskkill /f /im ' gamefile, , "Hide"
        } else {
            ToolTip "未运行,执行启动"
        }
    }
    RunWait 'taskkill /f /im ' "upc.exe", , "Hide"
    Sleep 10000
    maxRetries := 60 ;重试次数
    retryCount := 0 ;初始化计量
    found := false

    while !found && retryCount < maxRetries {
        retryCount += 1

    if ProcessExist(gamefile){
            ToolTip "游戏运行中，重试... (" retryCount "/" maxRetries ")"
            SetTimer () => ToolTip(), -1500
            RunWait 'taskkill /f /im ' gamefile, , "Hide"
            Sleep 10000   ; 等待10秒后重试
        } else {
            ToolTip "开始运行游戏"
            SetTimer () => ToolTip(), -1500 
            Run TheDivision2Path
            found := true
        }
    }

    if !found {
        ToolTip "超过最大重试次数，脚本退出"
        SetTimer () => ToolTip(), -1500
        ExitApp
    }
    autto := 0

    loop 60{
    gamghwd := WinExist("ahk_exe" gamefile)
        if gamghwd {
        ToolTip "已捕获游戏窗口"
        SetTimer () => ToolTip(), -2000
        break
        }
        Sleep 5000
    }
    if !gamghwd{
        ToolTip "未找到游戏窗口，重新运行"
        SetTimer () => ToolTip(), -1500
        goto re
    }

    Sleep 2000
    WinActivate gamghwd               ; 激活（聚焦）
    WinMaximize gamghwd               ; 全屏
        ;进入主页面
        ;检测是否到选人界面
        advertisement := true
        Sleep 30000
        ToolTip "开始检测是否到选人界面"
        foundol := CheckColorWithRetry(gamghwd,0.50234375,0.9361,0x136AFF,5, 60,1000,false)
        found2 :=  CheckColorWithRetry(gamghwd,0.498046875,0.250694,0x136AFF,5, 30,1000,false)
        loop 30{
            if foundol{
                Sleep 1000
                Loop "已恢复，守护进程退出"
                SetTimer () => ToolTip(), -1500
                numberOfErrors += 1
                RunAutomation()
                return
            }else{
                if found2{
                    SendInput "{Space down}"
                    Sleep 50
                    SendInput "{Space up}"
                    Sleep 500
                }else{
                    advertisement := false
                }
            }
        }
        if !advertisement {
            goto re
        }
    }
;==================================

;主要函数
RunAutomation(){
    ToolTip "开始运行..."
    SetTimer () => ToolTip(), -1500
    ;============初始化==================
    global stopLoop
    stopLoop := false
    global adapter
    global gamefile
    global iterationCount
    gameHwnd := WinExist("ahk_exe " gamefile)
    Sleep 500
    ; 获取游戏窗口句柄
    if !gameHwnd {
        MsgBox "未找到游戏窗口，请确保游戏正在运行`n" gamefile "`n" gameHwnd
        SetTimer () => ToolTip(), -1500
        return
    }
    ;===================================
    while !stopLoop {
        totalRetries := 3
        found := false
        ;检测是否在主角色
        mainObj := CheckColorWithRetry(gameHwnd,0.50234375,0.936,0x136AFF,5,150,1000,false)
        if mainObj{
            ToolTip "已检测到主角色，开始切换角色"
            SetTimer () => ToolTip(), -1500
            loop totalRetries {
                SendMode "Input"
                Loop 5 {
                    SendInput "{c down}"
                    Sleep 30
                    SendInput "{c up}"
                    Sleep 100
                }
                Sleep 500

                ; 检测切换到新建角色
                found := CheckColorWithRetry(gameHwnd,0.551953125,0.93125,0x136AFF,5,10,200,false)

                if found {
                    ToolTip "已检测到控件准备断网"
                    SetTimer () => ToolTip(), -1500
                    break   ; 找到按钮，跳出外层循环
                }
                ; 未找到，等待一下再重试整个流程
                ToolTip "未检测到控件，重试切换"
                SetTimer () => ToolTip(), -2000
                Sleep 3000
            }

            if found {
                next:
                Sleep 500
                SendInput "{Space down}"
                Sleep 30
                SendInput "{Space up}"
                ;选择战役
                Sleep 800
                SendInput "{Space down}"
                Sleep 500
                SendInput "{Space up}"   
                Sleep 1000
                ; 断网
                DisableAdapter(adapter)
                foundSecond := CheckColorWithRetry(gameHwnd,0.431640625,0.55625,0x3C3A93,20,300,500,false)
                if foundSecond{
                    ToolTip "已检测到控件恢复联网"
                    SetTimer () => ToolTip(), -1500
                    ; 恢复
                    EnableAdapter(adapter)
                    Sleep 30
                    SendInput "{Space down}"
                    Sleep 100
                    SendInput "{Space up}"
                    Sleep 1000
                    SendInput "{Space down}"
                    Sleep 100
                    SendInput "{Space up}"
                    ;检测切换主角色
                    nextEquipment:
                    foundtheer := CheckColorWithRetry(gameHwnd,0.50234375,0.936,0x136AFF,5,150,1000,false)
                    if foundtheer{
                        ToolTip "已检测到控件，继续主角色拆解零件"
                        SetTimer () => ToolTip(), -1500
                        Sleep 1000
                        SendInput "{Space down}"
                        Sleep 50
                        SendInput "{Space up}"
                        foundf := CheckColorWithRetry(gameHwnd,0.029296875,0.9263889,0xFFFFFF,5,150,1000,false)
                        if foundf{
                            ToolTip "已检测到控件，确认已成功进入世界，开始移动"
                            SetTimer () => ToolTip(), -2000
                            Sleep 1500
                            Send "{W down}{D down}"
                            Sleep 220
                            Send "{W up}"
                            Sleep 120
                            Send "{D up}"
                            Sleep 200
                            Send "{F down}"
                            Sleep 1800
                            Send "{F up}"
                            ;进入装备页面
                            Sleep 500
                            equipment := CheckColorWithRetry(gameHwnd,0.725390625,0.240278,0x000000,0,5,500,false)
                            equipmentnd := CheckColorWithRetry(gameHwnd,0.029296875,0.9263889,0xFFFFFF,0,5,100,false)
                            if equipment && !equipmentnd{
                                ToolTip "确认进入装备页面"
                                SetTimer () => ToolTip(), -2000
                                SendInput "{E down}"
                                Sleep 50
                                SendInput "{E up}"
                                Sleep 100
                                equipment2 := CheckColorWithRetry(gameHwnd,0.68125,0.490278,0x000000,5, 30,500,false)
                                if equipment2 {
                                    ToolTip "开始收取武器"
                                    SetTimer () => ToolTip(), -2000
                                    Sleep 700
                                    SendInput "{D down}"
                                    Sleep 50
                                    SendInput "{D up}"
                                    Sleep 100
                                    SendInput "{W down}"
                                    Sleep 50
                                    SendInput "{W up}"
                                    Sleep 100
                                    SendInput "{Space down}"
                                    Sleep 50
                                    SendInput "{Space up}"
                                    Sleep 1200
                                    SendInput "{X down}"
                                    Sleep 50
                                    SendInput "{X up}"
                                    Sleep 100
                                    SendInput "{S down}"
                                    Sleep 50
                                    SendInput "{S up}"
                                    Sleep 100
                                    SendInput "{Space down}"
                                    Sleep 50
                                    SendInput "{Space up}"
                                    Sleep 300
                                    Loop 4 {
                                        SendInput "{F down}"
                                        Sleep 50
                                        SendInput "{F up}"
                                        Sleep 300
                                    }
                                    Sleep 200
                                    Loop 3{
                                        SendInput "{Q down}"
                                        Sleep 50
                                        SendInput "{Q up}"
                                        Sleep 50
                                    }
                                        Sleep 450
                                        ToolTip "开始拆解"
                                        SetTimer () => ToolTip(), -2000
                                        SendInput "{Tab down}"
                                        Sleep 1800
                                        SendInput "{Tab up}"
                                        Sleep 200
                                        SendInput "{Space down}"
                                        Sleep 50
                                        SendInput "{Space up}"
                                        Sleep 100
                                        SendInput "{ESC down}"
                                        Sleep 1500
                                        SendInput "{ESC up}"
                                        Sleep 100
                                }else{
                                    SendInput "{ESC down}"
                                    Sleep 1500
                                    SendInput "{ESC up}"
                                    Sleep 100
                                }
                            }else{
                                SendInput "{ESC down}"
                                Sleep 50
                                SendInput "{ESC up}"
                                Sleep 500
                                SendInput "{G down}"
                                Sleep 50
                                SendInput "{G up}"
                                Sleep 500
                                SendInput "{Space down}"
                                Sleep 50
                                SendInput "{Space up}"
                                goto nextEquipment
                            }
                            ;退出
                            SendInput "{ESC down}"
                            Sleep 50
                            SendInput "{ESC up}"
                            Sleep 500
                            Send "{G down}"
                            Sleep 50
                            Send "{G up}"
                            Sleep 500
                            SendInput "{Space down}"
                            Sleep 50
                            SendInput "{Space up}"
                            ToolTip "准备开始下一次循环"
                            SetTimer () => ToolTip(), -1500
                            ;确认回到主界面
                            foundtheer := CheckColorWithRetry(gameHwnd,0.50234375,0.936,0x136AFF,5, 150,1000,false)
                            if foundtheer{
                                iterationCount += 1
                                goto End
                            }else{
                                LogStep("循环末尾未能检测到回到主页面")
                                reboot()
                                return
                            }
                        }else{
                            LogStep("未能检测到聊天气泡图标（无法确认进入世界）")
                            reboot()
                            return
                        }
                    }else{
                        LogStep("断网后切回未能检测到主角色")
                        reboot()
                        return
                    }
                }else{
                    EnableAdapter(adapter)
                    Sleep 10000
                    LogStep("断网后未能检测到控件")
                    reboot()
                    return
                }
            } else {
                LogStep("未能检测到切换到新建角色")
                reboot()
                return
            }
            End:
        }else{
            LogStep("未能检测到主角色")
            reboot()
            return
        }
    }
}
;终止程序
exitkill(){
    global adapter, pbPath
    RunWait 'netsh interface set interface "' adapter '" admin=enable', , "Hide"
    RunWait 'netsh advfirewall firewall delete rule name="BlockGame_Out"', , "Hide"
    RunWait 'netsh advfirewall firewall delete rule name="BlockGame_In"', , "Hide"
    RunWait '*RunAs "' pbPath '" unblockall', , "Hide"
}
;退出执行
OnExit((*) => exitkill())

F11:: global stopLoop := true
F12:: {
    exitkill()
    ExitApp
}
F10:: RunAutomation()
F9:: reboot()
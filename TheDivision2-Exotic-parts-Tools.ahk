#Requires AutoHotkey v2.0
#UseHook
#SingleInstance Force
Persistent

if !A_IsAdmin {
    Run '*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"'
    ExitApp
}

MsgBox "请将程序所在的整个目录加入杀毒软件白名单，否则可能导致断网失效"

;=======全局变量=========
global configFile := A_ScriptDir "\config.ini"
;EDRSilencer路径
global windowstite := "TheDivision2-Exotic-parts-Tools-1.5.5"
global pbPath := A_ScriptDir "\EDRSilencer\EDRSilencer.exe"
global stopLoop := false
global TheDivision2Path := IniRead(A_ScriptDir "\config.ini", "Game", "TheDivision2Path", "")
;检测网络连接
global adapter := IniRead(A_ScriptDir "\config.ini", "Network", "Adapter", "")
SplitPath(TheDivision2Path, &fileName)  ; 提取文件名
global gamefile := fileName
; 断网方式常量
global NET_PROXYBRIDGE := 1   ; EDRSilencer
global NET_ADAPTER := 2       ; 禁用网卡
global NetMethod := NET_PROXYBRIDGE
;运行状态显示
global iterationCount := 0
global numberOfErrors := 0
global netError := 0
global logBuffer := []          ; 存储最近的操作记录
global maxLogLines := 100       ; 最多保留 100 条记录
;抓点参数定义
;x坐标百分比小数，y坐标百分比小数，颜色值，容差，重试次数，重试间隔时间ms,调试模式
global Thefirstcharacter := [0.5019531250, 0.9354166667,0xFF6A13,5,150,1000,false] ;选中拆零件的角色
global Thefourthcharacter := [0.5468750000, 0.9402645,0xFF6A13,5,10,200,false] ;选中第四个角色
global NDPW := [0.6761718750, 0.5576388889,0x973A3C,20,300,500,false] ;断网提示窗口
global Bubbleicon := [0.0300781250, 0.9284722222,0xFFFFFF,5,150,1000,false] ;气泡图标
global Storagebox := [0.7207031250, 0.2458333333,0x000000,0,5,500,false] ;储藏箱
global mailbox := [0.6808593750, 0.4625000000,0x000000,5, 30,500,false] ;信箱
global advertisement := [0.498046875,0.250694,0xFF6A13,5, 30,1000,false] ;育碧广告
;抓取工具变量
global grabWaiting := false
global grabTargetX, grabTargetY, grabTargetColor
global grabTargetIdx := 0
global windowedMode := false   ; 窗口化模式，默认关闭
global useCustomParams := false   ; 是否使用自定义抓点参数
;安全屋
global safeHouseOption := "商店"
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

; ========== 抓点参数持久化 ==========
WriteArrayToIni(section, arr) {
    global configFile
    IniWrite arr[1], configFile, section, "percentX"
    IniWrite arr[2], configFile, section, "percentY"
    IniWrite Format("0x{:06X}", arr[3]), configFile, section, "color"
    IniWrite arr[4], configFile, section, "variation"
    IniWrite arr[5], configFile, section, "maxRetries"
    IniWrite arr[6], configFile, section, "retryDelay"
    IniWrite arr[7] ? "true" : "false", configFile, section, "debug"
}
LoadOrCreateParams() {
    global configFile
    global Thefirstcharacter, Thefourthcharacter, NDPW, Bubbleicon, Storagebox, mailbox, advertisement

    ; 直接存储数组对象
    arrays := Map(
        "Thefirstcharacter", Thefirstcharacter,
        "Thefourthcharacter", Thefourthcharacter,
        "NDPW", NDPW,
        "Bubbleicon", Bubbleicon,
        "Storagebox", Storagebox,
        "mailbox", mailbox,
        "advertisement", advertisement
    )

    if !FileExist(configFile) {
        for section, arr in arrays
            WriteArrayToIni(section, arr)
        return
    }

    for section, arr in arrays {
        ; 检查该 section 的所有键是否存在，缺失则补充完整
        missing := false
        for _, key in ["percentX", "percentY", "color", "variation", "maxRetries", "retryDelay", "debug"] {
            if IniRead(configFile, section, key, "") == "" {
                missing := true
                break
            }
        }
        if missing
            WriteArrayToIni(section, arr)

        ; 读取并覆盖数组
        arr[1] := IniRead(configFile, section, "percentX", arr[1])
        arr[2] := IniRead(configFile, section, "percentY", arr[2])
        colorStr := IniRead(configFile, section, "color", Format("{:#X}", arr[3]))
        arr[3] := Integer(colorStr)
        arr[4] := IniRead(configFile, section, "variation", arr[4])
        arr[5] := IniRead(configFile, section, "maxRetries", arr[5])
        arr[6] := IniRead(configFile, section, "retryDelay", arr[6])
        debugStr := IniRead(configFile, section, "debug", arr[7] ? "true" : "false")
        arr[7] := (debugStr = "true")
    }
}

;======== 通过注册表搜索游戏路径 ======== 
AutoFindDivision2Fast() {
    ; ===== 1. Ubisoft 注册表 =====
    try {
        installPath := RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\Ubisoft\Launcher\Installs\4932", "InstallDir")
        if installPath {
            exePath := installPath "\TheDivision2.exe"
            if FileExist(exePath)
                return NormalizePath(exePath)
        }
    }
    try {
        installPath := RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs\4932", "InstallDir")
        if installPath {
            exePath := installPath "\TheDivision2.exe"
            if FileExist(exePath)
                return NormalizePath(exePath)
        }
    }

    ; ===== 2. Steam =====
    try {
        steamPath := RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath")
        if steamPath {
            libFile := steamPath "\steamapps\libraryfolders.vdf"
            if FileExist(libFile) {
                libs := ParseSteamLibraries(libFile)
                for lib in libs {
                    testPath := lib "\steamapps\common\Tom Clancy's The Division 2\TheDivision2.exe"
                    if FileExist(testPath)
                        return testPath
                }
            }
        }
    }

    ; ===== 3. 常见路径 =====
    commonPaths := [
        "C:\Program Files\Ubisoft\Ubisoft Game Launcher\games\Tom Clancy's The Division 2\TheDivision2.exe",
        "D:\Ubisoft\games\Tom Clancy's The Division 2\TheDivision2.exe",
        "E:\Ubisoft\games\Tom Clancy's The Division 2\TheDivision2.exe"
    ]
    for p in commonPaths {
        if FileExist(p)
            return p
    }

    ; 未找到则返回空
    return ""
}

NormalizePath(path) {
    ; 统一斜杠
    path := StrReplace(path, "/", "\")

    ; 去掉重复反斜杠（除了盘符后的）
    while InStr(path, "\\")
        path := StrReplace(path, "\\", "\")

    return path
}

ParseSteamLibraries(vdfPath) {
    libs := []
    content := FileRead(vdfPath)

    for line in StrSplit(content, "`n") {
        if RegExMatch(line, '"path"\s*"(.+?)"', &m) {
            libs.Push(StrReplace(m[1], "\\", "\"))
        }
    }

    return libs
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
;安全屋选项回调函数
SafeHouseListCallback(*){
    global SafeHousePreset, configFile, safeHouseOption
    selected := SafeHousePreset.Text
    safeHouseOption := selected
    IniWrite selected, configFile, "SafeHouse", "Preset"
    ToolTip "安全屋预设已保存: " selected
    SetTimer () => ToolTip(), -1500
}

ApplyCustomParamsSetting() {
    global chkUseCustom, windowedMode
    global Thefirstcharacter, Thefourthcharacter, NDPW, Bubbleicon, Storagebox, mailbox, advertisement

    if chkUseCustom.Value {
        ; 用户勾选了“使用自定义抓点参数”，从配置文件加载
        LoadOrCreateParams()
    } else {
        ; 未勾选自定义参数，根据窗口化模式选择不同的默认参数
        if windowedMode {
            ; ========== 窗口化模式下的默认参数==========
            Thefirstcharacter := [0.50289, 0.826,0xFF6A13,5,150,1000,false]
            Thefourthcharacter := [0.5461538462, 0.8277571252,0xFF6A13,5,10,200,false]
            NDPW := [0.6538461538, 0.5588599752,0x963A3C,20,300,500,false] ;已更新
            Bubbleicon := [0.0538461538, 0.9244114002,0xFFFFFF,5,150,1000,false]
            Storagebox := [0.6336538462, 0.2715,0x000000,5,10,500,false]
            mailbox := [0.5836538462, 0.4795539033,0x000000,5,30,500,false]
            advertisement := [0.4970703125, 0.3125,0xFF6A13,5,30,1000,false]
        } else {
            ; ========== 全屏模式下的默认参数（原有值）==========
            Thefirstcharacter := [0.5019531250, 0.9354166667,0xFF6A13,5,150,1000,false]
            Thefourthcharacter := [0.5468750000, 0.9402645,0xFF6A13,5,10,200,false]
            NDPW := [0.6761718750, 0.5576388889,0x973A3C,20,300,500,false]
            Bubbleicon := [0.0300781250, 0.9284722222,0xFFFFFF,5,150,1000,false]
            Storagebox := [0.7207031250, 0.2458333333,0x000000,0,5,500,false]
            mailbox := [0.6808593750, 0.4625000000,0x000000,5, 30,500,false]
            advertisement := [0.498046875,0.250694,0xFF6A13,5, 30,1000,false]
        }
        ApplyRolePreset()
    }
}
ApplyRolePreset(*) {
    global Thefirstcharacter, comboRolePreset, windowedMode
    selected := comboRolePreset.Text
    if (windowedMode) {
        ; 窗口化模式下的坐标预设
        if (selected = "第一个角色") {
            Thefirstcharacter[1] := 0.50289
            Thefirstcharacter[2] := 0.826
        } else if (selected = "第二个角色") {
            Thefirstcharacter[1] := 0.518999999
            Thefirstcharacter[2] := 0.826
        } else if (selected = "第三个角色") {
            Thefirstcharacter[1] := 0.5345
            Thefirstcharacter[2] := 0.826
        } else {
            return
        }
    } else {
        ; 全屏模式下的坐标预设
        if (selected = "第一个角色") {
            Thefirstcharacter[1] := 0.5019531250
            Thefirstcharacter[2] := 0.9354166667
        } else if (selected = "第二个角色") {
            Thefirstcharacter[1] := 0.517578125
            Thefirstcharacter[2] := 0.9354166667
        } else if (selected = "第三个角色") {
            Thefirstcharacter[1] := 0.53398437499999996
            Thefirstcharacter[2] := 0.9354166667
        } else {
            return
        }
    }
    ToolTip "已切换到 " selected " 的抓点参数"
    SetTimer () => ToolTip(), -1500
}
OnUseCustomClick(*) {
    global chkUseCustom, configFile
    ; 保存复选框状态到配置文件
    IniWrite chkUseCustom.Value ? 1 : 0, configFile, "Settings", "UseCustomParams"
    ; 立即应用设置（更新全局数组）
    ApplyCustomParamsSetting()
    ToolTip (chkUseCustom.Value ? "已启用自定义抓点参数" : "已禁用自定义抓点参数，使用默认值")
    SetTimer () => ToolTip(), -1500
}
OnWindowedModeClick(*) {
    global chkWindowed, windowedMode, configFile
    windowedMode := chkWindowed.Value
    ; 保存窗口模式状态到配置文件（可选，保持与保存按钮同步）
    IniWrite windowedMode ? 1 : 0, configFile, "Settings", "WindowedMode"
    ; 立即更新抓点参数数组（根据当前窗口模式和使用自定义参数标志）
    ApplyCustomParamsSetting()
    ToolTip (windowedMode ? "已切换到窗口化模式，抓点参数已更新" : "已切换到全屏模式，抓点参数已更新")
    SetTimer () => ToolTip(), -2000
    ApplyRolePreset()
}

SaveCurrentConfig() {
    global editPath, comboAdapter, configFile, TheDivision2Path, NetworkAdapter, gamefile, NetMethod, comboNetMethod
    path := Trim(editPath.Value)
    ; 不再强制要求选择网卡
    ; adapter := Trim(comboAdapter.Text)
    if path = "" {
        MsgBox "请先选择游戏路径！", "提示", 0x40
        return false
    }
    ; 移除网卡检查
    ; if adapter = "" || adapter = "未检测到可用网卡" {
    ;     MsgBox "请先选择一个有效的网络适配器！", "提示", 0x40
    ;     return false
    ; }
    
    ; 更新全局变量
    TheDivision2Path := path
    windowedMode := chkWindowed.Value
    ; 如果用户没有选择网卡，NetworkAdapter 可能为空或保持原值，这里允许为空
    NetworkAdapter := Trim(comboAdapter.Text)
    if NetworkAdapter = "未检测到可用网卡"
        NetworkAdapter := ""   ; 将无效值置空
    NetMethod := comboNetMethod.Value
    SplitPath(TheDivision2Path, &fileName)
    gamefile := fileName

    ; 保存配置到文件
    IniWrite path, configFile, "Game", "TheDivision2Path"
    IniWrite NetworkAdapter, configFile, "Network", "Adapter"
    IniWrite comboNetMethod.Value, configFile, "Settings", "NetMethod"
    IniWrite chkWindowed.Value ? 1 : 0, configFile, "Settings", "WindowedMode"
    IniWrite chkUseCustom.Value ? 1 : 0, configFile, "Settings", "UseCustomParams"

    ApplyCustomParamsSetting()

    ToolTip "配置已保存"
    SetTimer () => ToolTip(), -1500
    return true
}

; 检查并关闭窗口
CheckAndClose() {
    if SaveCurrentConfig() {
        mainGui.Destroy()
        return true
    }
    return false
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
; 游戏路径区域
mainGui.Add("Text", "x10 y10 w300 h30", "请选择《全境封锁2》的主程序路径(TheDivision2.exe)：")
editPath := mainGui.Add("Edit", "x10 y50 w400 h25 ReadOnly")
btnBrowse := mainGui.Add("Button", "x420 y49 w80 h27", "浏览")

; 网卡选择区域
mainGui.Add("Text", "x10 y80 w300 h30", "选择当前连接的网络适配器：")
comboAdapter := mainGui.Add("ComboBox", "x10 y100 w300 h200 Choose1")
btnRefresh := mainGui.Add("Button", "x320 y98 w80 h27", "刷新")

mainGui.Add("Text", "x10 y130 w300 h30", "选择断网方式：")
comboNetMethod := mainGui.Add("ComboBox", "x10 y150 w400 h200 Choose1", ["EDRSilencer（WFP过滤，可使用加速器）","禁用网卡（暴力断网，需选择网络适配器）"])

; 窗口化模式勾选框
chkWindowed := mainGui.Add("CheckBox", "x10 y180 w120 h30", "窗口化模式`n1024 x 768")
chkWindowed.OnEvent("Click", OnWindowedModeClick)
mainGui.Add("Text", "x130 y183 w250 h30", "请将游戏画面设置同步修改为`n窗口化:1024 x 768")

; 角色预设选择
mainGui.Add("Text", "x10 y220 w300 h30", "角色预设：")
comboRolePreset := mainGui.Add("ComboBox", "x10 y240 w150 h90 Choose1", ["第一个角色", "第二个角色", "第三个角色"])
comboRolePreset.OnEvent("Change", ApplyRolePreset)
mainGui.Add("Text", "x170 y240 w300 h50", "修改后需要用该角色进入一次游戏然后注销再运行`n会覆盖自定义抓点参数")

;安全屋预设选择
safeHouseOptions := ["商店", "白宫"]
mainGui.Add("Text", "x10 y280 w300 h30", "安全屋预设：")
SafeHousePreset := mainGui.Add("ComboBox", "x10 y300 w150 h90 Choose1", safeHouseOptions)
mainGui.Add("Text", "x170 y300 w220 h30", "先使用角色预设中的角色`n传送到对应的安全屋然后注销再运行")
SafeHousePreset.OnEvent("Change", SafeHouseListCallback)

;自定义抓点参数
chkUseCustom := mainGui.Add("CheckBox", "x10 y360 w140 h30", "使用自定义抓点参数")
chkUseCustom.OnEvent("Click", OnUseCustomClick)
btnEditParams  := mainGui.Add("Button", "x150 y360 w100 h30", "自定义抓点参数")
btnEditParams.OnEvent("Click", OpenParamEditor)
mainGui.Add("Text", "x260 y365 w250 h30", "如果你不知道这是什么`n请不要勾选和修改")


; 抓点函数：设置抓取目标控件
SetGrabTarget(idx, editX, editY, editColor) {
    global grabWaiting, grabTargetIdx, grabTargetX, grabTargetY, grabTargetColor
    grabTargetIdx := idx
    grabTargetX := editX
    grabTargetY := editY
    grabTargetColor := editColor
    grabWaiting := true
    ToolTip "请按 Alt+F1 抓取 (行 " idx ")"
    SetTimer () => ToolTip(), -3000
}
; ========== 参数编辑窗口 ==========
; 生成抓取按钮的回调函数
MakeGrabHandler(idx, editX, editY, editColor) {
    return (GuiCtrl, Info) => SetGrabTarget(idx, editX, editY, editColor)
}
OpenParamEditor(*) {
    global chkUseCustom
    if !chkUseCustom.Value {
        MsgBox "请先勾选“使用自定义抓点参数”后再编辑抓点参数。", "提示", 0x40
        return
    }
    global configFile
    global Thefirstcharacter, Thefourthcharacter, NDPW, Bubbleicon, Storagebox, mailbox, advertisement

    arrays := [
        {name: "拆零件角色的选中UI", arr: Thefirstcharacter, desc: "选中第一个角色"},
        {name: "第四个角色的选中UI", arr: Thefourthcharacter, desc: "选中第四个角色"},
        {name: "掉线提示窗口", arr: NDPW, desc: "断网提示窗口"},
        {name: "聊天气泡图标", arr: Bubbleicon, desc: "气泡图标"},
        {name: "进入储藏箱的UI", arr: Storagebox, desc: "储藏箱"},
        {name: "切换到信箱的UI", arr: mailbox, desc: "信箱"},
        {name: "育碧广告", arr: advertisement, desc: "育碧广告"}
    ]

    paramGui := Gui()
    paramGui.Title := "自定义抓点参数"
    paramGui.SetFont("s10")

    controls := []

    ; 表头
    paramGui.Add("Text", "x10 y10 w150 h30", "参数点位")
    paramGui.Add("Text", "x170 y10 w100 h30", "X%")
    paramGui.Add("Text", "x280 y10 w100 h30", "Y%")
    paramGui.Add("Text", "x390 y10 w100 h30", "颜色")
    paramGui.Add("Text", "x500 y10 w80 h30", "容差")
    paramGui.Add("Text", "x590 y10 w90 h30", "重试次数")
    paramGui.Add("Text", "x690 y10 w90 h30", "重试间隔")
    paramGui.Add("Text", "x790 y10 w90 h30", "调试模式")
    paramGui.Add("Text", "x890 y10 w60 h30", "抓取")

    y := 50
    rowHeight := 45

    for idx, item in arrays {
        
        paramGui.Add("Text", "x10 y" y " w150 h" rowHeight, item.name)
        editX := paramGui.Add("Edit", "x170 y" y " w100 h" rowHeight, Round(item.arr[1], 10))
        editY := paramGui.Add("Edit", "x280 y" y " w100 h" rowHeight, Round(item.arr[2], 10))
        colorRaw := IniRead(configFile, item.name, "color", Format("0x{:06X}", item.arr[3]))
        editColor := paramGui.Add("Edit", "x390 y" y " w100 h" rowHeight, colorRaw)
        editVar := paramGui.Add("Edit", "x500 y" y " w80 h" rowHeight, item.arr[4])
        editRetries := paramGui.Add("Edit", "x590 y" y " w90 h" rowHeight, item.arr[5])
        editDelay := paramGui.Add("Edit", "x690 y" y " w90 h" rowHeight, item.arr[6])
        cbDebug := paramGui.Add("ComboBox", "x790 y" y " w90 h" rowHeight, ["启用", "禁用"])
        cbDebug.Choose(item.arr[7] ? 1 : 2)
        ; 抓取按钮
        btnGrab := paramGui.Add("Button", "x890 y" y " w60 h" rowHeight, "抓")
        btnGrab.OnEvent("Click", MakeGrabHandler(idx, editX, editY, editColor))

        controls.Push({arr: item.arr, ctrls: [editX, editY, editColor, editVar, editRetries, editDelay, cbDebug]})
        y += rowHeight
        
    }

    btnSave := paramGui.Add("Button", "x10 y" y+10 " w160 h40", "保存并关闭窗口")
    btnSave.OnEvent("Click", (*) => SaveParamsAndClose(paramGui, controls))

    paramGui.OnEvent("Close", (*) => SaveParamsAndClose(paramGui, controls))
    paramGui.Show("w980 h" (y+80))
}
; 保存参数并关闭窗口
SaveParamsAndClose(gui, controls) {
    global configFile, grabWaiting
    grabWaiting := false
    ; 更新数组值
    for item in controls {
        arr := item.arr
        ctrls := item.ctrls
        ; 配置文件中的颜色需转换为数字，其他为数值
        arr[1] := Float(ctrls[1].Value)
        arr[2] := Float(ctrls[2].Value)
        colorStr := ctrls[3].Value
        ; 确保颜色值以0x开头
        if !RegExMatch(colorStr, "^0x")
            colorStr := "0x" colorStr
        arr[3] := Integer(colorStr)
        arr[4] := Integer(ctrls[4].Value)
        arr[5] := Integer(ctrls[5].Value)
        arr[6] := Integer(ctrls[6].Value)
        arr[7] := (ctrls[7].Text = "启用")
    }
    WriteAllParamsToIni()
    LoadOrCreateParams()

    gui.Destroy()
}
WriteAllParamsToIni() {
    global configFile
    global Thefirstcharacter, Thefourthcharacter, NDPW, Bubbleicon, Storagebox, mailbox, advertisement
    WriteArrayToIni("Thefirstcharacter", Thefirstcharacter)
    WriteArrayToIni("Thefourthcharacter", Thefourthcharacter)
    WriteArrayToIni("NDPW", NDPW)
    WriteArrayToIni("Bubbleicon", Bubbleicon)
    WriteArrayToIni("Storagebox", Storagebox)
    WriteArrayToIni("mailbox", mailbox)
    WriteArrayToIni("advertisement", advertisement)
}

; ========== 说明文本 ==========
mainGui.Add("Text", "x10 y410 w480 h30", "网线和WIFI使用其中一个，保存后F10运行，F12强制停止程序，F5暂停并重启程序")

; 关闭按钮
btnCancel := mainGui.Add("Button", "x10 y440 w200 h40", "保存并关闭窗口")

btnSaveOnly := mainGui.Add("Button", "x220 y440 w100 h40", "保存")
btnSaveOnly.OnEvent("Click", (*) => SaveCurrentConfig())


; 加载网卡配置
savedMethod := IniRead(configFile, "Settings", "NetMethod", NET_PROXYBRIDGE)
savedMethod := savedMethod + 0
if (savedMethod < 1 || savedMethod > 2)
    savedMethod := NET_PROXYBRIDGE
comboNetMethod.Choose(savedMethod)

; 加载游戏路径
savedPath := IniRead(configFile, "Game", "TheDivision2Path", "")

; ===== 自动检测 =====
if (savedPath = "" || !FileExist(savedPath)) {
    ToolTip "正在自动搜索游戏路径，请稍候..."

    foundPath := AutoFindDivision2Fast()

    ToolTip

    if (foundPath != "") {
        savedPath := foundPath
        IniWrite savedPath, configFile, "Game", "TheDivision2Path"
        MsgBox "已自动找到游戏路径：`n" savedPath
    } else {
        MsgBox "未自动找到游戏，请手动选择路径"
    }
}

if savedPath
    editPath.Value := savedPath

savedAdapter := IniRead(configFile, "Network", "Adapter", "")
RefreshAdapterList()   ; 填充网卡列表

; 加载窗口化模式设置
savedWindowedMode := IniRead(configFile, "Settings", "WindowedMode", 0)
chkWindowed.Value := savedWindowedMode
windowedMode := savedWindowedMode

useCustomParams := IniRead(configFile, "Settings", "UseCustomParams", 0)
chkUseCustom.Value := useCustomParams

; 加载安全屋预设
savedSafeHouse := IniRead(configFile, "SafeHouse", "Preset", "")
if savedSafeHouse = "" {
    savedSafeHouse := "商店"
    IniWrite savedSafeHouse, configFile, "SafeHouse", "Preset"
}
for idx, opt in safeHouseOptions {
    if (opt = savedSafeHouse) {
        SafeHousePreset.Choose(idx)
        break
    }
}
safeHouseOption := savedSafeHouse

ApplyCustomParamsSetting()

; 绑定事件
btnBrowse.OnEvent("Click", BrowseFile)
btnRefresh.OnEvent("Click", (*) => RefreshAdapterList())
btnCancel.OnEvent("Click", (*) => CheckAndClose() && mainGui.Destroy())
mainGui.OnEvent("Close", GuiClose)   ; 处理右上角 X

; 创建悬浮窗
FloatingWindow := Gui("+AlwaysOnTop +ToolWindow -Caption +LastFound")
floatingHwnd := FloatingWindow.Hwnd 
FloatingWindow.BackColor := "000000"
WinSetTransparent(180, FloatingWindow)
WinSetExStyle("+0x20", FloatingWindow)

textCtrl := FloatingWindow.Add("Text", "cWhite x10 y10 w200 h100", "循环次数:0`n错误重置次数:0`n掉线重连次数:0")
textCtrl.SetFont("s12")  ; 不指定字体名，使用默认

; 获取屏幕工作区
MonitorGetWorkArea(, &Left, &Top, &Right, &Bottom)
winWidth := 220
winHeight := 70
xPos := 10
yPos := 10

; 显示悬浮窗
FloatingWindow.Show("x" xPos " y" yPos " w" winWidth " h" winHeight " NoActivate")

; 显示窗口
mainGui.Show()

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
GetColorFromScreen(x, y) {
    hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    color := DllCall("GetPixel", "Ptr", hdc, "Int", x, "Int", y, "UInt")
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
    ; 转换颜色格式 (GetPixel 返回 0xBBGGRR)
    return ((color & 0xFF) << 16) | (color & 0xFF00) | ((color >> 16) & 0xFF)
}
CheckColorWithRetry(hwnd, percentX, percentY, targetColor, variation := 20, maxRetries := 20, retryDelay := 200, debug := false) {
        ; 检查窗口句柄是否有效
        global windowedMode
        loop maxRetries {
            if !WinExist("ahk_id " hwnd){
                return false
            }
        if windowedMode {
            WinGetPos(&winX, &winY, &winW, &winH, hwnd)
        } else {
            WinGetPos(, , &winW, &winH, hwnd)  ; 只获取宽高，不获取位置
            winX := 0
            winY := 0
        }
        screenX := winX + winW * percentX
        screenY := winY + winH * percentY

        if debug {
            ToolTip "检查颜色位置: " screenX "," screenY "`n预期: " Format("{:06X}", targetColor)
            SetTimer () => ToolTip(), -1000
        } 

        actualColor := GetColorFromScreen(screenX, screenY)

        if debug {
            Sleep 1000
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


; 颜色匹配辅助函数
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
    if (NetMethod = NET_ADAPTER) {
        if (adapterName = "")
            adapterName := "以太网"
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
    if (NetMethod = NET_ADAPTER) {
        if (adapterName = "")
            adapterName := "以太网"
        ; 启用网卡
        RunWait 'netsh interface set interface "' adapterName '" admin=enable', , "Hide"
    } else if (NetMethod = NET_PROXYBRIDGE) {
        ; 删除 EDRSilencer 规则
        RunWait '*RunAs "' pbPath '" unblockall', , "Hide"
    }
}
;===========

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
    ;==== 导入取色参数 ====
    global Thefirstcharacter
    global advertisement
    global NDPW
    global floatingHwnd
    EnableAdapter(adapter)
    SaveLogToFile()
    gamghwd := WinExist("ahk_exe " gamefile)

    Sleep 500
    ;检测是否掉线
    lopNbr := 0
    if gamghwd{
        loop 10{
            networkerror := CheckColorWithRetry(gamghwd,NDPW[1],NDPW[2],NDPW[3],NDPW[4],10,500,NDPW[7])
            if networkerror{
                SendInput "{Space down}"
                Sleep 100
                SendInput "{Space up}"
                Sleep 100
                SendInput "{Space down}"
                Sleep 100
                SendInput "{Space up}"
                Sleep 500
                mainObj := CheckColorWithRetry(gamghwd,Thefirstcharacter[1],Thefirstcharacter[2],Thefirstcharacter[3],Thefirstcharacter[4],Thefirstcharacter[5],Thefirstcharacter[6],Thefirstcharacter[7])
                if mainObj{
                    Sleep 1000
                    ToolTip "已恢复，守护进程退出"
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
    if WinExist("ahk_exe " gamefile) {
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
    gamghwd := WinExist("ahk_exe " gamefile)
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
    WinSetAlwaysOnTop true, gamghwd
    WinSetAlwaysOnTop true, floatingHwnd
    WinActivate gamghwd
        ;进入主页面
        ;检测是否到选人界面
        adFlag := true
        Sleep 30000
        ToolTip "开始检测是否到选人界面"
        foundol := CheckColorWithRetry(gamghwd,Thefirstcharacter[1],Thefirstcharacter[2],Thefirstcharacter[3],Thefirstcharacter[4],60,1000,Thefirstcharacter[7])
        found2 :=  CheckColorWithRetry(gamghwd,advertisement[1],advertisement[2],advertisement[3],advertisement[4],advertisement[5],advertisement[6],advertisement[7])
        loop 30{
            if foundol{
                Sleep 1000
                ToolTip "已恢复，守护进程退出"
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
                    adFlag := false
                }
            }
        }
        if !adFlag {
            goto re
        }
    }
;==================================
;注销操作函数
LoGout(){
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
}
;这里放置不同安全屋寻路使用的参数根据全局变量safeHouseOption
PathfindingParameter(){
    global safeHouseOption
    if (safeHouseOption = "商店"){
        SendInput "{W down}{D down}"
        Sleep 220
        SendInput "{W up}"
        Sleep 120
        SendInput "{D up}"
        return true
    }else if(safeHouseOption = "白宫"){
        SendInput "{W down}"
        Sleep 2100
        SendInput "{A down}"
        Sleep 1900
        SendInput "{A up}"
        Sleep 3000
        SendInput "{W up}"
        return true
    }else{
        MsgBox "未能读取到正确的寻路参数，请将该窗口截图提供给开发者`n程序中止运行`nsafeHouseOption:" safeHouseOption
        return false
    }
}
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
    global floatingHwnd

    ;========导入颜色参数=========
    global Thefirstcharacter
    global Thefourthcharacter
    global NDPW
    global Bubbleicon
    global Storagebox
    global mailbox
    gameHwnd := WinExist("ahk_exe " gamefile)
    Sleep 500
    ; 获取游戏窗口句柄
    if !gameHwnd {
        MsgBox "未找到游戏窗口，请确保游戏正在运行`n" gamefile "`n" gameHwnd
        SetTimer () => ToolTip(), -1500
        return
    }
    ;===================================
    WinSetAlwaysOnTop true, gameHwnd
    WinSetAlwaysOnTop true, floatingHwnd
    WinActivate gameHwnd
    while !stopLoop {
        totalRetries := 3
        found := false
        ;检测是否在主角色
        mainObj := CheckColorWithRetry(gameHwnd,Thefirstcharacter[1],Thefirstcharacter[2],Thefirstcharacter[3],Thefirstcharacter[4],Thefirstcharacter[5],Thefirstcharacter[6],Thefirstcharacter[7])
        if mainObj{
            ToolTip "已检测到主角色，开始切换角色"
            SetTimer () => ToolTip(), -1500
            loop totalRetries {
                SendMode "Input"
                Loop 5 {
                    SendInput "{c down}"
                    Sleep 30
                    SendInput "{c up}"
                    Sleep 50
                }
                ; 检测切换到新建角色
                found := CheckColorWithRetry(gameHwnd,Thefourthcharacter[1],Thefourthcharacter[2],Thefourthcharacter[3],Thefourthcharacter[4],Thefourthcharacter[5],Thefourthcharacter[6],Thefourthcharacter[7])

                if found {
                    ToolTip "已检测到控件,新建角色"
                    SetTimer () => ToolTip(), -1500
                    break   ; 找到按钮，跳出外层循环
                }
                ; 未找到，等待一下再重试整个流程
                ToolTip "未检测到控件，重试切换"
                SetTimer () => ToolTip(), -2000
                Sleep 300
            }

            if found {
                next:
                Sleep 1000
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
                foundSecond := CheckColorWithRetry(gameHwnd,NDPW[1],NDPW[2],NDPW[3],NDPW[4],NDPW[5],NDPW[6],NDPW[7])
                WinSetAlwaysOnTop true, floatingHwnd
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
                    foundtheer := CheckColorWithRetry(gameHwnd,Thefirstcharacter[1],Thefirstcharacter[2],Thefirstcharacter[3],Thefirstcharacter[4],Thefirstcharacter[5],Thefirstcharacter[6],Thefirstcharacter[7])
                    if foundtheer{
                        ToolTip "已检测到控件，继续主角色拆解零件"
                        SetTimer () => ToolTip(), -1500
                        Sleep 1000
                        SendInput "{Space down}"
                        Sleep 50
                        SendInput "{Space up}"
                        foundf := CheckColorWithRetry(gameHwnd,Bubbleicon[1],Bubbleicon[2],Bubbleicon[3],Bubbleicon[4],Bubbleicon[5],Bubbleicon[6],Bubbleicon[7])
                        if foundf{
                            ToolTip "已检测到控件，确认已成功进入世界，开始移动"
                            SetTimer () => ToolTip(), -2000
                            Sleep 1500
                            if !PathfindingParameter(){
                                return
                            }
                            Sleep 200
                            SendInput "{F down}"
                            Sleep 1800
                            SendInput "{F up}"
                            ;进入装备页面
                            Sleep 500
                            equipment := CheckColorWithRetry(gameHwnd,Storagebox[1],Storagebox[2],Storagebox[3],Storagebox[4],Storagebox[5],Storagebox[6],Storagebox[7])
                            equipmentnd := CheckColorWithRetry(gameHwnd,Bubbleicon[1],Bubbleicon[2],Bubbleicon[3],0,5,100,Bubbleicon[7])
                            ;这里同时检测开启了箱子并且气泡不存在，防止误识别
                            if equipment && !equipmentnd{
                                ToolTip "确认进入装备页面"
                                SetTimer () => ToolTip(), -2000
                                SendInput "{E down}"
                                Sleep 50
                                SendInput "{E up}"
                                Sleep 100
                                equipment2 := CheckColorWithRetry(gameHwnd,mailbox[1],mailbox[2],mailbox[3],mailbox[4],mailbox[5],mailbox[6],mailbox[7])
                                if equipment2 {
                                    ToolTip "开始收取武器"
                                    SetTimer () => ToolTip(), -500
                                    Sleep 1000
                                    Loop 3{
                                        SendInput "{D down}"
                                        Sleep 50
                                        SendInput "{D up}"
                                        Sleep 50
                                    }
                                    Loop 3{
                                        SendInput "{W down}"
                                        Sleep 50
                                        SendInput "{W up}"
                                        Sleep 50
                                    }
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
                                        Sleep 200
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
                                    Sleep 1000
                                    LoGout()
                                    goto nextEquipment
                                }
                            }else{
                                if !equipmentnd{
                                    Sleep 200
                                    SendInput "{ESC down}"
                                    Sleep 1500
                                    SendInput "{ESC up}"
                                    Sleep 1000
                                }
                                LoGout()
                                goto nextEquipment
                            }
                            ;退出
                            LoGout()
                            ToolTip "准备开始下一次循环"
                            SetTimer () => ToolTip(), -1500
                            ;确认回到主界面
                            foundtheer := CheckColorWithRetry(gameHwnd,Thefirstcharacter[1],Thefirstcharacter[2],Thefirstcharacter[3],Thefirstcharacter[4],Thefirstcharacter[5],Thefirstcharacter[6],Thefirstcharacter[7])
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
    global adapter, pbPath,gamefile
    RunWait 'netsh interface set interface "' adapter '" admin=enable', , "Hide"
    RunWait '*RunAs "' pbPath '" unblockall', , "Hide"
    hwnd := WinExist("ahk_exe " gamefile)
    if !hwnd{
        return
    }
    WinSetAlwaysOnTop false, hwnd
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
;抓点热键
!F1:: {
    global grabWaiting, grabTargetX, grabTargetY, grabTargetColor,grabTargetColor , gamefile
    if !grabWaiting
        return

    ; 获取游戏窗口句柄
    hwnd := WinExist("ahk_exe " gamefile)
    if !hwnd {
        MsgBox "未找到游戏窗口，请确保游戏正在运行"
        grabWaiting := false
        return
    }

    ; 获取窗口矩形（用于判断鼠标是否在窗口内）
    GetWindowRect(hwnd, &left, &top, &right, &bottom) {
        rect := Buffer(16, 0)
        if !DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect)
            return false
        left := NumGet(rect, 0, "Int")
        top := NumGet(rect, 4, "Int")
        right := NumGet(rect, 8, "Int")
        bottom := NumGet(rect, 12, "Int")
        return true
    }
    MouseGetPos(&mouseX, &mouseY)
    ;获取整个窗口的位置和大小
    WinGetPos(&winX, &winY, &winW, &winH, hwnd)
    ;获取客户区的窗口大小
    WinGetClientPos(&clientX, &clientY, &clientW, &clientH, hwnd)
    ;计算标题高度和边框
    titleW := Integer((winW - clientW) / 2)
    titleH := (winH - clientH) - titleW
    ; 计算鼠标相对于整个窗口左上角的坐标
    relX := mouseX + titleW
    relY := mouseY + titleH

    if (relX < 0 || relY < 0 || relX > winW || relY > winH) {
        ToolTip "鼠标不在游戏窗口内"
        SetTimer () => ToolTip(), -2000
        return
    }
    
    GetCursorPos(&PmouseX, &PmouseY) {
        static POINT := Buffer(8)
        if DllCall("GetCursorPos", "Ptr", POINT) {
            PmouseX := NumGet(POINT, 0, "Int")
            PmouseY := NumGet(POINT, 4, "Int")
            return true
        }
        return false
    }
    GetCursorPos(&PmouseX, &PmouseY)

    color := GetColorFromScreen(PmouseX, PmouseY)
    if (color = -1) {
        ToolTip "颜色捕获失败"
        SetTimer () => ToolTip(), -2000
        return
    }

    ; 计算百分比坐标（基于整个窗口）
    percentX := Round(relX / winW, 10)
    percentY := Round(relY / winH, 10)
    colorHex := Format("0x{:06X}", color)
    ; 不再获取颜色，直接填充坐标（颜色控件留空或不修改）
    if grabTargetX && grabTargetY {
        grabTargetX.Value := percentX
        grabTargetY.Value := percentY
        grabTargetColor.Value := colorHex
        result := Format("窗口尺寸: {}x{}`n鼠标坐标: ({}, {})`n坐标百分比: ({}, {})`n颜色: {}", winW, winH, relX, relY, percentX, percentY, colorHex)

        MsgBox "抓取成功 `nX坐标百分比: " percentX "`nY坐标百分比: " percentY "`n16进制颜色值: " colorHex "`n已复制详细信息到剪切板"
        A_Clipboard := result
    } else {
        MsgBox "抓取失败：目标控件无效"
    }
    grabWaiting := false
}
;重新加载
F5::{
    exitkill()
    Reload
}
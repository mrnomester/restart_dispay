param(
    [Parameter(Mandatory = $false)]
    [string]$ComputerName,
    
    [switch]$FullRestore
)

#region Инициализация
$scriptVersion = "1.4"

# Функция для вывода сообщений
function Write-Status {
    param(
        [string]$Message,
        [string]$Status = "INFO" # INFO, SUCCESS, ERROR
    )
    
    $color = switch ($Status) {
        "SUCCESS" { "Green" }
        "ERROR"   { "Red" }
        default   { "Cyan" }
    }
    
    $prefix = switch ($Status) {
        "SUCCESS" { "[УСПЕХ] " }
        "ERROR"   { "[ОШИБКА] " }
        default   { "[ИНФО] " }
    }
    
    Write-Host "$prefix$Message" -ForegroundColor $color
}

# Проверка прав администратора
function Test-IsAdmin {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        Write-Status "Ошибка проверки прав администратора: $_" -Status "ERROR"
        return $false
    }
}

# Функции доступа (без изменений)
function Get-PCAccess {
    param([string]$TargetPC)
    
    # Метод 1: WMI
    try {
        $null = Get-WmiObject -ComputerName $TargetPC -Class Win32_OperatingSystem -ErrorAction Stop
        Write-Status "Выбран метод доступа: WMI" -Status "INFO"
        return "WMI"
    }
    catch {
        Write-Status "Метод WMI недоступен: $($_.Exception.Message)" -Status "WARNING"
    }

    # Метод 2: PsExec
    try {
        if ($psexecPath = Get-Command psexec.exe -ErrorAction SilentlyContinue | 
            Select-Object -ExpandProperty Source) 
        {
            & $psexecPath \\$TargetPC -nobanner -accepteula cmd /c "exit 0" | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Status "Выбран метод доступа: PsExec" -Status "INFO"
                return "PsExec"
            }
        }
    }
    catch {
        Write-Status "Метод PsExec недоступен: $($_.Exception.Message)" -Status "WARNING"
    }

    # Метод 3: WinRM
    try {
        $session = New-PSSession -ComputerName $TargetPC -ErrorAction Stop
        Remove-PSSession $session
        Write-Status "Выбран метод доступа: WinRM" -Status "INFO"
        return "WinRM"
    }
    catch {
        Write-Status "Метод WinRM недоступен: $($_.Exception.Message)" -Status "WARNING"
    }

    return $null
}

# Функции восстановления (объединённые)
function Reset-Display {
    param(
        [string]$TargetPC,
        [string]$AccessMethod,
        [bool]$FullMode = $false
    )

    $success = $false
    $actions = @(
        @{Name = "Перезапуск DWM"; Script = { 
            # Код перезапуска DWM
            switch ($AccessMethod) {
                "WMI" {
                    $process = [wmiclass]"\\$TargetPC\root\cimv2:Win32_Process"
                    $result = $process.Create('cmd /c taskkill /f /im dwm.exe & start dwm.exe')
                    if ($result.ReturnValue -eq 0) { $true } else { $false }
                }
                "PsExec" {
                    if ($psexecPath = Get-Command psexec.exe -ErrorAction SilentlyContinue | 
                        Select-Object -ExpandProperty Source) 
                    {
                        & $psexecPath \\$TargetPC -s cmd /c "taskkill /f /im dwm.exe & start dwm.exe"
                        $LASTEXITCODE -eq 0
                    } else { $false }
                }
                "WinRM" {
                    try {
                        Invoke-Command -ComputerName $TargetPC -ScriptBlock {
                            taskkill /f /im dwm.exe -ErrorAction SilentlyContinue
                            Start-Process dwm.exe -WindowStyle Hidden
                        } -ErrorAction Stop
                        $true
                    } catch { $false }
                }
            }
        }},
        @{Name = "Отправка комбинации клавиш"; Script = {
            # Код отправки клавиш
            $keyScript = {
                Add-Type -MemberDefinition @"
                    [DllImport("user32.dll")]
                    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
"@ -Name Keyboard -Namespace Win32 -PassThru
                0x11, 0x5B, 0x10, 0x42 | ForEach-Object { [Win32.Keyboard]::keybd_event($_, 0, 0, [UIntPtr]::Zero) }
                0x42, 0x10, 0x5B, 0x11 | ForEach-Object { [Win32.Keyboard]::keybd_event($_, 0, 2, [UIntPtr]::Zero) }
            }

            switch ($AccessMethod) {
                "WMI" {
                    $process = [wmiclass]"\\$TargetPC\root\cimv2:Win32_Process"
                    $result = $process.Create("powershell -Command `"$keyScript`"")
                    $result.ReturnValue -eq 0
                }
                "PsExec" {
                    if ($psexecPath = Get-Command psexec.exe -ErrorAction SilentlyContinue | 
                        Select-Object -ExpandProperty Source) 
                    {
                        & $psexecPath \\$TargetPC -i 1 -s powershell -Command $keyScript
                        $LASTEXITCODE -eq 0
                    } else { $false }
                }
                "WinRM" {
                    try {
                        Invoke-Command -ComputerName $TargetPC -ScriptBlock $keyScript -ErrorAction Stop
                        $true
                    } catch { $false }
                }
            }
        }},
        @{Name = "Перезапуск Explorer"; Script = {
            # Код перезапуска Explorer
            switch ($AccessMethod) {
                "WMI" {
                    $process = [wmiclass]"\\$TargetPC\root\cimv2:Win32_Process"
                    $result = $process.Create('cmd /c taskkill /f /im explorer.exe & start explorer.exe')
                    $result.ReturnValue -eq 0
                }
                "PsExec" {
                    if ($psexecPath = Get-Command psexec.exe -ErrorAction SilentlyContinue | 
                        Select-Object -ExpandProperty Source) 
                    {
                        & $psexecPath \\$TargetPC -s cmd /c "taskkill /f /im explorer.exe & start explorer.exe"
                        $LASTEXITCODE -eq 0
                    } else { $false }
                }
                "WinRM" {
                    try {
                        Invoke-Command -ComputerName $TargetPC -ScriptBlock {
                            taskkill /f /im explorer.exe -ErrorAction SilentlyContinue
                            Start-Process explorer.exe
                        } -ErrorAction Stop
                        $true
                    } catch { $false }
                }
            }
        }}
    )

    foreach ($action in $actions) {
        $actionName = $action.Name
        try {
            Write-Status "Попытка: $actionName" -Status "INFO"
            $result = & $action.Script
            
            if ($result) {
                Write-Status "$actionName успешно выполнена" -Status "SUCCESS"
                $success = $true
                
                # Если не в полном режиме - выходим после первого успеха
                if (-not $FullMode) {
                    return $true
                }
            }
            else {
                Write-Status "$actionName не удалась" -Status "WARNING"
            }
        }
        catch {
            Write-Status "Ошибка при выполнении $actionName`: $($_.Exception.Message)" -Status "ERROR"
        }
        
        # Пауза между действиями
        if ($FullMode) {
            Start-Sleep -Milliseconds 10000
        }
    }

    return $success
}
#endregion

#region Основная логика
try {
    # Запрос имени компьютера, если не указан
    if (-not $ComputerName) {
        $ComputerName = Read-Host "Введите имя или IP-адрес компьютера"
    }

    # Проверка прав администратора
    if (-not (Test-IsAdmin)) {
        Write-Status "Требуются права администратора. Перезапуск..." -Status "INFO"
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$($MyInvocation.MyCommand.Path)`""
        if ($ComputerName) { $arguments += " -ComputerName `"$ComputerName`"" }
        if ($FullRestore) { $arguments += " -FullRestore" }
        Start-Process powershell -ArgumentList $arguments -Verb RunAs
        exit
    }

    # Вывод информации о запуске
    Write-Host "`n=== Утилита перезапуска графической подсистемы v$scriptVersion ===" -ForegroundColor Yellow
    Write-Status "Целевой компьютер: $ComputerName"
    Write-Status "Режим восстановления: $(if($FullRestore){'Полный (3 метода)'}else{'Только DWM'})" -Status "INFO"

    # Проверка доступности компьютера
    Write-Status "Проверка доступности компьютера..."
    if (-not (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet)) {
        throw "Компьютер $ComputerName недоступен по сети"
    }
    Write-Status "Компьютер доступен" -Status "SUCCESS"

    # Получение метода доступа
    $accessMethod = Get-PCAccess -TargetPC $ComputerName
    if (-not $accessMethod) {
        throw "Не удалось установить соединение с $ComputerName"
    }
    Write-Status "Используется метод доступа: $accessMethod" -Status "INFO"

    # Выполнение восстановления
    $success = Reset-Display -TargetPC $ComputerName -AccessMethod $accessMethod -FullMode:$FullRestore

    if (-not $success) {
        throw "Все методы восстановления не сработали"
    }
    else {
        Write-Status "Графическая подсистема успешно восстановлена" -Status "SUCCESS"
    }
}
catch {
    Write-Status "КРИТИЧЕСКАЯ ОШИБКА: $_" -Status "ERROR"
}
finally {
    # Ожидание нажатия клавиши
    Write-Host "`nНажмите любую клавишу для выхода..."
    [void][System.Console]::ReadKey($true)
}

#endregion

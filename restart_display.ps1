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

function Test-IsAdmin {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Проверяем, запущен ли скрипт с правами администратора
if (-not (Test-IsAdmin)) {
    Write-Status "Скрипт не запущен с правами администратора. Перезапускаем с повышенными правами..." -Status "INFO"
    
    # Получаем полный путь к текущему скрипту
    $scriptPath = $MyInvocation.MyCommand.Definition
    
    # Формируем аргументы для перезапуска
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    if ($ComputerName) { $arguments += " -ComputerName `"$ComputerName`"" }
    if ($FullRestore) { $arguments += " -FullRestore" }

    # Запускаем с правами админа
    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs
    exit
}
# ===== КОНЕЦ ТВОЕГО МОДУЛЯ =====

# Остальной код скрипта (функции Get-PCAccess, Reset-Display и основная логика) остаётся без изменений
# ...

#region Основная логика
try {
    # Запрос имени компьютера, если не указан
    if (-not $ComputerName) {
        $ComputerName = Read-Host "Введите имя или IP-адрес компьютера"
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
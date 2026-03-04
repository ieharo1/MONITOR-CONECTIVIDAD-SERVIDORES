# ===============================================================
# server-connectivity-monitor.ps1
# Monitor de conectividad y latencia a servidores/IP configurables
# ===============================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ================= CONFIG =================
$Config = @{
    ScriptName = 'Server-Connectivity-Monitor'
    LogRoot = 'C:\Scripts\Logs\Server-Connectivity-Monitor'
    Targets = @('8.8.8.8','1.1.1.1','server01.company.local')
    PingCount = 2
    TimeoutSeconds = 2
    Sql = @{ Enabled = $true; Server = 'SQLSERVER01'; Database = 'AutomationDB'; Table = 'dbo.ServerConnectivityHistory'; UseIntegratedSecurity = $true; SqlUser = 'sql_user_placeholder'; SqlPasswordEnvVar = 'AUTOMATION_SQL_PASSWORD'; CommandTimeoutSeconds = 30 }
    Notification = @{
        Mail = @{ Enabled = $true; SmtpServer = 'smtp.company.local'; Port = 587; UseSsl = $true; User = 'smtp_user_placeholder'; PasswordEnvVar = 'AUTOMATION_SMTP_PASSWORD'; From = 'automation@company.local'; To = @('ops@company.local') }
        Telegram = @{ Enabled = $true; BotTokenEnvVar = 'AUTOMATION_TELEGRAM_BOT_TOKEN'; ChatIdEnvVar = 'AUTOMATION_TELEGRAM_CHAT_ID' }
    }
}

# ================= LOG =================
if (-not (Test-Path -Path $Config.LogRoot)) { New-Item -Path $Config.LogRoot -ItemType Directory -Force | Out-Null }
$LogFile = Join-Path $Config.LogRoot ('{0}-{1:yyyyMMdd}.log' -f $Config.ScriptName, (Get-Date))

function Log {
    param([Parameter(Mandatory)] [string]$Message, [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO', [hashtable]$Data)
    $entry = [ordered]@{ timestamp=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); level=$Level; script=$Config.ScriptName; host=$env:COMPUTERNAME; message=$Message; data=$Data }
    Add-Content -Path $LogFile -Value ($entry | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
    Write-Host ('[{0}] {1}' -f $Level, $Message)
}

function Send-Mail {
    param([Parameter(Mandatory)] [string]$Subject, [Parameter(Mandatory)] [string]$Body)
    if (-not $Config.Notification.Mail.Enabled) { return }
    try {
        $pwd = [Environment]::GetEnvironmentVariable($Config.Notification.Mail.PasswordEnvVar, 'Machine')
        if ([string]::IsNullOrWhiteSpace($pwd)) { $pwd = [Environment]::GetEnvironmentVariable($Config.Notification.Mail.PasswordEnvVar, 'Process') }
        if ([string]::IsNullOrWhiteSpace($pwd)) { throw "No existe variable '$($Config.Notification.Mail.PasswordEnvVar)'" }
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = $Config.Notification.Mail.From
        foreach ($recipient in $Config.Notification.Mail.To) { [void]$mail.To.Add($recipient) }
        $mail.Subject = $Subject
        $mail.Body = $Body
        $smtp = New-Object System.Net.Mail.SmtpClient($Config.Notification.Mail.SmtpServer, $Config.Notification.Mail.Port)
        $smtp.EnableSsl = $Config.Notification.Mail.UseSsl
        $smtp.Credentials = New-Object System.Net.NetworkCredential($Config.Notification.Mail.User, $pwd)
        $smtp.Send($mail)
        $mail.Dispose(); $smtp.Dispose()
        Log -Message 'Notificación SMTP enviada.'
    }
    catch { Log -Message "Error SMTP: $($_.Exception.Message)" -Level 'ERROR' }
}

function Send-Telegram {
    param([Parameter(Mandatory)] [string]$Message)
    if (-not $Config.Notification.Telegram.Enabled) { return }
    try {
        $bot = [Environment]::GetEnvironmentVariable($Config.Notification.Telegram.BotTokenEnvVar, 'Machine')
        $chat = [Environment]::GetEnvironmentVariable($Config.Notification.Telegram.ChatIdEnvVar, 'Machine')
        if ([string]::IsNullOrWhiteSpace($bot)) { $bot = [Environment]::GetEnvironmentVariable($Config.Notification.Telegram.BotTokenEnvVar, 'Process') }
        if ([string]::IsNullOrWhiteSpace($chat)) { $chat = [Environment]::GetEnvironmentVariable($Config.Notification.Telegram.ChatIdEnvVar, 'Process') }
        if ([string]::IsNullOrWhiteSpace($bot) -or [string]::IsNullOrWhiteSpace($chat)) { throw 'Faltan credenciales Telegram.' }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-RestMethod -Uri ("https://api.telegram.org/bot{0}/sendMessage" -f $bot) -Method Post -Body @{ chat_id=$chat; text=$Message } | Out-Null
        Log -Message 'Notificación Telegram enviada.'
    }
    catch { Log -Message "Error Telegram: $($_.Exception.Message)" -Level 'ERROR' }
}

function New-SqlConnection {
    if (-not $Config.Sql.Enabled) { return $null }
    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source'] = $Config.Sql.Server
    $builder['Initial Catalog'] = $Config.Sql.Database
    if ($Config.Sql.UseIntegratedSecurity) {
        $builder['Integrated Security'] = $true
    }
    else {
        $pwd = [Environment]::GetEnvironmentVariable($Config.Sql.SqlPasswordEnvVar, 'Machine')
        if ([string]::IsNullOrWhiteSpace($pwd)) { $pwd = [Environment]::GetEnvironmentVariable($Config.Sql.SqlPasswordEnvVar, 'Process') }
        if ([string]::IsNullOrWhiteSpace($pwd)) { throw "No existe variable '$($Config.Sql.SqlPasswordEnvVar)'" }
        $builder['User ID'] = $Config.Sql.SqlUser
        $builder['Password'] = $pwd
    }
    $cn = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
    $cn.Open()
    return $cn
}

function Test-Prerequisites {
    if (-not (Get-Command -Name Test-Connection -ErrorAction SilentlyContinue)) { throw 'Test-Connection no está disponible.' }
}

$errorsList = New-Object System.Collections.Generic.List[string]
$offlineTargets = New-Object System.Collections.Generic.List[string]
$sqlConnection = $null

Log -Message '=== INICIO SERVER CONNECTIVITY MONITOR ==='

try {
    Test-Prerequisites
    $sqlConnection = New-SqlConnection

    foreach ($target in $Config.Targets) {
        $isOnline = $false
        $latency = $null

        try {
            $replies = Test-Connection -ComputerName $target -Count $Config.PingCount -TimeoutSeconds $Config.TimeoutSeconds -ErrorAction Stop
            if ($replies) {
                $isOnline = $true
                $latency = [math]::Round((($replies | Measure-Object -Property ResponseTime -Average).Average), 2)
                Log -Message "Conectividad OK: $target" -Data @{ LatencyMs = $latency }
            }
        }
        catch {
            $offlineTargets.Add($target)
            Log -Message "Sin respuesta: $target - $($_.Exception.Message)" -Level 'WARN'
        }

        if ($Config.Sql.Enabled -and $null -ne $sqlConnection) {
            $cmd = $sqlConnection.CreateCommand()
            $cmd.CommandText = "INSERT INTO $($Config.Sql.Table) (ServerName, Target, IsOnline, LatencyMs, CheckedAt) VALUES (@ServerName, @Target, @IsOnline, @LatencyMs, @CheckedAt)"
            [void]$cmd.Parameters.Add('@ServerName', [System.Data.SqlDbType]::VarChar, 64)
            [void]$cmd.Parameters.Add('@Target', [System.Data.SqlDbType]::VarChar, 256)
            [void]$cmd.Parameters.Add('@IsOnline', [System.Data.SqlDbType]::Bit)
            [void]$cmd.Parameters.Add('@LatencyMs', [System.Data.SqlDbType]::Decimal)
            [void]$cmd.Parameters.Add('@CheckedAt', [System.Data.SqlDbType]::DateTime)
            $cmd.Parameters['@ServerName'].Value = $env:COMPUTERNAME
            $cmd.Parameters['@Target'].Value = $target
            $cmd.Parameters['@IsOnline'].Value = $isOnline
            if ($null -eq $latency) { $cmd.Parameters['@LatencyMs'].Value = [DBNull]::Value } else { $cmd.Parameters['@LatencyMs'].Value = $latency }
            $cmd.Parameters['@CheckedAt'].Value = Get-Date
            [void]$cmd.ExecuteNonQuery()
            $cmd.Dispose()
        }
    }
}
catch {
    $errorsList.Add($_.Exception.Message)
    Log -Message "Error general: $($_.Exception.Message)" -Level 'ERROR'
}
finally {
    if ($null -ne $sqlConnection) {
        if ($sqlConnection.State -eq [System.Data.ConnectionState]::Open) { $sqlConnection.Close() }
        $sqlConnection.Dispose()
    }
}

# ================= NOTIFICACION FINAL =================
if ($errorsList.Count -gt 0 -or $offlineTargets.Count -gt 0) {
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($err in $errorsList) { $lines.Add("ERROR: $err") }
    foreach ($target in $offlineTargets) { $lines.Add("OFFLINE: $target") }
    $msg = "Server Connectivity Monitor ($env:COMPUTERNAME)`n" + ($lines -join "`n")
    Send-Mail -Subject "ALERTA Conectividad Servidores - $env:COMPUTERNAME" -Body $msg
    Send-Telegram -Message $msg
}
else {
    Send-Telegram -Message "Server Connectivity Monitor sin alertas en $env:COMPUTERNAME"
}

Log -Message '=== FIN SERVER CONNECTIVITY MONITOR ==='

# ---
# ## ‍ Desarrollado por Isaac Esteban Haro Torres
# **Ingeniero en Sistemas · Full Stack · Automatización · Data**
# -  Email: zackharo1@gmail.com
# -  WhatsApp: 098805517
# -  GitHub: https://github.com/ieharo1
# -  Portafolio: https://ieharo1.github.io/portafolio-isaac.haro/
# ---
# ##  Licencia
# © 2026 Isaac Esteban Haro Torres - Todos los derechos reservados.

# Monitor de Conectividad a Servidores - Documentacion Operativa

Script principal: `server-connectivity-monitor.ps1`

## Objetivo
Monitorear conectividad de una lista de servidores/IP, medir latencia, guardar historico en SQL y alertar caidas.

## Funcionamiento
1. Valida cmdlet `Test-Connection`.
2. Recorre `Targets` configurados.
3. Ejecuta ping (cantidad y timeout configurables).
4. Calcula latencia promedio cuando hay respuesta.
5. Inserta resultados en SQL (`dbo.ServerConnectivityHistory`).
6. Notifica targets offline y errores por SMTP/Telegram.

## Prerequisitos
- Windows Server 2019/2022
- Permiso de red ICMP hacia targets
- SQL Server y SMTP accesibles
- Salida HTTPS para Telegram

## Configuracion
- `Targets` (hostnames o IPs)
- `PingCount`
- `TimeoutSeconds`
- `Sql.Server`, `Sql.Database`, `Sql.Table`
- `Notification.Mail.*`
- `Notification.Telegram.*`

## Variables de entorno
- `AUTOMATION_SQL_PASSWORD` (si SQL auth)
- `AUTOMATION_SMTP_PASSWORD`
- `AUTOMATION_TELEGRAM_BOT_TOKEN`
- `AUTOMATION_TELEGRAM_CHAT_ID`

## Estructura SQL esperada (referencia)
Tabla: `dbo.ServerConnectivityHistory`
Campos sugeridos:
- `ServerName`
- `Target`
- `IsOnline`
- `LatencyMs`
- `CheckedAt`

## Como ejecutar

```powershell
cd C:\Users\Nabetse\Downloads\server\DibujarFiguraGeom
.\server-connectivity-monitor.ps1
```

## Programacion recomendada
- Trigger: cada 5 minutos o 15 minutos
- Definir SLA de latencia y disponibilidad para interpretar alertas

## Seguridad
- Separar red de monitoreo
- Proteger credenciales en variables de entorno
- Auditar cambios de targets y umbrales
---
## ‍ Desarrollado por Isaac Esteban Haro Torres
**Ingeniero en Sistemas · Full Stack · Automatización · Data**
-  Email: zackharo1@gmail.com
-  WhatsApp: 098805517
-  GitHub: https://github.com/ieharo1
-  Portafolio: https://ieharo1.github.io/portafolio-isaac.haro/
---
##  Licencia
© 2026 Isaac Esteban Haro Torres - Todos los derechos reservados.

param(
    [string]$MySqlBin = 'C:/Program Files/MySQL/MySQL Server 8.0/bin',
    [string]$JdbcJar = 'C:/Users/USUARIO/.m2/repository/com/mysql/mysql-connector-j/9.7.0/mysql-connector-j-9.7.0.jar',
    [string]$LoginPath = 'horarios_auditoria',
    [string]$SourceUser = 'horarios_migra'
)

# Prueba integral en OTRA instancia MySQL, sin escribir en el servidor original.
# Requiere PowerShell, Java 25+ y MySQL 8.0.45. No ejecuta seed, Flyway ni V3.
# Uso, desde la raiz del repositorio:
#   powershell -ExecutionPolicy Bypass -File database/tools/probar_control_almuerzo.ps1
# Conserva logs/copia/datadir en backend/target; apaga solo el proceso temporal.
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$taskRun = Join-Path $taskRoot ('backend/target/mysql-almuerzo-integral-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$taskExpectedPrefix = [IO.Path]::GetFullPath((Join-Path $taskRoot 'backend/target')) + [IO.Path]::DirectorySeparatorChar
if (-not $taskRun.StartsWith($taskExpectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'La carpeta temporal no esta dentro de backend/target.'
}
New-Item -ItemType Directory -Path $taskRun | Out-Null
$taskData = Join-Path $taskRun 'data'
New-Item -ItemType Directory -Path $taskData | Out-Null
$taskClient = Join-Path $MySqlBin 'mysql.exe'
$taskDump = Join-Path $MySqlBin 'mysqldump.exe'
$taskServer = Join-Path $MySqlBin 'mysqld.exe'
$taskAdmin = Join-Path $MySqlBin 'mysqladmin.exe'
foreach ($taskFile in @($taskClient,$taskDump,$taskServer,$taskAdmin,$JdbcJar)) {
    if (-not (Test-Path -LiteralPath $taskFile -PathType Leaf)) { throw "No existe $taskFile" }
}
$taskUtf8 = New-Object System.Text.UTF8Encoding($false)
$taskProcess = $null
$taskUuid = $null
$taskPort = $null
$taskFailure = $null
$taskSuccess = $false
$taskSourceUntouched = $false
$taskSourceHashBefore = $null
$taskSourceHashAfter = $null
$taskSourceV3Before = $null
$taskSourceV3After = $null
$taskInstalledRoutines = $null
$taskNativeRollback = $false
$taskScripts = [ordered]@{}
$taskBefore = Join-Path $taskRun 'origen-antes.sql'
$taskAfter = Join-Path $taskRun 'origen-despues.sql'
$taskSummary = Join-Path $taskRun 'resumen.json'

function Invoke-SourceQuery([string]$taskSql) {
    $ErrorActionPreference = 'Continue' # Evaluar salida y exit code nativos, no avisos stderr.
    $taskOutput = & $taskClient "--login-path=$LoginPath" "--user=$SourceUser" --protocol=TCP --host=127.0.0.1 --port=3306 --connect-timeout=5 --database=horarios_ueb --default-character-set=utf8mb4 --batch --raw --skip-column-names "--execute=$taskSql" 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('Consulta de lectura al origen: ' + ($taskOutput -join "`n")) }
    return ($taskOutput -join "`n")
}

function Export-Source([string]$taskDestination) {
    $ErrorActionPreference = 'Continue'
    # Sin LOCK TABLES, FLUSH, GTID_PURGED, ni operaciones DDL/DML en el origen.
    $taskOutput = & $taskDump "--login-path=$LoginPath" "--user=$SourceUser" --protocol=TCP --host=127.0.0.1 --port=3306 --single-transaction --skip-lock-tables --routines --triggers --events --no-tablespaces --set-gtid-purged=OFF --column-statistics=0 --skip-comments --hex-blob --order-by-primary --skip-add-drop-table "--result-file=$taskDestination" horarios_ueb 2>&1
    if ($LASTEXITCODE -ne 0) { throw ('Copia de lectura del origen: ' + ($taskOutput -join "`n")) }
}

function Get-TemporaryIdentity {
    $ErrorActionPreference = 'Continue'
    if (-not $taskPort -or $taskPort -eq 3306) { throw 'Puerto temporal invalido.' }
    $taskOutput = & $taskClient --no-defaults --protocol=TCP --host=127.0.0.1 "--port=$taskPort" --user=root --skip-password --connect-timeout=2 --batch --raw --skip-column-names '--execute=SELECT @@port,@@server_uuid,@@datadir,VERSION();' 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'La instancia temporal no responde aun.' }
    $taskIdentity = ($taskOutput -join "`n").Trim().Split("`t")
    if ($taskIdentity.Length -ne 4) { throw 'Identidad temporal no reconocida.' }
    $taskActualData = [IO.Path]::GetFullPath($taskIdentity[2].TrimEnd('\','/'))
    if ([int]$taskIdentity[0] -ne $taskPort -or $taskActualData -ine [IO.Path]::GetFullPath($taskData)) {
        throw 'La identidad del servidor no coincide con el puerto/datadir temporal.'
    }
    if ($taskUuid -and $taskIdentity[1] -ne $taskUuid) { throw 'Cambio el UUID de la instancia temporal.' }
    if ($taskIdentity[3] -ne '8.0.45') { throw 'Se requiere MySQL temporal 8.0.45.' }
    return $taskIdentity
}

function Invoke-Temporary([string]$taskSql, [string]$taskLog) {
    $ErrorActionPreference = 'Continue'
    $null = Get-TemporaryIdentity
    $taskOutput = & $taskClient --no-defaults --protocol=TCP --host=127.0.0.1 "--port=$taskPort" --user=root --skip-password --connect-timeout=5 --default-character-set=utf8mb4 --batch --raw "--execute=$taskSql" 2>&1
    [IO.File]::WriteAllText($taskLog, ($taskOutput -join "`n"), $taskUtf8)
    if ($LASTEXITCODE -ne 0 -or (($taskOutput -join "`n") -match '(?m)^ERROR ')) {
        throw "Fallo SQL SOLO en la instancia temporal; revisar $taskLog"
    }
}

try {
    Write-Output "Evidencia de prueba: $taskRun"
    $taskScriptDir = Join-Path $taskRun 'scripts-probados'
    New-Item -ItemType Directory -Path $taskScriptDir | Out-Null
    foreach ($taskScriptName in @('preparar_control_almuerzo_2026_2.sql','aplicar_almuerzo_2026_2.sql','permisos_control_almuerzo_2026_2.sql','probar_control_almuerzo.ps1','PruebaIntegralAlmuerzo.java')) {
        $taskScriptFile = Join-Path $PSScriptRoot $taskScriptName
        $taskScripts[$taskScriptName] = (Get-FileHash -LiteralPath $taskScriptFile -Algorithm SHA256).Hash
        Copy-Item -LiteralPath $taskScriptFile -Destination (Join-Path $taskScriptDir $taskScriptName)
    }
    [IO.File]::WriteAllText((Join-Path $taskRun 'versiones-probadas.json'),($taskScripts | ConvertTo-Json),$taskUtf8)
    $taskSourceIdentity = Invoke-SourceQuery 'SELECT @@port,@@server_uuid,@@datadir,VERSION(),CURRENT_USER(),USER(),CURRENT_ROLE();'
    [IO.File]::WriteAllText((Join-Path $taskRun 'identidad-origen.tsv'), $taskSourceIdentity, $taskUtf8)
    if (($taskSourceIdentity.Split("`t"))[0] -ne '3306') { throw 'El origen no corresponde al puerto esperado.' }
    $taskSourceV3Before = [int](Invoke-SourceQuery "SELECT COUNT(*) FROM flyway_schema_history WHERE version='3';")
    Export-Source $taskBefore
    $taskSourceHashBefore = (Get-FileHash -LiteralPath $taskBefore -Algorithm SHA256).Hash
    Write-Output 'Copia de solo lectura del origen obtenida; inicializando servidor temporal.'

    $taskListener = New-Object System.Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
    $taskListener.Start()
    $taskPort = $taskListener.LocalEndpoint.Port
    $taskListener.Stop()
    if ($taskPort -eq 3306) { throw 'El puerto temporal no puede ser el original.' }
    $taskInitArgs = @('--no-defaults','--initialize-insecure',"--datadir=$taskData",'--innodb-buffer-pool-size=67108864','--innodb-redo-log-capacity=16777216')
    $taskInitQuoted = ($taskInitArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $taskInit = Start-Process -FilePath $taskServer -ArgumentList $taskInitQuoted -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $taskRun 'inicializar-out.log') -RedirectStandardError (Join-Path $taskRun 'inicializar-error.log')
    if ($taskInit.ExitCode -ne 0) { throw ('No se pudo inicializar el datadir temporal; codigo ' + $taskInit.ExitCode + '. Revisar el log .err en data.') }

    $taskServerArgs = @('--no-defaults',"--datadir=$taskData",'--bind-address=127.0.0.1',"--port=$taskPort",'--mysqlx=OFF','--skip-log-bin','--event-scheduler=OFF','--performance-schema=OFF','--innodb-buffer-pool-size=67108864','--innodb-redo-log-capacity=16777216',"--log-error=$(Join-Path $taskRun 'servidor.log')", "--pid-file=$(Join-Path $taskRun 'servidor.pid')")
    $taskServerQuoted = ($taskServerArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
    $taskProcess = Start-Process -FilePath $taskServer -ArgumentList $taskServerQuoted -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $taskRun 'servidor-out.log') -RedirectStandardError (Join-Path $taskRun 'servidor-error.log')
    $taskReady = $false
    for ($taskAttempt=0; $taskAttempt -lt 80; $taskAttempt++) {
        if ($taskProcess.HasExited) { throw 'El proceso temporal termino antes de aceptar conexiones.' }
        try {
            $taskIdentity = Get-TemporaryIdentity
            $taskUuid = $taskIdentity[1]
            $taskReady = $true
            break
        } catch { Start-Sleep -Milliseconds 250 }
    }
    if (-not $taskReady) { throw 'La instancia temporal no quedo disponible.' }
    if ($taskSourceIdentity.Contains($taskUuid)) { throw 'El UUID temporal no puede coincidir con el original.' }
    [IO.File]::WriteAllText((Join-Path $taskRun 'identidad-temporal.tsv'), ($taskIdentity -join "`t"), $taskUtf8)
    Write-Output "Servidor temporal verificado: puerto $taskPort; UUID $taskUuid."

    # Solo la copia cambia sus DEFINER a la cuenta root de la instancia privada.
    # Los cuerpos de tablas/vistas/triggers/rutinas y los datos se conservan.
    $taskDumpText = [IO.File]::ReadAllText($taskBefore, [Text.Encoding]::UTF8)
    $taskDefinerPattern = 'DEFINER\s*=\s*`[^`]*`\s*@\s*`[^`]*`'
    $taskDefiners = @([regex]::Matches($taskDumpText,$taskDefinerPattern) | ForEach-Object { $_.Value } | Sort-Object -Unique)
    $taskCloneText = [regex]::Replace($taskDumpText,$taskDefinerPattern,'DEFINER=CURRENT_USER')
    # MySQL 8.0.45 expande esta vista recursiva con alias internos >64 caracteres
    # que su propio dump no puede restaurar (error 1166). La lista explicita
    # de columnas del CTE hace que esos alias internos no definan su contrato.
    # Acortarlos SOLO en la copia no cambia expresiones, filtros ni resultados.
    $taskViewPattern = '(?s)/\*!50001 CREATE ALGORITHM=UNDEFINED \*/\s*/\*!50013 DEFINER=CURRENT_USER SQL SECURITY DEFINER \*/\s*/\*!50001 VIEW `v_bloque_valido` AS .*?\*/;'
    $taskViewMatch = [regex]::Match($taskCloneText,$taskViewPattern)
    if (-not $taskViewMatch.Success) { throw 'No se encontro la definicion exportada de v_bloque_valido.' }
    $taskAliasNotes = New-Object 'System.Collections.Generic.List[string]'
    $taskViewFixed = [regex]::Replace($taskViewMatch.Value, '(?s)\bAS\s+`([^`]+)`', [System.Text.RegularExpressions.MatchEvaluator]{
        param($taskAlias)
        if ($taskAlias.Groups[1].Value.Length -le 64) { return $taskAlias.Value }
        $taskReplacement = 'AS `expresion_' + $taskAliasNotes.Count + '`'
        $taskAliasNotes.Add($taskAlias.Value + ' -> ' + $taskReplacement)
        return $taskReplacement
    })
    $taskCloneText = $taskCloneText.Substring(0,$taskViewMatch.Index) + $taskViewFixed + $taskCloneText.Substring($taskViewMatch.Index+$taskViewMatch.Length)
    $taskClone = Join-Path $taskRun 'copia-solo-instancia-temporal.sql'
    [IO.File]::WriteAllText($taskClone,$taskCloneText,$taskUtf8)
    [IO.File]::WriteAllText((Join-Path $taskRun 'adaptacion-definers.txt'), ('Solo en la copia: ' + ($taskDefiners -join '; ') + ' -> DEFINER=CURRENT_USER'),$taskUtf8)
    [IO.File]::WriteAllText((Join-Path $taskRun 'adaptacion-alias-vista.txt'),($taskAliasNotes -join "`n"),$taskUtf8)
    Invoke-Temporary 'CREATE DATABASE horarios_ueb CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;' (Join-Path $taskRun 'crear-base-temporal.log')
    Invoke-Temporary ("USE horarios_ueb;`nSOURCE " + $taskClone.Replace('\','/')) (Join-Path $taskRun 'importacion.log')
    $taskGridQuery = 'SELECT periodo_id,dia,hora_inicio,hora_fin FROM v_bloque_valido ORDER BY periodo_id,dia,hora_inicio;'
    $taskOriginalGrid = Invoke-SourceQuery $taskGridQuery
    $null = Get-TemporaryIdentity
    $ErrorActionPreference = 'Continue'
    $taskClonedGrid = & $taskClient --no-defaults --protocol=TCP --host=127.0.0.1 "--port=$taskPort" --user=root --skip-password --database=horarios_ueb --batch --raw --skip-column-names "--execute=$taskGridQuery" 2>$null
    $taskGridExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($taskGridExit -ne 0 -or ($taskClonedGrid -join "`n") -cne $taskOriginalGrid) { throw 'La cuadricula del clon no coincide exactamente con el origen.' }
    [IO.File]::WriteAllText((Join-Path $taskRun 'cuadricula-clon-verificada.tsv'),$taskOriginalGrid,$taskUtf8)
    $taskSetup = Join-Path $taskRoot 'database/tools/preparar_control_almuerzo_2026_2.sql'
    # Se instala el archivo real SIN remapear USE, CALL ni logica del control.
    Invoke-Temporary ('SOURCE ' + $taskSetup.Replace('\','/')) (Join-Path $taskRun 'instalacion-control.log')
    $taskInstallLog = Join-Path $taskRun 'verificacion-cuatro-auxiliares.log'
    Invoke-Temporary "SELECT CONCAT('AUXILIARES_INSTALADOS=',COUNT(*)) FROM information_schema.routines WHERE routine_schema='horarios_ueb' AND routine_type='PROCEDURE' AND security_type='INVOKER' AND routine_name IN ('sp_almuerzo_2026_2_huellas','sp_almuerzo_2026_2_verificar','sp_almuerzo_2026_2_aplicar','sp_almuerzo_2026_2_confirmar'); SELECT routine_name,routine_type,security_type FROM information_schema.routines WHERE routine_schema='horarios_ueb' AND routine_name LIKE 'sp_almuerzo_2026_2_%' ORDER BY routine_name;" $taskInstallLog
    $taskInstallText = [IO.File]::ReadAllText($taskInstallLog,$taskUtf8)
    $taskInstallMatch = [regex]::Match($taskInstallText,'(?m)^AUXILIARES_INSTALADOS=(\d+)\r?$')
    if (-not $taskInstallMatch.Success) { throw 'No se pudo medir la instalacion de los auxiliares.' }
    $taskInstalledRoutines = [int]$taskInstallMatch.Groups[1].Value
    if ($taskInstalledRoutines -ne 4) { throw 'La consulta no encontro cuatro procedimientos INVOKER.' }
    Write-Output 'Copia y procedimientos reales instalados SOLO en la instancia temporal.'

    # El archivo de permisos es una propuesta enteramente comentada: se comprueba
    # literalmente sin conceder permisos a cuentas reales. Java prueba sus minimos
    # con una cuenta creada exclusivamente en esta instancia temporal.
    $taskPermissionFile = Join-Path $PSScriptRoot 'permisos_control_almuerzo_2026_2.sql'
    $taskPermissionText = [IO.File]::ReadAllText($taskPermissionFile,$taskUtf8)
    if ([regex]::Replace($taskPermissionText,'(?m)--[^\r\n]*','').Trim().Length -gt 0) { throw 'El archivo de permisos contiene SQL activo; detenerse.' }
    Invoke-Temporary ('SOURCE ' + $taskPermissionFile.Replace('\','/')) (Join-Path $taskRun 'permisos-comentados.log')

    # Ejecutar el archivo SQL real del operador, manteniendo su conexion hasta
    # verificar y revertir. No sustituirlo solo por una llamada equivalente.
    $taskOperatorFile = Join-Path $PSScriptRoot 'aplicar_almuerzo_2026_2.sql'
    $taskOperatorTrial = Join-Path $taskRun 'probar-operador-rollback.sql'
    $taskOperatorSql = "USE horarios_ueb;`nSET SESSION group_concat_max_len=1048576;`nCALL sp_almuerzo_2026_2_huellas(@operador_pre);`nSOURCE " + $taskOperatorFile.Replace('\','/') + "`nROLLBACK AND NO CHAIN NO RELEASE;`nCALL sp_almuerzo_2026_2_huellas(@operador_post);`nSELECT CONCAT('NATIVE_ROLLBACK_OK=',CAST(@operador_pre AS BINARY)<=>CAST(@operador_post AS BINARY));`n"
    [IO.File]::WriteAllText($taskOperatorTrial,$taskOperatorSql,$taskUtf8)
    $taskOperatorLog = Join-Path $taskRun 'operador-real-rollback.log'
    Invoke-Temporary ('SOURCE ' + $taskOperatorTrial.Replace('\','/')) $taskOperatorLog
    $taskNativeRollback = [regex]::IsMatch([IO.File]::ReadAllText($taskOperatorLog,$taskUtf8),'(?m)^NATIVE_ROLLBACK_OK=1\r?$')
    if (-not $taskNativeRollback) { throw 'El archivo SQL del operador no restauro las ocho huellas mediante ROLLBACK.' }

    $taskHarness = Join-Path $taskRoot 'database/tools/PruebaIntegralAlmuerzo.java'
    if (-not (Test-Path -LiteralPath $taskHarness)) { throw 'Falta PruebaIntegralAlmuerzo.java.' }
    $taskReport = Join-Path $taskRun 'resultados-integrales.json'
    $null = Get-TemporaryIdentity
    $ErrorActionPreference = 'Continue'
    $taskJavaOutput = & java --class-path $JdbcJar $taskHarness $taskPort $taskData $taskUuid $taskReport 2>&1
    $taskJavaExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    [IO.File]::WriteAllText((Join-Path $taskRun 'prueba-java.log'),($taskJavaOutput -join "`n"),$taskUtf8)
    $taskJavaOutput | ForEach-Object { Write-Output $_ }
    if ($taskJavaExit -ne 0) { throw 'La prueba integral fallo; revisar prueba-java.log.' }
    $taskSuccess = $true
} catch {
    $taskFailure = $_.Exception.Message
    Write-Output ("FALLO: $taskFailure")
} finally {
    # Apagar exclusivamente la instancia temporal propia, nunca el servicio MySQL80.
    if ($taskProcess -and -not $taskProcess.HasExited) {
        try {
            $null = Get-TemporaryIdentity
            $ErrorActionPreference = 'Continue'
            $taskStopOutput = & $taskAdmin --no-defaults --protocol=TCP --host=127.0.0.1 "--port=$taskPort" --user=root --skip-password --connect-timeout=5 shutdown 2>&1
            $ErrorActionPreference = 'Stop'
            if ($LASTEXITCODE -ne 0) { throw 'No se completo el apagado temporal.' }
            if (-not $taskProcess.WaitForExit(15000)) { throw 'El proceso temporal no termino tras shutdown.' }
        } catch {
            # PID devuelto por Start-Process de ESTE datadir; no se busca otro mysqld.
            if (-not $taskProcess.HasExited) {
                Stop-Process -Id $taskProcess.Id -ErrorAction SilentlyContinue
                $null = $taskProcess.WaitForExit(5000)
            }
        }
    }
    $taskStopped = ($null -eq $taskProcess -or $taskProcess.HasExited)
    if (-not $taskStopped) {
        $taskSuccess = $false
        $taskFailure = ($taskFailure + ' La instancia temporal sigue activa.').Trim()
    }
    if (Test-Path -LiteralPath $taskBefore -PathType Leaf) {
        try {
            Export-Source $taskAfter
            $taskSourceHashAfter = (Get-FileHash -LiteralPath $taskAfter -Algorithm SHA256).Hash
            $taskSourceUntouched = $taskSourceHashBefore -eq $taskSourceHashAfter
            $taskSourceV3After = [int](Invoke-SourceQuery "SELECT COUNT(*) FROM flyway_schema_history WHERE version='3';")
            if (-not $taskSourceUntouched) { throw 'La huella completa del origen difiere; no atribuir ni corregir cambios automaticamente.' }
            if ($taskSourceV3After -ne $taskSourceV3Before) { throw 'Cambio el historial V3 del origen.' }
            Write-Output 'Origen intacto: copia completa antes/despues identica (datos y objetos).'
        } catch {
            $taskSuccess = $false
            $taskFailure = ($taskFailure + ' ' + $_.Exception.Message).Trim()
        }
    }
    $taskRecord = [ordered]@{
        pruebas_correctas=$taskSuccess; origen_intacto=$taskSourceUntouched;
        origen_puerto=3306; temporal_puerto=$taskPort; temporal_uuid=$taskUuid;
        temporal_datadir=$taskData; temporal_detenido=$taskStopped;
        auxiliares_instalados=$taskInstalledRoutines; rollback_archivo_operador=$taskNativeRollback;
        origen_sha256_antes=$taskSourceHashBefore; origen_sha256_despues=$taskSourceHashAfter;
        v3_registros_origen_antes=$taskSourceV3Before; v3_registros_origen_despues=$taskSourceV3After;
        versiones_scripts=$taskScripts; evidencia=$taskRun; error=$taskFailure
    }
    [IO.File]::WriteAllText($taskSummary,($taskRecord | ConvertTo-Json -Depth 4),$taskUtf8)
    Write-Output "Resumen: $taskSummary"
}
if (-not $taskSuccess -or -not $taskSourceUntouched) { exit 1 }
exit 0

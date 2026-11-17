# Analisis completo de envios-service con SonarQube en Docker.
#  1. Levanta SonarQube (contenedor "sonarqube"), cambia la clave de admin y genera un token.
#  2. Analiza la version inicial (tag parte1-inicial) con el perfil y el gate por defecto.
#  3. Crea el Quality Profile y el Quality Gate "Estándar Laboratorio" y analiza la version actual.
#  4. Guarda capturas en docs\ y escribe las metricas reales en README.md y docs\metricas-sonar.md.
# Uso: powershell -ExecutionPolicy Bypass -File analisis-sonar.ps1
$ErrorActionPreference = 'Continue'
trap { Write-Host "[ERROR] $_" -ForegroundColor Red; exit 1 }
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding $false
$sonar = 'http://localhost:9000'
$proyecto = 'com.universidad:envios-service'
$archivoServicio = "${proyecto}:src/main/java/com/universidad/enviosservice/service/ServicioCalculoEnvio.java"
$credenciales = Join-Path $PSScriptRoot '.sonar-local'
$claveNueva = 'Laboratorio-U10-envios'
$nombreEstandar = 'Estándar Laboratorio'
$docs = Join-Path $PSScriptRoot 'docs'
New-Item -ItemType Directory -Force -Path $docs | Out-Null

function Fallar([string]$mensaje) { Write-Host "[ERROR] $mensaje" -ForegroundColor Red; exit 1 }
function Codificar([string]$s) { [uri]::EscapeDataString($s) }
function Cabecera([string]$usuario, [string]$clave) {
    @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("${usuario}:${clave}")) }
}
function Api([string]$metodo, [string]$ruta, [hashtable]$datos = $null) {
    $uri = "$sonar$ruta"
    if ($datos) {
        $cuerpo = ($datos.GetEnumerator() | ForEach-Object { "$($_.Key)=$(Codificar ([string]$_.Value))" }) -join '&'
        return Invoke-RestMethod -Method $metodo -Uri $uri -Headers $script:H -Body $cuerpo -ContentType 'application/x-www-form-urlencoded; charset=utf-8' -ErrorAction Stop
    }
    return Invoke-RestMethod -Method $metodo -Uri $uri -Headers $script:H -ErrorAction Stop
}

# ---------------------------------------------------------------- 1. SonarQube
Write-Host '=== 1/5 SonarQube en Docker ==='
docker version *> $null
if ($LASTEXITCODE -ne 0) { Fallar 'Docker no responde. Abre Docker Desktop, espera a que diga "running" y vuelve a ejecutar.' }
$existe = docker ps -a --filter 'name=^sonarqube$' --format '{{.Names}}'
if (-not $existe) {
    docker run -d --name sonarqube -p 9000:9000 -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true sonarqube:community | Out-Null
} else {
    docker start sonarqube | Out-Null
}
Write-Host 'Esperando a que SonarQube este operativo (la primera vez tarda unos minutos)...'
$estado = $null
for ($i = 0; $i -lt 120; $i++) {
    try { $estado = (Invoke-RestMethod "$sonar/api/system/status" -TimeoutSec 5 -ErrorAction Stop).status } catch { }
    if ($estado -eq 'UP') { break }
    Start-Sleep -Seconds 5
}
if ($estado -ne 'UP') { Fallar 'SonarQube no arranco. Revisa con: docker logs sonarqube' }

function Valida([string]$clave) {
    try { return (Invoke-RestMethod "$sonar/api/authentication/validate" -Headers (Cabecera 'admin' $clave) -ErrorAction Stop).valid } catch { return $false }
}
$clave = $null
foreach ($c in @((Get-Content $credenciales -Raw -ErrorAction SilentlyContinue), $claveNueva, 'admin')) {
    if ($c -and (Valida $c.Trim())) { $clave = $c.Trim(); break }
}
if (-not $clave) { Fallar 'No se pudo entrar como admin. Si cambiaste la clave a mano, escribela en el archivo .sonar-local' }
if ($clave -eq 'admin') {
    $script:H = Cabecera 'admin' 'admin'
    Api Post '/api/users/change_password' @{ login = 'admin'; previousPassword = 'admin'; password = $claveNueva } | Out-Null
    $clave = $claveNueva
}
[System.IO.File]::WriteAllText($credenciales, $clave, $utf8)
$script:H = Cabecera 'admin' $clave
$token = (Api Post '/api/user_tokens/generate' @{ name = "envios-$(Get-Date -Format 'yyyyMMddHHmmss')" }).token
# Permite que el navegador sin sesion (capturas automaticas) vea el dashboard
try { Api Post '/api/settings/set' @{ key = 'sonar.forceAuthentication'; value = 'false' } | Out-Null } catch { }
try { Api Post '/api/projects/create' @{ project = $proyecto; name = 'Envios Service' } | Out-Null } catch { }
Write-Host "SonarQube listo en $sonar (usuario admin, clave guardada en .sonar-local)"

# ---------------------------------------------------------------- utilidades
function Analizar([string]$pom, [string]$version) {
    $dir = Split-Path -Parent (Resolve-Path $pom)
    & .\mvnw.cmd -B -q -f $pom clean verify sonar:sonar "-Dsonar.token=$token" "-Dsonar.projectVersion=$version"
    if ($LASTEXITCODE -ne 0) { Fallar "mvn verify sonar:sonar fallo para la version $version" }
    $tarea = (Get-Content (Join-Path $dir 'target\sonar\report-task.txt') | ConvertFrom-StringData).ceTaskId
    do { Start-Sleep -Seconds 3; $t = (Api Get "/api/ce/task?id=$tarea").task } while ($t.status -eq 'PENDING' -or $t.status -eq 'IN_PROGRESS')
    if ($t.status -ne 'SUCCESS') { Fallar "SonarQube no pudo procesar el analisis ($($t.status))" }
    return $dir
}

function Medidas([string]$componente) {
    $valores = @{}
    foreach ($m in 'complexity', 'cognitive_complexity', 'coverage', 'line_coverage', 'branch_coverage', 'code_smells',
                   'duplicated_lines_density', 'ncloc', 'software_quality_maintainability_issues') {
        try {
            $r = Api Get "/api/measures/component?component=$(Codificar $componente)&metricKeys=$m"
            foreach ($x in $r.component.measures) { $valores[$x.metric] = $x.value }
        } catch { }
    }
    return $valores
}

function Smells() {
    try { return @((Api Get "/api/issues/search?componentKeys=$(Codificar $proyecto)&types=CODE_SMELL&resolved=false&ps=100").issues) } catch { return @() }
}

function Captura([string]$url, [string]$salida, [int]$ancho = 1400, [int]$alto = 1000) {
    $navegadores = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
                     "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
                     "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                     "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")
    $nav = $navegadores | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $nav) { Write-Host "  (no se encontro Edge ni Chrome: guarda a mano $salida)"; return }
    $perfil = Join-Path $env:TEMP 'captura-envios'
    # Start-Process no pone comillas: se agregan para rutas con espacios
    $argumentos = "--headless=new --disable-gpu --hide-scrollbars --user-data-dir=`"$perfil`" --window-size=$ancho,$alto " +
                  "--virtual-time-budget=20000 --screenshot=`"$salida`" `"$url`""
    Start-Process -FilePath $nav -Wait -WindowStyle Hidden -ArgumentList $argumentos
    Write-Host "  captura: $salida"
}

function UrlArchivo([string]$ruta) { 'file:///' + ((Resolve-Path $ruta).Path -replace '\\', '/' -replace ' ', '%20') }

function Fila([string]$nombre, $valor, [string]$sufijo = '') {
    if ($null -eq $valor -or "$valor" -eq '') { return "| $nombre | n/d |" }
    return "| $nombre | $valor$sufijo |"
}

function Bloque([string]$titulo, $archivo, $proyectoM, $smells) {
    $l = @("**$titulo** (SonarQube, $(Get-Date -Format 'yyyy-MM-dd HH:mm'))", '',
           '| Métrica | Valor |', '|---|---|',
           (Fila 'Complejidad ciclomática de `ServicioCalculoEnvio.java` (único método: `calcularCosto`)' $archivo['complexity']),
           (Fila 'Complejidad cognitiva de `ServicioCalculoEnvio.java`' $archivo['cognitive_complexity']),
           (Fila 'Cobertura de líneas de `ServicioCalculoEnvio`' $archivo['line_coverage'] ' %'),
           (Fila 'Cobertura de ramas de `ServicioCalculoEnvio`' $archivo['branch_coverage'] ' %'),
           (Fila 'Cobertura total del proyecto' $proyectoM['coverage'] ' %'),
           (Fila 'Complejidad ciclomática total del proyecto' $proyectoM['complexity']),
           (Fila 'Code smells del proyecto' $(if ($proyectoM.ContainsKey('code_smells')) { $proyectoM['code_smells'] } else { $proyectoM['software_quality_maintainability_issues'] })),
           (Fila 'Líneas duplicadas' $proyectoM['duplicated_lines_density'] ' %'), '')
    if ($smells.Count -gt 0) {
        $l += 'Code smells reportados:'; $l += ''
        foreach ($s in $smells) { $l += "- ``$($s.rule)`` en ``$(($s.component -split ':')[-1])`` línea $($s.line): $($s.message)" }
    } else { $l += 'Sin code smells reportados.' }
    return ($l -join "`r`n")
}

function Reemplazar([string]$texto, [string]$marca, [string]$contenido) {
    $patron = "(?s)<!-- ${marca}:inicio -->.*?<!-- ${marca}:fin -->"
    $nuevo = "<!-- ${marca}:inicio -->`r`n$contenido`r`n<!-- ${marca}:fin -->"
    return [regex]::Replace($texto, $patron, [System.Text.RegularExpressions.MatchEvaluator] { param($m) $nuevo })
}

# ---------------------------------------------------------------- 2. Analisis inicial
Write-Host '=== 2/5 Analisis de la version inicial (tag parte1-inicial) ==='
$wt = Join-Path $PSScriptRoot '.analisis-inicial'
git worktree remove --force $wt *> $null
git worktree add --force --detach $wt parte1-inicial | Out-Null
if (-not (Test-Path (Join-Path $wt 'pom.xml'))) { Fallar 'No se pudo preparar la version inicial (git worktree).' }
$dirInicial = Analizar (Join-Path $wt 'pom.xml') '1.0-inicial'
$mInicialArchivo = Medidas $archivoServicio
$mInicialProyecto = Medidas $proyecto
$smellsInicial = Smells
$gateInicial = (Api Get "/api/qualitygates/project_status?projectKey=$(Codificar $proyecto)").projectStatus.status
Captura "$sonar/dashboard?id=$(Codificar $proyecto)" (Join-Path $docs 'sonar-dashboard-inicial.png')
Captura "$sonar/component_measures?id=$(Codificar $proyecto)&metric=complexity&view=list" (Join-Path $docs 'sonar-complejidad-inicial.png')
Captura (UrlArchivo (Join-Path $dirInicial 'target\site\jacoco\com.universidad.enviosservice.service\ServicioCalculoEnvio.html')) (Join-Path $docs 'jacoco-inicial.png') 1300 220
Captura (UrlArchivo (Join-Path $dirInicial 'target\site\jacoco\com.universidad.enviosservice.service\ServicioCalculoEnvio.java.html')) (Join-Path $docs 'jacoco-inicial-ramas.png') 1300 1200
git worktree remove --force $wt *> $null

# ---------------------------------------------------------------- 3. Perfil y Quality Gate
Write-Host "=== 3/5 Quality Profile y Quality Gate '$nombreEstandar' ==="
$perfiles = (Api Get '/api/qualityprofiles/search?language=java').profiles
$perfil = $perfiles | Where-Object { $_.name -eq $nombreEstandar } | Select-Object -First 1
if (-not $perfil) {
    $base = $perfiles | Where-Object { $_.name -eq 'Sonar way' } | Select-Object -First 1
    $perfil = Api Post '/api/qualityprofiles/copy' @{ fromKey = $base.key; toName = $nombreEstandar }
}
Api Post '/api/qualityprofiles/activate_rule' @{ key = $perfil.key; rule = 'java:S1541'; params = 'Threshold=10' } | Out-Null
Api Post '/api/qualityprofiles/add_project' @{ language = 'java'; qualityProfile = $nombreEstandar; project = $proyecto } | Out-Null

$gates = (Api Get '/api/qualitygates/list').qualitygates
if (-not ($gates | Where-Object { $_.name -eq $nombreEstandar })) {
    Api Post '/api/qualitygates/create' @{ name = $nombreEstandar } | Out-Null
    Api Post '/api/qualitygates/create_condition' @{ gateName = $nombreEstandar; metric = 'coverage'; op = 'LT'; error = '70' } | Out-Null
    try {
        Api Post '/api/qualitygates/create_condition' @{ gateName = $nombreEstandar; metric = 'new_code_smells'; op = 'GT'; error = '0' } | Out-Null
    } catch {
        # Servidores en modo MQR: los code smells se cuentan como problemas de mantenibilidad
        Api Post '/api/qualitygates/create_condition' @{ gateName = $nombreEstandar; metric = 'new_software_quality_maintainability_issues'; op = 'GT'; error = '0' } | Out-Null
    }
    Api Post '/api/qualitygates/create_condition' @{ gateName = $nombreEstandar; metric = 'duplicated_lines_density'; op = 'GT'; error = '5' } | Out-Null
}
Api Post '/api/qualitygates/select' @{ gateName = $nombreEstandar; projectKey = $proyecto } | Out-Null

# ---------------------------------------------------------------- 4. Analisis final
Write-Host '=== 4/5 Analisis de la version actual (refactorizada) ==='
$dirFinal = Analizar (Join-Path $PSScriptRoot 'pom.xml') '2.0-strategy'
$mFinalArchivo = Medidas $archivoServicio
$mFinalProyecto = Medidas $proyecto
$smellsFinal = Smells
$gate = (Api Get "/api/qualitygates/project_status?projectKey=$(Codificar $proyecto)").projectStatus
Captura "$sonar/dashboard?id=$(Codificar $proyecto)" (Join-Path $docs 'sonar-dashboard-final.png')
Captura "$sonar/component_measures?id=$(Codificar $proyecto)&metric=complexity&view=list" (Join-Path $docs 'sonar-complejidad-final.png')
Captura (UrlArchivo (Join-Path $dirFinal 'target\site\jacoco\index.html')) (Join-Path $docs 'jacoco-final.png') 1300 220
Captura (UrlArchivo (Join-Path $dirFinal 'target\site\jacoco\com.universidad.enviosservice.estrategia\index.html')) (Join-Path $docs 'jacoco-final-estrategias.png') 1300 260

# ---------------------------------------------------------------- 5. Documentacion
Write-Host '=== 5/5 Escribiendo metricas en README.md y docs\metricas-sonar.md ==='
$bInicial = Bloque 'Análisis inicial (tag parte1-inicial)' $mInicialArchivo $mInicialProyecto $smellsInicial
$bInicial += "`r`n`r`nQuality Gate en ese análisis (Sonar way por defecto): **$gateInicial**`r`n`r`n![Dashboard inicial](docs/sonar-dashboard-inicial.png)`r`n![Complejidad inicial](docs/sonar-complejidad-inicial.png)"
$bFinal = Bloque 'Análisis final (versión con Strategy)' $mFinalArchivo $mFinalProyecto $smellsFinal
$condiciones = @('', "Quality Gate **$nombreEstandar**: **$($gate.status)**", '', '| Condición | Valor real | Umbral | Estado |', '|---|---|---|---|')
foreach ($c in $gate.conditions) { $condiciones += "| $($c.metricKey) ($($c.comparator)) | $($c.actualValue) | $($c.errorThreshold) | $($c.status) |" }
$bFinal += "`r`n" + ($condiciones -join "`r`n") + "`r`n`r`n![Dashboard final](docs/sonar-dashboard-final.png)`r`n![Complejidad final](docs/sonar-complejidad-final.png)"

$fmt = { param($v, $s) if ($null -eq $v -or "$v" -eq '') { 'n/d' } else { "$v$s" } }
$smellsI = if ($mInicialProyecto.ContainsKey('code_smells')) { $mInicialProyecto['code_smells'] } else { $mInicialProyecto['software_quality_maintainability_issues'] }
$smellsF = if ($mFinalProyecto.ContainsKey('code_smells')) { $mFinalProyecto['code_smells'] } else { $mFinalProyecto['software_quality_maintainability_issues'] }
$comparacion = @('| Métrica (SonarQube) | Antes (Parte 1) | Después (Parte 2) |', '|---|---|---|',
    "| Complejidad ciclomática de ``calcularCosto()`` | $(& $fmt $mInicialArchivo['complexity'] '') | $(& $fmt $mFinalArchivo['complexity'] '') |",
    "| Complejidad cognitiva de ``calcularCosto()`` | $(& $fmt $mInicialArchivo['cognitive_complexity'] '') | $(& $fmt $mFinalArchivo['cognitive_complexity'] '') |",
    "| Cobertura de ramas de ``ServicioCalculoEnvio`` | $(& $fmt $mInicialArchivo['branch_coverage'] ' %') | $(& $fmt $mFinalArchivo['branch_coverage'] ' %') |",
    "| Cobertura total del proyecto | $(& $fmt $mInicialProyecto['coverage'] ' %') | $(& $fmt $mFinalProyecto['coverage'] ' %') |",
    "| Code smells | $(& $fmt $smellsI '') | $(& $fmt $smellsF '') |",
    "| Quality Gate | $gateInicial (Sonar way) | $($gate.status) ($nombreEstandar) |") -join "`r`n"

$readme = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'README.md'), [System.Text.Encoding]::UTF8)
$readme = Reemplazar $readme 'sonar-inicial' $bInicial
$readme = Reemplazar $readme 'sonar-final' $bFinal
$readme = Reemplazar $readme 'sonar-comparacion' $comparacion
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'README.md'), $readme, $utf8)
[System.IO.File]::WriteAllText((Join-Path $docs 'metricas-sonar.md'), "# Métricas de SonarQube`r`n`r`n$bInicial`r`n`r`n---`r`n`r`n$bFinal`r`n`r`n## Comparación`r`n`r`n$comparacion`r`n", $utf8)
Write-Host ''
Write-Host "Listo. Quality Gate final: $($gate.status). Dashboard: $sonar/dashboard?id=$(Codificar $proyecto)"

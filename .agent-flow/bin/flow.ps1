[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$CommandArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$FlowDirectory = [System.IO.Path]::GetFullPath((Join-Path $ScriptDirectory ".."))
$RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $FlowDirectory ".."))
$ConfigFile = Join-Path $FlowDirectory "config.env"

function Stop-Flow {
    param([Parameter(Mandatory = $true)][string]$Message)

    [Console]::Error.WriteLine("ошибка: $Message")
    exit 1
}

function Get-NativeLines {
    param([object[]]$Values)

    return @($Values | ForEach-Object { $_.ToString() })
}

$GitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $GitCommand) {
    $GitRootOutput = @(& git -C $FlowDirectory rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -eq 0 -and $GitRootOutput.Count -gt 0) {
        $GitRoot = ((Get-NativeLines $GitRootOutput) -join "`n").Trim()
        if (-not [string]::IsNullOrWhiteSpace($GitRoot)) {
            $RepositoryRoot = [System.IO.Path]::GetFullPath($GitRoot)
        }
    }
}

function Invoke-FlowGit {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
        if ($AllowFailure) {
            return [PSCustomObject]@{ ExitCode = 1; Lines = @("git не найден") }
        }
        Stop-Flow "git не найден в PATH"
    }

    $Output = @(& git -C $RepositoryRoot @Arguments 2>&1)
    $ExitCode = $LASTEXITCODE
    [string[]]$Lines = @(Get-NativeLines $Output)

    if ($ExitCode -ne 0 -and -not $AllowFailure) {
        Stop-Flow (($Lines -join "`n").Trim())
    }

    return [PSCustomObject]@{ ExitCode = $ExitCode; Lines = $Lines }
}

function Get-FlowConfigValue {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$DefaultValue
    )

    $EnvironmentValue = [Environment]::GetEnvironmentVariable($Name)
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentValue)) {
        return $EnvironmentValue.Trim()
    }

    if (Test-Path -LiteralPath $ConfigFile -PathType Leaf) {
        $Pattern = "^\s*" + [regex]::Escape($Name) + "\s*=\s*(.*?)\s*$"
        foreach ($Line in [System.IO.File]::ReadAllLines($ConfigFile)) {
            $Match = [regex]::Match($Line, $Pattern)
            if (-not $Match.Success) {
                continue
            }

            $Value = $Match.Groups[1].Value.Trim()
            if (($Value.StartsWith('"') -and $Value.EndsWith('"')) -or
                ($Value.StartsWith("'") -and $Value.EndsWith("'"))) {
                $Value = $Value.Substring(1, $Value.Length - 2)
            }

            # Поддержка config.env из версии 2: ${NAME:-value}.
            $LegacyMatch = [regex]::Match($Value, '^\$\{[A-Z0-9_]+:-([^}]*)\}$')
            if ($LegacyMatch.Success) {
                return $LegacyMatch.Groups[1].Value
            }
            return $Value
        }
    }

    return $DefaultValue
}

function Assert-NonNegativeInteger {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if ($Value -notmatch '^[0-9]+$') {
        Stop-Flow "$Name должен быть целым неотрицательным числом, получено: $Value"
    }
}

$SliceBudget = Get-FlowConfigValue "AGENT_FLOW_SLICE_BUDGET" "300"
$PrBudget = Get-FlowConfigValue "AGENT_FLOW_PR_BUDGET" "1800"
$FileBudget = Get-FlowConfigValue "AGENT_FLOW_PRODUCTION_FILE_BUDGET" "5"
$DefaultDiff = Get-FlowConfigValue "AGENT_FLOW_DEFAULT_DIFF" "HEAD"

function Show-Usage {
    @(
        "Использование: .\.agent-flow\bin\flow.ps1 <команда> [аргументы]",
        "",
        "Команды:",
        "  setup-local        Локально исключить flow-файлы через .git/info/exclude",
        "  new <slug>         Создать task-папку из шаблонов",
        "  status             Показать состояния задач",
        "  budget [git-range] Классифицировать и посчитать изменённые строки (по умолчанию HEAD)",
        "  budget-task [base] Информационный размер всей задачи/PR",
        "  validate           Проверить файлы flow, состояния и обязательные gates",
        "  help               Показать эту справку"
    ) | ForEach-Object { Write-Output $_ }
}

function Invoke-SetupLocal {
    $GitRepository = Invoke-FlowGit -Arguments @("rev-parse", "--git-dir") -AllowFailure
    if ($GitRepository.ExitCode -ne 0) {
        Stop-Flow "setup-local требует Git-репозиторий"
    }

    $ExcludeResult = Invoke-FlowGit -Arguments @("rev-parse", "--git-path", "info/exclude")
    $ExcludePath = ($ExcludeResult.Lines -join "`n").Trim()
    if (-not [System.IO.Path]::IsPathRooted($ExcludePath)) {
        $ExcludePath = Join-Path $RepositoryRoot $ExcludePath
    }
    $ExcludePath = [System.IO.Path]::GetFullPath($ExcludePath)

    $ExcludeDirectory = Split-Path -Parent $ExcludePath
    if (-not (Test-Path -LiteralPath $ExcludeDirectory -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $ExcludeDirectory -Force)
    }
    if (-not (Test-Path -LiteralPath $ExcludePath -PathType Leaf)) {
        [System.IO.File]::WriteAllText($ExcludePath, "", $Utf8NoBom)
    }

    $Existing = @([System.IO.File]::ReadAllLines($ExcludePath))
    $ToAppend = New-Object System.Collections.Generic.List[string]
    $Header = "# Agent Context Flow: local-only files"
    if ($Existing -notcontains $Header) {
        if ($Existing.Count -gt 0 -and $Existing[$Existing.Count - 1] -ne "") {
            $ToAppend.Add("")
        }
        $ToAppend.Add($Header)
    }
    foreach ($Rule in @("/AGENTS.md", "/.agent-flow/")) {
        if ($Existing -notcontains $Rule) {
            $ToAppend.Add($Rule)
        }
    }
    if ($ToAppend.Count -gt 0) {
        [System.IO.File]::AppendAllLines($ExcludePath, $ToAppend.ToArray(), $Utf8NoBom)
    }

    Write-Output "Flow-файлы локально исключены через $ExcludePath"

    $TrackedResult = Invoke-FlowGit -Arguments @("ls-files", "--", "AGENTS.md", ".agent-flow")
    if ($TrackedResult.Lines.Count -gt 0) {
        [Console]::Error.WriteLine("ПРЕДУПРЕЖДЕНИЕ: некоторые flow-файлы уже находятся в Git index:")
        foreach ($Line in $TrackedResult.Lines) {
            [Console]::Error.WriteLine($Line)
        }
        [Console]::Error.WriteLine("Index не был изменён автоматически.")
        [Console]::Error.WriteLine("После проверки их можно удалить только из index командой:")
        [Console]::Error.WriteLine("  git rm -r --cached -- AGENTS.md .agent-flow")
    }
}

function New-FlowTask {
    param([string[]]$Arguments = @())

    if ($Arguments.Count -ne 1) {
        Stop-Flow "new ожидает один короткий slug, например: add-payment-retry"
    }

    $Slug = $Arguments[0].ToLowerInvariant().Replace('_', '-')
    $Slug = $Slug -replace '[^a-z0-9-]', ''
    $Slug = $Slug -replace '-+', '-'
    $Slug = $Slug.Trim('-')
    if ([string]::IsNullOrWhiteSpace($Slug)) {
        Stop-Flow "slug должен содержать латинские буквы или цифры"
    }

    $Now = [DateTime]::UtcNow
    $CreatedAt = $Now.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $TaskId = $Now.ToString("yyyyMMdd-HHmmss") + "-" + $Slug
    $Destination = Join-Path (Join-Path $FlowDirectory "tasks") $TaskId
    if (Test-Path -LiteralPath $Destination) {
        Stop-Flow "задача уже существует: $Destination"
    }

    [void](New-Item -ItemType Directory -Path (Join-Path $Destination "decisions") -Force)
    $TemplateDirectory = Join-Path (Join-Path $FlowDirectory "templates") "task"
    foreach ($Template in Get-ChildItem -LiteralPath $TemplateDirectory -Filter "*.md" -File | Sort-Object Name) {
        $Target = Join-Path $Destination $Template.Name
        $Content = [System.IO.File]::ReadAllText($Template.FullName)
        $Content = $Content.Replace("__TASK_ID__", $TaskId).Replace("__CREATED_AT__", $CreatedAt)
        [System.IO.File]::WriteAllText($Target, $Content, $Utf8NoBom)
    }

    Write-Output "Создано: $Destination"
    Write-Output "Далее: заполнить $Destination\brief.md и следовать WORKFLOW.md"
}

function Show-FlowStatus {
    $TasksDirectory = Join-Path $FlowDirectory "tasks"
    $Found = $false
    if (Test-Path -LiteralPath $TasksDirectory -PathType Container) {
        foreach ($TaskDirectory in Get-ChildItem -LiteralPath $TasksDirectory -Directory | Sort-Object Name) {
            $Brief = Join-Path $TaskDirectory.FullName "brief.md"
            if (-not (Test-Path -LiteralPath $Brief -PathType Leaf)) {
                continue
            }

            $Found = $true
            $State = "UNKNOWN"
            foreach ($Line in [System.IO.File]::ReadAllLines($Brief)) {
                if ($Line -match '^- (?:Состояние|State): `([^`]*)`') {
                    $State = $Matches[1]
                    break
                }
            }
            Write-Output ("{0,-48} {1}" -f $TaskDirectory.Name, $State)
        }
    }

    if (-not $Found) {
        Write-Output "Записи задач не найдены."
    }
}

function Test-IsBinaryFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Stream = [System.IO.File]::OpenRead($Path)
    try {
        $Buffer = New-Object byte[] 8192
        while (($Read = $Stream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
            for ($Index = 0; $Index -lt $Read; $Index++) {
                if ($Buffer[$Index] -eq 0) {
                    return $true
                }
            }
        }
        return $false
    }
    finally {
        $Stream.Dispose()
    }
}

function Get-TextLineCount {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ((Get-Item -LiteralPath $Path).Length -eq 0 -or (Test-IsBinaryFile $Path)) {
        return 0
    }

    $Count = 0L
    try {
        foreach ($Unused in [System.IO.File]::ReadLines($Path)) {
            $Count++
        }
        return $Count
    }
    catch {
        return 0
    }
}

function Test-IsTestPath {
    param([string]$Path)

    return $Path -match '(^|/)(test|tests|spec|specs|__tests__|fixtures)(/|$)' -or
        $Path -match '(_test|\.test|\.spec)\.[^./]+$'
}

function Test-IsGeneratedPath {
    param([string]$Path)

    return $Path -match '(^|/)(generated|dist|build|vendor)(/|$)' -or
        $Path -match '(^|/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.sum|Cargo\.lock)$'
}

# Read NUL-separated Git output without PowerShell's line splitting. Compatible
# with Windows PowerShell 5.1 (ProcessStartInfo.ArgumentList is not available).
function Invoke-FlowGitRaw {
    param([string[]]$Arguments)
    $Info = New-Object System.Diagnostics.ProcessStartInfo
    $Info.FileName = (Get-Command git -ErrorAction Stop).Source
    $Quoted = foreach ($Value in (@('-C', $RepositoryRoot) + $Arguments)) {
        '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
    }
    $Info.Arguments = $Quoted -join ' '
    $Info.UseShellExecute = $false
    $Info.RedirectStandardOutput = $true
    $Info.RedirectStandardError = $true
    $Info.StandardOutputEncoding = $Utf8NoBom
    $Info.StandardErrorEncoding = $Utf8NoBom
    $Info.CreateNoWindow = $true
    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $Info
    try {
        [void]$Process.Start()
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $Process.WaitForExit()
        $OutputText = $OutputTask.GetAwaiter().GetResult()
        $ErrorText = $ErrorTask.GetAwaiter().GetResult()
        if ($Process.ExitCode -ne 0) { Stop-Flow $ErrorText }
        return $OutputText
    }
    finally { $Process.Dispose() }
}

function Get-TreeSignature {
    param([string]$Revision, [string]$Path)
    $Entry = Invoke-FlowGitRaw @('--literal-pathspecs', 'ls-tree', '-z', $Revision, '--', $Path)
    if ([string]::IsNullOrEmpty($Entry)) { return '' }
    return ($Entry -split "`t", 2)[0]
}

function Show-FlowBudget {
    param([string[]]$Arguments = @(), [switch]$TaskReport)
    if ($Arguments.Count -gt 1) { Stop-Flow 'budget принимает не более одного Git-диапазона' }
    Assert-NonNegativeInteger 'AGENT_FLOW_SLICE_BUDGET' $SliceBudget
    Assert-NonNegativeInteger 'AGENT_FLOW_PR_BUDGET' $PrBudget
    Assert-NonNegativeInteger 'AGENT_FLOW_PRODUCTION_FILE_BUDGET' $FileBudget
    $DiffRange = if ($Arguments.Count -eq 1) { $Arguments[0] } else { $DefaultDiff }
    if ([string]::IsNullOrWhiteSpace($DiffRange)) { $DiffRange = $DefaultDiff }
    if ($DiffRange.StartsWith('-', [StringComparison]::Ordinal)) {
        Stop-Flow 'git-range не может начинаться с дефиса'
    }
    $Base = $DiffRange
    $Target = ''
    if ($DiffRange.Contains('...')) {
        $Parts = $DiffRange -split '\.\.\.', 2
        $Left = if ($Parts[0]) { $Parts[0] } else { 'HEAD' }
        $Target = if ($Parts[1]) { $Parts[1] } else { 'HEAD' }
        $Base = (Invoke-FlowGitRaw @('merge-base', $Left, $Target)).Trim()
    }
    elseif ($DiffRange.Contains('..')) {
        $Parts = $DiffRange -split '\.\.', 2
        $Base = if ($Parts[0]) { $Parts[0] } else { 'HEAD' }
        $Target = if ($Parts[1]) { $Parts[1] } else { 'HEAD' }
    }
    $Base = (Invoke-FlowGitRaw @('rev-parse', '--verify', "$Base^{commit}")).Trim()
    $DiffArguments = @('diff', '--no-ext-diff', '--no-textconv', '--no-renames', '--numstat', '-z', $Base)
    if ($Target) { $DiffArguments += $Target }
    $DiffArguments += @('--', '.')
    $DiffText = Invoke-FlowGitRaw $DiffArguments
    $Records = New-Object System.Collections.Generic.List[object]
    foreach ($Entry in $DiffText.Split([char]0)) {
        if ($Entry.Length -eq 0) { continue }
        $Parts = $Entry -split "`t", 3
        if ($Parts.Count -ne 3) { Stop-Flow 'неожиданный формат git numstat' }
        $Records.Add([PSCustomObject]@{
            Additions = $Parts[0]; Deletions = $Parts[1]; Path = $Parts[2]
            Old = ''; Current = ''; Paired = $false
        })
    }
    if (-not $Target) {
        $UntrackedText = Invoke-FlowGitRaw @('ls-files', '--others', '--exclude-standard', '-z')
        foreach ($Path in $UntrackedText.Split([char]0)) {
            if ($Path.Length -eq 0) { continue }
            $Absolute = Join-Path $RepositoryRoot $Path
            $Item = Get-Item -LiteralPath $Absolute -Force -ErrorAction SilentlyContinue
            if ($null -eq $Item -or $Item.PSIsContainer) { continue }
            $IsLink = ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
            $Lines = if ($IsLink -or (Test-IsBinaryFile $Absolute)) { '-' } else { (Get-TextLineCount $Absolute).ToString() }
            $Records.Add([PSCustomObject]@{
                Additions = $Lines; Deletions = '0'; Path = $Path
                Old = ''; Current = ''; Paired = $false
            })
        }
    }
    $FileModeResult = Invoke-FlowGit -Arguments @('config', '--get', 'core.filemode') -AllowFailure
    $FileMode = ($FileModeResult.Lines -join '').Trim()
    foreach ($Record in $Records) {
        $Record.Old = Get-TreeSignature $Base $Record.Path
        if ($Target) {
            $Record.Current = Get-TreeSignature $Target $Record.Path
            continue
        }
        $Absolute = Join-Path $RepositoryRoot $Record.Path
        $Item = Get-Item -LiteralPath $Absolute -Force -ErrorAction SilentlyContinue
        if ($null -eq $Item) { continue }
        if ($Item.PSIsContainer -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            $Record.Current = 'special'
            continue
        }
        $Hash = (Invoke-FlowGitRaw @('hash-object', '--no-filters', '--', $Absolute)).Trim()
        $FilePermissions = '100644'
        if ($FileMode -ne 'false') {
            # On Windows filemode is normally false. Unix PowerShell exposes
            # UnixStat.Mode; if unavailable, be conservative about move pairing.
            if ($Item.PSObject.Properties['UnixStat']) {
                if (($Item.UnixStat.Mode -band 73) -ne 0) { $FilePermissions = '100755' }
            }
            else { $FilePermissions = 'unknown' }
        }
        $Record.Current = "$FilePermissions blob $Hash"
    }
    $Moves = 0
    foreach ($Deleted in $Records) {
        if ($Deleted.Current -or $Deleted.Old -notmatch '^100[0-9]{3} blob ') { continue }
        foreach ($Added in $Records) {
            if (-not $Added.Paired -and -not $Added.Old -and $Added.Current -ceq $Deleted.Old) {
                $Deleted.Paired = $true
                $Added.Paired = $true
                $Moves++
                Write-Output ('Чистый перенос: {0} -> {1}' -f ($Deleted.Path | ConvertTo-Json -Compress), ($Added.Path | ConvertTo-Json -Compress))
                break
            }
        }
    }
    $Counters = @{
        Production = 0L; ProductionFiles = 0L; Tests = 0L; TestFiles = 0L
        Generated = 0L; GeneratedFiles = 0L; Workflow = 0L; WorkflowFiles = 0L
    }
    $Binaries = 0
    foreach ($Record in $Records) {
        if ($Record.Paired) { continue }
        if ($Record.Additions -eq '-' -or $Record.Deletions -eq '-') { $Binaries++ }
        $Additions = if ($Record.Additions -eq '-') { 0L } else { [int64]$Record.Additions }
        $Deletions = if ($Record.Deletions -eq '-') { 0L } else { [int64]$Record.Deletions }
        $Changed = $Additions + $Deletions
        $Path = $Record.Path
        if ($Path -cmatch '^\.agent-flow/' -or $Path -ceq 'AGENTS.md') {
            $Counters.Workflow += $Changed; $Counters.WorkflowFiles++
        }
        elseif (Test-IsGeneratedPath $Path) {
            $Counters.Generated += $Changed; $Counters.GeneratedFiles++
        }
        elseif (Test-IsTestPath $Path) {
            $Counters.Tests += $Changed; $Counters.TestFiles++
        }
        else { $Counters.Production += $Changed; $Counters.ProductionFiles++ }
    }
    Write-Output ('Production-код: {0} строк в {1} файлах' -f $Counters.Production, $Counters.ProductionFiles)
    Write-Output ('Тесты:          {0} строк в {1} файлах' -f $Counters.Tests, $Counters.TestFiles)
    Write-Output ('Сгенерированное: {0} строк в {1} файлах' -f $Counters.Generated, $Counters.GeneratedFiles)
    Write-Output ('Документы flow:  {0} строк в {1} файлах' -f $Counters.Workflow, $Counters.WorkflowFiles)
    Write-Output ('Чистые переносы: {0} (вне LOC и лимита файлов; требуется ревью путей)' -f $Moves)
    Write-Output ('Бинарные/нетекстовые изменения: {0} (LOC не измерен)' -f $Binaries)
    if ($TaskReport) {
        Write-Output ('Ориентир задачи/PR: {0} строк production-кода' -f $PrBudget)
        if ($Counters.Production -gt [int64]$PrBudget) {
            Write-Output 'ИНФОРМАЦИЯ: превышен ориентир задачи/PR; лимиты slice здесь не применяются'
        }
        Write-Output 'РЕЗУЛЬТАТ: информационный отчёт задачи; бюджет slice проверяется отдельно'
    }
    else {
        Write-Output ('Бюджет этапа: {0} строк / {1} production-файлов' -f $SliceBudget, $FileBudget)
        if ($Counters.Production -gt [int64]$SliceBudget -or $Counters.ProductionFiles -gt [int64]$FileBudget) {
            Write-Output 'РЕЗУЛЬТАТ: превышен бюджет этапа; остановитесь для решения человека'
            exit 2
        }
        Write-Output 'РЕЗУЛЬТАТ: изменение укладывается в стандартный бюджет этапа'
    }
}

function Test-NonEmptyFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Test-Path -LiteralPath $Path -PathType Leaf) -and
        (Get-Item -LiteralPath $Path).Length -gt 0
}

function Get-TaskState {
    param([Parameter(Mandatory = $true)][string]$Path)

    foreach ($Line in [System.IO.File]::ReadAllLines($Path)) {
        if ($Line -match '^- (?:Состояние|State): `([^`]*)`') {
            return $Matches[1]
        }
    }
    return ""
}

function Test-IsValidTaskState {
    param([string]$State)

    if ($State -in @(
        "INTAKE", "DISCOVERY", "WAIT_PLAN_APPROVAL", "WAIT_SLICE_APPROVAL",
        "VERIFYING", "WAIT_FINAL_HUMAN_REVIEW", "CONTEXT_HANDOFF", "BLOCKED",
        "DONE", "ABANDONED"
    )) {
        return $true
    }
    return $State -match '^IMPLEMENTING_SLICE_[1-9][0-9]*$'
}

function Get-MarkdownField {
    param([string]$Path, [string]$Name)
    if (-not (Test-NonEmptyFile $Path)) { return '' }
    $Prefix = '- ' + $Name + ':'
    $Lines = @([IO.File]::ReadAllLines($Path) | Where-Object { $_.StartsWith($Prefix, [StringComparison]::Ordinal) })
    if ($Lines.Count -ne 1) { return '' }
    $Pattern = '^' + [regex]::Escape($Prefix) + ' `([^`]*)`[ \t]*$'
    $Match = [regex]::Match($Lines[0], $Pattern)
    if (-not $Match.Success) { return '' }
    return $Match.Groups[1].Value
}

function Test-FilledField {
    param([string]$Path, [string]$Name)
    $Value = Get-MarkdownField $Path $Name
    return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -cnotin @(
        'NOT_APPROVED', 'NOT_REVIEWED', 'UNKNOWN', 'НЕИЗВЕСТНО', 'НЕТ', 'NONE', 'N/A', 'REJECTED'
    )
}

function Test-ChecksComplete {
    param([string]$Path)
    $Status = Get-MarkdownField $Path 'Обязательные проверки'
    return $Status -ceq 'PASSED' -or ($Status -ceq 'APPROVED_EXCEPTION' -and
        (Test-FilledField $Path 'Исключение по проверкам'))
}

function Test-HandoffComplete {
    param([string]$Path, [string]$Brief)
    if ((Get-MarkdownField $Path 'Результат') -cne 'IMPLEMENTED' -or
        (Get-MarkdownField $Path 'Краткое резюме передано') -cne 'ДА') { return $false }
    $Risk = Get-MarkdownField $Path 'Режим задачи'
    if ($Risk -cnotin @('QUICK', 'GUIDED', 'MECHANICAL', 'CRITICAL') -or
        $Risk -cne (Get-MarkdownField $Brief 'Режим риска')) { return $false }
    $Choice = Get-MarkdownField $Path 'Выбор человека'
    if ($Choice -ceq 'РАЗОБРАТЬ_ПОТОК') {
        if ((Get-MarkdownField $Path 'Разбор потока проведён') -cne 'ДА') { return $false }
    }
    elseif ($Choice -ceq 'РАЗОБРАТЬ_ДИАГНОСТИКУ') {
        if ((Get-MarkdownField $Path 'Разбор диагностики и отката проведён') -cne 'ДА') { return $false }
    }
    elseif ($Choice -cne 'КОНТЕКСТА_ДОСТАТОЧНО') { return $false }
    return $Risk -cne 'CRITICAL' -or (Get-MarkdownField $Path 'Разбор диагностики и отката проведён') -ceq 'ДА'
}

function Test-FlowStructure {
    $Required = @(
        (Join-Path $RepositoryRoot "AGENTS.md"),
        (Join-Path $FlowDirectory "README.md"),
        (Join-Path $FlowDirectory "PROJECT.md"),
        (Join-Path $FlowDirectory "POLICY.md"),
        (Join-Path $FlowDirectory "WORKFLOW.md"),
        (Join-Path $FlowDirectory "HUMAN_REVIEW.md"),
        (Join-Path $FlowDirectory "CONTEXT_HANDOFF.md"),
        (Join-Path $FlowDirectory "REFERENCES.md"),
        (Join-Path $FlowDirectory "config.env"),
        (Join-Path $ScriptDirectory "flow"),
        (Join-Path $ScriptDirectory "flow.ps1"),
        (Join-Path $FlowDirectory "prompts/bootstrap.md"),
        (Join-Path $FlowDirectory "prompts/debug.md"),
        (Join-Path $FlowDirectory "prompts/finalize.md"),
        (Join-Path $FlowDirectory "prompts/new-feature.md"),
        (Join-Path $FlowDirectory "prompts/resume.md"),
        (Join-Path $FlowDirectory "prompts/review-slice.md"),
        (Join-Path $FlowDirectory "tasks/README.md"),
        (Join-Path $FlowDirectory "templates/decision.md"),
        (Join-Path $FlowDirectory "templates/pr-description.md"),
        (Join-Path $FlowDirectory "templates/task/brief.md"),
        (Join-Path $FlowDirectory "templates/task/discovery.md"),
        (Join-Path $FlowDirectory "templates/task/final-review.md"),
        (Join-Path $FlowDirectory "templates/task/handoff.md"),
        (Join-Path $FlowDirectory "templates/task/plan.md"),
        (Join-Path $FlowDirectory "templates/task/progress.md")
    )

    $Issues = $false
    $Warnings = $false
    foreach ($Item in $Required) {
        if (-not (Test-NonEmptyFile $Item)) {
            [Console]::Error.WriteLine("ОТСУТСТВУЕТ $Item")
            $Issues = $true
        }
    }

    $TasksDirectory = Join-Path $FlowDirectory "tasks"
    if (Test-Path -LiteralPath $TasksDirectory -PathType Container) {
        foreach ($TaskDirectory in Get-ChildItem -LiteralPath $TasksDirectory -Directory) {
            foreach ($TaskFile in @("brief.md", "discovery.md", "plan.md", "progress.md", "handoff.md")) {
                $TaskPath = Join-Path $TaskDirectory.FullName $TaskFile
                if (-not (Test-NonEmptyFile $TaskPath)) {
                    [Console]::Error.WriteLine("ОТСУТСТВУЕТ $TaskPath")
                    $Issues = $true
                }
            }

            $FinalReview = Join-Path $TaskDirectory.FullName "final-review.md"
            if (-not (Test-NonEmptyFile $FinalReview)) {
                $LegacyReview = Join-Path $TaskDirectory.FullName "review.md"
                if (Test-NonEmptyFile $LegacyReview) {
                    [Console]::Error.WriteLine("УСТАРЕВШИЙ ФОРМАТ $LegacyReview (создайте final-review.md перед финальной приёмкой)")
                }
                else {
                    [Console]::Error.WriteLine("ОТСУТСТВУЕТ $FinalReview")
                    $Issues = $true
                }
            }

            $HasTemplateMarker = $false
            foreach ($MarkdownFile in Get-ChildItem -LiteralPath $TaskDirectory.FullName -Recurse -Filter "*.md" -File) {
                $MarkdownContent = [System.IO.File]::ReadAllText($MarkdownFile.FullName)
                if ($MarkdownContent.Contains("__TASK_ID__") -or
                    $MarkdownContent.Contains("__CREATED_AT__")) {
                    $HasTemplateMarker = $true
                    break
                }
            }
            if ($HasTemplateMarker) {
                [Console]::Error.WriteLine("НЕЗАМЕНЁННЫЙ МАРКЕР ШАБЛОНА $($TaskDirectory.FullName)")
                $Issues = $true
            }

            $Brief = Join-Path $TaskDirectory.FullName "brief.md"
            $Progress = Join-Path $TaskDirectory.FullName "progress.md"
            if (-not (Test-NonEmptyFile $Brief) -or -not (Test-NonEmptyFile $Progress)) {
                continue
            }

            $BriefState = Get-TaskState $Brief
            $ProgressState = Get-TaskState $Progress
            if (-not (Test-IsValidTaskState $BriefState)) {
                $ShownState = if ([string]::IsNullOrWhiteSpace($BriefState)) { "ОТСУТСТВУЕТ" } else { $BriefState }
                [Console]::Error.WriteLine("НЕДОПУСТИМОЕ СОСТОЯНИЕ ${Brief}: $ShownState")
                $Issues = $true
                continue
            }
            if (-not (Test-IsValidTaskState $ProgressState)) {
                $ShownState = if ([string]::IsNullOrWhiteSpace($ProgressState)) { "ОТСУТСТВУЕТ" } else { $ProgressState }
                [Console]::Error.WriteLine("НЕДОПУСТИМОЕ СОСТОЯНИЕ ${Progress}: $ShownState")
                $Issues = $true
                continue
            }
            if ($BriefState -ne $ProgressState) {
                [Console]::Error.WriteLine("РАССИНХРОНИЗАЦИЯ СОСТОЯНИЯ $($TaskDirectory.FullName): brief=$BriefState, progress=$ProgressState")
                $Issues = $true
            }

            $NeedsApprovedPlan = $BriefState -match '^IMPLEMENTING_SLICE_' -or
                $BriefState -in @(
                    "WAIT_SLICE_APPROVAL", "VERIFYING", "WAIT_FINAL_HUMAN_REVIEW",
                    "CONTEXT_HANDOFF", "DONE"
                )
            if ($NeedsApprovedPlan) {
                $Plan = Join-Path $TaskDirectory.FullName 'plan.md'
                if ((Get-MarkdownField $Plan 'Состояние') -cne 'APPROVED' -or
                    -not (Test-FilledField $Plan 'Согласовал') -or
                    (Get-MarkdownField $Plan 'Дата согласования') -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}($|T)') {
                    [Console]::Error.WriteLine("НЕ ПРИНЯТ ПЛАН $Plan")
                    $Issues = $true
                }
            }
            if ($BriefState -in @('WAIT_FINAL_HUMAN_REVIEW', 'CONTEXT_HANDOFF', 'DONE')) {
                if ((Get-MarkdownField $FinalReview 'Состояние') -cne 'READY') {
                    [Console]::Error.WriteLine("НЕ ГОТОВ ПАКЕТ ФИНАЛЬНОГО РЕВЬЮ $FinalReview")
                    $Issues = $true
                }
            }
            if ($BriefState -in @('CONTEXT_HANDOFF', 'DONE')) {
                if ((Get-MarkdownField $FinalReview 'Решение человека') -cne 'APPROVED') {
                    [Console]::Error.WriteLine("НЕ ПРИНЯТО ФИНАЛЬНОЕ РЕВЬЮ $FinalReview")
                    $Issues = $true
                }
                if (-not (Test-ChecksComplete $FinalReview)) {
                    [Console]::Error.WriteLine("НЕ ЗАВЕРШЕНЫ ОБЯЗАТЕЛЬНЫЕ ПРОВЕРКИ $FinalReview")
                    $Issues = $true
                }
            }
            if ($BriefState -eq 'DONE') {
                $Handoff = Join-Path $TaskDirectory.FullName 'handoff.md'
                if (-not (Test-HandoffComplete $Handoff $Brief)) {
                    [Console]::Error.WriteLine("НЕ ЗАВЕРШЕНА ПЕРЕДАЧА КОНТЕКСТА $Handoff")
                    $Issues = $true
                }
            }

        }
    }

    Assert-NonNegativeInteger "AGENT_FLOW_SLICE_BUDGET" $SliceBudget
    Assert-NonNegativeInteger "AGENT_FLOW_PR_BUDGET" $PrBudget
    Assert-NonNegativeInteger "AGENT_FLOW_PRODUCTION_FILE_BUDGET" $FileBudget

    $ProjectFile = Join-Path $FlowDirectory "PROJECT.md"
    if ((Test-NonEmptyFile $ProjectFile) -and
        ([System.IO.File]::ReadAllText($ProjectFile)).Contains('Статус: `NOT_INITIALIZED`')) {
        [Console]::Error.WriteLine("ПРЕДУПРЕЖДЕНИЕ: PROJECT.md ещё не инициализирован.")
        $Warnings = $true
    }

    if ($Issues) {
        exit 1
    }
    if ($Warnings) {
        Write-Output "Структура и состояния flow корректны; есть предупреждения."
    }
    else {
        Write-Output "Структура и состояния flow корректны."
    }
}

$RemainingArguments = @($CommandArguments)
switch ($Command.ToLowerInvariant()) {
    "setup-local" {
        if ($RemainingArguments.Count -ne 0) { Stop-Flow "setup-local не принимает аргументы" }
        Invoke-SetupLocal
    }
    "new" { New-FlowTask $RemainingArguments }
    "status" {
        if ($RemainingArguments.Count -ne 0) { Stop-Flow "status не принимает аргументы" }
        Show-FlowStatus
    }
    "budget" { Show-FlowBudget $RemainingArguments }
    "budget-task" { Show-FlowBudget -Arguments $RemainingArguments -TaskReport }
    "validate" {
        if ($RemainingArguments.Count -ne 0) { Stop-Flow "validate не принимает аргументы" }
        Test-FlowStructure
    }
    { $_ -in @("help", "-h", "--help") } { Show-Usage }
    default { Stop-Flow "неизвестная команда: $Command" }
}

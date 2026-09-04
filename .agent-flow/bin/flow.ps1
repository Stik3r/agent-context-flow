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
$PrBudget = Get-FlowConfigValue "AGENT_FLOW_PR_BUDGET" "600"
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

function Show-FlowBudget {
    param([string[]]$Arguments = @())

    if ($Arguments.Count -gt 1) {
        Stop-Flow "budget принимает не более одного Git-диапазона"
    }

    Assert-NonNegativeInteger "AGENT_FLOW_SLICE_BUDGET" $SliceBudget
    Assert-NonNegativeInteger "AGENT_FLOW_PR_BUDGET" $PrBudget
    Assert-NonNegativeInteger "AGENT_FLOW_PRODUCTION_FILE_BUDGET" $FileBudget

    $GitRepository = Invoke-FlowGit -Arguments @("rev-parse", "--git-dir") -AllowFailure
    if ($GitRepository.ExitCode -ne 0) {
        Stop-Flow "budget требует Git-репозиторий"
    }

    $DiffRange = if ($Arguments.Count -eq 1) { $Arguments[0] } else { $DefaultDiff }
    if ([string]::IsNullOrWhiteSpace($DiffRange)) {
        $DiffRange = $DefaultDiff
    }
    if ($DiffRange.StartsWith("-", [StringComparison]::Ordinal)) {
        Stop-Flow "git-range не может начинаться с дефиса"
    }
    $DiffResult = Invoke-FlowGit -Arguments @("diff", "--numstat", $DiffRange, "--", ".")
    $Records = New-Object System.Collections.Generic.List[object]

    foreach ($Line in $DiffResult.Lines) {
        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }
        $Parts = $Line -split "`t", 3
        if ($Parts.Count -eq 3) {
            $Records.Add([PSCustomObject]@{
                Additions = $Parts[0]
                Deletions = $Parts[1]
                Path = $Parts[2].Replace('\', '/')
            })
        }
    }

    $UntrackedResult = Invoke-FlowGit -Arguments @("-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard")
    foreach ($RelativePath in $UntrackedResult.Lines) {
        if ([string]::IsNullOrWhiteSpace($RelativePath)) {
            continue
        }
        $AbsolutePath = Join-Path $RepositoryRoot $RelativePath
        if (-not (Test-Path -LiteralPath $AbsolutePath -PathType Leaf)) {
            continue
        }
        $Records.Add([PSCustomObject]@{
            Additions = (Get-TextLineCount $AbsolutePath).ToString()
            Deletions = "0"
            Path = $RelativePath.Replace('\', '/')
        })
    }

    $Counters = @{
        Production = 0L; ProductionFiles = 0L
        Tests = 0L; TestFiles = 0L
        Generated = 0L; GeneratedFiles = 0L
        Workflow = 0L; WorkflowFiles = 0L
    }

    foreach ($Record in $Records) {
        $Additions = if ($Record.Additions -eq "-") { 0L } else { [int64]$Record.Additions }
        $Deletions = if ($Record.Deletions -eq "-") { 0L } else { [int64]$Record.Deletions }
        $Changed = $Additions + $Deletions
        $Path = $Record.Path

        if ($Path -match '^\.agent-flow/' -or $Path -eq "AGENTS.md") {
            $Counters.Workflow += $Changed
            $Counters.WorkflowFiles++
        }
        elseif (Test-IsGeneratedPath $Path) {
            $Counters.Generated += $Changed
            $Counters.GeneratedFiles++
        }
        elseif (Test-IsTestPath $Path) {
            $Counters.Tests += $Changed
            $Counters.TestFiles++
        }
        else {
            $Counters.Production += $Changed
            $Counters.ProductionFiles++
        }
    }

    Write-Output ("Production-код: {0} строк в {1} файлах" -f $Counters.Production, $Counters.ProductionFiles)
    Write-Output ("Тесты:          {0} строк в {1} файлах" -f $Counters.Tests, $Counters.TestFiles)
    Write-Output ("Сгенерированное: {0} строк в {1} файлах" -f $Counters.Generated, $Counters.GeneratedFiles)
    Write-Output ("Документы flow:  {0} строк в {1} файлах" -f $Counters.Workflow, $Counters.WorkflowFiles)
    Write-Output ("Бюджет этапа: {0} строк / {1} production-файлов" -f $SliceBudget, $FileBudget)
    Write-Output ("Бюджет PR:    {0} строк production-кода" -f $PrBudget)

    if ($Counters.Production -gt [int64]$PrBudget) {
        Write-Output "РЕЗУЛЬТАТ: превышен бюджет PR; разделите изменение или зафиксируйте согласованное исключение"
        exit 3
    }
    if ($Counters.Production -gt [int64]$SliceBudget -or
        $Counters.ProductionFiles -gt [int64]$FileBudget) {
        Write-Output "РЕЗУЛЬТАТ: превышен бюджет этапа; остановитесь для решения человека"
        exit 2
    }
    Write-Output "РЕЗУЛЬТАТ: изменение укладывается в стандартный бюджет этапа"
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
                $Plan = Join-Path $TaskDirectory.FullName "plan.md"
                if (Test-NonEmptyFile $Plan) {
                    $PlanContent = [System.IO.File]::ReadAllText($Plan)
                    if ($PlanContent.Contains('- Согласовал: `NOT_APPROVED`') -or
                        $PlanContent.Contains('- Состояние: `DRAFT`')) {
                        [Console]::Error.WriteLine("НЕ ПРИНЯТ ПЛАН $Plan")
                        $Issues = $true
                    }
                }
            }

            if ($BriefState -in @("WAIT_FINAL_HUMAN_REVIEW", "CONTEXT_HANDOFF", "DONE")) {
                if (-not (Test-NonEmptyFile $FinalReview)) {
                    [Console]::Error.WriteLine("НЕ ГОТОВ ПАКЕТ ФИНАЛЬНОГО РЕВЬЮ $FinalReview")
                    $Issues = $true
                }
                else {
                    $FinalReviewContent = [System.IO.File]::ReadAllText($FinalReview)
                    if ($FinalReviewContent.Contains('- Состояние: `NOT_READY`') -or
                        $FinalReviewContent.Contains('`НЕ_ПРОВЕРЕНО`')) {
                        [Console]::Error.WriteLine("НЕ ГОТОВ ПАКЕТ ФИНАЛЬНОГО РЕВЬЮ $FinalReview")
                        $Issues = $true
                    }
                }
            }

            if ($BriefState -in @("CONTEXT_HANDOFF", "DONE")) {
                if (Test-NonEmptyFile $FinalReview) {
                    $FinalReviewContent = [System.IO.File]::ReadAllText($FinalReview)
                    if ($FinalReviewContent.Contains('- Решение человека: `NOT_REVIEWED`')) {
                        [Console]::Error.WriteLine("НЕ ПРИНЯТО ФИНАЛЬНОЕ РЕВЬЮ $FinalReview")
                        $Issues = $true
                    }
                }
            }

            if ($BriefState -eq "DONE") {
                $Handoff = Join-Path $TaskDirectory.FullName "handoff.md"
                if (Test-NonEmptyFile $Handoff) {
                    $HandoffContent = [System.IO.File]::ReadAllText($Handoff)
                    if ($HandoffContent.Contains('`NOT_IMPLEMENTED`') -or
                        $HandoffContent.Contains('- Выбор человека: `НЕИЗВЕСТНО`')) {
                        [Console]::Error.WriteLine("НЕ ЗАВЕРШЕНА ПЕРЕДАЧА КОНТЕКСТА $Handoff")
                        $Issues = $true
                    }
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
    "validate" {
        if ($RemainingArguments.Count -ne 0) { Stop-Flow "validate не принимает аргументы" }
        Test-FlowStructure
    }
    { $_ -in @("help", "-h", "--help") } { Show-Usage }
    default { Stop-Flow "неизвестная команда: $Command" }
}

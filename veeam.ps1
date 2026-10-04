# Veeam Backup & Replication PowerShell セッションで実行する
# 例: Veeam Backup PowerShell を起動後に実行

$OutputDir = Join-Path $PWD "Output\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

$JobsCsv      = Join-Path $OutputDir 'Jobs.csv'
$ObjectsCsv   = Join-Path $OutputDir 'Objects.csv'
$OptionsCsv   = Join-Path $OutputDir 'Options.csv'
$ScheduleCsv  = Join-Path $OutputDir 'Schedule.csv'
$RawJson      = Join-Path $OutputDir 'RawJobDefinition.json'

$jobsRows     = [System.Collections.Generic.List[object]]::new()
$objectsRows  = [System.Collections.Generic.List[object]]::new()
$optionsRows  = [System.Collections.Generic.List[object]]::new()
$scheduleRows = [System.Collections.Generic.List[object]]::new()
$rawRows      = [System.Collections.Generic.List[object]]::new()

# 循環参照を持つ .NET オブジェクトを JSON 経由で PSObject に変換する
function ConvertTo-SerializableObject {
    param([object]$InputObject, [int]$Depth = 100)
    if ($null -eq $InputObject) { return $null }
    $json = $InputObject | ConvertTo-Json -Depth $Depth -Compress -WarningAction SilentlyContinue
    return $json | ConvertFrom-Json
}

function Add-ScalarProperties {
    param(
        [string]$JobName,
        [string]$Category,
        [object]$InputObject,
        [System.Collections.Generic.List[object]]$TargetList
    )

    if ($null -eq $InputObject) {
        return
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        $value = $property.Value

        # 複雑なネストは JSON として 1 セルに格納する。
        # CSV を壊さず、帳票上でも確認可能にする。
        if ($null -eq $value) {
            $textValue = $null
        }
        elseif (
            $value -is [string] -or
            $value -is [ValueType] -or
            $value -is [DateTime]
        ) {
            $textValue = [string]$value
        }
        else {
            $textValue = $value | ConvertTo-Json -Depth 100 -Compress -WarningAction SilentlyContinue
        }

        $TargetList.Add([pscustomobject]@{
            JobName      = $JobName
            Category     = $Category
            PropertyName = $property.Name
            Value        = $textValue
        })
    }
}

$allJobs = @(Get-VBRJob | Sort-Object Name)
Write-Host "処理開始: $($allJobs.Count) ジョブ" -ForegroundColor Cyan

foreach ($job in $allJobs) {
    Write-Host "  [$($jobsRows.Count + 1)/$($allJobs.Count)] $($job.Name)" -NoNewline

    $options  = $null
    $schedule = $null
    $objects  = @()

    try { $options = $job.GetOptions() } catch {}
    try { $schedule = $job.GetScheduleOptions() } catch {}
    try { $objects = @(Get-VBRJobObject -Job $job) } catch {}

    # 共通台帳。環境に存在しないプロパティでも空欄になる。
    $jobsRows.Add([pscustomobject]@{
        JobName          = $job.Name
        JobType          = $job.JobType
        IsEnabled        = $job.IsEnabled
        Description      = $job.Description
        Id               = $job.Id
        Repository       = $job.TargetRepository.Name
        ScheduleEnabled  = $job.IsScheduleEnabled
        ObjectCount      = $objects.Count
    })

    # 保護対象一覧
    foreach ($object in $objects) {
        $objectsRows.Add([pscustomobject]@{
            JobName       = $job.Name
            ObjectName    = $object.Name
            ObjectType    = $object.Type
            ObjectId      = $object.Id
            DisplayName   = $object.DisplayName
            RawDefinition = $object | ConvertTo-Json -Depth 100 -Compress -WarningAction SilentlyContinue
        })
    }

    # 詳細設定を「カテゴリ／項目／値」で縦持ち出力
    Add-ScalarProperties -JobName $job.Name -Category 'Job'      -InputObject $job      -TargetList $optionsRows
    Add-ScalarProperties -JobName $job.Name -Category 'Options'  -InputObject $options  -TargetList $optionsRows
    Add-ScalarProperties -JobName $job.Name -Category 'Schedule' -InputObject $schedule -TargetList $scheduleRows

    Write-Host "  ($($objects.Count) objects)" -ForegroundColor Green

    # 後日の機械的な差分比較用 (循環参照を切るため事前にシリアライズ変換)
    $rawRows.Add([pscustomobject]@{
        JobName    = $job.Name
        Job        = ConvertTo-SerializableObject $job
        Options    = ConvertTo-SerializableObject $options
        Schedule   = ConvertTo-SerializableObject $schedule
        JobObjects = ConvertTo-SerializableObject $objects
    })
}

# Windows PowerShell 5.1 は UTF8、PowerShell 7 は UTF8 BOM を利用
$encoding = if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' }

$jobsRows     | Export-Csv -Path $JobsCsv     -NoTypeInformation -Encoding $encoding
$objectsRows  | Export-Csv -Path $ObjectsCsv  -NoTypeInformation -Encoding $encoding
$optionsRows  | Export-Csv -Path $OptionsCsv  -NoTypeInformation -Encoding $encoding
$scheduleRows | Export-Csv -Path $ScheduleCsv -NoTypeInformation -Encoding $encoding

$rawRows | ConvertTo-Json -Depth 100 -WarningAction SilentlyContinue | Set-Content -Path $RawJson -Encoding $encoding

Write-Host ""
Write-Host "CSV/JSON 出力完了: $OutputDir" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$psScript  = Join-Path $scriptDir 'Generate-ParameterSheet.ps1'
if (Test-Path $psScript) {
    Write-Host ""
    & $psScript -JsonPath $RawJson
} else {
    Write-Host "Generate-ParameterSheet.ps1 が見つかりません: $psScript" -ForegroundColor Yellow
}
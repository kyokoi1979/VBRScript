#Requires -Version 5.1
<#
.SYNOPSIS
    RawJobDefinition.json から Veeam バックアップジョブのパラメータシート (HTML) を生成します。
.EXAMPLE
    .\Generate-ParameterSheet.ps1 -JsonPath .\Output\20261004_153000\RawJobDefinition.json
#>
param(
    [Parameter(Mandatory)]
    [string]$JsonPath,
    [string]$OutputPath
)

Set-StrictMode -Off
Add-Type -AssemblyName System.Web

# ---- JSON 読み込み (UTF8 BOM 対応) ----
$content = Get-Content -Path $JsonPath -Raw -Encoding UTF8
if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) { $content = $content.Substring(1) }
$rawData = $content | ConvertFrom-Json
$jobs    = if ($rawData -is [array]) { $rawData } else { @($rawData) }

if (-not $OutputPath) {
    $OutputPath = [System.IO.Path]::ChangeExtension((Resolve-Path $JsonPath).Path, 'html')
}

# ---- ラベル変換 ----
function label-compression($v) {
    switch ([int]$v) {
        0 { 'なし' }  4 { '重複排除対応' }  5 { '最適 (既定)' }  6 { '高' }  9 { '最大' }
        default { $v }
    }
}

function label-blocksize($v) {
    switch ([int]$v) {
        0 { '512 KB' }  1 { '1 MB' }  2 { '4 MB' }  3 { '8 MB (ローカルターゲット)' }
        default { $v }
    }
}

function label-retention($v) {
    switch ([int]$v) { 0 { 'リストアポイント数' }  1 { '日数' }  default { $v } }
}

function label-algorithm($v) {
    switch ([int]$v) {
        0 { 'フォワードインクリメンタル' }
        1 { 'リバースインクリメンタル' }
        2 { 'フォーエバーフォワードインクリメンタル' }
        default { $v }
    }
}

function label-dailykind($v) {
    switch ([int]$v) { 0 { '毎日' }  1 { '平日のみ' }  2 { '特定の曜日' }  default { $v } }
}

function label-bool($v) {
    if ($null -eq $v) { return '' }
    if ($v) { '有効' } else { '無効' }
}

function safe($v) {
    if ($null -eq $v) { return '' }
    [string]$v
}

function enc($v) {
    [System.Web.HttpUtility]::HtmlEncode((safe $v))
}

# ---- HTML 行・テーブル部品 ----
function row([string]$label, [string]$value) {
    $display = if ($value -eq '') { '<span class="empty">&mdash;</span>' } else { enc $value }
    "<tr><th>$label</th><td>$display</td></tr>"
}

# ---- ジョブ HTML 生成 ----
function job-html($j) {
    $jb    = $j.Job
    $opts  = $j.Options
    $sch   = $j.Schedule
    $objs  = @($j.JobObjects)

    $stor  = $opts.BackupStorageOptions
    $tgt   = $opts.BackupTargetOptions
    $jopt  = $opts.JobOptions
    $notif = $opts.NotificationOptions
    $daily = $sch.OptionsDaily
    $mon   = $sch.OptionsMonthly
    $per   = $sch.OptionsPeriodically
    $bkwin = $sch.OptionsBackupWindow

    # スケジュール説明
    $schedDesc = if ($jopt.RunManually -or $sch.IsFakeSchedule) {
        '手動実行'
    } elseif ($daily -and $daily.Enabled) {
        $time = try { ([datetime]$daily.TimeLocal).ToString('HH:mm') } catch { safe $daily.TimeLocal }
        "$(label-dailykind $daily.Kind)  $time"
    } elseif ($mon -and $mon.Enabled) {
        $time = try { ([datetime]$mon.TimeLocal).ToString('HH:mm') } catch { safe $mon.TimeLocal }
        "毎月 第$($mon.DayNumberInMonth)回目の $([System.DayOfWeek]$mon.DayOfWeek)  $time"
    } elseif ($per -and $per.Enabled) {
        "定期実行 ($($per.FullPeriod) $($per.Unit))"
    } else {
        '未設定'
    }

    # 保護対象行
    $objRows = foreach ($obj in $objs) {
        $type = if ($obj.TypeDisplayName) { enc $obj.TypeDisplayName } else { enc $obj.Type }
        "<tr><td>$(enc $obj.Name)</td><td>$type</td><td>$(enc $obj.Role)</td><td>$(enc $obj.Location)</td></tr>"
    }

    # 作成日時をローカル表示
    $createdAt = try { ([datetime]$jb.Info.CreationTimeUtc).ToLocalTime().ToString('yyyy/MM/dd HH:mm:ss') } catch { safe $jb.Info.CreationTimeUtc }

    # ヒアストリング内で if を直接引数に渡せないため事前計算
    $bkwinStatus = if ($bkwin -and $bkwin.IsEnabled) { '有効' } else { '無効' }
    $emailStatus = if ($notif.SendEmailNotification2AdditionalAddresses -or $notif.UseCustomEmailNotificationOptions) { '有効' } else { '無効 (グローバル設定を使用)' }

    return @"
<section>
<h1 class="job-title">$(enc $j.JobName)</h1>

<h2>1. ジョブ基本情報</h2>
<table>
$(row 'ジョブ名'       (safe $jb.Name))
$(row 'ジョブタイプ'   (safe $jb.TypeToString))
$(row '説明'           (safe $jb.Description))
$(row '作成日時'       $createdAt)
$(row '最終更新者'     (safe $jb.Info.CommonInfo.ModifiedBy.FullName))
$(row 'ジョブ ID'      (safe $jb.Id))
</table>

<h2>2. 保護対象</h2>
<table class="wide">
<tr><th>名前</th><th>種別</th><th>ロール</th><th>場所</th></tr>
$($objRows -join "`n")
</table>

<h2>3. ストレージ / 保持設定</h2>
<table>
$(row '保持タイプ'             (label-retention $stor.RetentionType))
$(row 'リストアポイント数'     (safe $stor.RetainCycles))
$(row '保持日数'               (safe $stor.RetainDaysToKeep))
$(row '削除済みVMデータ保持'   (label-bool $stor.EnableDeletedVmDataRetention))
$(row '圧縮レベル'             (label-compression $stor.CompressionLevel))
$(row 'ストレージブロックサイズ' (label-blocksize $stor.StgBlockSize))
$(row '重複排除'               (label-bool $stor.EnableDeduplication))
$(row '整合性チェック'         (label-bool $stor.EnableIntegrityChecks))
$(row 'ストレージ暗号化'       (label-bool $stor.StorageEncryptionEnabled))
</table>

<h2>4. バックアップ方式</h2>
<table>
$(row 'バックアップアルゴリズム' (label-algorithm $tgt.Algorithm))
$(row '合成フルへ変換'           (label-bool $tgt.TransformToSyntheticFull))
$(row 'ロールバックへ変換'       (label-bool $tgt.TransformToRollbacks))
</table>

<h2>5. スケジュール</h2>
<table>
$(row '実行スケジュール'     $schedDesc)
$(row 'リトライ回数'         (safe $sch.RetryTimes))
$(row 'リトライ間隔 (分)'    (safe $sch.RetryTimeout))
$(row '次回実行予定'         (safe $sch.NextRun))
$(row '最終実行'             (safe $sch.LatestRunLocal))
$(row 'バックアップウィンドウ' $bkwinStatus)
</table>

<h2>6. 通知設定</h2>
<table>
$(row 'メール通知'             $emailStatus)
$(row '追加通知先アドレス'     (safe $notif.EmailNotificationAdditionalAddresses))
$(row '成功時通知'             (label-bool $notif.EmailNotifyOnSuccess))
$(row '警告時通知'             (label-bool $notif.EmailNotifyOnWarning))
$(row 'エラー時通知'           (label-bool $notif.EmailNotifyOnError))
$(row '最終リトライのみ通知'   (label-bool $notif.EmailNotifyOnLastRetryOnly))
$(row '通知件名テンプレート'   (safe $notif.EmailNotificationSubject))
</table>

</section>
"@
}

# ---- HTML 全体 ----
Write-Host "パラメータシート生成: $($jobs.Count) ジョブ" -ForegroundColor Cyan

$generatedAt = Get-Date -Format 'yyyy/MM/dd HH:mm:ss'
$srcFile     = Split-Path $JsonPath -Leaf

$jobHtmlParts = for ($i = 0; $i -lt $jobs.Count; $i++) {
    $j = $jobs[$i]
    Write-Host "  [$($i + 1)/$($jobs.Count)] $($j.JobName)" -ForegroundColor Green
    job-html $j
}
$body = $jobHtmlParts -join "<hr class='job-sep'>`n"

$html = @"
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Veeam バックアップジョブ パラメータシート</title>
<style>
  :root {
    --bg:          #fff;
    --text:        #222;
    --head-bg:     #1e3a5f;
    --head-fg:     #fff;
    --h2-bg:       #2d6a9f;
    --th-bg:       #eef2f7;
    --border:      #c4d0de;
    --empty:       #aaa;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: 'Meiryo', 'Yu Gothic', 'Noto Sans JP', sans-serif;
    background: var(--bg); color: var(--text); font-size: 13px; line-height: 1.65;
  }
  .page { max-width: 960px; margin: 0 auto; padding: 28px 20px; }

  /* レポートヘッダ */
  .report-header {
    background: var(--head-bg); color: var(--head-fg);
    padding: 14px 24px; border-radius: 6px; margin-bottom: 28px;
  }
  .report-header h1 { font-size: 17px; }
  .report-header p  { font-size: 11px; margin-top: 4px; opacity: .75; }

  /* ジョブタイトル */
  h1.job-title {
    font-size: 15px; background: var(--head-bg); color: var(--head-fg);
    padding: 9px 16px; border-radius: 4px; margin-bottom: 14px;
  }

  /* セクション見出し */
  h2 {
    font-size: 12px; background: var(--h2-bg); color: #fff;
    padding: 5px 12px; margin: 14px 0 0; border-radius: 3px;
  }

  /* テーブル共通 */
  table { width: 100%; border-collapse: collapse; border: 1px solid var(--border); }
  th, td { border: 1px solid var(--border); padding: 5px 10px; vertical-align: top; }

  /* ラベル列 (2カラムテーブル) */
  table:not(.wide) th {
    background: var(--th-bg); width: 230px;
    font-weight: normal; color: #444; white-space: nowrap;
  }
  table:not(.wide) td { background: #fff; }

  /* ワイドテーブル (保護対象) */
  table.wide th { background: var(--th-bg); font-weight: normal; text-align: left; }
  table.wide td { background: #fff; }

  .empty { color: var(--empty); }

  hr.job-sep { border: none; border-top: 2px solid var(--border); margin: 40px 0; }

  .footer { text-align: right; font-size: 11px; color: #999; margin-top: 32px; }

  @media print {
    body { font-size: 11px; }
    .page { padding: 0; max-width: 100%; }
    section { page-break-after: always; }
    hr.job-sep { display: none; }
    .report-header, h1.job-title, h2 { border-radius: 0 !important; }
  }
</style>
</head>
<body>
<div class="page">

<div class="report-header">
  <h1>Veeam Backup &amp; Replication &mdash; バックアップジョブ パラメータシート</h1>
  <p>生成日時: $generatedAt &nbsp;|&nbsp; ソース: $(enc $srcFile) &nbsp;|&nbsp; ジョブ数: $($jobs.Count)</p>
</div>

$body

<p class="footer">Generated by Generate-ParameterSheet.ps1</p>
</div>
</body>
</html>
"@

$encoding = if ($PSVersionTable.PSVersion.Major -ge 6) { 'utf8BOM' } else { 'UTF8' }
$html | Set-Content -Path $OutputPath -Encoding $encoding
Write-Host "出力完了: $OutputPath" -ForegroundColor Cyan

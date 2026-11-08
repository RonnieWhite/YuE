<#
YuE2 本地一键生成脚本

常用用法（在本目录下执行）：
  .\run.cmd                              # 用 examples/song.json 生成一首（低显存模式）
  .\run.cmd -LyricsFile my.txt -Style "Mandarin, warm piano pop, female vocal"
  .\run.cmd -Plan -NoOpen                # 只生成可编辑的 score.abc，不渲染音频
  .\run.cmd -AbcFile my.abc -Cot full    # 用你自己的乐谱渲染
  .\run.cmd -FullVram                    # 24GB 以上显存，关闭 low-vram
  .\run.cmd -AllowNetwork                # 允许访问 HuggingFace（默认强制离线）
#>
[CmdletBinding()]
param(
  [string]$Request = 'examples/song.json',
  [string]$LyricsFile,
  [string]$Lyrics,
  [string]$Style,
  [string]$AbcFile,
  [string]$Id,
  [int]$Seed = -1,
  [ValidateSet('full', 'melody', 'off')][string]$Cot,
  [string]$Device = 'cuda',
  [double]$Budget = 12,
  [switch]$FullVram,
  [switch]$Plan,
  [string]$Output = 'runs',
  [switch]$AllowNetwork,
  [switch]$NoOpen
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
Set-Location $root

$exe = Join-Path $root '.venv\Scripts\yue2.exe'
if (-not (Test-Path $exe)) {
  Write-Host '找不到 .venv\Scripts\yue2.exe' -ForegroundColor Red
  Write-Host '请先安装环境：python -m venv .venv; .\.venv\Scripts\python.exe -m pip install -e .'
  exit 1
}

$model = Join-Path $root 'models\YuE2-3B\model.safetensors'
$vae = Join-Path $root 'models\YuE2-Vae\model.safetensors'
if ((Test-Path $model) -and (Test-Path $vae)) {
  # 本地权重齐全，默认不联网
  if (-not $AllowNetwork) {
    $env:HF_HUB_OFFLINE = '1'
    $env:TRANSFORMERS_OFFLINE = '1'
    $env:HF_HUB_DISABLE_TELEMETRY = '1'
  }
}
else {
  Write-Host '本地权重不完整（models\YuE2-3B / models\YuE2-Vae），将尝试从 HuggingFace 下载。' -ForegroundColor Yellow
}

function Resolve-InputPath([string]$path) {
  if ([IO.Path]::IsPathRooted($path)) { return $path }
  return (Join-Path $root $path)
}

if ($Request) {
  $Request = Resolve-InputPath $Request
  if (-not (Test-Path $Request)) {
    Write-Host ('请求文件不存在：' + $Request) -ForegroundColor Red
    exit 1
  }
}
if ($LyricsFile) {
  $LyricsFile = Resolve-InputPath $LyricsFile
  if (-not (Test-Path $LyricsFile)) {
    Write-Host ('歌词文件不存在：' + $LyricsFile) -ForegroundColor Red
    exit 1
  }
  # Windows 记事本可能写成 UTF-8 BOM，直接按字节传给模型会在开头混入一个不可见字符
  $bytes = [IO.File]::ReadAllBytes($LyricsFile)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    Write-Host '提示：歌词文件带 UTF-8 BOM，已自动去除。' -ForegroundColor Yellow
    $Lyrics = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    $LyricsFile = $null
  }
}
if ($AbcFile) {
  $AbcFile = Resolve-InputPath $AbcFile
  if (-not (Test-Path $AbcFile)) {
    Write-Host ('乐谱文件不存在：' + $AbcFile) -ForegroundColor Red
    exit 1
  }
}

$tag = Get-Date -Format 'yyyyMMdd-HHmmss'
if ($Plan) { $tag = $tag + '-plan' }
$outDir = Join-Path (Join-Path $root $Output) $tag

$cliArgs = @('generate')
if ($Request) { $cliArgs += @('--request', $Request) }
if ($LyricsFile) { $cliArgs += @('--lyrics-file', $LyricsFile) }
elseif ($Lyrics) { $cliArgs += @('--lyrics', $Lyrics) }
if ($Style) { $cliArgs += @('--style', $Style) }
if ($AbcFile) { $cliArgs += @('--abc-file', $AbcFile) }
if ($Cot) { $cliArgs += @('--cot', $Cot) }
if ($Id) { $cliArgs += @('--id', $Id) }
if ($Seed -ge 0) { $cliArgs += @('--seed', [string]$Seed) }
if ($Plan) { $cliArgs += @('--stage', 'plan') }
$cliArgs += @('--output', $outDir, '--device', $Device)
if (-not $FullVram) {
  $budgetText = $Budget.ToString([Globalization.CultureInfo]::InvariantCulture)
  $cliArgs += @('--low-vram', '--budget', $budgetText)
}
else {
  $budgetText = '默认'
}

Write-Host ''
Write-Host '=== YuE2 开始生成 ===' -ForegroundColor Cyan
Write-Host ('  输出目录 : ' + $outDir)
Write-Host ('  设备     : ' + $Device + '   显存策略: ' + $(if ($FullVram) { '默认(24GB+)' } else { 'low-vram / budget ' + $budgetText + ' GB' }))
Write-Host ('  模式     : ' + $(if ($Plan) { '仅生成乐谱(plan)' } else { '完整歌曲' }))
Write-Host ''

$sw = [Diagnostics.Stopwatch]::StartNew()
& $exe @cliArgs 2>&1 | ForEach-Object { Write-Host $_.ToString() }
$code = $LASTEXITCODE
$sw.Stop()

$audio = Get-ChildItem $outDir -Recurse -Filter 'audio.flac' -ErrorAction SilentlyContinue | Select-Object -First 1
$score = Get-ChildItem $outDir -Recurse -Filter 'score.abc' -ErrorAction SilentlyContinue | Select-Object -First 1

Write-Host ''
if ($code -eq 0) {
  Write-Host ('=== 完成，用时 {0:N1} 秒 ===' -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
}
else {
  Write-Host ('=== 失败或异常结束（退出码 {0}），用时 {1:N1} 秒 ===' -f $code, $sw.Elapsed.TotalSeconds) -ForegroundColor Yellow
  Write-Host ('失败详情见：' + (Join-Path $outDir 'failure.json'))
}
if ($audio) { Write-Host ('音频: ' + $audio.FullName) }
if ($score) { Write-Host ('乐谱: ' + $score.FullName) }
if (-not $audio -and -not $score) { Write-Host ('目录: ' + $outDir) }

if (-not $NoOpen) {
  if ($audio) { Invoke-Item $audio.FullName }
  elseif ($score) { Invoke-Item $score.Directory.FullName }
  elseif (Test-Path $outDir) { Invoke-Item $outDir }
}

exit $code

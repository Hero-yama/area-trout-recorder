# ルアーリスト.txt を読み込み、アプリ用の lures-data.js を生成する
# 使い方：このフォルダで  powershell -ExecutionPolicy Bypass -File .\リスト更新.ps1
# ルアーリスト.txt の書式：
#   「1. スプーン」のような行 = 大分類
#   「/」を含まない行など = 小分類（見出し）
#   ブランド / モデル 重さg (カラー) の形式の行 = ルアー

$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$src = Get-ChildItem -Path $dir -Filter '*.txt' | Select-Object -First 1
if (-not $src) { throw 'txtファイルが見つかりません' }
$lines = [System.IO.File]::ReadAllLines($src.FullName, [System.Text.Encoding]::UTF8)

$cats = New-Object System.Collections.Generic.List[object]
$cat = $null; $grp = $null; $prevBlank = $true
$count = 0

foreach ($raw in $lines) {
    $t = $raw.Trim()
    if ($t -eq '') { $prevBlank = $true; continue }

    # 大分類
    if ($t -match '^\d+\.\s*(.+)$') {
        $cat = [ordered]@{ name = $Matches[1].Trim(); groups = (New-Object System.Collections.Generic.List[object]) }
        $cats.Add($cat); $grp = $null; $prevBlank = $true
        continue
    }
    if (-not $cat) { continue }   # タイトル行などは無視

    # ルアー行の判定：「/」があり、その手前の括弧が閉じている（ブランド名として成立する）
    $i = $t.IndexOf('/')
    $isEntry = $false
    if ($i -ge 0) {
        $head = $t.Substring(0, $i)
        $open = ([regex]::Matches($head, '[（(]')).Count
        $close = ([regex]::Matches($head, '[）)]')).Count
        $isEntry = ($open -eq $close)
    }

    # 小分類（見出し）。括弧書きは見出しから除く
    if (-not $isEntry) {
        $gname = ($t -replace '\s*[（(].*$', '').Trim()
        $grp = [ordered]@{ name = $gname; models = (New-Object System.Collections.Generic.List[object]) }
        $cat.groups.Add($grp)
        continue
    }
    if (-not $grp) { Write-Warning "見出し前のルアー行: $t"; continue }

    # ブランドと残りに分ける
    $brand = $t.Substring(0, $i).Trim()
    $rest = $t.Substring($i + 1).Trim()

    # 最初の括弧以降がカラー
    $color = ''
    $model = $rest
    $m = [regex]::Match($rest, '[（(]')
    if ($m.Success) {
        $model = $rest.Substring(0, $m.Index).Trim()
        $color = ($rest.Substring($m.Index + 1) -replace '[）)]\s*$', '').Trim()
    }

    # 重さ
    $weight = ''
    $wm = [regex]::Match($model, '(\d+(?:\.\d+)?)\s*g(?![A-Za-z])')
    if ($wm.Success) {
        $weight = $wm.Groups[1].Value
        $model = ($model.Remove($wm.Index, $wm.Length)).Trim()
    }

    # 同じブランド・モデル・重さはカラーをまとめる
    $found = $null
    foreach ($e in $grp.models) {
        if ($e.brand -eq $brand -and $e.name -eq $model -and $e.weight -eq $weight) { $found = $e; break }
    }
    if (-not $found) {
        $found = [ordered]@{ brand = $brand; name = $model; weight = $weight; colors = (New-Object System.Collections.Generic.List[object]) }
        $grp.models.Add($found)
    }
    $found.colors.Add($color)
    $count++
}

$json = $cats | ConvertTo-Json -Depth 8 -Compress
$out = "// 自動生成ファイル（リスト更新.ps1）。直接編集しないでください。`r`nwindow.LURE_CATALOG = $json;`r`n"
[System.IO.File]::WriteAllText((Join-Path $dir 'lures-data.js'), $out, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "完了: $count 件を lures-data.js に出力しました"

param([string]$Repo = "D:\SSDWP\unity\UnityURPToonLitShaderExample", [string]$FileList = "")

# 用法：pwsh -NoProfile -File Docs/tools/verify-comment-only.ps1 -FileList "Assets/a.shader;Assets/b.hlsl"
$Files = @($FileList -split ';' | Where-Object { $_ })

# 去掉注释后只比较代码，验证"注释翻译"没有动到任何一行 shader 代码
function Strip-Comments([string]$text) {
    $t = [regex]::Replace($text, '/\*[\s\S]*?\*/', ' ')   # 块注释
    $t = [regex]::Replace($t, '(?m)//.*$', ' ')            # 行注释
    $t = $t -replace '\s+', ' '                             # 折叠空白
    return $t.Trim()
}

$fail = 0
foreach ($f in $Files) {
    $head = (git -C $Repo show "HEAD:$f") -join "`n"
    $work = Get-Content -Raw -Path (Join-Path $Repo $f)
    $a = Strip-Comments $head
    $b = Strip-Comments $work
    if ($a -ceq $b) {
        Write-Host "OK    $f  (代码零改动)"
    } else {
        $fail = 1
        Write-Host "DIFF  $f  HEAD代码长度=$($a.Length) 工作区代码长度=$($b.Length)"
        # 找出第一段差异
        $n = [Math]::Min($a.Length, $b.Length); $i = 0
        while ($i -lt $n -and $a[$i] -ceq $b[$i]) { $i++ }
        $s = [Math]::Max(0, $i - 60)
        Write-Host ("      差异位置 {0}`n      HEAD: ...{1}`n      WORK: ...{2}" -f $i, $a.Substring($s, [Math]::Min(160, $a.Length - $s)), $b.Substring($s, [Math]::Min(160, $b.Length - $s)))
    }
    # 顺带检查编码：不应出现替换字符（乱码信号）
    if ($work -match [char]0xFFFD) { Write-Host "ENCODE-WARN $f 含乱码替换符"; $fail = 1 }
}
exit $fail

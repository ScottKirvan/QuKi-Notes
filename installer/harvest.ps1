param(
    [string]$SourceDir = "build\windows\x64\runner\Release",
    [string]$OutputFile = "installer\AppFiles.wxs"
)

$ErrorActionPreference = "Stop"
$resolved = (Resolve-Path $SourceDir).Path
$compIds = [System.Collections.Generic.List[string]]::new()

function Sanitize([string]$s) {
    return "x" + ($s -replace '[^a-zA-Z0-9]', '_')
}

function Emit-Tree {
    param([string]$path, [string]$relBase, [int]$depth)
    $pad = "  " * $depth
    $sb = [System.Text.StringBuilder]::new()

    $items = Get-ChildItem -Path $path | Sort-Object { $_.PSIsContainer }, Name

    foreach ($item in $items) {
        $rel = if ($relBase) { "$relBase\$($item.Name)" } else { $item.Name }

        if ($item.PSIsContainer) {
            $dirId = Sanitize $rel
            $null = $sb.AppendLine("${pad}<Directory Id=""$dirId"" Name=""$($item.Name)"">")
            $childXml = Emit-Tree -path $item.FullName -relBase $rel -depth ($depth + 1)
            $null = $sb.Append($childXml)
            $null = $sb.AppendLine("${pad}</Directory>")
        } else {
            $cmpId = Sanitize $rel
            $script:compIds.Add($cmpId)
            $src = "$SourceDir\$rel"
            $null = $sb.AppendLine("${pad}<Component Id=""$cmpId"" Guid=""*"">")
            $null = $sb.AppendLine("${pad}  <File Source=""$src"" />")
            $null = $sb.AppendLine("${pad}</Component>")
        }
    }

    return $sb.ToString()
}

$treeXml = Emit-Tree -path $resolved -relBase "" -depth 3

$out = [System.Text.StringBuilder]::new()
$null = $out.AppendLine('<?xml version="1.0" encoding="UTF-8"?>')
$null = $out.AppendLine('<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">')
$null = $out.AppendLine('  <Fragment>')
$null = $out.AppendLine('    <DirectoryRef Id="INSTALLFOLDER">')
$null = $out.Append($treeXml)
$null = $out.AppendLine('    </DirectoryRef>')
$null = $out.AppendLine('    <ComponentGroup Id="AppFiles">')
foreach ($id in $compIds) {
    $null = $out.AppendLine("      <ComponentRef Id=""$id"" />")
}
$null = $out.AppendLine('    </ComponentGroup>')
$null = $out.AppendLine('  </Fragment>')
$null = $out.AppendLine('</Wix>')

[System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($OutputFile),
    $out.ToString(),
    [System.Text.Encoding]::UTF8
)

Write-Host "Generated $OutputFile with $($compIds.Count) components"

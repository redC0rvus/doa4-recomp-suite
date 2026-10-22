# Turn git symlinks into plain files, in a repo and all its submodules, so nothing needs symlink rights
# (no Developer Mode). Clone with -c core.symlinks=false first: git then writes each link as a small text
# file holding its target path. Each one becomes a copy of its target when that is a regular file inside
# the same repo; any other link (directory, dangling, outside the repo, another link) is removed, as a
# snapshot would leave it out. Either way it is marked skip-worktree, so git status stays clean.
# The SDK build needs only libmspack's cabextract/mspack/*.c,h (copies of libmspack/mspack/*); the
# skipped ones are MoltenVK (macOS only).
# ponytail: copies are frozen at clone time; an SDK upgrade re-clones.
# Usage: pwsh tools/link_copies.ps1 -Dir thirdparty\rexglue-sdk
param([Parameter(Mandatory)][string]$Dir)
$ErrorActionPreference = 'Stop'

$Dir = (Resolve-Path $Dir).Path
$repos = @($Dir) + @(git -C $Dir submodule foreach --quiet --recursive 'echo "$displaypath"' | ForEach-Object { Join-Path $Dir $_ })
$copied = 0; $skipped = @()
foreach ($repo in $repos) {
    $links = @(git -C $repo -c core.quotepath=off ls-files -s | Where-Object { $_ -match '^120000 ' } | ForEach-Object { ($_ -split "`t", 2)[1] })
    if (-not $links) { continue }
    $linkPaths = $links | ForEach-Object { [IO.Path]::GetFullPath((Join-Path $repo $_)) }
    foreach ($l in $links) {
        $p = [IO.Path]::GetFullPath((Join-Path $repo $l))
        $item = Get-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        if (-not $item -or $item.LinkType) { throw "$p is not a link placeholder; clone with -c core.symlinks=false." }
        $target = [IO.Path]::GetFullPath((Join-Path (Split-Path $p) (Get-Content -LiteralPath $p -Raw)))
        if ($target.StartsWith("$repo\", 'OrdinalIgnoreCase') -and $target -notin $linkPaths -and (Test-Path -LiteralPath $target -PathType Leaf)) {
            Copy-Item -LiteralPath $target $p -Force
            $copied++
        } else {
            Remove-Item -LiteralPath $p -Force
            $skipped += $p.Substring($Dir.Length + 1)
        }
    }
    git -C $repo update-index --skip-worktree -- @links
    if ($LASTEXITCODE) { throw "git update-index failed in $repo" }
}
"  symlinks as copies: $copied copied, $($skipped.Count) left out$(if ($skipped) { ': ' + ($skipped -join ', ') })"

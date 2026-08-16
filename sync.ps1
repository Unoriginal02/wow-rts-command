# sync.ps1 -- refresh this backup from the three live working locations.
#
# The project is not one tree. It is three pieces that live where each has to
# live: the addon inside the WoW client on F:, the server module inside the
# AzerothCore checkout, and the injected DLL in its own CMake project. This
# folder is a COPY of all three in one place, so a single push backs up the lot.
#
# Run it, then commit. It is deliberately a copy rather than a set of nested
# repos: a backup that has to be assembled from three remotes when you need it
# is not much of a backup.
#
# WHAT IS DELIBERATELY NOT COPIED
#   dist/configs/*.conf   -- worldserver.conf, authserver.conf and dbimport.conf
#                            carry the MySQL user and password in plain text.
#   build output, logs, mysql-data, the azerothcore fork itself
#                         -- rebuildable, huge, or has its own remote already.

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

$pairs = @(
    @{ From = "F:\Games\WOW WOTLK\Interface\AddOns\RTSCommand"; To = "addon" },
    @{ From = "C:\Server\rts-client-mod";                       To = "rts-client-mod" },
    @{ From = "C:\Server\azerothcore\modules\mod-rts";           To = "mod-rts" }
)

foreach ($p in $pairs) {
    $dest = Join-Path $root $p.To
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    # /MIR mirrors; the excludes keep build artefacts and VCS metadata out.
    robocopy $p.From $dest /MIR /NFL /NDL /NJH /NJS /NP `
        /XD build .git .vs out bin obj `
        /XF *.log *.dll *.exe *.pdb *.ilk *.obj *.tga | Out-Null
}

# Docs and launcher scripts live loose in C:\Server.
$docs = Join-Path $root "docs"
New-Item -ItemType Directory -Path $docs -Force | Out-Null
Copy-Item C:\Server\CLAUDE.md      $docs -Force
Copy-Item C:\Server\PRUEBAS*.txt   $docs -Force

$scripts = Join-Path $root "scripts"
New-Item -ItemType Directory -Path $scripts -Force | Out-Null
Copy-Item C:\Server\*.bat $scripts -Force

# The addon art is the one binary worth keeping -- it is authored, not built.
Copy-Item "F:\Games\WOW WOTLK\Interface\AddOns\RTSCommand\*.tga" `
          (Join-Path $root "addon") -Force -ErrorAction SilentlyContinue

Write-Host "sync done." -ForegroundColor Green
Get-ChildItem $root -Directory | ForEach-Object {
    $n = (Get-ChildItem $_.FullName -Recurse -File).Count
    "  {0,-18} {1} files" -f $_.Name, $n
}

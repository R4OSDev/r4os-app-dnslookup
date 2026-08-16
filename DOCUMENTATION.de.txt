DNSLOOKUP.R4X
=============

DNSLOOKUP.R4X ist das Terminalwerkzeug fuer DNS-Aufloesung ueber R4NET.

Projektstruktur seit 0.51.19:
- `build.zig` baut die App als eigenes SDK-Projekt.
- `build.zig.zon` bindet `r4os_sdk` als Paket.
- `module.R4MF` beschreibt Artefakt, Zielpfad, Imports und Contract.

Build:

    cd Code\System\Software\DnsLookup
    ..\..\..\DevTools\Zig\zig.exe build

Ergebnis:

    Code\System\Software\DnsLookup\zig-out\DNSLOOKUP.R4X

Contract:
- R4XStart-Entry: `dnslookup_main`
- App-Klasse: `console`
- R4L-Imports: `R4SYS`, `R4NET`
- Zielpfad im Image: `C:\R4OS\SOFTWARE\TERMINAL\DNSLOOKUP.R4X`


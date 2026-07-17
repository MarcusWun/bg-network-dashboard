; B&G Network Dashboard -- Inno Setup 6 Script
; Dependency downloads and service configuration handled entirely by setup.ps1

[Setup]
AppName=B&G Network Dashboard
AppVersion=1.0.0
AppPublisher=StratosRacing
AppPublisherURL=https://github.com/MarcusWun/bg-network-dashboard
DefaultDirName={autopf}\bg-network-dashboard
DefaultGroupName=B&G Network Dashboard
OutputBaseFilename=bg-network-dashboard-1.0.0-setup
SetupIconFile=compiler:SetupClassicIcon.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
DisableProgramGroupPage=yes
UninstallDisplayName=B&G Network Dashboard
VersionInfoVersion=1.0.0
VersionInfoProductName=B&G Network Dashboard
VersionInfoCompany=StratosRacing
MinVersion=10.0
OutputDir=..\Output

[Files]
Source: "..\telegraf.toml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\downsample_signalk.flux"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dashboard-n2k-network-monitor.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dashboard-ethernet-monitor.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\VALUE-MAPPINGS.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\INSTALL.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SERVICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\service-controller.js"; DestDir: "{app}"; Flags: ignoreversion
Source: "setup.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "launch.cmd"; DestDir: "{app}\installer"; Flags: ignoreversion

[Run]
Filename: "{app}\installer\launch.cmd"; Parameters: """{app}"""; StatusMsg: "Installing dependencies and configuring services (this may take 10-15 minutes)..."; Flags: waituntilterminated
Filename: "{sys}\cmd.exe"; Parameters: "/c start http://localhost:3001"; Description: "Open Grafana Dashboard"; Flags: postinstall nowait skipifsilent shellexec

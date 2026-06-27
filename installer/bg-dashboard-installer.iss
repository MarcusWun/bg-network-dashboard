; B&G Network Dashboard -- Inno Setup 6 Script
; All dependency downloads are handled by setup.ps1 (no IDP required)

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

[CustomMessages]
InstallWireshark=Install Wireshark (network packet analysis, optional)
InstallNSSM=Install NSSM -- required for Signal K to run as a Windows service

[Types]
Name: "full"; Description: "Full installation (recommended)"
Name: "custom"; Description: "Custom installation"; Flags: iscustom

[Components]
Name: "core"; Description: "Dashboard config files and setup script"; Types: full custom; Flags: fixed
Name: "nssm"; Description: "{cm:InstallNSSM}"; Types: full
Name: "wireshark"; Description: "{cm:InstallWireshark}"; Types: full

[Files]
Source: "..\telegraf.toml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\downsample_signalk.flux"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dashboard-n2k-network-monitor.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dashboard-ethernet-monitor.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\VALUE-MAPPINGS.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\INSTALL.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SERVICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "setup.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion

[Run]
Filename: "powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -NonInteractive -File ""{app}\installer\setup.ps1"" {code:GetSetupParameters}"; \
  StatusMsg: "Installing dependencies and configuring services (this may take 10-15 minutes)..."; \
  Flags: runhidden waituntilterminated

[UninstallDelete]
Type: filesandirs; Name: "{app}"

[Code]
function GetSetupParameters(Param: String): String;
var
  S: String;
begin
  S := '-AppDir "' + ExpandConstant('{app}') + '"';
  if IsComponentSelected('nssm') then
    S := S + ' -InstallNSSM';
  if IsComponentSelected('wireshark') then
    S := S + ' -InstallWireshark';
  Result := S;
end;

; B&G Network Dashboard — Inno Setup 6 Script
; Produces a bundled Windows installer that downloads dependencies and runs setup.ps1

#include <idp.iss>

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
LicenseFile=
OutputDir=..\Output

[CustomMessages]
OptionalComponents=Optional Components
InstallWireshark=Install Wireshark (network packet analysis)
InstallNSSM=Install NSSM (required for Signal K service)

[Types]
Name: "full"; Description: "Full installation (recommended)"
Name: "custom"; Description: "Custom installation"; Flags: iscustom

[Components]
Name: "core"; Description: "Dashboard config files and setup script"; Types: full custom; Flags: fixed
Name: "wireshark"; Description: "{cm:InstallWireshark}"; Types: full
Name: "nssm"; Description: "{cm:InstallNSSM}"; Types: full

[Files]
; Config and documentation files
Source: "..\telegraf.toml"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\downsample_signalk.flux"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dashboard-n2k-network-monitor.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\dashboard-ethernet-monitor.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\VALUE-MAPPINGS.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\INSTALL.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SERVICES.md"; DestDir: "{app}"; Flags: ignoreversion
; Setup script
Source: "setup.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion

[Run]
Filename: "powershell.exe"; \
  Parameters: "-ExecutionPolicy Bypass -File ""{app}\installer\setup.ps1"" -AppDir ""{app}"""; \
  StatusMsg: "Configuring B&G Network Dashboard..."; \
  Flags: runhidden waituntilterminated
Filename: "{sys}\cmd.exe"; \
  Parameters: "/c start http://localhost:3001"; \
  Description: "Open Grafana Dashboard"; \
  Flags: postinstall nowait skipifsilent shellexec

[UninstallDelete]
Type: filesandirs; Name: "{app}"

[Code]
procedure InitializeWizard();
begin
  // Mandatory downloads
  idpAddFile('https://nodejs.org/dist/v20.19.0/node-v20.19.0-x64.msi', ExpandConstant('{tmp}\node-v20.19.0-x64.msi'));
  idpAddFile('https://dl.influxdata.com/influxdb/releases/influxdb2-2.7.6-windows.zip', ExpandConstant('{tmp}\influxdb2-windows.zip'));
  idpAddFile('https://dl.grafana.com/oss/release/grafana-11.6.0.windows-amd64.msi', ExpandConstant('{tmp}\grafana-11.6.0.msi'));
  idpAddFile('https://dl.influxdata.com/telegraf/releases/telegraf-1.33.0_windows_amd64.zip', ExpandConstant('{tmp}\telegraf-windows.zip'));

  idpDownloadAfter(wpReady);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    // Download optional components based on selection
    if IsComponentSelected('nssm') then
      idpAddFile('https://nssm.cc/release/nssm-2.24.zip', ExpandConstant('{tmp}\nssm-2.24.zip'));

    if IsComponentSelected('wireshark') then
      idpAddFile('https://2.na.dl.wireshark.org/win64/Wireshark-latest-x64.exe', ExpandConstant('{tmp}\Wireshark-latest-x64.exe'));
  end;

  if CurStep = ssPostInstall then
  begin
    // Install Node.js MSI silently
    Exec('msiexec.exe', ExpandConstant('/i "{tmp}\node-v20.19.0-x64.msi" /qn /norestart'), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Extract InfluxDB zip to Program Files
    Exec('powershell.exe', ExpandConstant('-ExecutionPolicy Bypass -Command "Expand-Archive -Path ''{tmp}\influxdb2-windows.zip'' -DestinationPath ''C:\Program Files\InfluxData'' -Force"'), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Install Grafana MSI silently
    Exec('msiexec.exe', ExpandConstant('/i "{tmp}\grafana-11.6.0.msi" /qn /norestart'), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Extract Telegraf zip
    Exec('powershell.exe', ExpandConstant('-ExecutionPolicy Bypass -Command "Expand-Archive -Path ''{tmp}\telegraf-windows.zip'' -DestinationPath ''C:\telegraf'' -Force; Get-ChildItem ''C:\telegraf\telegraf-*'' | ForEach-Object { Move-Item $_.FullName\* ''C:\telegraf\'' -Force; Remove-Item $_.FullName -Force }"'), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Extract NSSM if selected
    if IsComponentSelected('nssm') then
    begin
      Exec('powershell.exe', ExpandConstant('-ExecutionPolicy Bypass -Command "Expand-Archive -Path ''{tmp}\nssm-2.24.zip'' -DestinationPath ''C:\nssm'' -Force; Get-ChildItem ''C:\nssm\nssm-*\win64\*'' | Move-Item -Destination ''C:\nssm\'' -Force"'), '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;

    // Run Wireshark installer if selected
    if IsComponentSelected('wireshark') then
    begin
      Exec(ExpandConstant('{tmp}\Wireshark-latest-x64.exe'), '/S', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    end;
  end;
end;

#define AppName "Liquid Launcher"
#ifndef AppVersion
  #define AppVersion "0.3.0"
#endif
#define AppPublisher "AlexPochmak"
#define AppExeName "Liquid.exe"

[Setup]
AppId={{8C2A5E71-3D4B-4F8A-9C61-2B7D5E9A1F30}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/Pochmak123/LiquidBec
AppSupportURL=https://github.com/Pochmak123/LiquidBec/issues
AppUpdatesURL=https://github.com/Pochmak123/LiquidBec/releases
VersionInfoVersion={#AppVersion}.0
VersionInfoDescription={#AppName} Setup
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
VersionInfoCopyright=Copyright (C) 2026 {#AppPublisher}
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=output
OutputBaseFilename=LiquidLauncher-Setup-{#AppVersion}
SetupIconFile=..\src-tauri\icons\icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "..\dist\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[InstallDelete]
Type: files; Name: "{app}\liquid_ios_design.exe"
Type: files; Name: "{app}\{#AppExeName}.old"
Type: files; Name: "{app}\{#AppExeName}.new"

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
const
  LegacyPrefix = 'Liquid Launcher';
  LegacyProcess = 'liquid_ios_design.exe';
  UninstallKey = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';

function NormalizeDir(const Path: String): String;
begin
  Result := Trim(Path);
  while (Length(Result) > 3) and (Result[Length(Result)] = '\') do
    Delete(Result, Length(Result), 1);
  Result := Lowercase(Result);
end;

function IsMsiProductCode(const Value: String): Boolean;
var
  I: Integer;
  C: Char;
begin
  Result := False;
  if Length(Value) <> 38 then Exit;
  if (Value[1] <> '{') or (Value[38] <> '}') then Exit;
  for I := 2 to 37 do
  begin
    C := Value[I];
    if not ((C = '-') or ((C >= '0') and (C <= '9')) or
            ((C >= 'a') and (C <= 'f')) or ((C >= 'A') and (C <= 'F'))) then
      Exit;
  end;
  Result := True;
end;

function IsVersionedName(const Name: String): Boolean;
var
  I: Integer;
  C: Char;
  HasDot: Boolean;
  Prefix: String;
begin
  Result := False;
  HasDot := False;
  Prefix := LegacyPrefix + ' ';
  if Length(Name) <= Length(Prefix) then Exit;
  if Copy(Name, 1, Length(Prefix)) <> Prefix then Exit;
  for I := Length(Prefix) + 1 to Length(Name) do
  begin
    C := Name[I];
    if C = '.' then
      HasDot := True
    else if (C < '0') or (C > '9') then
      Exit;
  end;
  Result := HasDot;
end;

function HasLiquidPrefix(const Value: String): Boolean;
begin
  Result := Lowercase(Copy(Value, 1, Length(LegacyPrefix))) = Lowercase(LegacyPrefix);
end;

procedure AddUnique(var Items: TArrayOfString; const Value: String);
var
  I, Count: Integer;
begin
  if Value = '' then Exit;
  Count := GetArrayLength(Items);
  for I := 0 to Count - 1 do
    if CompareText(Items[I], Value) = 0 then Exit;
  SetArrayLength(Items, Count + 1);
  Items[Count] := Value;
end;

procedure ScanUninstallRoot(const RootKey: HKEY; const SubKey: String; var Codes, Dirs: TArrayOfString);
var
  Names: TArrayOfString;
  I: Integer;
  KeyPath, DisplayName, Location: String;
begin
  if not RegGetSubkeyNames(RootKey, SubKey, Names) then Exit;
  for I := 0 to GetArrayLength(Names) - 1 do
  begin
    KeyPath := SubKey + '\' + Names[I];
    if RegQueryStringValue(RootKey, KeyPath, 'DisplayName', DisplayName) then
    begin
      if HasLiquidPrefix(DisplayName) then
      begin
        if IsMsiProductCode(Names[I]) then
          AddUnique(Codes, Names[I]);
        if RegQueryStringValue(RootKey, KeyPath, 'InstallLocation', Location) then
          AddUnique(Dirs, NormalizeDir(Location));
      end;
    end;
  end;
end;

procedure ScanLegacyDir(const BaseDir: String; var Dirs: TArrayOfString);
var
  FindRec: TFindRec;
begin
  if not DirExists(BaseDir) then Exit;
  if FindFirst(AddBackslash(BaseDir) + '*', FindRec) then
  try
    repeat
      if ((FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0) and
         (FindRec.Name <> '.') and (FindRec.Name <> '..') and
         IsVersionedName(FindRec.Name) then
        AddUnique(Dirs, NormalizeDir(AddBackslash(BaseDir) + FindRec.Name));
    until not FindNext(FindRec);
  finally
    FindClose(FindRec);
  end;
end;

procedure StopLegacyProcesses();
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'),
    '/F /IM ' + LegacyProcess + ' /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function UninstallProduct(const Code: String): Boolean;
var
  ErrorCode: Integer;
begin
  Result := False;
  if not ShellExec('runas', ExpandConstant('{sys}\msiexec.exe'),
    '/x ' + Code + ' /passive /norestart', '', SW_SHOWNORMAL,
    ewWaitUntilTerminated, ErrorCode) then
  begin
    Log('Elevated MSI uninstall could not start: ' + SysErrorMessage(ErrorCode));
    Exit;
  end;
  if (ErrorCode <> 0) and (ErrorCode <> 1605) and (ErrorCode <> 3010) then
  begin
    Log('MSI uninstall ' + Code + ' exited with code ' + IntToStr(ErrorCode));
    Exit;
  end;
  Result := True;
end;

procedure RemoveLegacyDirs(const Dirs: TArrayOfString);
var
  I: Integer;
  Current: String;
begin
  Current := NormalizeDir(ExpandConstant('{app}'));
  for I := 0 to GetArrayLength(Dirs) - 1 do
    if (Dirs[I] <> '') and (Dirs[I] <> Current) then
      DelTree(Dirs[I], True, True, True);
end;

procedure RemoveLegacyRegistry();
var
  Names: TArrayOfString;
  I: Integer;
begin
  if RegGetSubkeyNames(HKEY_CURRENT_USER, 'Software\AlexPochmak', Names) then
    for I := 0 to GetArrayLength(Names) - 1 do
      if IsVersionedName(Names[I]) then
        RegDeleteKeyIncludingSubkeys(HKEY_CURRENT_USER, 'Software\AlexPochmak\' + Names[I]);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Codes, Dirs: TArrayOfString;
  I: Integer;
begin
  Result := '';

  SetArrayLength(Codes, 0);
  SetArrayLength(Dirs, 0);
  ScanUninstallRoot(HKLM64, UninstallKey, Codes, Dirs);
  ScanUninstallRoot(HKLM32, UninstallKey, Codes, Dirs);
  ScanUninstallRoot(HKCU, UninstallKey, Codes, Dirs);
  ScanUninstallRoot(HKCU32, UninstallKey, Codes, Dirs);

  ScanLegacyDir(ExpandConstant('{commonpf}'), Dirs);
  ScanLegacyDir(ExpandConstant('{commonpf32}'), Dirs);
  ScanLegacyDir(ExpandConstant('{localappdata}\Programs'), Dirs);
  ScanLegacyDir(ExpandConstant('{localappdata}'), Dirs);

  if (GetArrayLength(Codes) = 0) and (GetArrayLength(Dirs) = 0) then Exit;

  StopLegacyProcesses();

  for I := 0 to GetArrayLength(Codes) - 1 do
  begin
    if not UninstallProduct(Codes[I]) then
    begin
      Result := 'Не удалось удалить старую версию Liquid Launcher (' +
        Codes[I] + '). Установка отменена.';
      Exit;
    end;
  end;

  RemoveLegacyDirs(Dirs);
  RemoveLegacyRegistry();
end;

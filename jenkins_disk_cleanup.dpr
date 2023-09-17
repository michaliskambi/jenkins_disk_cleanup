uses SysUtils, DateUtils,
  CastleFindFiles, CastleLog, CastleStringUtils, CastleFilesUtils,
  CastleUtils,
  ToolCommonUtils;

const
  { Delete builds older than this number of days. }
  DeleteWhenOlderThanDays = 40;

  { Keep this many last builds.
    They will not be deleted, even if older than DeleteWhenOlderThanDays. }
  KeepLastBuilds = 5;

  BaseJenkinsJobsDir = '/var/lib/jenkins/jobs';

{ Get the last modification time of a directory.
  Returns @false if cannot get the time. (e.g. because the directory doesn't
  exist, or user doesn't have permissions to get this data).

  Implemented because FPC FileAge doesn't work for directories,
  documented: https://www.freepascal.org/docs-html/rtl/sysutils/fileage.html .
  Similar to solution on https://forum.lazarus.freepascal.org/index.php?topic=14090.0
  Note: Alternative satisfactory solution would be Unix-specific code,
  https://forum.lazarus.freepascal.org/index.php?topic=60580.0 . }
function DirectoryAge(const DirectoryName: String; out Age: TDateTime): Boolean;
var
  Rec: TSearchRec;
begin
  if FindFirst(DirectoryName, faAnyFile or faDirectory, Rec) = 0 then
  begin
    Age := Rec.TimeStamp;
    FindClose(Rec);
    Result := Rec.Time <> 0; // check whether Time looks sensible
  end else
  begin
    Result := false;
  end;
end;

var
  SizeAll, SizeAllToFree, SizeInBranch, SizeInBranchToFree: QWord;

procedure FindBuildDir(const FileInfo: TFileInfo; Data: Pointer; var StopSearch: boolean);
var
  BuildNumber: Integer;
  DirSize: QWord;
  DirAge: TDateTime;
begin
  // consider only builds with name being a number
  if TryStrToInt(FileInfo.Name, BuildNumber) then
  begin
    DirSize := DirectorySize(FileInfo.AbsoluteName);
    SizeAll += DirSize;
    SizeInBranch += DirSize;

    if not DirectoryAge(FileInfo.AbsoluteName, DirAge) then
    begin
      Writeln('WARNING: Cannot get file age for ' + FileInfo.AbsoluteName);
      Exit;
    end;

    if DaysBetween(Now, DirAge) > DeleteWhenOlderThanDays then
    begin
      SizeAllToFree += DirSize;
      SizeInBranchToFree += DirSize;
      // TODO: actually delete, if not DryRun
      // TODO: honor KeepLastBuilds
      // TODO: do not delete builds indicated by symlinks "last successful" etc.
    end;
  end;
end;

procedure FindBranchDir(const FileInfo: TFileInfo; Data: Pointer; var StopSearch: boolean);
begin
  if not FileInfo.Directory then
    Exit;
  SizeInBranch := 0;
  SizeInBranchToFree := 0;
  FindFiles(InclPathDelim(FileInfo.AbsoluteName) + 'builds', '*',
    true, @FindBuildDir, nil, []);
  Writeln(Format('  Branch: ' + FileInfo.Name + ' (to free: %s, total: %s)', [
    SizeToStr(SizeInBranchToFree),
    SizeToStr(SizeInBranch)
  ]));
  Flush(Output); // see results immediately, while sizes of next dirs is calculated
end;

procedure ProcessBranchesDir(const BranchesDir: String);
begin
  Writeln('Job: ', ExtractFileDir(BranchesDir));
  FindFiles(BranchesDir, '*', true, @FindBranchDir, nil, []);
end;

procedure CheckDiskUsage;
begin
  Writeln('Disk usage on :' + BaseJenkinsJobsDir);
  RunCommandSimple('df', ['-h', BaseJenkinsJobsDir]);
end;

var
  FindResultsStr, RelativeBranchesDir: String;
  FindResults: TCastleStringList;
  FindExitStatus: Integer;
begin
  CheckDiskUsage;

  RunCommandIndirPassthrough(BaseJenkinsJobsDir, '/usr/bin/find',
    ['-maxdepth', '4', '-type', 'd', '-name', 'branches'],
    FindResultsStr, FindExitStatus);
  if FindExitStatus <> 0 then
    raise Exception.CreateFmt('find failed with exit status %d', [FindExitStatus]);

  FindResults := TCastleStringList.Create;
  try
    FindResults.Text := FindResultsStr;
    Writeln(Format('Got %d dirs with builds', [FindResults.Count]));
    for RelativeBranchesDir in FindResults do
      ProcessBranchesDir(CombinePaths(BaseJenkinsJobsDir, RelativeBranchesDir));
  finally FreeAndNil(FindResults) end;

  Writeln(Format('  Total: to free: %s, everything: %s', [
    SizeToStr(SizeAllToFree),
    SizeToStr(SizeAll)
  ]));

  CheckDiskUsage;
end.

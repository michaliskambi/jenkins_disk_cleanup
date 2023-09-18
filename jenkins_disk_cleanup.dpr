uses SysUtils, DateUtils,
  CastleFindFiles, CastleLog, CastleStringUtils, CastleFilesUtils,
  CastleUtils,
  ToolCommonUtils;

const
  { Delete builds older than this number of days. }
  DeleteWhenOlderThanDays = 40;

  { Keep this many last builds.
    They will not be deleted, even if older than DeleteWhenOlderThanDays. }
  KeepLastBuilds = 10;

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
var
  BranchPermalinks: TIntegerList;

  { Read permalinks Jenkins file (with "last successfull" etc.),
    put all numbers into Permalinks.
    We don't differentiate between them (what is "last successfull",
    "last failed") because they all should be protected from deletion.

    Sample file contents:

      lastCompletedBuild 2
      lastFailedBuild 2
      lastStableBuild -1
      lastSuccessfulBuild -1
      lastUnstableBuild -1
      lastUnsuccessfulBuild 2
  }
  procedure ReadPermalinks(const FileName: String; Permalinks: TIntegerList);
  var
    Lines: TCastleStringList;
    Line, Token: String;
    SeekPos, BuildNum: Integer;
  begin
    Permalinks.Clear;
    Lines := TCastleStringList.Create;
    try
      Lines.LoadFromFile(FileName);
      for Line in Lines do
        if Trim(Line) <> '' then
        begin
          SeekPos := 1;

          Token := NextToken(Line, SeekPos);
          if Token = '' then
            raise Exception.CreateFmt('Cannot read 1st token in line "%s" from file "%s"', [
              Line,
              FileName
            ]);

          Token := NextToken(Line, SeekPos);
          if Token = '' then
            raise Exception.CreateFmt('Cannot read 2nd token in line "%s" from file "%s"', [
              Line,
              FileName
            ]);

          BuildNum := StrToInt(Token);
          if BuildNum >= 0 then
            Permalinks.Add(BuildNum)
          else
          if BuildNum <> -1 then
            raise Exception.CreateFmt('Unexpected negative build number "%d" in file "%s"', [
              BuildNum,
              FileName
            ]);
        end;
    finally FreeAndNil(Lines) end;
  end;

  function PermalinksToStr(const List: TIntegerList): String;
  var
    I: Integer;
  begin
    Result := '';
    for I in List do
      Result := SAppendPart(Result, ', ', IntToStr(I));
    Result := '[' + Result + ']';
  end;

begin
  if not FileInfo.Directory then
    Exit;

  BranchPermalinks := TIntegerList.Create;
  try
    ReadPermalinks(
      InclPathDelim(FileInfo.AbsoluteName) + 'builds' + PathDelim + 'permalinks',
      BranchPermalinks);

    // TODO: BranchBuildToKeep := GetMinimumBuildToKeep(BranchPermalinks) - KeepLastBuilds;

    SizeInBranch := 0;
    SizeInBranchToFree := 0;
    FindFiles(InclPathDelim(FileInfo.AbsoluteName) + 'builds', '*',
      true, @FindBuildDir, nil, []);
    Writeln(Format('  Branch: ' + FileInfo.Name + '. To free: %s, total: %s. Permalinks: %s', [
      SizeToStr(SizeInBranchToFree),
      SizeToStr(SizeInBranch),
      PermalinksToStr(BranchPermalinks)
    ]));
    Flush(Output); // see results immediately, while sizes of next dirs is calculated

  finally FreeAndNil(BranchPermalinks) end;
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

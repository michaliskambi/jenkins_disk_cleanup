uses SysUtils, DateUtils,
  CastleFindFiles, CastleLog, CastleStringUtils, CastleFilesUtils,
  CastleUtils, CastleParameters, CastleApplicationProperties,
  ToolCommonUtils;

const
  { Delete builds older than this number of days. }
  DeleteWhenOlderThanDays = 40;

  { Keep this many last builds.
    They will not be deleted, even if older than DeleteWhenOlderThanDays. }
  KeepLastBuilds = 10;

  BaseJenkinsJobsDir = '/var/lib/jenkins/jobs';

var
  { Set to @false to actually delete. }
  DryRun: Boolean = true;

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
  SizeAll, SizeAllFreed: QWord;

{ TOneBranchProcessor -------------------------------------------------------- }

type
  TOneBranchProcessor = class
  strict private
    SizeInBranch, SizeInBranchFreed: QWord;

    { Filled with permalink numbers ("last succesfull" etc.)
      before ProcessBuildDir is called.
      Contains only numbers >= 0 (that look like actual build numbers). }
    BranchPermalinks: TIntegerList;

    procedure ProcessBuildDir(const FileInfo: TFileInfo; var StopSearch: boolean);

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
    class procedure ReadPermalinks(const FileName: String;
      const Permalinks: TIntegerList); static;
  public
    constructor Create;
    destructor Destroy; override;
    procedure ProcessOneBranch(const BranchDir: String);
  end;

constructor TOneBranchProcessor.Create;
begin
  inherited;
  BranchPermalinks := TIntegerList.Create;
end;

destructor TOneBranchProcessor.Destroy;
begin
  FreeAndNil(BranchPermalinks);
  inherited;
end;

procedure TOneBranchProcessor.ProcessBuildDir(const FileInfo: TFileInfo; var StopSearch: boolean);

  function BuildNumberCanBeRemoved(const BuildNumber: Integer): Boolean;
  var
    PermalinkNumber: Integer;
  begin
    for PermalinkNumber in BranchPermalinks do
      if Between(BuildNumber, PermalinkNumber - KeepLastBuilds + 1, PermalinkNumber) then
        Exit(false);
    Result := true;
  end;

var
  BuildNumber, AgeInDays: Integer;
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

    AgeInDays := DaysBetween(Now, DirAge);
    if AgeInDays > DeleteWhenOlderThanDays then
      if BuildNumberCanBeRemoved(BuildNumber) then
      begin
        SizeAllFreed += DirSize;
        SizeInBranchFreed += DirSize;
        Writeln(Format('    %s %d, age %dd', [
          Iff(DryRun, 'Would remove', 'Removing'),
          BuildNumber,
          AgeInDays
        ]));
        if not DryRun then
          RemoveNonEmptyDir(FileInfo.AbsoluteName);
    end;
  end;
end;

class procedure TOneBranchProcessor.ReadPermalinks(const FileName: String;
  const Permalinks: TIntegerList); static;
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

procedure TOneBranchProcessor.ProcessOneBranch(const BranchDir: String);

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
  ReadPermalinks(
    InclPathDelim(BranchDir) + 'builds' + PathDelim + 'permalinks',
    BranchPermalinks);

  SizeInBranch := 0;
  SizeInBranchFreed := 0;
  FindFiles(InclPathDelim(BranchDir) + 'builds', '*', true, @ProcessBuildDir, []);
  Writeln(Format('  Branch: ' + ExtractFileName(BranchDir) + '. Removed: %s, total: %s. Permalinks: %s', [
    SizeToStr(SizeInBranchFreed),
    SizeToStr(SizeInBranch),
    PermalinksToStr(BranchPermalinks)
  ]));
  Flush(Output); // see results immediately, while sizes of next dirs is calculated
end;

{ end of TOneBranchProcessor -------------------------------------------------------- }

procedure FindBranchDir(const FileInfo: TFileInfo; Data: Pointer; var StopSearch: boolean);
var
  OneBranchProcessor: TOneBranchProcessor;
begin
  if not FileInfo.Directory then
    Exit;

  OneBranchProcessor := TOneBranchProcessor.Create;
  try
    OneBranchProcessor.ProcessOneBranch(FileInfo.AbsoluteName);
  finally FreeAndNil(OneBranchProcessor) end;
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
  InitializeLog;
  // no need, log will go to console by default on Unix
  //ApplicationProperties.OnWarning.Add(@ApplicationProperties.WriteWarningOnConsole);

  CheckDiskUsage;

  { Parse --really-remove param }
  Parameters.CheckHighAtMost(1);
  if Parameters.High = 1 then
  begin
    if Parameters[1] = '--really-remove' then
      DryRun := false
    else
      raise EInvalidParams.CreateFmt('Invalid 1st param %s', [Parameters[1]]);
  end;

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

  Writeln(Format('  Summary: Removed: %s, total: %s', [
    SizeToStr(SizeAllFreed),
    SizeToStr(SizeAll)
  ]));

  CheckDiskUsage;
end.

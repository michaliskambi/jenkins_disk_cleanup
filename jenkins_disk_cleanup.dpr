uses SysUtils,
  CastleFindFiles, CastleLog;

procedure FindFilesCallback(const FileInfo: TFileInfo; Data: Pointer; var StopSearch: boolean);
begin
  WritelnLog('FindFiles', 'Found URL:%s, Name:%s, AbsoluteName:%s, Directory:%s',
    [FileInfo.URL, FileInfo.Name, FileInfo.AbsoluteName, BoolToStr(FileInfo.Directory, true)]);
end;

begin
  FindFiles('/var/lib/jenkins/jobs', 'branches',
    true, @FindFilesCallback, nil, [ffRecursive]);
end.

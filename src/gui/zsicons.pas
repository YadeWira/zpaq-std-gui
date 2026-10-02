{ zsicons: the program's icons (PeaZip art recoloured to coral, linked from icons/gen/zsicons.res)
  in multi-resolution image lists with one fixed index per name, single pictures in the size that
  fits the screen DPI, and the list icon of a file name by its extension. Light set until M8. }
unit zsicons;

{$mode objfpc}{$H+}

(* Public API

  Resources: icons/gen/zsicons.res (tools/make-icons.py; see icons/MAPPING.md). Every name exists as
  RCDATA '<NAME>_<SIZE>' (a PNG) at 16 24 32 36 48 72 96 px, APP also at 128 160 192 256; a name
  may also have '<NAME>_<SIZE>_DARK' (only TB_MENU today).

  TIconId                       one value per resource name, in IconResNames order
  IconIndex(Id): Integer        the index of Id in SmallImages, BigImages and (for the toolbar
                                names, icoOpen..LastToolbarIcon) ToolbarImages. The same index in
                                every list, so one TAction.ImageIndex serves the toolbar and menus.
  InitIcons(Dark)               creates SmallImages and ToolbarImages, owned by Application. Call
                                once, after Application.Initialize and before the first form.
  SmallImages                   16 px at 96 PPI (24, 32 registered): list, menus, path bar
  ToolbarImages                 24 px at 96 PPI (36, 48): toolbar names only
  BigImages                     48 px at 96 PPI (72, 96): dialogs, progress header, type icons;
                                created on first use
  LoadIconPng(Name, Size, Dark) one resource as a new PNG (the caller frees it); the _DARK variant
                                when Dark and it exists; raises EResNotFound for an unknown name
  LoadIconPicture(Id, Wanted)   new PNG of the smallest size >= Wanted pixels (the biggest if none),
                                for a TImage whose size is already scaled to the screen
  FileIconId(Name, IsFolder)    list icon for an entry: folder, archive types, documents... by the
                                extension of Name (case-insensitive); icoFtFile when unknown
*)

interface

uses
  Classes, SysUtils, Graphics, Controls, Forms, ImgList, LCLType;

type
  TIconId = (
    // toolbar: also the only names in ToolbarImages, so they come first
    icoOpen, icoCreate, icoAdd, icoExtract, icoExtractTo, icoTest, icoInfo, icoCloseArchive,
    icoSettings, icoMenu,
    // menus and path bar
    icoUp, icoSearch, icoReload, icoCopy, icoDelete,
    // dialogs and the encrypted overlay
    icoKey, icoLock, icoOk, icoWarn, icoError, icoInfoDlg,
    // progress header
    icoOpAdd, icoOpExtract, icoOpTest,
    // big type icons (Properties header)
    icoTypeZpaq, icoType7z, icoTypeRar, icoTypeZip, icoTypeArchive, icoTypeDisc, icoTypeOther,
    // file list
    icoFtFolder, icoFtZpaq, icoFt7z, icoFtRar, icoFtZip, icoFtArchive, icoFtDisc, icoFtText,
    icoFtConfig, icoFtCode, icoFtImage, icoFtAudio, icoFtVideo, icoFtPdf, icoFtSheet, icoFtSlides,
    icoFtExe, icoFtLink, icoFtMail, icoFtFile,
    // application box
    icoApp);

const
  LastToolbarIcon = icoMenu;

  IconResNames: array[TIconId] of string = (
    'TB_OPEN', 'TB_CREATE', 'TB_ADD', 'TB_EXTRACT', 'TB_EXTRACT_TO', 'TB_TEST', 'TB_INFO',
    'TB_CLOSE', 'TB_SETTINGS', 'TB_MENU',
    'MI_UP', 'MI_SEARCH', 'MI_RELOAD', 'MI_COPY', 'MI_DELETE',
    'DLG_KEY', 'OV_LOCK', 'DLG_OK', 'DLG_WARN', 'DLG_ERROR', 'DLG_INFO',
    'OP_ADD', 'OP_EXTRACT', 'OP_TEST',
    'TYPE_ZPAQ', 'TYPE_7Z', 'TYPE_RAR', 'TYPE_ZIP', 'TYPE_ARCHIVE', 'TYPE_DISC', 'TYPE_OTHER',
    'FT_FOLDER', 'FT_ZPAQ', 'FT_7Z', 'FT_RAR', 'FT_ZIP', 'FT_ARCHIVE', 'FT_DISC', 'FT_TEXT',
    'FT_CONFIG', 'FT_CODE', 'FT_IMAGE', 'FT_AUDIO', 'FT_VIDEO', 'FT_PDF', 'FT_SHEET', 'FT_SLIDES',
    'FT_EXE', 'FT_LINK', 'FT_MAIL', 'FT_FILE',
    'APP');

function IconIndex(Id: TIconId): Integer;
procedure InitIcons(Dark: Boolean);
function SmallImages: TImageList;
function ToolbarImages: TImageList;
function BigImages: TImageList;
function LoadIconPng(const Name: string; Size: Integer; Dark: Boolean): TPortableNetworkGraphic;
function LoadIconPicture(Id: TIconId; Wanted: Integer): TPortableNetworkGraphic;
function FileIconId(const FileName: string; IsFolder: Boolean): TIconId;

implementation

{$R ../../icons/gen/zsicons.res}

const
  SmallSizes: array[0..2] of Integer = (16, 24, 32);
  ToolbarSizes: array[0..2] of Integer = (24, 36, 48);
  BigSizes: array[0..2] of Integer = (48, 72, 96);
  AllSizes: array[0..10] of Integer = (16, 24, 32, 36, 48, 72, 96, 128, 160, 192, 256);

  { list icons by extension; each list is ' ext ext ... ' }
  FileTypes: array[0..17] of record
    Exts: string;
    Id: TIconId;
  end = (
    (Exts: ' zpaq '; Id: icoFtZpaq),
    (Exts: ' 7z '; Id: icoFt7z),
    (Exts: ' rar '; Id: icoFtRar),
    (Exts: ' zip zipx jar apk '; Id: icoFtZip),
    (Exts: ' tar gz tgz xz txz bz2 tbz2 zst tzst lz lz4 br cab wim cpio '; Id: icoFtArchive),
    (Exts: ' iso img udf dmg vhd vhdx '; Id: icoFtDisc),
    (Exts: ' txt md log nfo rtf doc docx odt '; Id: icoFtText),
    (Exts: ' ini cfg conf reg inf toml yaml yml '; Id: icoFtConfig),
    (Exts: ' pas pp lpr inc c h cpp hpp py js ts html htm css xml json java cs go rs php lua ';
      Id: icoFtCode),
    (Exts: ' png jpg jpeg gif bmp webp tif tiff ico svg heic '; Id: icoFtImage),
    (Exts: ' mp3 flac wav ogg opus m4a aac wma '; Id: icoFtAudio),
    (Exts: ' mp4 mkv avi mov webm wmv flv m4v '; Id: icoFtVideo),
    (Exts: ' pdf '; Id: icoFtPdf),
    (Exts: ' xls xlsx ods csv tsv '; Id: icoFtSheet),
    (Exts: ' ppt pptx odp '; Id: icoFtSlides),
    (Exts: ' exe dll sys com msi bat cmd ps1 sh '; Id: icoFtExe),
    (Exts: ' lnk url desktop '; Id: icoFtLink),
    (Exts: ' eml msg mbox '; Id: icoFtMail));

var
  FDark: Boolean;
  FSmall, FToolbar, FBig: TImageList;

function IconIndex(Id: TIconId): Integer;
begin
  Result := Ord(Id);
end;

function IconResName(const Name: string; Size: Integer; Dark: Boolean): string;
begin
  Result := Name + '_' + IntToStr(Size);
  if Dark and (FindResource(HInstance, PChar(Result + '_DARK'), RT_RCDATA) <> 0) then
    Result := Result + '_DARK';
end;

function LoadIconPng(const Name: string; Size: Integer; Dark: Boolean): TPortableNetworkGraphic;
begin
  Result := TPortableNetworkGraphic.Create;
  try
    Result.LoadFromResourceName(HInstance, IconResName(Name, Size, Dark));
  except
    Result.Free;
    raise;
  end;
end;

{ one entry in List per name First..Last, each with every size of Sizes (smallest first) }
procedure FillList(List: TImageList; First, Last: TIconId; const Sizes: array of Integer);
var
  Id: TIconId;
  Pngs: array of TCustomBitmap;
  I: Integer;
begin
  Pngs := nil;
  for Id := First to Last do
  begin
    SetLength(Pngs, Length(Sizes));
    for I := 0 to High(Pngs) do
      Pngs[I] := nil;
    try
      for I := 0 to High(Sizes) do
        Pngs[I] := LoadIconPng(IconResNames[Id], Sizes[I], FDark);
      List.AddMultipleResolutions(Pngs);
    finally
      for I := 0 to High(Pngs) do
        Pngs[I].Free;
    end;
  end;
end;

function NewList(const Sizes: array of Integer): TImageList;
begin
  Result := TImageList.Create(Application);
  Result.Width := Sizes[0];
  Result.Height := Sizes[0];
  Result.Scaled := True;
  Result.RegisterResolutions(Sizes);
end;

procedure InitIcons(Dark: Boolean);
begin
  FDark := Dark;
  if FSmall = nil then
  begin
    FSmall := NewList(SmallSizes);
    FillList(FSmall, Low(TIconId), High(TIconId), SmallSizes);
  end;
  if FToolbar = nil then
  begin
    FToolbar := NewList(ToolbarSizes);
    FillList(FToolbar, Low(TIconId), LastToolbarIcon, ToolbarSizes);
  end;
end;

function SmallImages: TImageList;
begin
  Assert(FSmall <> nil, 'InitIcons was not called');
  Result := FSmall;
end;

function ToolbarImages: TImageList;
begin
  Assert(FToolbar <> nil, 'InitIcons was not called');
  Result := FToolbar;
end;

function BigImages: TImageList;
begin
  if FBig = nil then
  begin
    FBig := NewList(BigSizes);
    FillList(FBig, Low(TIconId), High(TIconId), BigSizes);
  end;
  Result := FBig;
end;

function LoadIconPicture(Id: TIconId; Wanted: Integer): TPortableNetworkGraphic;
var
  I, Size: Integer;
begin
  Size := 0;
  for I := 0 to High(AllSizes) do
    if FindResource(HInstance, PChar(IconResNames[Id] + '_' + IntToStr(AllSizes[I])),
      RT_RCDATA) <> 0 then
    begin
      Size := AllSizes[I];
      if Size >= Wanted then
        Break;
    end;
  if Size = 0 then
    raise EResNotFound.CreateFmt('No icon resource for %s', [IconResNames[Id]]);
  Result := LoadIconPng(IconResNames[Id], Size, FDark);
end;

function FileIconId(const FileName: string; IsFolder: Boolean): TIconId;
var
  Ext: string;
  I: Integer;
begin
  if IsFolder then
    Exit(icoFtFolder);
  Ext := LowerCase(ExtractFileExt(FileName));
  if Length(Ext) < 2 then
    Exit(icoFtFile);
  Ext := ' ' + Copy(Ext, 2, MaxInt) + ' ';
  for I := Low(FileTypes) to High(FileTypes) do
    if Pos(Ext, FileTypes[I].Exts) > 0 then
      Exit(FileTypes[I].Id);
  Result := icoFtFile;
end;

end.

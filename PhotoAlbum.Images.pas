unit PhotoAlbum.Images;

{ Thumbnail generation and original-file copying using Skia4Delphi.
  Cross-platform: runs unchanged on Windows and Linux.

  For each photo in an album two output files are produced:
    thumbs/<filename>  — JPEG resized to ThumbWidth, EXIF-rotation corrected
    full/<filename>    — the original file copied byte-for-byte (no re-encode)

  EXIF orientation is read directly from the raw JPEG bytes (no external lib).
  Skia handles decode, scale, and re-encode. }

interface

uses
  System.SysUtils,
  System.IOUtils;

type
  TThumbSize = record
    Width:  Integer;
    Height: Integer;
  end;

  TImageProcessor = class
  private
    FThumbWidth:   Integer;
    FThumbQuality: Integer;
    { Returns the EXIF Orientation tag value (1–8), or 1 if absent/unreadable. }
    function ReadExifOrientation(const APath: string): Integer;
  public
    constructor Create(AThumbWidth, AThumbQuality: Integer);

    { Decode ASrcPath, apply EXIF rotation, scale to ThumbWidth, write JPEG.
      Returns the actual pixel dimensions of the written thumbnail. }
    function GenerateThumb(const ASrcPath, ADestPath: string): TThumbSize;

    { Copy the source file to ADestPath without any re-encoding. }
    procedure CopyOriginal(const ASrcPath, ADestPath: string);
  end;

implementation

uses
  System.Classes,
  System.Math,
  System.Types,
  System.UITypes,
  Skia;

{ ── EXIF orientation reader ──────────────────────────────────────────────── }
{ Reads only the bytes needed: SOI marker, then the APP1 TIFF block.
  Handles both little-endian (II) and big-endian (MM) TIFF byte orders. }

function TImageProcessor.ReadExifOrientation(const APath: string): Integer;
var
  F:   TFileStream;
  B:   array[0..11] of Byte;
  LE:  Boolean;     // little-endian TIFF?
  TiffBase: Int64;
  IFDOff:   Cardinal;
  NEntries: Word;
  I:        Integer;
  Tag:      Word;

  function RW(off: Integer): Word;
  begin
    if LE then Result := B[off] or (B[off+1] shl 8)
    else        Result := (B[off] shl 8) or B[off+1];
  end;

  function RD(off: Integer): Cardinal;
  begin
    if LE then Result := B[off] or (B[off+1] shl 8) or
                         (B[off+2] shl 16) or (B[off+3] shl 24)
    else        Result := (B[off] shl 24) or (B[off+1] shl 16) or
                          (B[off+2] shl 8) or B[off+3];
  end;

begin
  Result := 1;
  try
    F := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
    try
      { Need at least SOI + one segment header }
      if F.Size < 4 then Exit;

      { Verify JPEG SOI }
      F.ReadBuffer(B, 2);
      if (B[0] <> $FF) or (B[1] <> $D8) then Exit;

      { Walk segments to find APP1 }
      while F.Position + 4 <= F.Size do
      begin
        F.ReadBuffer(B, 4); // marker(2) + length(2)
        if B[0] <> $FF then Exit;

        var Marker := B[1];
        var SegLen: Word := (B[2] shl 8) or B[3]; // big-endian, includes itself

        if Marker = $E1 then  // APP1
        begin
          if SegLen < 8 then Exit;

          { Check 'Exif\0\0' magic }
          F.ReadBuffer(B, 6);
          if not ((B[0] = Ord('E')) and (B[1] = Ord('x')) and
                  (B[2] = Ord('i')) and (B[3] = Ord('f'))) then Exit;

          TiffBase := F.Position;  // TIFF header starts here

          { TIFF byte order }
          F.ReadBuffer(B, 2);
          LE := (B[0] = $49);  // 'II' = little-endian, 'MM' = big-endian

          F.ReadBuffer(B, 2);  // magic 42 — skip
          F.ReadBuffer(B, 4);  // IFD0 offset from TiffBase
          IFDOff := RD(0);

          F.Seek(TiffBase + IFDOff, soBeginning);
          F.ReadBuffer(B, 2);
          NEntries := RW(0);

          for I := 0 to NEntries - 1 do
          begin
            if F.Read(B, 12) < 12 then Exit;
            Tag := RW(0);
            if Tag = $0112 then  // Orientation
            begin
              { Type=SHORT (3), Count=1; value is in bytes 8-9 }
              Result := RW(8);
              if Result < 1 then Result := 1;
              if Result > 8 then Result := 1;
              Exit;
            end;
          end;
          Exit; // APP1 processed, no orientation tag found
        end
        else if Marker in [$D9, $DA] then
          Exit  // EOI / SOS — no more headers
        else
          F.Seek(SegLen - 2, soCurrent); // skip payload
      end;
    finally
      F.Free;
    end;
  except
    Result := 1;
  end;
end;

{ ── TImageProcessor ──────────────────────────────────────────────────────── }

constructor TImageProcessor.Create(AThumbWidth, AThumbQuality: Integer);
begin
  inherited Create;
  FThumbWidth   := AThumbWidth;
  FThumbQuality := AThumbQuality;
end;

function TImageProcessor.GenerateThumb(const ASrcPath,
                                        ADestPath: string): TThumbSize;
var
  LSrc:     ISkImage;
  LOrient:  Integer;
  LSrcW, LSrcH:   Integer;
  LDispW, LDispH: Integer;   // visual dimensions after rotation
  LDstW, LDstH:   Integer;   // thumbnail canvas size
  LDrawW, LDrawH: Integer;   // draw rect in the (possibly-rotated) canvas space
  LSurface: ISkSurface;
  LCanvas:  ISkCanvas;
  LSampling: TSkSamplingOptions;
begin
  LSrc := TSkImage.MakeFromEncodedFile(ASrcPath);
  if LSrc = nil then
    raise Exception.CreateFmt('Cannot load image: %s', [ASrcPath]);

  LOrient := ReadExifOrientation(ASrcPath);
  LSrcW   := LSrc.Width;
  LSrcH   := LSrc.Height;

  { Orientations 5–8 swap width ↔ height for display }
  if LOrient in [5, 6, 7, 8] then
  begin
    LDispW := LSrcH;
    LDispH := LSrcW;
  end
  else
  begin
    LDispW := LSrcW;
    LDispH := LSrcH;
  end;

  { Scale to thumb width, preserving aspect ratio }
  LDstW := FThumbWidth;
  LDstH := Max(1, Round(LDispH * (FThumbWidth / LDispW)));

  Result.Width  := LDstW;
  Result.Height := LDstH;

  { The draw rect lives in the (possibly rotated) canvas space.
    After a 90/270° rotation the canvas axes are swapped, so the
    rect that fills the canvas has its dimensions transposed. }
  if LOrient in [5, 6, 7, 8] then
  begin
    LDrawW := LDstH;
    LDrawH := LDstW;
  end
  else
  begin
    LDrawW := LDstW;
    LDrawH := LDstH;
  end;

  LSurface := TSkSurface.MakeRaster(TSkImageInfo.Create(LDstW, LDstH));
  if LSurface = nil then
    raise Exception.CreateFmt('Cannot create surface for: %s', [ASrcPath]);

  LCanvas  := LSurface.Canvas;
  LCanvas.Clear(TAlphaColors.White);
  LSampling := TSkSamplingOptions.Create(TSkCubicResampler.Mitchell);

  LCanvas.Save;
  try
    { Rotate canvas to correct the EXIF orientation before drawing }
    case LOrient of
      2: begin LCanvas.Translate(LDstW, 0);        LCanvas.Scale(-1, 1);  end;
      3: begin LCanvas.Translate(LDstW, LDstH);    LCanvas.Rotate(180);   end;
      4: begin LCanvas.Translate(0, LDstH);        LCanvas.Scale(1, -1);  end;
      5: begin LCanvas.Rotate(90);  LCanvas.Scale(1, -1); end;
      6: begin LCanvas.Translate(LDstW, 0);        LCanvas.Rotate(90);    end;
      7: begin LCanvas.Translate(LDstW, LDstH); LCanvas.Rotate(90); LCanvas.Scale(1, -1); end;
      8: begin LCanvas.Translate(0, LDstH);        LCanvas.Rotate(270);   end;
      // orientation 1: no transform
    end;

    LCanvas.DrawImageRect(LSrc,
      TRectF.Create(0, 0, LSrcW, LSrcH),
      TRectF.Create(0, 0, LDrawW, LDrawH),
      LSampling);
  finally
    LCanvas.Restore;
  end;

  { Write thumbnail }
  TDirectory.CreateDirectory(TPath.GetDirectoryName(ADestPath));
  var LSnap := LSurface.MakeImageSnapshot;
  if not LSnap.EncodeToFile(ADestPath, TSkEncodedImageFormat.JPEG, FThumbQuality) then
    raise Exception.CreateFmt('Failed to encode thumbnail: %s', [ADestPath]);
end;

procedure TImageProcessor.CopyOriginal(const ASrcPath, ADestPath: string);
begin
  TDirectory.CreateDirectory(TPath.GetDirectoryName(ADestPath));
  TFile.Copy(ASrcPath, ADestPath, True);
end;

end.

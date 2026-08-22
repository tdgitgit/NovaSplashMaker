# Nova Splash + Boot Animation Maker v1.6 FIXED3 FIXED
# Retroid Pocket Nova splash generator/flasher + Magisk boot animation maker.
# No USB debugging is required for generation or Fastboot flashing.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -AssemblyName System.IO.Compression

Add-Type -AssemblyName System.IO.Compression.FileSystem

$ErrorActionPreference = "Stop"

$codec = @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class NovaSplashCodec
{
    public const int Width = 1280;
    public const int Height = 960;
    public const long PartitionSize = 33554432; // 0x2000000
    public const int BmpOffset = 0x4000;
    public const int PixelOffset = 1078; // 14 + 40 + 256*4
    public const int PixelBytes = Width * Height;
    public const int DeclaredImageBytes = PixelBytes + 2;
    public const int BmpSize = PixelOffset + DeclaredImageBytes;

    public static Bitmap Compose(string inputPath, string mode, Color background)
    {
        using (Image src = Image.FromFile(inputPath))
        {
            Bitmap dst = new Bitmap(Width, Height, PixelFormat.Format24bppRgb);
            dst.SetResolution(72, 72);

            using (Graphics g = Graphics.FromImage(dst))
            {
                g.Clear(background);
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.SmoothingMode = SmoothingMode.HighQuality;
                g.CompositingQuality = CompositingQuality.HighQuality;

                RectangleF r;
                if (mode == "Stretch")
                {
                    r = new RectangleF(0, 0, Width, Height);
                }
                else
                {
                    float sx = (float)Width / src.Width;
                    float sy = (float)Height / src.Height;
                    float scale = mode == "Fill / Crop" ? Math.Max(sx, sy) : Math.Min(sx, sy);
                    float w = src.Width * scale;
                    float h = src.Height * scale;
                    r = new RectangleF((Width - w) / 2f, (Height - h) / 2f, w, h);
                }
                g.DrawImage(src, r);
            }
            return dst;
        }
    }

    private static byte Rgb332Index(byte r, byte g, byte b)
    {
        return (byte)(((r >> 5) << 5) | ((g >> 5) << 2) | (b >> 6));
    }

    private static byte Expand3(int v) { return (byte)Math.Round(v * 255.0 / 7.0); }
    private static byte Expand2(int v) { return (byte)Math.Round(v * 255.0 / 3.0); }

    public static void BuildSplash(Bitmap source, string outputPath)
    {
        if (source.Width != Width || source.Height != Height)
            throw new ArgumentException("Source bitmap must be 1280x960.");

        using (FileStream fs = new FileStream(outputPath, FileMode.Create, FileAccess.ReadWrite, FileShare.None))
        using (BinaryWriter bw = new BinaryWriter(fs))
        {
            fs.SetLength(PartitionSize);

            // Nova splash partition header:
            // "DDPH", version 1, then zero padding to 0x4000.
            fs.Position = 0;
            bw.Write((byte)'D');
            bw.Write((byte)'D');
            bw.Write((byte)'P');
            bw.Write((byte)'H');
            bw.Write((byte)1);

            // Embedded BMP starts at 0x4000.
            fs.Position = BmpOffset;

            // BITMAPFILEHEADER (14 bytes)
            bw.Write((byte)'B');
            bw.Write((byte)'M');
            bw.Write(BmpSize);
            bw.Write((ushort)0);
            bw.Write((ushort)0);
            bw.Write(PixelOffset);

            // BITMAPINFOHEADER (40 bytes)
            bw.Write(40);
            bw.Write(Width);
            bw.Write(Height); // positive = bottom-up
            bw.Write((ushort)1);
            bw.Write((ushort)8); // indexed 8-bit
            bw.Write(0); // BI_RGB
            bw.Write(DeclaredImageBytes);
            bw.Write(2834); // stock Nova value
            bw.Write(2834);
            bw.Write(0); // colors used
            bw.Write(0); // important colors

            // RGB332 palette, written as BGRA quads.
            for (int i = 0; i < 256; i++)
            {
                int r3 = (i >> 5) & 7;
                int g3 = (i >> 2) & 7;
                int b2 = i & 3;
                byte r = Expand3(r3);
                byte g = Expand3(g3);
                byte b = Expand2(b2);
                bw.Write(b);
                bw.Write(g);
                bw.Write(r);
                bw.Write((byte)0);
            }

            Rectangle rect = new Rectangle(0, 0, Width, Height);
            BitmapData bits = source.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            try
            {
                int stride = bits.Stride;
                int absStride = Math.Abs(stride);
                byte[] raw = new byte[absStride * Height];
                Marshal.Copy(bits.Scan0, raw, 0, raw.Length);

                byte[] row = new byte[Width];

                // BMP is bottom-up. GDI+ memory can have either stride sign,
                // so calculate the top-origin row safely.
                for (int outY = 0; outY < Height; outY++)
                {
                    int logicalY = Height - 1 - outY;
                    int memY = stride >= 0 ? logicalY : (Height - 1 - logicalY);
                    int basePos = memY * absStride;

                    for (int x = 0; x < Width; x++)
                    {
                        int p = basePos + x * 3;
                        byte b = raw[p + 0];
                        byte g = raw[p + 1];
                        byte r = raw[p + 2];
                        row[x] = Rgb332Index(r, g, b);
                    }
                    bw.Write(row);
                }

                // Stock Nova BMP declares two extra zero bytes.
                bw.Write((byte)0);
                bw.Write((byte)0);
            }
            finally
            {
                source.UnlockBits(bits);
            }
        }

        FileInfo fi = new FileInfo(outputPath);
        if (fi.Length != PartitionSize)
            throw new IOException("Generated splash has wrong size: " + fi.Length);
    }
}
"@

Add-Type -TypeDefinition $codec -ReferencedAssemblies System.Drawing

# ---------------- UI helpers ----------------

function Set-Log([string]$text) {
    $logBox.AppendText($text + [Environment]::NewLine)
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
}

function Save-FastbootPath([string]$path) {
    try {
        $cfg = Join-Path $PSScriptRoot "fastboot_path.txt"
        Set-Content -Path $cfg -Value $path -Encoding UTF8
    } catch {}
}

function Find-Fastboot {
    if ($script:FastbootPath -and (Test-Path $script:FastbootPath)) {
        return $script:FastbootPath
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    # 1) Saved choice from a previous run.
    $cfg = Join-Path $PSScriptRoot "fastboot_path.txt"
    if (Test-Path $cfg) {
        $saved = (Get-Content $cfg -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($saved) { $candidates.Add($saved.Trim()) }
    }

    # 2) Beside this tool.
    $candidates.Add((Join-Path $PSScriptRoot "fastboot.exe"))

    # 3) Common easy locations.
    $candidates.Add("C:\platform-tools\fastboot.exe")
    $candidates.Add((Join-Path $env:USERPROFILE "platform-tools\fastboot.exe"))
    $candidates.Add((Join-Path $env:USERPROFILE "Downloads\platform-tools\fastboot.exe"))
    $candidates.Add((Join-Path $env:USERPROFILE "Desktop\platform-tools\fastboot.exe"))
    $candidates.Add((Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\fastboot.exe"))

    # 4) PATH.
    $cmd = Get-Command fastboot.exe -ErrorAction SilentlyContinue
    if ($cmd) { $candidates.Add($cmd.Source) }

    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) {
            $script:FastbootPath = $c
            $fastbootLabel.Text = "Fastboot: READY"
            $fastbootLabel.ForeColor = [System.Drawing.Color]::LightGreen
            $fastbootPathLabel.Text = $c
            Save-FastbootPath $c
            return $c
        }
    }

    $fastbootLabel.Text = "Fastboot: NOT SET UP"
    $fastbootLabel.ForeColor = [System.Drawing.Color]::Gold
    $fastbootPathLabel.Text = "Click SET UP FASTBOOT once."
    return $null
}

function Show-FastbootSetup {
    $setup = New-Object System.Windows.Forms.Form
    $setup.Text = "Fastboot Setup"
    $setup.ClientSize = New-Object System.Drawing.Size(610, 390)
    $setup.StartPosition = "CenterParent"
    $setup.FormBorderStyle = "FixedDialog"
    $setup.MaximizeBox = $false
    $setup.MinimizeBox = $false
    $setup.BackColor = [System.Drawing.Color]::FromArgb(22,22,24)
    $setup.ForeColor = [System.Drawing.Color]::White
    $setup.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $h = New-Object System.Windows.Forms.Label
    $h.Text = "ONE-TIME FASTBOOT SETUP"
    $h.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 15)
    $h.Location = New-Object System.Drawing.Point(20, 18)
    $h.AutoSize = $true
    $setup.Controls.Add($h)

    $info = New-Object System.Windows.Forms.Label
    $info.Text = "You only need this if you want the tool to FLASH the logo.`r`nGenerating splash.img does NOT need Fastboot.`r`n`r`nRECOMMENDED EASY SETUP:`r`n1. Download Google's Platform Tools for Windows.`r`n2. Extract the ZIP.`r`n3. Move the folder to C:\platform-tools`r`n4. The final file should be: C:\platform-tools\fastboot.exe`r`n5. Return here and click 'Use C:\platform-tools'.`r`n`r`nYou only do this once."
    $info.Location = New-Object System.Drawing.Point(22, 58)
    $info.Size = New-Object System.Drawing.Size(565, 205)
    $setup.Controls.Add($info)

    $download = New-Object System.Windows.Forms.Button
    $download.Text = "1. DOWNLOAD PLATFORM TOOLS"
    $download.Location = New-Object System.Drawing.Point(22, 270)
    $download.Size = New-Object System.Drawing.Size(270, 40)
    $setup.Controls.Add($download)

    $useC = New-Object System.Windows.Forms.Button
    $useC.Text = "2. USE C:\platform-tools"
    $useC.Location = New-Object System.Drawing.Point(310, 270)
    $useC.Size = New-Object System.Drawing.Size(270, 40)
    $setup.Controls.Add($useC)

    $select = New-Object System.Windows.Forms.Button
    $select.Text = "Choose Another Folder..."
    $select.Location = New-Object System.Drawing.Point(22, 320)
    $select.Size = New-Object System.Drawing.Size(270, 36)
    $setup.Controls.Add($select)

    $close = New-Object System.Windows.Forms.Button
    $close.Text = "Close"
    $close.Location = New-Object System.Drawing.Point(430, 320)
    $close.Size = New-Object System.Drawing.Size(150, 36)
    $setup.Controls.Add($close)

    $download.Add_Click({
        Start-Process "https://developer.android.com/tools/releases/platform-tools"
    })

    $useC.Add_Click({
        $fb = "C:\platform-tools\fastboot.exe"
        if (Test-Path $fb) {
            $script:FastbootPath = $fb
            Save-FastbootPath $fb
            $fastbootLabel.Text = "Fastboot: READY"
            $fastbootLabel.ForeColor = [System.Drawing.Color]::LightGreen
            $fastbootPathLabel.Text = $fb
            $statusLabel.Text = "Current step: Put Nova in Fastboot Mode, connect USB, then click CHECK NOVA."
            $statusLabel.ForeColor = [System.Drawing.Color]::LightSkyBlue
            Set-Log "Fastboot setup complete: $fb"
            [System.Windows.Forms.MessageBox]::Show(
                "Fastboot is ready at:`r`nC:\platform-tools\fastboot.exe",
                "Setup complete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
            $setup.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show(
                "Not found:`r`nC:\platform-tools\fastboot.exe`r`n`r`nMake sure you extracted the downloaded ZIP and moved the folder named 'platform-tools' directly into C:\",
                "C:\platform-tools not found",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    })

    $select.Add_Click({
        $folder = New-Object System.Windows.Forms.FolderBrowserDialog
        $folder.Description = "Choose the extracted platform-tools folder"
        if ($folder.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $fb = Join-Path $folder.SelectedPath "fastboot.exe"
            if (Test-Path $fb) {
                $script:FastbootPath = $fb
                Save-FastbootPath $fb
                $fastbootLabel.Text = "Fastboot: READY"
                $fastbootLabel.ForeColor = [System.Drawing.Color]::LightGreen
                $fastbootPathLabel.Text = $fb
                Set-Log "Fastboot setup complete: $fb"
                $statusLabel.Text = "Current step: Put Nova in Fastboot Mode, connect USB, then click CHECK NOVA."
                $statusLabel.ForeColor = [System.Drawing.Color]::LightSkyBlue
                [System.Windows.Forms.MessageBox]::Show(
                    "Fastboot is ready. You only need to do this once.",
                    "Setup complete",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                ) | Out-Null
                $setup.Close()
            } else {
                [System.Windows.Forms.MessageBox]::Show(
                    "fastboot.exe was not found in that folder.`r`nChoose the folder named 'platform-tools'.",
                    "Wrong folder",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                ) | Out-Null
            }
        }
    })

    $close.Add_Click({ $setup.Close() })
    [void]$setup.ShowDialog($form)
}


function Show-EnterFastbootHelp {
    $help = New-Object System.Windows.Forms.Form
    $help.Text = "How to Enter Fastboot Mode - Retroid Pocket Nova"
    $help.ClientSize = New-Object System.Drawing.Size(700, 690)
    $help.StartPosition = "CenterParent"
    $help.FormBorderStyle = "FixedDialog"
    $help.MaximizeBox = $false
    $help.MinimizeBox = $false
    $help.BackColor = [System.Drawing.Color]::FromArgb(22,22,24)
    $help.ForeColor = [System.Drawing.Color]::White
    $help.Font = New-Object System.Drawing.Font("Segoe UI", 10)

    $title2 = New-Object System.Windows.Forms.Label
    $title2.Text = "PUT NOVA INTO FASTBOOT MODE"
    $title2.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16)
    $title2.Location = New-Object System.Drawing.Point(22, 18)
    $title2.AutoSize = $true
    $help.Controls.Add($title2)

    $easy = New-Object System.Windows.Forms.Label
    $easy.Text = "METHOD 1 - NO USB DEBUGGING (recommended)"
    $easy.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
    $easy.Location = New-Object System.Drawing.Point(24, 65)
    $easy.AutoSize = $true
    $easy.ForeColor = [System.Drawing.Color]::LightGreen
    $help.Controls.Add($easy)

    $steps = New-Object System.Windows.Forms.Label
    $steps.Text = "1. Shut down the Nova completely.`r`n2. Hold VOLUME DOWN.`r`n3. While holding VOLUME DOWN, press and hold POWER.`r`n4. Keep holding until the FastBoot Mode screen appears.`r`n5. Connect the Nova to the PC with USB.`r`n6. Return to Nova Splash Maker and click CHECK NOVA."
    $steps.Location = New-Object System.Drawing.Point(28, 98)
    $steps.Size = New-Object System.Drawing.Size(580, 150)
    $help.Controls.Add($steps)

    $screen = New-Object System.Windows.Forms.Label
    $screen.Text = "YOU ARE IN THE RIGHT SCREEN IF YOU SEE:`r`nFastBoot Mode  |  DEVICE STATE - UNLOCKED  |  BOOT MODE - Android"
    $screen.Location = New-Object System.Drawing.Point(28, 255)
    $screen.Size = New-Object System.Drawing.Size(580, 58)
    $screen.ForeColor = [System.Drawing.Color]::Khaki
    $help.Controls.Add($screen)

    $alt = New-Object System.Windows.Forms.Label
    $alt.Text = "METHOD 2 - FROM ANDROID (USB DEBUGGING)"
    $alt.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
    $alt.Location = New-Object System.Drawing.Point(24, 325)
    $alt.AutoSize = $true
    $alt.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $help.Controls.Add($alt)

    $altSteps = New-Object System.Windows.Forms.TextBox
    $altSteps.Location = New-Object System.Drawing.Point(28, 356)
    $altSteps.Size = New-Object System.Drawing.Size(642, 245)
    $altSteps.Multiline = $true
    $altSteps.ReadOnly = $true
    $altSteps.ScrollBars = "Vertical"
    $altSteps.BackColor = [System.Drawing.Color]::FromArgb(10,10,12)
    $altSteps.ForeColor = [System.Drawing.Color]::Gainsboro
    $altSteps.BorderStyle = "FixedSingle"
    $altSteps.Text = "1. On Nova, open Settings > About device.`r`n2. Find Build number and tap it 7 times until Developer Options are enabled.`r`n3. Go back to Settings > System > Developer options.`r`n4. Turn ON USB debugging.`r`n5. Connect Nova to the PC with a USB data cable.`r`n6. On Nova, accept the 'Allow USB debugging?' prompt. Check 'Always allow from this computer' if you want.`r`n7. On the PC, make sure Google's Platform Tools are in C:\platform-tools.`r`n8. Open Command Prompt or PowerShell in C:\platform-tools.`r`n9. Run: adb.exe devices`r`n10. Your Nova should appear as 'device'. If it says 'unauthorized', unlock Nova and accept the USB debugging prompt.`r`n11. Run: adb.exe reboot bootloader`r`n12. Nova will reboot into Fastboot Mode.`r`n13. Return to Nova Splash Maker and click CHECK NOVA.`r`n`r`nNOTE: Method 2 requires USB Debugging. Method 1 above does NOT require USB Debugging."
    $help.Controls.Add($altSteps)

    $copyAdbBtn = New-Object System.Windows.Forms.Button
    $copyAdbBtn.Text = "COPY ADB COMMANDS"
    $copyAdbBtn.Location = New-Object System.Drawing.Point(28, 612)
    $copyAdbBtn.Size = New-Object System.Drawing.Size(205, 38)
    $help.Controls.Add($copyAdbBtn)

    $checkNow = New-Object System.Windows.Forms.Button
    $checkNow.Text = "I'M IN FASTBOOT - CHECK NOVA"
    $checkNow.Location = New-Object System.Drawing.Point(245, 612)
    $checkNow.Size = New-Object System.Drawing.Size(270, 38)
    $help.Controls.Add($checkNow)

    $closeHelp = New-Object System.Windows.Forms.Button
    $closeHelp.Text = "Close"
    $closeHelp.Location = New-Object System.Drawing.Point(528, 612)
    $closeHelp.Size = New-Object System.Drawing.Size(142, 38)
    $help.Controls.Add($closeHelp)

    $copyAdbBtn.Add_Click({
        [System.Windows.Forms.Clipboard]::SetText("cd /d C:\platform-tools`r`nadb.exe devices`r`nadb.exe reboot bootloader")
        [System.Windows.Forms.MessageBox]::Show(
            "Copied these commands:`r`n`r`ncd /d C:\platform-tools`r`nadb.exe devices`r`nadb.exe reboot bootloader",
            "ADB commands copied",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    })

    $checkNow.Add_Click({
        $help.Close()
        $detectBtn.PerformClick()
    })
    $closeHelp.Add_Click({ $help.Close() })

    [void]$help.ShowDialog($form)
}


function Get-NovaCrc32([byte[]]$Data) {
    [uint32]$crc = 4294967295
    [uint32]$poly = 3988292384

    foreach ($b in $Data) {
        $crc = [uint32]($crc -bxor [uint32]$b)
        for ($i = 0; $i -lt 8; $i++) {
            if (($crc -band 1) -ne 0) {
                $crc = [uint32](($crc -shr 1) -bxor $poly)
            } else {
                $crc = [uint32]($crc -shr 1)
            }
        }
    }

    return [uint32]($crc -bxor 4294967295)
}

function Get-NovaDosDateTime {
    $dt = Get-Date
    $year = [Math]::Max(1980, [Math]::Min(2107, $dt.Year))

    [uint16]$dosTime = [uint16](
        (($dt.Hour -band 31) -shl 11) -bor
        (($dt.Minute -band 63) -shl 5) -bor
        ([Math]::Floor($dt.Second / 2) -band 31)
    )

    [uint16]$dosDate = [uint16](
        ((($year - 1980) -band 127) -shl 9) -bor
        (($dt.Month -band 15) -shl 5) -bor
        ($dt.Day -band 31)
    )

    return @($dosTime, $dosDate)
}

function New-NovaStoredBootZip([string]$SourceDir, [string]$ZipPath) {
    if (-not (Test-Path -LiteralPath $SourceDir -PathType Container)) {
        throw "Boot ZIP source folder does not exist: $SourceDir"
    }

    $descPath = Join-Path $SourceDir "desc.txt"
    $part0Path = Join-Path $SourceDir "part0"
    $part1Path = Join-Path $SourceDir "part1"

    if (-not (Test-Path -LiteralPath $descPath -PathType Leaf)) {
        throw "bootanimation source is missing desc.txt"
    }
    if (-not (Test-Path -LiteralPath $part0Path -PathType Container)) {
        throw "bootanimation source is missing part0"
    }
    if (-not (Test-Path -LiteralPath $part1Path -PathType Container)) {
        throw "bootanimation source is missing part1"
    }

    $files = New-Object System.Collections.Generic.List[object]
    $files.Add([PSCustomObject]@{ File = Get-Item -LiteralPath $descPath; Name = "desc.txt" })

    $initialPart0Frames = @(
        Get-ChildItem -LiteralPath $part0Path -File -Filter "*.png" |
            Sort-Object Name
    )
    foreach ($frame in $initialPart0Frames) {
        $files.Add([PSCustomObject]@{
            File = $frame
            Name = ("part0/" + $frame.Name)
        })
    }

    $part0Frames = @(
        Get-ChildItem -LiteralPath $part0Path -File -Filter "*.png" |
            Sort-Object Name
    )

    if ($part0Frames.Count -lt 1) {
        throw "part0 has no PNG frames"
    }

    # part0 entries were already added above.
    # For part1, use an existing PNG if present.
    $part1Frames = @(
        Get-ChildItem -LiteralPath $part1Path -File -Filter "*.png" |
            Sort-Object Name
    )

    if ($part1Frames.Count -gt 0) {
        foreach ($frame in $part1Frames) {
            $files.Add([PSCustomObject]@{
                File = $frame
                Name = ("part1/" + $frame.Name)
            })
        }
    } else {
        # GIF hotfix:
        # Some Windows/PowerShell combinations were reaching the ZIP stage
        # before part1 was visible to Get-ChildItem. Never fail generation.
        # Reuse the final part0 frame directly as part1/00000.png.
        $fallbackFrame = $part0Frames[$part0Frames.Count - 1]
        $files.Add([PSCustomObject]@{
            File = $fallbackFrame
            Name = "part1/00000.png"
        })
    }

    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -Force -LiteralPath $ZipPath
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $dt = Get-NovaDosDateTime
    [uint16]$dosTime = $dt[0]
    [uint16]$dosDate = $dt[1]

    $central = New-Object System.Collections.Generic.List[object]

    $fs = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Create)
    $bw = New-Object System.IO.BinaryWriter($fs)

    try {
        foreach ($item in $files) {
            [byte[]]$data = [System.IO.File]::ReadAllBytes($item.File.FullName)
            [byte[]]$nameBytes = $utf8.GetBytes([string]$item.Name)

            if ($data.LongLength -gt 4294967295) {
                throw "Frame/file too large for standard ZIP: $($item.Name)"
            }

            [uint32]$size = [uint32]$data.Length
            [uint32]$crc = Get-NovaCrc32 $data
            [uint32]$localOffset = [uint32]$fs.Position

            # Local file header.
            $bw.Write([uint32]0x04034B50)
            $bw.Write([uint16]20)
            $bw.Write([uint16]0)
            $bw.Write([uint16]0)   # compression method 0 = STORE
            $bw.Write($dosTime)
            $bw.Write($dosDate)
            $bw.Write($crc)
            $bw.Write($size)
            $bw.Write($size)
            $bw.Write([uint16]$nameBytes.Length)
            $bw.Write([uint16]0)
            $bw.Write($nameBytes)
            $bw.Write($data)

            $central.Add([PSCustomObject]@{
                NameBytes   = $nameBytes
                Crc         = $crc
                Size        = $size
                LocalOffset = $localOffset
            })
        }

        [uint32]$centralOffset = [uint32]$fs.Position

        foreach ($entry in $central) {
            # Central directory header.
            $bw.Write([uint32]0x02014B50)
            $bw.Write([uint16]20)
            $bw.Write([uint16]20)
            $bw.Write([uint16]0)
            $bw.Write([uint16]0)   # compression method 0 = STORE
            $bw.Write($dosTime)
            $bw.Write($dosDate)
            $bw.Write([uint32]$entry.Crc)
            $bw.Write([uint32]$entry.Size)
            $bw.Write([uint32]$entry.Size)
            $bw.Write([uint16]$entry.NameBytes.Length)
            $bw.Write([uint16]0)
            $bw.Write([uint16]0)
            $bw.Write([uint16]0)
            $bw.Write([uint16]0)
            $bw.Write([uint32]0)
            $bw.Write([uint32]$entry.LocalOffset)
            $bw.Write([byte[]]$entry.NameBytes)
        }

        [uint32]$centralSize = [uint32]($fs.Position - $centralOffset)
        [uint16]$entryCount = [uint16]$central.Count

        # End of central directory.
        $bw.Write([uint32]0x06054B50)
        $bw.Write([uint16]0)
        $bw.Write([uint16]0)
        $bw.Write($entryCount)
        $bw.Write($entryCount)
        $bw.Write($centralSize)
        $bw.Write($centralOffset)
        $bw.Write([uint16]0)
    } finally {
        $bw.Dispose()
        $fs.Dispose()
    }
}

function New-ZipFromFolder([string]$SourceDir, [string]$ZipPath, [bool]$StoreOnly) {
    if ($StoreOnly) {
        # Android bootanimation.zip on this Nova must be TRUE ZIP method 0 / STORE.
        New-NovaStoredBootZip -SourceDir $SourceDir -ZipPath $ZipPath
        return
    }

    if (-not (Test-Path -LiteralPath $SourceDir)) {
        throw "ZIP source folder does not exist: $SourceDir"
    }

    if (Test-Path -LiteralPath $ZipPath) {
        Remove-Item -Force -LiteralPath $ZipPath
    }

    $fs = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Create)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive(
            $fs,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $false
        )
        try {
            $files = Get-ChildItem -LiteralPath $SourceDir -Recurse -File | Sort-Object FullName
            foreach ($file in $files) {
                $rel = $file.FullName.Substring($SourceDir.Length)
                while ($rel.StartsWith("\") -or $rel.StartsWith("/")) {
                    $rel = $rel.Substring(1)
                }
                $rel = $rel.Replace("\", "/")

                $entry = $zip.CreateEntry(
                    $rel,
                    [System.IO.Compression.CompressionLevel]::Optimal
                )

                $outStream = $entry.Open()
                $inStream = [System.IO.File]::OpenRead($file.FullName)
                try {
                    $inStream.CopyTo($outStream)
                } finally {
                    $inStream.Dispose()
                    $outStream.Dispose()
                }
            }
        } finally {
            $zip.Dispose()
        }
    } finally {
        $fs.Dispose()
    }
}


function New-NovaMagiskBootModule(
    [string]$BootAnimationZip,
    [string]$OutputZip
) {
    if (-not (Test-Path -LiteralPath $BootAnimationZip -PathType Leaf)) {
        throw "bootanimation.zip does not exist: $BootAnimationZip"
    }

    if (Test-Path -LiteralPath $OutputZip) {
        Remove-Item -Force -LiteralPath $OutputZip
    }

    $modulePropText = @"
id=nova_custom_bootanimation
name=Nova Custom Boot Animation
version=1.0
versionCode=1
author=Nova Splash Maker
description=Custom 1280x960 boot animation generated by Nova Splash Maker.
"@

    $postFsText = "#!/system/bin/sh`nresetprop -n debug.sf.nobootanimation 0`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    $fs = [System.IO.File]::Open($OutputZip, [System.IO.FileMode]::Create)
    try {
        $zip = New-Object System.IO.Compression.ZipArchive(
            $fs,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $false
        )
        try {
            # 1/3: post-fs-data.sh at ZIP ROOT
            $entry = $zip.CreateEntry(
                "post-fs-data.sh",
                [System.IO.Compression.CompressionLevel]::Optimal
            )
            $stream = $entry.Open()
            try {
                $bytes = $utf8NoBom.GetBytes($postFsText)
                $stream.Write($bytes, 0, $bytes.Length)
            } finally {
                $stream.Dispose()
            }

            # 2/3: module.prop at ZIP ROOT
            $entry = $zip.CreateEntry(
                "module.prop",
                [System.IO.Compression.CompressionLevel]::Optimal
            )
            $stream = $entry.Open()
            try {
                $bytes = $utf8NoBom.GetBytes(($modulePropText -replace "`r`n", "`n"))
                $stream.Write($bytes, 0, $bytes.Length)
            } finally {
                $stream.Dispose()
            }

            # 3/3: bootanimation.zip at EXACT Nova overlay path
            $entry = $zip.CreateEntry(
                "system/product/media/bootanimation.zip",
                [System.IO.Compression.CompressionLevel]::Optimal
            )
            $outStream = $entry.Open()
            $inStream = [System.IO.File]::OpenRead($BootAnimationZip)
            try {
                $inStream.CopyTo($outStream)
            } finally {
                $inStream.Dispose()
                $outStream.Dispose()
            }
        } finally {
            $zip.Dispose()
        }
    } finally {
        $fs.Dispose()
    }

    # HARD VALIDATION: output must contain EXACTLY these 3 files.
    $checkFs = [System.IO.File]::OpenRead($OutputZip)
    try {
        $checkZip = New-Object System.IO.Compression.ZipArchive(
            $checkFs,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $false
        )
        try {
            $actual = @($checkZip.Entries | ForEach-Object { $_.FullName } | Sort-Object)
            $expected = @(
                "module.prop",
                "post-fs-data.sh",
                "system/product/media/bootanimation.zip"
            ) | Sort-Object

            if ($actual.Count -ne 3) {
                throw "Magisk ZIP validation failed: expected exactly 3 files, found $($actual.Count)."
            }

            for ($i = 0; $i -lt 3; $i++) {
                if ($actual[$i] -ne $expected[$i]) {
                    throw "Magisk ZIP validation failed. Wrong structure: $($actual -join ', ')"
                }
            }
        } finally {
            $checkZip.Dispose()
        }
    } finally {
        $checkFs.Dispose()
    }
}

function Get-AnimationFitSettings([string]$Mode) {
    $bg = [System.Drawing.Color]::Black
    $codecMode = "Fit"

    if ($Mode -eq "Fit - White") {
        $bg = [System.Drawing.Color]::White
    } elseif ($Mode -eq "Fill / Crop") {
        $codecMode = "Fill / Crop"
    } elseif ($Mode -eq "Stretch") {
        $codecMode = "Stretch"
    }

    return [PSCustomObject]@{
        Background = $bg
        CodecMode = $codecMode
    }
}

function Build-AnimationFramesFromFolder(
    [string]$SourceFolder,
    [string]$OutputFolder,
    [string]$FitMode
) {
    if (-not (Test-Path -LiteralPath $SourceFolder -PathType Container)) {
        throw "Frame source folder does not exist: $SourceFolder"
    }
    if (-not (Test-Path -LiteralPath $OutputFolder -PathType Container)) {
        throw "Temporary output folder does not exist: $OutputFolder"
    }

    $settings = Get-AnimationFitSettings $FitMode

    $files = Get-ChildItem -LiteralPath $SourceFolder -File | Where-Object {
        $_.Extension.ToLowerInvariant() -in @(".png", ".jpg", ".jpeg", ".bmp")
    } | Sort-Object Name

    if (-not $files -or $files.Count -eq 0) {
        throw "No PNG/JPG/BMP frames were found in that folder."
    }

    $i = 0
    foreach ($file in $files) {
        $bmp = [NovaSplashCodec]::Compose(
            $file.FullName,
            $settings.CodecMode,
            $settings.Background
        )
        try {
            $out = Join-Path $OutputFolder ("{0:D5}.png" -f $i)
            $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $bmp.Dispose()
        }
        $i++
    }
    return $i
}

function Build-AnimationFramesFromGif(
    [string]$GifPath,
    [string]$OutputFolder,
    [string]$FitMode,
    [string]$TempRawFolder
) {
    if (-not (Test-Path -LiteralPath $GifPath -PathType Leaf)) {
        throw "GIF file does not exist: $GifPath"
    }
    if (-not (Test-Path -LiteralPath $OutputFolder -PathType Container)) {
        throw "Temporary output folder does not exist: $OutputFolder"
    }
    if (-not (Test-Path -LiteralPath $TempRawFolder -PathType Container)) {
        throw "Temporary GIF folder does not exist: $TempRawFolder"
    }

    $settings = Get-AnimationFitSettings $FitMode
    $gif = [System.Drawing.Image]::FromFile($GifPath)

    try {
        $dimension = New-Object System.Drawing.Imaging.FrameDimension -ArgumentList $gif.FrameDimensionsList[0]
        $count = $gif.GetFrameCount($dimension)

        for ($i = 0; $i -lt $count; $i++) {
            [void]$gif.SelectActiveFrame($dimension, $i)

            $rawPath = Join-Path $TempRawFolder ("raw_{0:D5}.png" -f $i)
            $rawBmp = New-Object System.Drawing.Bitmap -ArgumentList $gif.Width, $gif.Height
            try {
                $g = [System.Drawing.Graphics]::FromImage($rawBmp)
                try {
                    $g.DrawImage($gif, 0, 0, $gif.Width, $gif.Height)
                } finally {
                    $g.Dispose()
                }
                $rawBmp.Save($rawPath, [System.Drawing.Imaging.ImageFormat]::Png)
            } finally {
                $rawBmp.Dispose()
            }

            $bmp = [NovaSplashCodec]::Compose(
                $rawPath,
                $settings.CodecMode,
                $settings.Background
            )
            try {
                $out = Join-Path $OutputFolder ("{0:D5}.png" -f $i)
                $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            } finally {
                $bmp.Dispose()
            }
        }
        return $count
    } finally {
        $gif.Dispose()
    }
}

function Show-BootAnimationMaker {
    $animForm = New-Object System.Windows.Forms.Form
    $animForm.Text = "Nova Boot Animation Maker - Magisk"
    $animForm.ClientSize = New-Object System.Drawing.Size(820, 650)
    $animForm.StartPosition = "CenterParent"
    $animForm.FormBorderStyle = "Sizable"
    $animForm.MinimumSize = New-Object System.Drawing.Size(760, 620)
    $animForm.BackColor = [System.Drawing.Color]::FromArgb(18,18,20)
    $animForm.ForeColor = [System.Drawing.Color]::White
    $animForm.Font = New-Object System.Drawing.Font("Segoe UI", 9)

    $animTitle = New-Object System.Windows.Forms.Label
    $animTitle.Text = "BOOT ANIMATION MAKER — MAGISK"
    $animTitle.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 17)
    $animTitle.Location = New-Object System.Drawing.Point(20, 16)
    $animTitle.AutoSize = $true
    $animForm.Controls.Add($animTitle)

    $magiskNote = New-Object System.Windows.Forms.Label
    $magiskNote.Text = "Boot animation is different from the splash logo. This creates a Magisk module ZIP and REQUIRES Magisk/root on the Nova."
    $magiskNote.Location = New-Object System.Drawing.Point(22, 52)
    $magiskNote.Size = New-Object System.Drawing.Size(760, 40)
    $magiskNote.ForeColor = [System.Drawing.Color]::Gold
    $animForm.Controls.Add($magiskNote)

    $animPicture = New-Object System.Windows.Forms.PictureBox
    $animPicture.Location = New-Object System.Drawing.Point(20, 100)
    $animPicture.Size = New-Object System.Drawing.Size(420, 315)
    $animPicture.BorderStyle = "FixedSingle"
    $animPicture.BackColor = [System.Drawing.Color]::Black
    $animPicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $animForm.Controls.Add($animPicture)

    $gifBtn = New-Object System.Windows.Forms.Button
    $gifBtn.Text = "CHOOSE ANIMATED GIF..."
    $gifBtn.Location = New-Object System.Drawing.Point(465, 105)
    $gifBtn.Size = New-Object System.Drawing.Size(320, 40)
    $animForm.Controls.Add($gifBtn)

    $folderBtn = New-Object System.Windows.Forms.Button
    $folderBtn.Text = "CHOOSE PNG/JPG FRAME FOLDER..."
    $folderBtn.Location = New-Object System.Drawing.Point(465, 153)
    $folderBtn.Size = New-Object System.Drawing.Size(320, 40)
    $animForm.Controls.Add($folderBtn)

    $animSourceLabel = New-Object System.Windows.Forms.Label
    $animSourceLabel.Text = "Source: none"
    $animSourceLabel.Location = New-Object System.Drawing.Point(465, 202)
    $animSourceLabel.Size = New-Object System.Drawing.Size(320, 56)
    $animSourceLabel.ForeColor = [System.Drawing.Color]::Silver
    $animForm.Controls.Add($animSourceLabel)

    $fpsLabel = New-Object System.Windows.Forms.Label
    $fpsLabel.Text = "FPS"
    $fpsLabel.Location = New-Object System.Drawing.Point(465, 270)
    $fpsLabel.AutoSize = $true
    $animForm.Controls.Add($fpsLabel)

    $fpsCombo = New-Object System.Windows.Forms.ComboBox
    $fpsCombo.DropDownStyle = "DropDownList"
    $fpsCombo.Location = New-Object System.Drawing.Point(465, 292)
    $fpsCombo.Size = New-Object System.Drawing.Size(145, 30)
    foreach ($fps in @("10", "12", "15", "20", "24", "30")) {
        [void]$fpsCombo.Items.Add($fps)
    }
    $fpsCombo.SelectedItem = "15"
    $animForm.Controls.Add($fpsCombo)

    $animFitLabel = New-Object System.Windows.Forms.Label
    $animFitLabel.Text = "Frame fit"
    $animFitLabel.Location = New-Object System.Drawing.Point(625, 270)
    $animFitLabel.AutoSize = $true
    $animForm.Controls.Add($animFitLabel)

    $animFitCombo = New-Object System.Windows.Forms.ComboBox
    $animFitCombo.DropDownStyle = "DropDownList"
    $animFitCombo.Location = New-Object System.Drawing.Point(625, 292)
    $animFitCombo.Size = New-Object System.Drawing.Size(160, 30)
    [void]$animFitCombo.Items.Add("Fit - Black")
    [void]$animFitCombo.Items.Add("Fit - White")
    [void]$animFitCombo.Items.Add("Fill / Crop")
    [void]$animFitCombo.Items.Add("Stretch")
    $animFitCombo.SelectedIndex = 0
    $animForm.Controls.Add($animFitCombo)

    $loopLabel = New-Object System.Windows.Forms.Label
    $loopLabel.Text = "Loop mode: animation repeats until Android finishes booting."
    $loopLabel.Location = New-Object System.Drawing.Point(465, 335)
    $loopLabel.Size = New-Object System.Drawing.Size(320, 38)
    $loopLabel.ForeColor = [System.Drawing.Color]::LightSkyBlue
    $animForm.Controls.Add($loopLabel)

    $generateAnimBtn = New-Object System.Windows.Forms.Button
    $generateAnimBtn.Text = "GENERATE MAGISK BOOT ANIMATION ZIP"
    $generateAnimBtn.Location = New-Object System.Drawing.Point(465, 375)
    $generateAnimBtn.Size = New-Object System.Drawing.Size(320, 48)
    $generateAnimBtn.BackColor = [System.Drawing.Color]::FromArgb(210, 0, 120)
    $generateAnimBtn.ForeColor = [System.Drawing.Color]::White
    $generateAnimBtn.FlatStyle = "Flat"
    $animForm.Controls.Add($generateAnimBtn)

    $animHelp = New-Object System.Windows.Forms.TextBox
    $animHelp.Location = New-Object System.Drawing.Point(20, 440)
    $animHelp.Size = New-Object System.Drawing.Size(765, 155)
    $animHelp.Multiline = $true
    $animHelp.ReadOnly = $true
    $animHelp.ScrollBars = "Vertical"
    $animHelp.BackColor = [System.Drawing.Color]::FromArgb(8,8,10)
    $animHelp.ForeColor = [System.Drawing.Color]::Gainsboro
    $animHelp.Text = "HOW TO USE:`r`n1. Choose an animated GIF OR a folder containing numbered PNG/JPG frames.`r`n2. Pick FPS and frame fit.`r`n3. Click GENERATE. The tool creates ONE Nova-compatible Magisk ZIP using the confirmed working 3-file module structure.`r`n4. Copy that Magisk ZIP to the Nova.`r`n5. Open Magisk > Modules > Install from storage > choose the generated ZIP > Reboot.`r`n`r`nIMPORTANT: Splash logo uses Fastboot and does NOT need root. Boot animation uses Magisk and DOES require Magisk/root.`r`nMP4 is not supported in this version; convert MP4 to GIF or PNG frames first."
    $animForm.Controls.Add($animHelp)

    $animStatus = New-Object System.Windows.Forms.Label
    $animStatus.Text = "Ready."
    $animStatus.Location = New-Object System.Drawing.Point(20, 607)
    $animStatus.Size = New-Object System.Drawing.Size(765, 28)
    $animStatus.ForeColor = [System.Drawing.Color]::Silver
    $animForm.Controls.Add($animStatus)

    $script:AnimSourceType = $null
    $script:AnimSourcePath = $null
    $script:AnimPreviewImage = $null

    $gifBtn.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "Animated GIF|*.gif"
        $dlg.Title = "Choose animated GIF"

        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                if ($animPicture.Image) {
                    $animPicture.Image.Dispose()
                    $animPicture.Image = $null
                }

                $script:AnimSourceType = "GIF"
                $script:AnimSourcePath = $dlg.FileName

                $img = [System.Drawing.Image]::FromFile($dlg.FileName)
                $dimension = New-Object System.Drawing.Imaging.FrameDimension -ArgumentList $img.FrameDimensionsList[0]
                $frameCount = $img.GetFrameCount($dimension)

                # Keep this Image alive so PictureBox can animate the GIF preview.
                $script:AnimPreviewImage = $img
                $animPicture.Image = $script:AnimPreviewImage
                $animSourceLabel.Text = "GIF: " + [System.IO.Path]::GetFileName($dlg.FileName) + "`r`nFrames: $frameCount"
                $animStatus.Text = "GIF loaded. Choose FPS, then generate."
            } catch {
                [System.Windows.Forms.MessageBox]::Show(
                    "Could not open GIF:`r`n$($_.Exception.Message)",
                    "Boot Animation Maker"
                ) | Out-Null
            }
        }
    })

    $folderBtn.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Choose a folder containing PNG/JPG/BMP animation frames"

        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $files = Get-ChildItem -Path $dlg.SelectedPath -File | Where-Object {
                $_.Extension.ToLowerInvariant() -in @(".png", ".jpg", ".jpeg", ".bmp")
            } | Sort-Object Name

            if (-not $files -or $files.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show(
                    "No PNG/JPG/BMP frames were found in that folder.",
                    "Boot Animation Maker"
                ) | Out-Null
                return
            }

            if ($animPicture.Image) {
                $animPicture.Image.Dispose()
                $animPicture.Image = $null
            }
            if ($script:AnimPreviewImage) {
                try { $script:AnimPreviewImage.Dispose() } catch {}
                $script:AnimPreviewImage = $null
            }

            $script:AnimSourceType = "Folder"
            $script:AnimSourcePath = $dlg.SelectedPath

            $sourceImg = [System.Drawing.Image]::FromFile($files[0].FullName)
            try {
                $preview = New-Object System.Drawing.Bitmap -ArgumentList $sourceImg.Width, $sourceImg.Height
                $g = [System.Drawing.Graphics]::FromImage($preview)
                try {
                    $g.DrawImage($sourceImg, 0, 0, $sourceImg.Width, $sourceImg.Height)
                } finally {
                    $g.Dispose()
                }
            } finally {
                $sourceImg.Dispose()
            }

            $script:AnimPreviewImage = $preview
            $animPicture.Image = $script:AnimPreviewImage
            $animSourceLabel.Text = "Frame folder: " + (Split-Path $dlg.SelectedPath -Leaf) + "`r`nFrames: $($files.Count)"
            $animStatus.Text = "Frame folder loaded. Files are played in filename order."
        }
    })

    $generateAnimBtn.Add_Click({
        if (-not $script:AnimSourceType -or -not $script:AnimSourcePath) {
            [System.Windows.Forms.MessageBox]::Show(
                "Choose an animated GIF or a frame folder first.",
                "Boot Animation Maker"
            ) | Out-Null
            return
        }

        $save = New-Object System.Windows.Forms.SaveFileDialog
        $save.Filter = "Magisk Module ZIP|*.zip"
        $save.FileName = "Nova_Custom_BootAnimation_MAGISK_INSTALL_THIS.zip"
        $save.Title = "Save Magisk boot animation module"

        if ($save.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

        $work = Join-Path $env:TEMP ("NovaBootAnim_" + [Guid]::NewGuid().ToString("N"))
        $bootRoot = Join-Path $work "boot"
        $part0 = Join-Path $bootRoot "part0"
        $part1 = Join-Path $bootRoot "part1"
        $rawTemp = Join-Path $work "raw"
        New-Item -ItemType Directory -Force -Path $part0 | Out-Null
        New-Item -ItemType Directory -Force -Path $part1 | Out-Null
        New-Item -ItemType Directory -Force -Path $rawTemp | Out-Null

        try {
            $generateAnimBtn.Enabled = $false
            $generateAnimBtn.Text = "GENERATING..."
            $animStatus.Text = "Building 1280x960 frames..."
            [System.Windows.Forms.Application]::DoEvents()

            $fitMode = [string]$animFitCombo.SelectedItem
            $fps = [int]$fpsCombo.SelectedItem

            if ($script:AnimSourceType -eq "GIF") {
                $frameCount = Build-AnimationFramesFromGif -GifPath $script:AnimSourcePath -OutputFolder $part0 -FitMode $fitMode -TempRawFolder $rawTemp
            } else {
                $frameCount = Build-AnimationFramesFromFolder -SourceFolder $script:AnimSourcePath -OutputFolder $part0 -FitMode $fitMode
            }

            if ($frameCount -lt 1) {
                throw "No animation frames were generated."
            }

            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

            # CONFIRMED WORKING NOVA FORMAT:
            # part0 = play the selected animation once.
            # part1 = hold/loop the last frame until Android finishes booting.
            $lastFrame = Get-ChildItem -LiteralPath $part0 -File -Filter "*.png" |
                Sort-Object Name |
                Select-Object -Last 1

            if (-not $lastFrame) {
                throw "No final frame found for part1."
            }

            $part1Frame = Join-Path $part1 "00000.png"
            try {
                [System.IO.File]::Copy($lastFrame.FullName, $part1Frame, $true)
            } catch {
                # New-NovaStoredBootZip has a direct fallback to the final part0
                # frame, so GIF generation can still complete safely.
            }

            $desc = "1280 960 $fps`n" +
                    "p 1 0 part0`n" +
                    "p 0 0 part1`n"

            [System.IO.File]::WriteAllText(
                (Join-Path $bootRoot "desc.txt"),
                $desc,
                $utf8NoBom
            )

            $rawBootZip = Join-Path $work "bootanimation.zip"

            $animStatus.Text = "Building internal bootanimation.zip..."
            [System.Windows.Forms.Application]::DoEvents()
            New-ZipFromFolder $bootRoot $rawBootZip $true

            # Build the Magisk ZIP directly with EXACTLY 3 files.
            # No META-INF. No system/media duplicate. No README. No outer folder.
            $animStatus.Text = "Packing one-file Nova Magisk module..."
            [System.Windows.Forms.Application]::DoEvents()
            New-NovaMagiskBootModule -BootAnimationZip $rawBootZip -OutputZip $save.FileName

            $animStatus.Text = "Done: $frameCount frames @ $fps FPS."
            [System.Windows.Forms.MessageBox]::Show(
                "Boot animation created successfully.`r`nOne-file output mode.`r`n`r`nFrames: $frameCount`r`nFPS: $fps`r`nResolution: 1280x960`r`n`r`nMAGISK MODULE — INSTALL THIS FILE:`r`n$($save.FileName)`r`n`r`nValidated Magisk structure:`r`npost-fs-data.sh`r`nmodule.prop`r`nsystem/product/media/bootanimation.zip`r`n`r`nInner bootanimation.zip:`r`ndesc.txt`r`npart0/`r`npart1/`r`nTRUE ZIP STORE / method 0`r`n`r`nInstall it in Magisk > Modules > Install from storage, then reboot.",
                "Boot Animation Ready",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        } catch {
            $animStatus.Text = "ERROR: $($_.Exception.Message)"
            [System.Windows.Forms.MessageBox]::Show(
                $_.Exception.Message,
                "Boot animation generation failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        } finally {
            $generateAnimBtn.Enabled = $true
            $generateAnimBtn.Text = "GENERATE MAGISK BOOT ANIMATION ZIP"
            try { Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue } catch {}
        }
    })

    $animForm.Add_FormClosed({
        if ($animPicture.Image) {
            try { $animPicture.Image.Dispose() } catch {}
            $animPicture.Image = $null
        }
        if ($script:AnimPreviewImage) {
            try { $script:AnimPreviewImage.Dispose() } catch {}
            $script:AnimPreviewImage = $null
        }
    })

    [void]$animForm.ShowDialog($form)
}

function Update-Preview {
    if (-not $script:ImagePath -or -not (Test-Path $script:ImagePath)) { return }

    try {
        $mode = [string]$fitCombo.SelectedItem
        if (-not $mode) { $mode = "Fit - Black" }

        $bg = [System.Drawing.Color]::Black
        $codecMode = "Fit"
        if ($mode -eq "Fit - White") {
            $bg = [System.Drawing.Color]::White
            $codecMode = "Fit"
        } elseif ($mode -eq "Fill / Crop") {
            $bg = [System.Drawing.Color]::Black
            $codecMode = "Fill / Crop"
        } elseif ($mode -eq "Stretch") {
            $codecMode = "Stretch"
        }

        $bmp = [NovaSplashCodec]::Compose($script:ImagePath, $codecMode, $bg)
        if ($picture.Image) { $picture.Image.Dispose() }
        $picture.Image = $bmp
        $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not preview image:`r`n$($_.Exception.Message)",
            "Nova Splash + Boot Animation Maker",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
}

function Invoke-Fastboot([string[]]$Arguments) {
    $fb = Find-Fastboot
    if (-not $fb) {
        throw "fastboot.exe was not found. Click SET UP FASTBOOT and select Google's platform-tools folder."
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $fb
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($a in $Arguments) {
        [void]$psi.ArgumentList.Add($a)
    }

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    return [PSCustomObject]@{
        ExitCode = $p.ExitCode
        Text = (($stdout + $stderr).Trim())
    }
}

# Windows PowerShell 5.1 does not expose ProcessStartInfo.ArgumentList.
# Use a quoted command-line fallback there.
function Invoke-FastbootCompat([string[]]$Arguments) {
    $fb = Find-Fastboot
    if (-not $fb) {
        throw "fastboot.exe was not found. Click SET UP FASTBOOT and select Google's platform-tools folder."
    }

    $quoted = @()
    foreach ($a in $Arguments) {
        if ($a -match '[\s"]') {
            $quoted += ('"' + ($a -replace '"','\"') + '"')
        } else {
            $quoted += $a
        }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $fb
    $psi.Arguments = ($quoted -join " ")
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    return [PSCustomObject]@{
        ExitCode = $p.ExitCode
        Text = (($stdout + $stderr).Trim())
    }
}

# ---------------- Main window ----------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "Nova Splash + Boot Animation Maker v1.6 FIXED3"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.AutoScroll = $true
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.BackColor = [System.Drawing.Color]::FromArgb(18,18,20)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# Fit the app to the user's actual Windows desktop.
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$targetW = [Math]::Min(1100, [Math]::Max(860, $wa.Width - 40))
$targetH = [Math]::Min(820, [Math]::Max(620, $wa.Height - 50))
$form.ClientSize = New-Object System.Drawing.Size($targetW, $targetH)
$form.MinimumSize = New-Object System.Drawing.Size(820, 700)

# On small/low-height screens start maximized so nothing gets cut off.
if ($wa.Height -lt 800 -or $wa.Width -lt 1150) {
    $form.WindowState = [System.Windows.Forms.FormWindowState]::Maximized
}

$title = New-Object System.Windows.Forms.Label
$title.Text = "RETROID POCKET NOVA — SPLASH + BOOT ANIMATION MAKER v1.6 FIXED3"
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 16)
$title.Location = New-Object System.Drawing.Point(20, 15)
$title.AutoSize = $true
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Generate a 1280×960 / 32 MiB Nova splash image. Fastboot flashing is optional."
$subtitle.Location = New-Object System.Drawing.Point(22, 49)
$subtitle.AutoSize = $true
$subtitle.ForeColor = [System.Drawing.Color]::Silver
$form.Controls.Add($subtitle)

$picture = New-Object System.Windows.Forms.PictureBox
$picture.Location = New-Object System.Drawing.Point(20, 80)
$picture.Size = New-Object System.Drawing.Size(600, 450)
$picture.BorderStyle = "FixedSingle"
$picture.BackColor = [System.Drawing.Color]::Black
$form.Controls.Add($picture)

$animGroup = New-Object System.Windows.Forms.GroupBox
$animGroup.Text = "Boot Animation (Magisk)"
$animGroup.Location = New-Object System.Drawing.Point(20, 545)
$animGroup.Size = New-Object System.Drawing.Size(600, 175)
$animGroup.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($animGroup)

$animMainNote = New-Object System.Windows.Forms.Label
$animMainNote.Text = "Splash logo = Fastboot, no root needed.`r`nBoot animation = Magisk module, REQUIRES Magisk/root."
$animMainNote.Location = New-Object System.Drawing.Point(15, 28)
$animMainNote.Size = New-Object System.Drawing.Size(565, 46)
$animMainNote.ForeColor = [System.Drawing.Color]::Gold
$animGroup.Controls.Add($animMainNote)

$openAnimBtn = New-Object System.Windows.Forms.Button
$openAnimBtn.Text = "OPEN BOOT ANIMATION MAKER"
$openAnimBtn.Location = New-Object System.Drawing.Point(15, 82)
$openAnimBtn.Size = New-Object System.Drawing.Size(280, 44)
$openAnimBtn.BackColor = [System.Drawing.Color]::FromArgb(32,32,38)
$openAnimBtn.ForeColor = [System.Drawing.Color]::LightSkyBlue
$animGroup.Controls.Add($openAnimBtn)

$animInstallNote = New-Object System.Windows.Forms.Label
$animInstallNote.Text = "Creates ONE Magisk ZIP only.`r`nInstall: Magisk > Modules > Install from storage > Reboot."
$animInstallNote.Location = New-Object System.Drawing.Point(315, 82)
$animInstallNote.Size = New-Object System.Drawing.Size(265, 58)
$animInstallNote.ForeColor = [System.Drawing.Color]::Silver
$animGroup.Controls.Add($animInstallNote)


$selectBtn = New-Object System.Windows.Forms.Button
$selectBtn.Text = "Choose Image..."
$selectBtn.Location = New-Object System.Drawing.Point(650, 85)
$selectBtn.Size = New-Object System.Drawing.Size(300, 38)
$form.Controls.Add($selectBtn)

$imageLabel = New-Object System.Windows.Forms.Label
$imageLabel.Text = "No image selected"
$imageLabel.Location = New-Object System.Drawing.Point(650, 130)
$imageLabel.Size = New-Object System.Drawing.Size(300, 42)
$imageLabel.ForeColor = [System.Drawing.Color]::Silver
$form.Controls.Add($imageLabel)

$fitLabel = New-Object System.Windows.Forms.Label
$fitLabel.Text = "Image fit"
$fitLabel.Location = New-Object System.Drawing.Point(650, 185)
$fitLabel.AutoSize = $true
$form.Controls.Add($fitLabel)

$fitCombo = New-Object System.Windows.Forms.ComboBox
$fitCombo.DropDownStyle = "DropDownList"
$fitCombo.Location = New-Object System.Drawing.Point(650, 207)
$fitCombo.Size = New-Object System.Drawing.Size(300, 30)
[void]$fitCombo.Items.Add("Fit - Black")
[void]$fitCombo.Items.Add("Fit - White")
[void]$fitCombo.Items.Add("Fill / Crop")
[void]$fitCombo.Items.Add("Stretch")
$fitCombo.SelectedIndex = 0
$form.Controls.Add($fitCombo)

$generateBtn = New-Object System.Windows.Forms.Button
$generateBtn.Text = "GENERATE SPLASH.IMG"
$generateBtn.Location = New-Object System.Drawing.Point(650, 255)
$generateBtn.Size = New-Object System.Drawing.Size(300, 46)
$generateBtn.BackColor = [System.Drawing.Color]::FromArgb(210, 0, 120)
$generateBtn.ForeColor = [System.Drawing.Color]::White
$generateBtn.FlatStyle = "Flat"
$form.Controls.Add($generateBtn)

$generatedLabel = New-Object System.Windows.Forms.Label
$generatedLabel.Text = "Generated file: none"
$generatedLabel.Location = New-Object System.Drawing.Point(650, 310)
$generatedLabel.Size = New-Object System.Drawing.Size(300, 52)
$generatedLabel.ForeColor = [System.Drawing.Color]::Silver
$form.Controls.Add($generatedLabel)

$fastGroup = New-Object System.Windows.Forms.GroupBox
$fastGroup.Text = "Flash to Nova (Optional)"
$fastGroup.Location = New-Object System.Drawing.Point(640, 350)
$fastGroup.Size = New-Object System.Drawing.Size(360, 450)
$fastGroup.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($fastGroup)

$flowHint = New-Object System.Windows.Forms.Label
$flowHint.Text = "SETUP  >  CHECK  >  FLASH  >  REBOOT"
$flowHint.Location = New-Object System.Drawing.Point(15, 26)
$flowHint.Size = New-Object System.Drawing.Size(330, 24)
$flowHint.ForeColor = [System.Drawing.Color]::LightSkyBlue
$fastGroup.Controls.Add($flowHint)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Current step: Setup Platform Tools. Step 2 includes its own Fastboot Mode help button."
$statusLabel.Location = New-Object System.Drawing.Point(15, 52)
$statusLabel.Size = New-Object System.Drawing.Size(330, 42)
$statusLabel.ForeColor = [System.Drawing.Color]::Khaki
$fastGroup.Controls.Add($statusLabel)

$fastbootLabel = New-Object System.Windows.Forms.Label
$fastbootLabel.Text = "Fastboot: checking..."
$fastbootLabel.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$fastbootLabel.Location = New-Object System.Drawing.Point(15, 98)
$fastbootLabel.Size = New-Object System.Drawing.Size(330, 24)
$fastGroup.Controls.Add($fastbootLabel)

$fastbootPathLabel = New-Object System.Windows.Forms.Label
$fastbootPathLabel.Text = ""
$fastbootPathLabel.Location = New-Object System.Drawing.Point(15, 122)
$fastbootPathLabel.Size = New-Object System.Drawing.Size(330, 32)
$fastbootPathLabel.ForeColor = [System.Drawing.Color]::Silver
$fastGroup.Controls.Add($fastbootPathLabel)

$setupFbBtn = New-Object System.Windows.Forms.Button
$setupFbBtn.Text = "1. SET UP FASTBOOT"
$setupFbBtn.Location = New-Object System.Drawing.Point(15, 160)
$setupFbBtn.Size = New-Object System.Drawing.Size(160, 42)
$fastGroup.Controls.Add($setupFbBtn)

$detectBtn = New-Object System.Windows.Forms.Button
$detectBtn.Text = "2. CHECK NOVA"
$detectBtn.Location = New-Object System.Drawing.Point(185, 160)
$detectBtn.Size = New-Object System.Drawing.Size(160, 42)
$fastGroup.Controls.Add($detectBtn)

$flashBtn = New-Object System.Windows.Forms.Button
$flashBtn.Text = "3. FLASH LOGO"
$flashBtn.Location = New-Object System.Drawing.Point(15, 250)
$flashBtn.Size = New-Object System.Drawing.Size(160, 42)
$flashBtn.Enabled = $false
$fastGroup.Controls.Add($flashBtn)

$rebootBtn = New-Object System.Windows.Forms.Button
$rebootBtn.Text = "4. REBOOT NOVA"
$rebootBtn.Location = New-Object System.Drawing.Point(185, 250)
$rebootBtn.Size = New-Object System.Drawing.Size(160, 42)
$fastGroup.Controls.Add($rebootBtn)

$fastbootHowBtn = New-Object System.Windows.Forms.Button
$fastbootHowBtn.Text = "? HOW TO ENTER FASTBOOT"
$fastbootHowBtn.Location = New-Object System.Drawing.Point(185, 208)
$fastbootHowBtn.Size = New-Object System.Drawing.Size(160, 34)
$fastbootHowBtn.BackColor = [System.Drawing.Color]::FromArgb(32,32,38)
$fastbootHowBtn.ForeColor = [System.Drawing.Color]::LightSkyBlue
$fastGroup.Controls.Add($fastbootHowBtn)


$helpBox = New-Object System.Windows.Forms.TextBox
$helpBox.Location = New-Object System.Drawing.Point(15, 302)
$helpBox.Size = New-Object System.Drawing.Size(330, 130)
$helpBox.Multiline = $true
$helpBox.ReadOnly = $true
$helpBox.ScrollBars = "Vertical"
$helpBox.BackColor = [System.Drawing.Color]::FromArgb(10,10,12)
$helpBox.ForeColor = [System.Drawing.Color]::Gainsboro
$helpBox.BorderStyle = "FixedSingle"
$helpBox.Text = "1 SETUP: Put Platform Tools in C:\platform-tools.`r`n2 CHECK: Use the HOW TO ENTER FASTBOOT button directly under CHECK NOVA if needed. Then connect USB and click CHECK NOVA.`r`n3 FLASH: Writes your generated logo to splash.`r`n4 REBOOT: Boots Nova back into Android."
$fastGroup.Controls.Add($helpBox)

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 12000
$toolTip.InitialDelay = 300
$toolTip.ReshowDelay = 100
$toolTip.ShowAlways = $true

$toolTip.SetToolTip($setupFbBtn, "Recommended: download Google Platform Tools, extract it, move the folder to C:\platform-tools, then use C:\platform-tools\fastboot.exe.")
$toolTip.SetToolTip($detectBtn, "Step 2. If you do not know Fastboot Mode, click the help button directly below this button first.")
$toolTip.SetToolTip($fastbootHowBtn, "Step 2 help: shows both the hardware-button method and the full Android/USB Debugging method.")
$toolTip.SetToolTip($flashBtn, "Writes your generated splash.img to the Nova splash partition. Enabled only after CHECK NOVA succeeds.")
$toolTip.SetToolTip($rebootBtn, "Use after a successful flash to reboot the Nova back into Android.")
$toolTip.SetToolTip($generateBtn, "Creates a Nova-compatible 1280x960, 32 MiB splash.img.")
$toolTip.SetToolTip($fitCombo, "Fit keeps the full image. Fill/Crop fills the screen. Stretch forces 4:3.")

$toolTip.SetToolTip($openAnimBtn, "Creates one ready-to-install Magisk boot animation ZIP. Requires Magisk/root on the Nova.")

$warning = New-Object System.Windows.Forms.Label
$warning.Text = "Splash: generate without root; Fastboot is only needed to flash.   Animation: generate on PC, then install the generated module with Magisk/root."
$warning.Location = New-Object System.Drawing.Point(20, 830)
$warning.Size = New-Object System.Drawing.Size(640, 45)
$warning.ForeColor = [System.Drawing.Color]::Gold
$form.Controls.Add($warning)

$warning.AutoSize = $false


$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(20, 885)
$logBox.Size = New-Object System.Drawing.Size(1000, 75)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::FromArgb(8,8,10)
$logBox.ForeColor = [System.Drawing.Color]::Gainsboro
$form.Controls.Add($logBox)

$script:ImagePath = $null
$script:GeneratedPath = $null
$script:FastbootPath = $null
$script:NovaVerified = $false

# Auto-discover fastboot if present.
$found = Find-Fastboot
if ($found) { Set-Log "Found fastboot: $found" }

$selectBtn.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Images|*.png;*.jpg;*.jpeg;*.bmp|All files|*.*"
    $dlg.Title = "Choose artwork"
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:ImagePath = $dlg.FileName
        $imageLabel.Text = [System.IO.Path]::GetFileName($dlg.FileName)
        Update-Preview
        Set-Log "Loaded image: $($dlg.FileName)"
    }
})

$fitCombo.Add_SelectedIndexChanged({ Update-Preview })

$generateBtn.Add_Click({
    if (-not $script:ImagePath) {
        [System.Windows.Forms.MessageBox]::Show("Choose an image first.") | Out-Null
        return
    }

    $save = New-Object System.Windows.Forms.SaveFileDialog
    $save.Filter = "Nova Splash Image|*.img"
    $base = [System.IO.Path]::GetFileNameWithoutExtension($script:ImagePath)
    $save.FileName = ($base + "_Nova_splash.img")
    $save.Title = "Save Nova splash image"

    if ($save.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $mode = [string]$fitCombo.SelectedItem
        $bg = [System.Drawing.Color]::Black
        $codecMode = "Fit"
        if ($mode -eq "Fit - White") {
            $bg = [System.Drawing.Color]::White
        } elseif ($mode -eq "Fill / Crop") {
            $codecMode = "Fill / Crop"
        } elseif ($mode -eq "Stretch") {
            $codecMode = "Stretch"
        }

        $generateBtn.Enabled = $false
        $generateBtn.Text = "GENERATING..."
        [System.Windows.Forms.Application]::DoEvents()

        $bmp = [NovaSplashCodec]::Compose($script:ImagePath, $codecMode, $bg)
        try {
            [NovaSplashCodec]::BuildSplash($bmp, $save.FileName)

            $previewPath = [System.IO.Path]::ChangeExtension($save.FileName, ".preview.png")
            $bmp.Save($previewPath, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $bmp.Dispose()
        }

        $script:GeneratedPath = $save.FileName
        $generatedLabel.Text = "Generated: " + [System.IO.Path]::GetFileName($save.FileName)
        $flashBtn.Enabled = $script:NovaVerified
        if ($script:NovaVerified) {
            $statusLabel.Text = "Current step: Splash ready + Nova verified. Click FLASH LOGO."
            $statusLabel.ForeColor = [System.Drawing.Color]::LightGreen
        } else {
            $statusLabel.Text = "Current step: Splash ready. Put Nova in Fastboot Mode and click CHECK NOVA."
            $statusLabel.ForeColor = [System.Drawing.Color]::LightSkyBlue
        }
        Set-Log "Generated 32 MiB splash: $($save.FileName)"
        Set-Log "Preview saved: $previewPath"

        [System.Windows.Forms.MessageBox]::Show(
            "Splash generated successfully.`r`n`r`n$($save.FileName)",
            "Nova Splash + Boot Animation Maker",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {
        Set-Log "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Generation failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } finally {
        $generateBtn.Enabled = $true
        $generateBtn.Text = "GENERATE SPLASH.IMG"
    }
})

$openAnimBtn.Add_Click({ Show-BootAnimationMaker })

$setupFbBtn.Add_Click({ Show-FastbootSetup })
$fastbootHowBtn.Add_Click({ Show-EnterFastbootHelp })

$detectBtn.Add_Click({
    try {
        $dev = Invoke-FastbootCompat @("devices")
        Set-Log "> fastboot devices"
        Set-Log $dev.Text
        if (-not $dev.Text) {
            $script:NovaVerified = $false
            $flashBtn.Enabled = $false
            $statusLabel.Text = "Current step: Nova not detected. Enter Fastboot Mode, check the USB driver, then try CHECK NOVA again."
            $statusLabel.ForeColor = [System.Drawing.Color]::Gold
            [System.Windows.Forms.MessageBox]::Show(
                "Nova was not found.`r`n`r`n1. Put Nova in Fastboot Mode.`r`n2. Connect USB.`r`n3. In Device Manager, it should show Android Bootloader Interface.`r`n4. Click CHECK NOVA again.",
                "Nova not detected",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }

        $size = Invoke-FastbootCompat @("getvar", "partition-size:splash")
        Set-Log "> fastboot getvar partition-size:splash"
        Set-Log $size.Text

        if ($size.Text -match "0x0*2000000") {
            Set-Log "Splash partition verified: 32 MiB (0x2000000)."
            $script:NovaVerified = $true
            $flashBtn.Enabled = [bool]($script:GeneratedPath -and (Test-Path $script:GeneratedPath))
            if ($script:GeneratedPath -and (Test-Path $script:GeneratedPath)) {
                $statusLabel.Text = "Current step: Nova verified. Click FLASH LOGO."
            } else {
                $statusLabel.Text = "Current step: Nova verified. Choose an image and GENERATE SPLASH.IMG, then FLASH LOGO."
            }
            $statusLabel.ForeColor = [System.Drawing.Color]::LightGreen
            [System.Windows.Forms.MessageBox]::Show(
                "Nova detected and splash partition verified (32 MiB).",
                "Ready",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        } else {
            $script:NovaVerified = $false
            $flashBtn.Enabled = $false
            $statusLabel.Text = "Current step: Device detected, but splash partition is not the expected Nova size. Do not flash."
            $statusLabel.ForeColor = [System.Drawing.Color]::Gold
            [System.Windows.Forms.MessageBox]::Show(
                "Fastboot device detected, but splash partition did not report 0x2000000.`r`n`r`nFor safety, do NOT flash this device.",
                "Partition mismatch",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    } catch {
        Set-Log "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Fastboot error") | Out-Null
    }
})

$flashBtn.Add_Click({
    if (-not $script:NovaVerified) {
        [System.Windows.Forms.MessageBox]::Show(
            "Click CHECK NOVA first.`r`n`r`nThis verifies that the connected device has the correct 32 MiB splash partition.",
            "Check Nova first",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }

    if (-not $script:GeneratedPath -or -not (Test-Path $script:GeneratedPath)) {
        [System.Windows.Forms.MessageBox]::Show("Generate a splash image first.") | Out-Null
        return
    }

    $len = (Get-Item $script:GeneratedPath).Length
    if ($len -ne 33554432) {
        [System.Windows.Forms.MessageBox]::Show(
            "Refusing to flash: image is not exactly 33,554,432 bytes.",
            "Safety check failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }

    try {
        $dev = Invoke-FastbootCompat @("devices")
        if (-not $dev.Text) { throw "No Fastboot device detected." }

        $size = Invoke-FastbootCompat @("getvar", "partition-size:splash")
        if ($size.Text -notmatch "0x0*2000000") {
            throw "Splash partition size mismatch. Expected 0x2000000."
        }

        $answer = [System.Windows.Forms.MessageBox]::Show(
            "Flash this splash to the connected Nova?`r`n`r`n$($script:GeneratedPath)`r`n`r`nThis writes the splash partition.",
            "Confirm flash",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }

        Set-Log "> fastboot flash splash `"$($script:GeneratedPath)`""
        $r = Invoke-FastbootCompat @("flash", "splash", $script:GeneratedPath)
        Set-Log $r.Text

        if ($r.ExitCode -eq 0 -and $r.Text -match "OKAY") {
            $statusLabel.Text = "Current step: Flash successful. Click REBOOT NOVA."
            $statusLabel.ForeColor = [System.Drawing.Color]::LightGreen
            [System.Windows.Forms.MessageBox]::Show(
                "Flash completed. Click REBOOT NOVA when ready.",
                "Flash complete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            ) | Out-Null
        } else {
            throw "Fastboot did not report a successful flash."
        }
    } catch {
        Set-Log "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Flash failed",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

$rebootBtn.Add_Click({
    try {
        $r = Invoke-FastbootCompat @("reboot")
        Set-Log "> fastboot reboot"
        Set-Log $r.Text
        $statusLabel.Text = "Done. Nova is rebooting into Android."
        $statusLabel.ForeColor = [System.Drawing.Color]::LightGreen
    } catch {
        Set-Log "ERROR: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Fastboot error") | Out-Null
    }
})


$form.Add_Resize({
    try {
        # Keep the log box and warning fitting the visible client width.
        $usableW = [Math]::Max(760, $form.ClientSize.Width - 40)
        $logBox.Width = $usableW
        $warning.Width = [Math]::Min(760, $usableW)

        # Let the right-side optional flashing box breathe a little on larger windows.
        if ($form.ClientSize.Width -gt 1030) {
            $extra = $form.ClientSize.Width - 1030
            $fastGroup.Width = 340 + [Math]::Min(80, $extra)
            $flowHint.Width = $fastGroup.Width - 30
            $statusLabel.Width = $fastGroup.Width - 30
            $fastbootLabel.Width = $fastGroup.Width - 35
            $fastbootPathLabel.Width = $fastGroup.Width - 35
            $fastbootHowBtn.Width = 160
            $fastbootHowBtn.Left = $fastGroup.Width - 175
            $helpBox.Width = $fastGroup.Width - 30
        }

        if ($form.ClientSize.Width -gt 1000) {
            $logBox.Width = $form.ClientSize.Width - 40
        }
    } catch {}
})

[void]$form.ShowDialog()

if ($picture.Image) { $picture.Image.Dispose() }

NOVA SPLASH + BOOT ANIMATION MAKER v1.3
========================

MAKE A CUSTOM RETROID POCKET NOVA BOOT LOGO
-------------------------------------------
1. Double-click NovaSplashMaker.bat
2. Choose your PNG / JPG / BMP
3. Pick Fit / Crop
4. Click GENERATE SPLASH.IMG

That's it if you only want to create/share an image.
NO USB DEBUGGING, DRIVER, ADB, FASTBOOT, OR PYTHON IS NEEDED TO GENERATE.

FLASH IT TO A NOVA
------------------
The first time only:
1. Click SET UP FASTBOOT inside the app.
2. Click "Open Official Download Page".
3. Download Google's Platform Tools for Windows.
4. Extract it.
5. Click "Select Platform-Tools Folder" and choose that extracted folder.

The app remembers the folder after that.

Then:
1. Put the Nova into Fastboot Mode.
2. Connect USB.
3. Click CHECK NOVA.
4. Generate/select your splash.
5. Click FLASH LOGO.
6. Click REBOOT NOVA.

IMPORTANT WINDOWS DRIVER
------------------------
If CHECK NOVA cannot find the handheld:
- Open Device Manager while Nova is in Fastboot Mode.
- The device should be "Android Bootloader Interface".
- If it appears as "Android" with a yellow warning icon, install/select the Android Bootloader Interface driver.

USB DEBUGGING?
--------------
Not required for this workflow.
The user can enter Fastboot manually.

SAFETY
------
Nova Splash Maker verifies:
- Output image = exactly 33,554,432 bytes (32 MiB)
- Connected device reports splash partition = 0x2000000

If the splash partition does not match, FLASH LOGO is refused.

FORMAT
------
Retroid Pocket Nova verified splash format:
- splash partition
- 32 MiB
- 1280 x 960 / 4:3
- DDPH v1
- indexed 8-bit BMP at offset 0x4000

FILES
-----
NovaSplashMaker.bat  -> double-click this
NovaSplashMaker.ps1  -> app code
README.txt           -> instructions
sample/              -> example artwork

SHARING
-------
Share the whole ZIP. Recipients do NOT need your splash_stock.img.


BUTTON GUIDE
------------
SET UP FASTBOOT
  First time only. Point the app to Google's extracted platform-tools folder.

CHECK NOVA
  Put Nova in Fastboot Mode, connect USB, then click this.
  The app verifies the device and the 32 MiB splash partition.

FLASH LOGO
  Writes the generated splash.img to the Nova splash partition.
  This button stays disabled until CHECK NOVA succeeds.

REBOOT NOVA
  Use after FLASH LOGO completes successfully.


DISPLAY / WINDOW FIX IN v0.4
----------------------------
- Window is resizable.
- Maximize is enabled.
- App auto-fits to the current Windows desktop size.
- On smaller screens it starts maximized automatically.
- Scrollbars appear if Windows scaling still makes the UI larger than the screen.
- Better for 720p/768p displays and 125%-150% Windows scaling.




LAYOUT FIX IN v0.5

------------------

- The Optional Flash section is taller so the helper notes are no longer cut off.

- Bottom warning/log area moved lower.

- Slightly taller minimum window to avoid clipped text.



GUIDED UI IN v0.6
-----------------
- Added a live "Current step" message.
- Added 4-step workflow labels: SETUP > CHECK > FLASH > REBOOT.
- Added hover ToolTips to the important buttons.
- FLASH remains locked until CHECK NOVA verifies the correct splash partition.


BUG FIX IN v0.7
---------------
- Fixed startup crash caused by applying AutoSize to the warning label before that label existed.
- The guided UI and ToolTips from v0.6 are retained.


UI FIX IN v0.8
--------------
- Removed the long helper labels under each button.
- Added one compact scrollable instruction box instead.
- Buttons are numbered 1-4 to make the order obvious.
- ToolTips still provide detailed explanations.
- This avoids clipped notes on 720p/768p screens and high Windows scaling.


EASIER FASTBOOT SETUP IN v0.9
-----------------------------
Recommended folder:
  C:\platform-tools

Expected file:
  C:\platform-tools\fastboot.exe

Simple setup:
1. Download Google Platform Tools for Windows.
2. Extract the ZIP.
3. Move the extracted "platform-tools" folder directly to C:\
4. Open Nova Splash Maker.
5. SET UP FASTBOOT > USE C:\platform-tools

The tool already auto-detects C:\platform-tools on future runs.


FASTBOOT HELP IN v1.0
---------------------
Step 2 now has a built-in "HOW TO ENTER FASTBOOT MODE" guide.

Manual method:
1. Shut down Nova.
2. Hold VOLUME DOWN.
3. While holding VOLUME DOWN, press/hold POWER.
4. Wait for the FastBoot Mode screen.
5. Connect USB.
6. Click CHECK NOVA.

This manual method does not require USB Debugging.

Optional Android method:
  adb reboot bootloader
This requires USB Debugging to already be enabled.


FULL METHOD 2 IN v1.1 - FROM ANDROID
------------------------------------
1. On Nova, open Settings > About device.
2. Find Build number and tap it 7 times to enable Developer Options.
3. Go to Settings > System > Developer options.
4. Turn ON USB debugging.
5. Connect Nova to the PC with a USB data cable.
6. Accept "Allow USB debugging?" on the Nova.
7. Make sure Platform Tools are at:
     C:\platform-tools
8. Open CMD or PowerShell in:
     C:\platform-tools
9. Run:
     adb.exe devices
10. Confirm Nova appears as:
     device
    If it says unauthorized, unlock Nova and accept the USB debugging prompt.
11. Run:
     adb.exe reboot bootloader
12. Nova reboots into Fastboot Mode.
13. Return to Nova Splash Maker and click CHECK NOVA.

Method 2 requires USB Debugging.
Method 1 using the hardware buttons does not.


STEP 2 UI CHANGE IN v1.2
------------------------
"HOW TO ENTER FASTBOOT" is now attached directly under:
  2. CHECK NOVA

This makes it obvious that Fastboot Mode is part of Step 2.
The help window includes:
- Method 1: hardware buttons, no USB Debugging required
- Method 2: full Android + USB Debugging + ADB instructions


BOOT ANIMATION MAKER IN v1.3
----------------------------
Boot Animation Maker is now integrated into the same tool.

Supported animation sources:
- Animated GIF
- Folder of PNG/JPG/JPEG/BMP frames (played in filename order)

Output:
- Android bootanimation.zip
- Ready-to-install Magisk module ZIP

Nova boot animation settings:
- Resolution: 1280x960
- FPS choices: 10 / 12 / 15 / 20 / 24 / 30
- Fit Black / Fit White / Fill-Crop / Stretch
- Loops until Android finishes booting

INSTALL:
1. Generate the Magisk ZIP.
2. Copy it to Nova.
3. Open Magisk.
4. Modules > Install from storage.
5. Select the generated Magisk ZIP.
6. Reboot.

IMPORTANT:
- Splash logo uses Fastboot and does NOT require root.
- Boot animation uses a Magisk module and DOES require Magisk/root.
- MP4 is not supported in v1.3. Convert MP4 to GIF or PNG frames first.

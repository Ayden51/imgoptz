imgoptz user guide
==================

imgoptz makes JPG and PNG files smaller on Windows.

Open imgoptz.exe, paste one image folder path, preview the results, and choose
whether to save the optimized files. By default, originals are not replaced.


First run
---------

1. Extract the whole zip file.

   Do not run imgoptz.exe from inside the zip preview window.

2. Keep the extracted files together.

   imgoptz.exe needs imgoptz.json, profiles, schema, tools, README.txt, and
   LICENSE.txt beside it.

3. Double-click imgoptz.exe.

4. Paste one folder path when the console asks for it.

   Example:

     C:\Users\YourName\Pictures\Trip

5. Press Enter and wait for the preview.

6. Save or discard the optimized files.

   Type y or yes to save.

   Press Enter, type N, or type no to discard.

7. Paste another folder path, or type exit to close the app.


Closing the app
---------------

At the folder prompt, type exit and press Enter.


What gets processed
-------------------

Supported files:

  .jpg
  .jpeg
  .png

Other files are ignored. By default, imgoptz checks only the folder you enter.
It does not search subfolders unless you turn on recursive mode.

Paths with spaces are okay. These both work:

  C:\Users\YourName\Pictures\Summer Trip
  "C:\Users\YourName\Pictures\Summer Trip"


Where files are saved
---------------------

Default settings:

  dry_run = true
  output_mode = dir
  out_dir = ~/imgoptz-output

This means imgoptz previews optimized files first. If you approve, it saves
smaller optimized files in an imgoptz-output folder inside the selected folder.

Example:

  You enter:
  C:\Users\YourName\Pictures\Trip

  Optimized files are saved in:
  C:\Users\YourName\Pictures\Trip\imgoptz-output

Only files that become smaller are saved. Files that do not become smaller are
skipped.


What the summary means
----------------------

Ready:
  The preview output is smaller and can be saved if you approve.

Succeeded:
  The optimized file was saved.

Skipped:
  The optimized output was not smaller, so no file was written.

Failed:
  imgoptz could not process that file. The original file was left unchanged.

Potential savings:
  Space that can be saved if you approve the preview.

Saved:
  Space saved after final files were written.


Common settings
---------------

Open imgoptz.json in Notepad to change settings.

Important: true and false must be lowercase and must not use quotes.

Search subfolders:

  "recursive": true,

Change the largest allowed width or height:

  "max_dimension": 1920,

Preview first and ask before saving:

  "dry_run": true,

Save optimized files to an output folder:

  "output_mode": "dir",
  "out_dir": "~/imgoptz-output",

Replace original files after approval:

  "output_mode": "in-place",

Write a troubleshooting log:

  "debug_log": true,

If imgoptz says the config is invalid, check for missing commas, quoted boolean
values such as "true", misspelled output modes such as "inplace", and empty
path values. If the config file is broken, imgoptz uses safe default settings.


Replacing originals
-------------------

The default mode does not replace originals.

Use in-place mode only if you want approved optimized files to replace original
image files:

  "output_mode": "in-place",

imgoptz still creates temporary files first. It replaces an original only when
the optimized file is smaller and you approve the prompt while dry_run is true.

Start with a copy of important photos if you are trying new settings.


Troubleshooting
---------------

The app says a tool is missing:
  Please extract the full zip again. Do not move imgoptz.exe by itself.

The app closes or does not start:
  Please use Windows and make sure the whole app folder was extracted.

Windows shows a security warning:
  This can happen with downloaded apps. Continue only if you downloaded imgoptz
  from the official GitHub release page and trust it.

No files are found:
  Please check that the folder contains .jpg, .jpeg, or .png files. If the files
  are in subfolders, set "recursive" to true in imgoptz.json.

No optimized files are saved:
  The optimized files may not have been smaller, or you may have declined the
  approval prompt.

Images fail to process:
  The image may be corrupt or unsupported. Set "debug_log" to true in
  imgoptz.json if you need a detailed log file.


Files to keep
-------------

Every file bundled in the release zip is mandatory. Do not delete or move any of
these files from the app folder:

  imgoptz\
  ├─ imgoptz.exe
  ├─ README.txt
  ├─ LICENSE.txt
  ├─ imgoptz.json
  ├─ schema\
  │  └─ imgoptz.schema.json
  ├─ profiles\
  │  ├─ sRGB2014.icc
  │  └─ sRGB2014.LICENSE.txt
  └─ tools\
     ├─ imagemagick\
     │  ├─ magick.exe
     │  ├─ LICENSE.txt
     │  ├─ NOTICE.txt
     │  └─ policy.xml
     ├─ mozjpeg\
     │  ├─ mozjpeg.exe
     │  ├─ LICENSE.md
     │  ├─ README.ijg
     │  └─ README-mozilla.txt
     ├─ oxipng\
     │  ├─ oxipng.exe
     │  └─ LICENSE
     └─ pngquant\
        ├─ pngquant.exe
        ├─ COPYRIGHT
        └─ SOURCE.txt


License and notices
-------------------

imgoptz uses third-party tools to optimize images. Their license and notice
files are included in the tools and profiles folders.

This software is based in part on the work of the Independent JPEG Group.

See LICENSE.txt for the imgoptz license. See these files for third-party license
details:

  imgoptz\
  ├─ profiles\
  │  └─ sRGB2014.LICENSE.txt
  └─ tools\
     ├─ imagemagick\
     │  ├─ LICENSE.txt
     │  └─ NOTICE.txt
     ├─ mozjpeg\
     │  ├─ LICENSE.md
     │  ├─ README.ijg
     │  └─ README-mozilla.txt
     ├─ oxipng\
     │  └─ LICENSE
     └─ pngquant\
        ├─ COPYRIGHT
        └─ SOURCE.txt

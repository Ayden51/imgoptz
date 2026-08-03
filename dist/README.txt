imgoptz user guide
==================

What imgoptz does
-----------------

imgoptz makes JPG and PNG image files smaller.

You choose one folder at a time. imgoptz checks the images in that folder,
creates optimized versions, shows you the result, and asks before saving.

By default, your original images are not replaced. Optimized files are saved in
a new folder named imgoptz-output inside the folder you selected.


Before you start
----------------

1. Extract the whole zip file first.

   Do not run imgoptz.exe from inside the zip preview window.

2. Keep the files and folders together.

   imgoptz.exe needs imgoptz.json, profiles, schema, tools, README.txt, and
   LICENSE.txt to stay beside it.

3. Use it on JPG and PNG files only.

   Supported file types are .jpg, .jpeg, and .png.

4. Start with a copy of important photos if you are trying new settings.

   The default mode is safe, but keeping backups is always a good habit.


Quick start
-----------

1. Double-click imgoptz.exe.

2. A console window opens.

3. When it asks for a folder path, paste one folder path.

   Example:

   C:\Users\YourName\Pictures\Trip

4. Press Enter.

5. Wait while imgoptz checks and optimizes the images.

6. Review the summary.

7. When imgoptz asks whether to save the optimized files:

   Type y or yes, then press Enter, to save them.

   Type N or no, then press Enter, to discard them.

8. Paste another folder path, or type exit to close the app.


Where optimized files go
------------------------

Default setting:

  output_mode = dir
  out_dir = ~/imgoptz-output

This means imgoptz creates optimized files in a folder named imgoptz-output
inside the image folder you selected.

Example:

  You enter:
  C:\Users\YourName\Pictures\Trip

  Optimized files are saved in:
  C:\Users\YourName\Pictures\Trip\imgoptz-output

Only files that become smaller are saved. If an optimized file is not smaller,
imgoptz skips it.


What the results mean
---------------------

Ready or Succeeded:
  The optimized file was smaller and can be saved.

Skipped:
  The optimized file was not smaller, so imgoptz did not keep it.

Failed:
  imgoptz could not process that file. The original file is left unchanged.

Potential savings:
  How much space could be saved if you approve the results.

Saved:
  How much space was saved after final files were written.


Using paths with spaces
-----------------------

Folder paths with spaces are okay.

These both work:

  C:\Users\YourName\Pictures\Summer Trip
  "C:\Users\YourName\Pictures\Summer Trip"


Searching subfolders
--------------------

By default, imgoptz only checks the folder you enter.

To include subfolders:

1. Open imgoptz.json in Notepad.
2. Find this line:

   "recursive": false,

3. Change it to:

   "recursive": true,

4. Save the file.
5. Open imgoptz.exe again.


Replacing original files
------------------------

The default mode does not replace originals.

If you want imgoptz to replace original files after approval, edit imgoptz.json:

  "output_mode": "in-place",

Keep this setting only if you understand that approved optimized files will
replace the original image files. imgoptz still asks before saving when
dry_run is true.


Useful settings
---------------

Open imgoptz.json in Notepad to change settings.

Important: true and false must be lowercase and must not use quotes.

Common settings:

  "recursive": false
    Search only the folder you enter.

  "recursive": true
    Search the folder you enter and its subfolders.

  "max_dimension": 1920
    Shrink large images so width and height fit within this size.

  "dry_run": true
    Preview first and ask before saving files.

  "output_mode": "dir"
    Save optimized files into an output folder.

  "output_mode": "in-place"
    Replace original files after approval.

  "out_dir": "~/imgoptz-output"
    Save output inside the selected folder.

  "debug_log": true
    Write a detailed log file for troubleshooting.


If imgoptz says a setting is invalid
------------------------------------

Check these common problems:

1. Missing comma between settings.
2. Quoted true or false values, such as "true" instead of true.
3. Misspelled output mode, such as inplace instead of in-place.
4. Empty path values.

If the config file is broken, imgoptz uses safe default settings.


Troubleshooting
---------------

The app says a tool is missing:
  Extract the full zip again. Do not move imgoptz.exe by itself.

The app closes or does not start:
  Make sure you are using Windows and that the whole app folder was extracted.

Windows shows a security warning:
  This can happen with downloaded apps. Choose to keep or run the app only if
  you downloaded it from the official GitHub release page and trust it.

No files are found:
  Make sure the folder contains .jpg, .jpeg, or .png files. If the files are in
  subfolders, set recursive to true in imgoptz.json.

No optimized files are saved:
  The optimized files may not have been smaller, or you may have declined the
  approval prompt.

Images fail to process:
  The image may be corrupt or unsupported. Turn on debug_log in imgoptz.json if
  you need a detailed log file.


Files included with imgoptz
---------------------------

Do not delete these files from the app folder:

  imgoptz.exe
  README.txt
  LICENSE.txt
  imgoptz.json
  schema\imgoptz.schema.json
  profiles\sRGB2014.icc
  profiles\sRGB2014.LICENSE.txt
  tools\mozjpeg\mozjpeg.exe
  tools\mozjpeg\LICENSE.md
  tools\mozjpeg\README.ijg
  tools\mozjpeg\README-mozilla.txt
  tools\oxipng\oxipng.exe
  tools\oxipng\LICENSE
  tools\pngquant\pngquant.exe
  tools\pngquant\COPYRIGHT
  tools\imagemagick\magick.exe
  tools\imagemagick\LICENSE.txt
  tools\imagemagick\NOTICE.txt
  tools\imagemagick\policy.xml


Third-party notices
-------------------

imgoptz uses third-party tools to optimize images. Their license and notice
files are included in the tools and profiles folders.

This software is based in part on the work of the Independent JPEG Group.

See these files for third-party license details:

  tools\mozjpeg\LICENSE.md
  tools\mozjpeg\README.ijg
  tools\mozjpeg\README-mozilla.txt
  tools\oxipng\LICENSE
  tools\pngquant\COPYRIGHT
  tools\imagemagick\LICENSE.txt
  tools\imagemagick\NOTICE.txt
  profiles\sRGB2014.LICENSE.txt


Closing the app
---------------

At the folder prompt, type:

  exit

Then press Enter.

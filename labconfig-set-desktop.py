#!/usr/bin/python

from AppKit import NSWorkspace, NSScreen
from Foundation import NSURL
from subprocess import call
from os import system

# "/Library/Caches/Test.jpg"
picture_path = args[4]

file_url = NSURL.fileURLWithPath_(picture_path)
options = {}
ws = NSWorkspace.sharedWorkspace()
for screen in NSScreen.screens():
	(result, error) = ws.setDesktopImageURL_forScreen_options_error_(file_url, screen, options, None)

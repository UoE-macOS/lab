#!/usr/bin/python
""" Set desktop background of all screens. Takes a path as the 4th argument.
    the path should be that of a jpg or png file, or of a directory containing
    at least one jpg or png file.

    If a file is specified, it will be set as the desktop background.
    if a directory is specifiued, we will search it for png or jpg files named
    with ether the full machine name, school-lab or school.

    eg for machine eca-alsems-m006, we would use, in this order, files named
    1. eca-alsems-m006.{jpg, png}
    2. eca-alsems.{jpg, png}
    3. eca.{jpg,png}
"""
from __future__ import print_function
from AppKit import NSWorkspace, NSScreen
from Foundation import NSURL
from subprocess import call
from os import system, listdir
import socket
import sys
import os 

my_fullname = socket.gethostname()
my_shortname = my_fullname.split('.')[0]

my_school = my_shortname.split('-')[0]
my_lab = my_shortname.split('-')[1]
my_number = my_shortname.split('-')[2]

print("School: ", my_school)
print("Lab: ", my_lab)
print("Number: ", my_number)

path = str(sys.argv[4])
picture_path = None

valid_types = ['jpg', 'png']

for file_type in valid_types:
    # If we've been given a path to an image file, just use it.
    if path.endswith(file_type):
        picture_path = path
        break

    # Otherwise, assume we have been given a directory
    # and search hierarchically for a machine-, lab-, or 
    # school-level image.
    if not os.path.isdir(path):
        print("Not a jpg, png or a directory: ", path)
        sys.exit(1)

    # Match files in the picture dir in order of preference
    candidates = os.listdir(path)

    if '{}.{}'.format(my_shortname, file_type) in candidates:
        picture_path = os.path.join(path, "{}.{}".format(my_shortname, file_type))
        break

    if '{}-{}.{}'.format(my_school, my_lab, file_type) in candidates:
        picture_path = os.path.join(path, '{}-{}.{}'.format(my_school, my_lab, file_type))
        break

    if '{}.{}'.format(my_school, file_type) in candidates:
        picture_path = os.path.join(path, "{}.{}".format(my_school, file_type))
        break

if not picture_path:
    print("Couldn't find a picture for ", my_shortname)
    sys.exit(0)

print('Picture Path - ', picture_path)

# file_url = NSURL.fileURLWithPath_(picture_path)
# options = {}
# ws = NSWorkspace.sharedWorkspace()
# for screen in NSScreen.screens():
#     (result, error) = ws.setDesktopImageURL_forScreen_options_error_(file_url,
#                                                                      screen, options, None)

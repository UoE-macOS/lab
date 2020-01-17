#!/usr/bin/python

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

if path.endswith('.jpg') or path.endswith('.png'):
    picture_path = path
else:
    if not os.path.isdir(path):
        print("Not a jpg, png or a directory:", path)
        sys.exit(1)
        # Match files in the picture dir in order of preference
    candidates = os.listdir(path)
    if my_shortname in candidates:
        picture_path = os.path.join(path, my_shortname)
    elif '-'.join((my_school, my_lab)) in candidates:
        picture_path = os.path.join(path, '-'.join((my_school, my_lab)))
    elif my_school in candidates:
        picture_path = os.path.join(path, my_school)
    else:
        print("Couldn't find a picture for ", my_shortname)
        sys.exit(0)


print('Picture Path - ', picture_path)

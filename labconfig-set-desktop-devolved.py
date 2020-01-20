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
import socket
import sys
import os
from AppKit import NSWorkspace, NSScreen
from Foundation import NSURL

VALID_TYPES = ['jpg', 'png']

def main():
    """ Find and apply the most appropriate desktop pic for this machine """
    final_path = find_picture(str(sys.argv[4]))

    if not final_path:
        sys.exit(1)

    print('Picture Path - ', final_path)

    file_url = NSURL.fileURLWithPath_(final_path)
    options = {}
    ws = NSWorkspace.sharedWorkspace()
    for screen in NSScreen.screens():
        (result, error) = ws.setDesktopImageURL_forScreen_options_error_(file_url,
                                                                         screen, options, None)


def find_picture(path):
    """ Return the most appropriate desktop picture for this machine
        or None if we can't find one
    """
    my_fullname = socket.gethostname()
    my_shortname = my_fullname.split('.')[0]

    my_school = my_shortname.split('-')[0]
    my_lab = my_shortname.split('-')[1]
    my_number = my_shortname.split('-')[2]

    print("School: ", my_school)
    print("Lab: ", my_lab)
    print("Number: ", my_number)

    picture_path = None

    for file_type in VALID_TYPES:
        # If we've been given a path to an image file, just use it.
        if path.endswith(file_type):
            return path

    # Otherwise, assume we have been given a directory
    # and search hierarchically for a machine-, lab-, or
    # school-level image.
    if not os.path.isdir(path):
        print("Not a jpg, png or a directory: ", path)
        return None

    # Match files in the picture dir in order of preference
    candidates = os.listdir(path)
    for file_type in VALID_TYPES:
        if '{}.{}'.format(my_shortname, file_type) in candidates:
            picture_path = os.path.join(path, "{}.{}".format(my_shortname, file_type))
            return picture_path

    for file_type in VALID_TYPES:
        if '{}-{}.{}'.format(my_school, my_lab, file_type) in candidates:
            picture_path = os.path.join(path, '{}-{}.{}'.format(my_school, my_lab, file_type))
            return picture_path

    for file_type in VALID_TYPES:
        if '{}.{}'.format(my_school, file_type) in candidates:
            picture_path = os.path.join(path, "{}.{}".format(my_school, file_type))
            return picture_path

    # If we got to here, we have run out of options.
    print("Couldn't find a picture for ", my_shortname)
    return None

if __name__ == "__main__":
    main()

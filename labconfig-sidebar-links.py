#!/usr/bin/env python

# Import required modules
import os
import sys
import subprocess
sys.path.append('/usr/local/python')
from FinderSidebarEditor import FinderSidebar
from SystemConfiguration import SCDynamicStoreCopyConsoleUser
from time import sleep, gmtime, strftime
import logging

# Remove current logfile if it exists
log_file = "/Library/Logs/sidebar.log"
if os.path.exists(log_file):
    os.remove(log_file)

# Create logger object
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Create console handler and set level to debug
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.DEBUG)

# Create file handler and set level to debug
file_handler = logging.FileHandler(r'/Library/Logs/sidebar.log')
file_handler.setLevel(logging.DEBUG)

# Create formatter
formatter = logging.Formatter('[%(asctime)s][%(levelname)s] %(message)s', datefmt='%a, %d-%b-%y %H:%M:%S')

# Set formatters for handlers
console_handler.setFormatter(formatter)
file_handler.setFormatter(formatter)

# Add handlers to logger
logger.addHandler(console_handler)
logger.addHandler(file_handler)

logger.info("\n*** LABS FINDER SIDEBAR ***\n")

# Function to close and remove logging handlers
def close_logger():
    console_handler.close()
    file_handler.close()
    logger.removeHandler(console_handler)
    logger.removeHandler(file_handler)

# Get logged in user
username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]
NetUser = [username,""][username in [u"loginwindow", None, u""]]
logger.info("Logged in user is " + NetUser)

# The python plugin appears to be a bit more robust if a Finder window is open, so lets do that.
# Open Finder window at root of drive. User shouldn't notice as it will be behind the jamf Helper window.
path = "/"
subprocess.call(["open", path])

# Create sidebar instance
sidebar = FinderSidebar()

# REMOVE ALL SIDEBAR ENTRIES
sidebar.removeAll()

# PREPARE TO ADD ENTRIES BACK
# Get Desktop path
desktop_mount = "/Users/" + NetUser + "/Desktop"
logger.info("Path to Desktop folder : " + desktop_mount)
# Get Documents path
documents_mount = "/Users/" + NetUser + "/Documents"
logger.info("Path to Documents : " + documents_mount)
# Get downloads path
downloads = "Users/" + NetUser + "/Downloads"
logger.info("Path to Downloads : " + downloads)
# Get Applications path
apps = "/Applications"

# Check if home space is mounted first. If so add the sidebar entries
if not (os.path.isdir("/Volumes/" + NetUser)):
    logger.error("Homespace does not appear to be mounted. Exiting script.")
    close_logger()
    exit(1)

logger.info("Homespace appears to be mounted.")

# ADD ENTRIES TO SIDEBAR
logger.info("Attempting to add sidebar entries..")
# Applications
logger.info("Applications..")
sidebar.add(apps)
# Downloads
logger.info("Downloads..")
sidebar.add(downloads)
# M: drive
logger.info("Homespace..")
sidebar.add("/Volumes/" + NetUser)
# Documents
logger.info("Documents..")
sidebar.add(documents_mount)
# Desktop
logger.info("Desktop..")
sidebar.add(desktop_mount)

# Remove iCloud entry as it sometimes seems to re-appear.
sidebar.remove("iCloud")

# Close all Finder windows
logger.info("Closing Finder Window..")
# Set Apple script command to run
cmd = """tell application "Finder" to close every window"""
# Close all Finder windows
subprocess.call(['osascript', '-e', cmd])

logger.info("Sidebar config complete.")

# Close and exit the logger
close_logger()

# Exit script
exit(0)

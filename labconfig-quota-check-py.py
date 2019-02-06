#!/usr/bin/env python

# Import modules
import os
import sys
from SystemConfiguration import SCDynamicStoreCopyConsoleUser
import subprocess
import commands
import signal
import logging

log_file = "/Library/Logs/quota-check-py.log"
if os.path.exists(log_file):
    os.remove(log_file)

# Create logger object and set default logging level
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Create console handler and set level to debug
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.DEBUG)

# Create file handler and set level to debug
file_handler = logging.FileHandler(r'/Library/Logs/quota-check-py.log')
file_handler.setLevel(logging.DEBUG)

# Create formatter
formatter = logging.Formatter('[%(asctime)s][%(levelname)s] %(message)s', datefmt='%a, %d-%b-%y %H:%M:%S')

# Set formatters for handlers
console_handler.setFormatter(formatter)
file_handler.setFormatter(formatter)

# Add handlers to logger
logger.addHandler(console_handler)
logger.addHandler(file_handler)

# Display heading for log file
logger.info("\n*** LAB QUOTA CHECK ***\n")

# Get logged in user
username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]
NetUser = [username,""][username in [u"loginwindow", None, u""]]
logger.info("Logged in user is " + NetUser)

def kill_jh():
    # Get jamfhelper PID. By default check_output returns "\n" at the end of it's line, so we want to strip the new line so it's not included in the output.
    # By default, check_output also returns an exception if there is a problem, so using a try
    try:
        jh_process = subprocess.check_output('pgrep jamfHelper', shell=True).strip()
    # If Jamf Helper is not running then break from the function
    except:
        logger.warn("No Jamf Helper process is running")
        return
    # As it's a string, convert it to integer
    jh_pid = int(jh_process)
    logger.info("jamfHelper process ID : %d" % jh_pid)
    # Kill the process
    os.kill(jh_pid, signal.SIGTERM)

# Display logout message if for some reason the redirect fails
def display_warning():
    logger.info("Displaying warning message.")
    # jamf helper icon location
    icon = '/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns'
    # jamf helper command to run
    helper_cmd = [
        '/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper',
        '-windowType', 'utility',
        '-title', 'University Lab Mac - QUOTA WARNING!',
        '-heading', 'QUOTA WARNING!',
        '-icon', icon,
        '-description', 'You are using over 95% of your allocated quota for data storage on your M: drive. Please be aware that if you attempt to save anything to your Desktop, Documents, Movies, Music or Pictures folder then this counts towards your allocated storage space.\n\nExceeding your quota can lead to loss of data and cause computer performance issues. It is strongly recommended that you attempt to free up some space.\n\nSelect "I understand" below to coninue logging in.',
        '-button1', 'I understand',
    ]

    # Run jamf helper process
    jh_window = subprocess.call(helper_cmd)
    # Close jamf helper window after user has selected "I understand"
    kill_jh()

# Function to check if homespace is already mounted
def check_mount(uun):
    if os.path.ismount("/Volumes/" + uun):
        return True
    else:
        return False

# *** Begin main program ***

# Check to make sure homespace is mounted
logger.info("Is homeshare mounted?")
if (check_mount(NetUser) == False):
    logger.warn("/Volumes/" + NetUser + " does not appear to be mounted. Unable to check quota.")
    # Exit script
    sys.exit(1)
else:
    logger.info("/Volumes/" + NetUser + " appears to be mounted.")

# Get usage
# Get disk details
disk = os.statvfs("/Volumes/" + NetUser)
# Get percentage and display in log
percentage = (disk.f_blocks - disk.f_bfree) * 100 / (disk.f_blocks -disk.f_bfree + disk.f_bavail) + 1
logger.info("Usage is %d %%." % percentage)
# If the usage is 95% or over then display the warning message
if percentage >= 95:
    logger.warn(NetUser + " using over 95% of quota.")
    display_warning()

# Log message to show that script has completed.
logger.info("Labs quota check complete.\n")

# Close and remove the logging handlers
console_handler.close()
file_handler.close()
logger.removeHandler(console_handler)
logger.removeHandler(file_handler)

# Exit script
sys.exit(0)

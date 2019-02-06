#!/usr/bin/env python

import datetime
import logging
import subprocess
import commands
import time
import signal
from SystemConfiguration import SCDynamicStoreCopyConsoleUser
import os

# Check to see if script has run today by looking at the creation date on the log file
# Get current day and time, convert to short version so we can check against log by extracting day, month and year.
current_date = datetime.datetime.now()
current_day = current_date.strftime("%d")
current_month = current_date.strftime("%b")
current_year = current_date.strftime("%y")
# Concatenate strings so we can compare to the log
current_short_date = current_day + "-" + current_month + "-" + current_year

# Log file location
log_file = "/Library/Logs/nightly-reboot-py.log"

# Check if log file currently exists
log_file_exists = os.path.isfile(log_file)
if log_file_exists == True:
    # Get creation timestamp on logfile
    log_file_date_ = os.path.getctime(log_file)
    # Convert to datetime format
    log_file_date = datetime.datetime.fromtimestamp(log_file_date_)
    log_file_day = log_file_date.strftime("%d")
    log_file_month = log_file_date.strftime("%b")
    log_file_year = log_file_date.strftime("%y")
    # Concatenate string so we can compare to the current date
    log_file_created = log_file_day + "-" + log_file_month + "-" + log_file_year
    # If the logfile was created today then reboot has already occurred
    if log_file_created == current_short_date:
        print "Reboot already done today. Exiting script."
        exit()
    else:
        # Else, restart the computer
        print "No restart has been done today. Restarting computer and removing last log file."
        os.remove(log_file)
else:
    print "No log file exists. Moving on."

# Create logger object
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Create console handler and set level to debug
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.DEBUG)

# Create file handler and set level to debug
file_handler = logging.FileHandler(r'/Library/Logs/nightly-reboot-py.log')
file_handler.setLevel(logging.DEBUG)

# Create formatter
formatter = logging.Formatter('[%(asctime)s][%(levelname)s] %(message)s', datefmt='%a, %d-%b-%y %H:%M:%S')

# Set formatters for handlers
console_handler.setFormatter(formatter)
file_handler.setFormatter(formatter)

# Add handlers to logger
logger.addHandler(console_handler)
logger.addHandler(file_handler)

# Declare location of university logo
uni_logo ="/usr/local/jamf/UoELogo.png"

# Function to close and remove logging handlers
def close_logger():
    console_handler.close()
    file_handler.close()
    logger.removeHandler(console_handler)
    logger.removeHandler(file_handler)

# Function for killing jamf helper process
def kill_jh():
    # Get jamfhelper PID. By default check_output returns "\n" at the end of it's line, so we want to strip the new line so it's not included in the output.
    # Bu default, check_output also returns an exception if there is a problem, so using a try
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

def display_countdown():
    counter = 15
    while (counter):
        logger.info("Countdown is %d. Displaying jamf helper message to user." % counter)
        # Prepare jamf helper window
        helper_cmd = [
            '/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper',
            '-windowType', 'utility',
            '-title', 'Nightly Mac Lab restart',
            '-heading', 'Automatic restart.',
            '-icon', uni_logo,
            '-description', 'This Mac will perform its nightly restart in %d minute(s). Please save your work.' % counter,
            '-timeout', '60',
        ]
        # Display window
        jh_window = subprocess.call(helper_cmd)
        counter -= 1

    # Just incase there are is a jamf helper processes running, kill it.
    kill_jh


# *** Begin main program ***

# Display heading for log file
logger.info("\n*** LAB NIGHTLY RESTART ***\n")

# Make sure jamf helper exists!
jamf_helper = "/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
jh_exists = os.path.isfile(jamf_helper)
# If jamf helper doesn't exist then exit the script, as we can't alert the user to the restart
if jh_exists == False:
    logger.error("Jamf Helper cannot be found at " + jamf_helper + ". This script will now exit.")
    exit(1)
else:
    logger.info("Jamf Helper found!")

# Make sure the university logo exists
uni_logo_exists = os.path.isfile(uni_logo)
if uni_logo_exists == False:
    logger.warn("Cannot find the university logo. Will continue without.")
else:
    logger.info("University logo found!")

# Get logged in user
username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]
NetUser = [username,""][username in [u"loginwindow", None, u""]]

logger.info("Checking to see if a user is logged in...")

if NetUser is not "":
    logger.info(NetUser + " is currently logged in. Displaying countdown.")
    # Display countdown
    display_countdown()
    # Prepare window showing final message for restart
    restart_window = [
        '/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper',
        '-windowType', 'utility',
        '-icon', uni_logo,
        '-heading', 'Restarting...',
        '-description','This Mac will now restart. You cannot halt this process.',
        '-timeout', '60',
    ]

    # Display final restart message
    jh_restart = subprocess.Popen(restart_window)
else:
    logger.info("No user currently logged in. Restarting.")

# Restart the computer in 1 minute time (should start in background so that policy can complete)
subprocess.Popen(['shutdown','-r', '+1'])

# Display log message for completion.
logger.info("Nightly reboot script complete.")

# Close the log handlers
close_logger()

exit()

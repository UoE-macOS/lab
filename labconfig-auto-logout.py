#!/usr/bin/env python
# -*- coding: utf-8 -*-

# Import modules
import os
import sys
from SystemConfiguration import SCDynamicStoreCopyConsoleUser
import subprocess
import commands
import signal
import logging
import thread
import threading
import time

# Declare location of university logo
uni_logo ="/usr/local/jamf/UoELogo.png"

log_file = "/Library/Logs/auto-logout-py.log"
if os.path.exists(log_file):
    os.remove(log_file)

# Create logger object and set default logging level
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Create console handler and set level to debug
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.DEBUG)

# Create file handler and set level to debug
file_handler = logging.FileHandler(r'/Library/Logs/auto-logout-py.log')
file_handler.setLevel(logging.DEBUG)

# Create formatter
formatter = logging.Formatter('[%(asctime)s][%(levelname)s] %(message)s', datefmt='%a, %d-%b-%y %H:%M:%S')

# Set formatters for handlers
console_handler.setFormatter(formatter)
file_handler.setFormatter(formatter)

# Add handlers to logger
logger.addHandler(console_handler)
logger.addHandler(file_handler)

# Function to close and remove logging handlers
def close_logger():
    console_handler.close()
    file_handler.close()
    logger.removeHandler(console_handler)
    logger.removeHandler(file_handler)

# Function for killing jamf helper process
def kill_jh():
    # Get all jamfhelper PIDs and kill. By default check_output returns "\n" at the end of it's line, so we want to strip the new line so it's not included in the output.
    # By default, check_output also returns an exception if there is a problem, so using a try
    try:
        jh_process = subprocess.check_output(['pgrep','jamfHelper']).strip()
    # If Jamf Helper is not running then break from the function
    except:
        logger.info("No Jamf Helper process is running")
        return
    # For each jamf helper process
    for proc in jh_process.splitlines():
        # As it's a string, convert it to integer
        jh_pid = int(proc)
        logger.info("Killing jamfHelper process ID : %d" % jh_pid)
        # Kill the process
        os.kill(jh_pid, signal.SIGTERM)

# Function to force logout
def force_logout():
    logger.warn("Starting logout process. Displaying message to user.")
    # Prepare jamf helper message
    logout_message = [
        '/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper',
        '-windowType', 'utility',
        '-icon', uni_logo,
        '-heading', 'Automatic logout after 30 minutes idle.',
        '-description', 'THIS MAC WILL NOW LOGOUT. YOU CANNOT HALT THIS PROCESS.',
        '-timeout', '5',
    ]

    # Display message to user
    log_out_window = subprocess.call(logout_message)

    # Force quit all open apps
    logger.info("Attempting to force quit all open apps.")
    # Get the process numbers in a temporary variable - unfortunately it grabs this as a string, so we need to convert it eventually
    running_processes_ = subprocess.check_output('ps axww -o pid,command | grep -v bash | grep [A]pplications/ | grep -v /bin/sh | grep -v [J]amf | grep -v [S]elf\ Service | grep -v grep | awk \'{print $1}\'', shell=True)
    # Grab all numerical digits from the string, convert to integers and store them in an array
    running_processes = [int(pr) for pr in running_processes_.split() if pr.isdigit()]
    # For each process, attempt to kill it.
    for process in running_processes:
        try:
            logger.info("Attmepting to close PID %d" % process)
            os.kill(process, signal.SIGKILL)
        except:
            logger.error("Unable to quit PID %d !" % process)


    # Just in case there was anything left that the above did not catch / kill, try a more graceful way of force quiting apps using Apple script
    apple_script_cmd = '''
        tell application "System Events"
            set listOfProcesses to (name of every process where background only is false)
        end tell
        repeat with processName in listOfProcesses
            do shell script "Killall " & quoted form of processName
        end repeat'''
    # Run the apple script command
    proc = subprocess.Popen(['osascript', '-'],
                        stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE)
    stdout_output = proc.communicate(apple_script_cmd)[0]
    print stdout_output

    logger.info("All apps now closed.")
    logger.info("***** Performing automatic logout ******")
    # Prepare logout command
    logout_cmd = '''tell application "loginwindow" to  «event aevtrlgo»'''
    # Logout
    subprocess.call(['osascript', '-e', logout_cmd])
    logger.info("Done.")

# Function to display initial warning message
def display_logout_message():
    # Make sure the function can grab the value of the countdown timer
    global countdown_timer
    jh_window_cmd = [
        '/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper',
        '-windowType', 'utility',
        '-heading', 'University Lab Mac - Auto-Logout',
        '-description', 'This Mac has been logged in and idle for over 10 minutes.\n\nFor security reasons, you will be automatically logged out in %d minute(s) if the Mac remains idle.\n\nANY UNSAVED WORK WILL BE LOST\n\n' % countdown_timer,
        '-icon', uni_logo,
    ]
    # Show message. If the idle time is 0 then throw the exception
    try :
        jh_window = subprocess.call(jh_window_cmd)
    except KeyboardInterrupt as e:
        logger.info("Countdown has been interrupted by " + NetUser)


# Function to start logout countdown from 20. Run as a thread.
def countdown():
    # Make sure this function can grab the value of the kill thread variable and countdown timer
    global kill_thread
    global countdown_timer
    # Countdown starts at 20 minutes
    countdown_timer = 20
    # Whlie the countdown is greater than 0 and kill_thread is set to false, start the timer
    while (countdown_timer > 0 and not kill_thread):
        logger.warn("Countdown timer now at %d minutes." % countdown_timer)
        # Sleep for 1 minute
        time.sleep(60)
        # Kill the current jamf helper window
        kill_jh()
        # Decrease the timer by 1
        countdown_timer -= 1
        # If the countdown timer is equal to 0, break from the loop
        if countdown_timer == 0:
            break
    # Return from function, which should end the thread
    return

# Function to return idle time
def get_idle_time():
    # Minutes
    idle_time_ = subprocess.check_output('/usr/sbin/ioreg -c IOHIDSystem | /usr/bin/awk \'/HIDIdleTime/ {print int($NF/1000000000)/60; exit}\' | awk -F "." \'{print $1}\'', shell=True)
    # Seconds - used for testing purposes
    #idle_time_ = subprocess.check_output('/usr/sbin/ioreg -c IOHIDSystem | /usr/bin/awk \'/HIDIdleTime/ {print int($NF/1000000000); exit}\' | awk -F "." \'{print $1}\'', shell=True)
    idle_time = int(idle_time_)
    return idle_time

# Function which checks the idle time every second. Run as a thread.
def idle_time_timer():
    # Make sure we can access the global kill thread setting within this function
    global kill_thread
    # While kill thread is false
    while (not kill_thread):
        # Sleep for 1 second
        time.sleep(1)
        # Get the idle time
        idle_time = get_idle_time()
        # If the idle time is less than 10 minutes, kill the jamf helper window and send an interrupt to the main thread / script
        if idle_time < 10:
            kill_jh()
            thread.interrupt_main()
    # Return from function.
    return

# *** Begin main program ***
# ==========================

# Set global kill thread variable to false. When we want to kill the threads for the countdown and the idle timechecker then we set it to true.
global kill_thread
kill_thread = False
# Display heading for log file
logger.info("\n*** LAB AUTO LOGOUT ***\n")

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

# Find out if a user is logged in
logger.info("Checking to see if a user is logged in.")
if NetUser is not "":
    logger.info(NetUser + " is currently logged in.")
    # Get idleTime in minutes
    idle_time = get_idle_time()
    logger.info("Idle time is %d minute(s)" % idle_time)
    # If the idle time is greater than 10 minutes
    if idle_time > 10:
        # Create the countdown thread and the idle time timer thread
        countdown_thread = threading.Thread(target=countdown)
        idle_time_timer_thread = threading.Thread(target=idle_time_timer)
        # Make them deamon threads to make sure they close if the main script exits
        countdown_thread.daemon = True
        idle_time_timer_thread.daemon = True
        # Start the threads
        logger.info("Starting countdown timer")
        countdown_thread.start()
        logger.info("Starting idle timer")
        idle_time_timer_thread.start()
        # While idle time is greater than 10 minutes and less than 30
        while idle_time > 10: #and idle_time < 30:
            # There could be a timing issue between the last idle time check, so try again and if it's less than 1 then break from loop
            idle_time = get_idle_time()
            if idle_time < 1:
                break
            # If idle time is still greater than 10, display the logout message
            logger.info("Displaying auto-logout message to user.")
            display_logout_message()
            # If the countdown timer is at 0, force the logout.
            if countdown_timer < 1:
                logger.warn("Countdown has expired. Logging out.")
                force_logout()
                break
            else:
                pass
        end_idle_time = get_idle_time()
        if end_idle_time < 1:
            logger.info(NetUser + " has cancelled logout.")
    else:
        logger.info("Idle time is only %d minutes. Exiting script." % idle_time)
else:
    logger.info(" No user logged in.")
    close_logger()
    exit()

# Kill all threads
kill_thread = True
# Close the loggers
close_logger()
exit()

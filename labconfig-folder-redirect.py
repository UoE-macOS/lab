#!/usr/bin/env python

# STILL TO BE DONE
# NETSTAT STUFF - problem connecting to geoscience server (v1dst04)

# Import modules
import os
import sys
from SystemConfiguration import SCDynamicStoreCopyConsoleUser
import time
import subprocess
import signal
import platform
import socket
import Cocoa
import logging
import shutil

# Remove current log file if it exists
log_file = "/Library/Logs/folder-redirect-py.log"
if os.path.exists(log_file):
    os.remove(log_file)

# Create logger object
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)

# Create console handler and set level to debug
console_handler = logging.StreamHandler()
console_handler.setLevel(logging.DEBUG)

# Create file handler and set level to debug
file_handler = logging.FileHandler(r'/Library/Logs/folder-redirect-py.log')
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
logger.info("\n*** LAB FOLDER REDIRECT ***\n")

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

# Function for killing jamf helper process
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

# Function for school code
def get_school_code(uun):
    # Declare bash command and store in temp variable
    school_code_=""" ldapsearch -x -H "ldaps://authorise.is.ed.ac.uk" -b"dc=authorise,dc=ed,dc=ac,dc=uk" -s sub "(uid=""" + uun + """)" "eduniSchoolCode" | awk -F ': ' '/^'"eduniSchoolCode"'/ {print $2}' """
    # Get output from command
    try:
        school_code = subprocess.check_output(school_code_, shell=True).strip()
        return school_code
    except:
        logger.warn("Unable to obtain school code!")

# Function to attempt network drive mount
def attempt_mount(uun, path):
    # Get full path to mount
    full_path = '"smb:' + path + '"'
    # Display info
    logger.info("full mount path : " + full_path)
    # Prepare command
    cmd = [
        "sudo",
        "-u",
        uun,
        "osascript",
        "-e",
        "mount volume {}".format(full_path),
    ]
    logger.info(cmd)
    mount_share = subprocess.call(cmd)

# Function to check if homespace is already mounted
def check_mount(uun):
    if os.path.ismount("/Volumes/" + uun):
        return True
    elif os.path.isdir("/Volumes/" + uun):
        return True
    else:
        return False

# Function to create link to folder
def create_link(uun,folder):
    logger.info('')
    logger.info("*** " + folder + " ***")
    path_to_folder = "/Volumes/" + uun + "/" + folder
    logger.info("Path to Network folder : " + path_to_folder)
    # Check the folder already exists in the network homespace. If not then create.
    if not os.path.isdir(path_to_folder):
        logger.info(folder + "folder on homespace does not exist. Creating folder.")
        # Create folder
        os.mkdir(path_to_folder)
        # Prepare command to change owner on the folder
        chown_cmd = [
            'chown',
            '{}:staff'.format(uun),
            path_to_folder,
        ]
        logger.info(chown_cmd)
        # Change the permissions to the appropriate owner
        process = subprocess.Popen(chown_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        stdout, stderr = process.communicate()
    else:
        # Folder already exists on network home space
        logger.info(folder + " folder already exists on server. Moving on...")

    # Check to see if local folder or link exists
    logger.info("Checking to see if local folder or alias exists.")
    local_folder = "/Users/" + uun + "/" + folder
    logger.info("Path to local Folder : " + local_folder)
    # If folder or link exists
    if os.path.isdir(local_folder) or os.path.islink(local_folder):
        # If what exists is a link
        if os.path.islink(local_folder):
            logger.info("Link already exists. Removing so we can re-create.")
            # Remove the link
            os.unlink(local_folder)
        else:
            # Else the entry is a local folder. Delete.
            logger.info("Local " + local_folder + " folder exists. Deleting.")
            shutil.rmtree(local_folder)
    else:
        # Else the local folder does not exist
        logger.info("Local " + local_folder + " folder does not exist.")

    # We've had instances of folders reappearing, so hopefully this will perform another remove
    if os.path.isdir(local_folder):
        logger.warn("FOLDER " + local_folder + " HAS RE-APPEARED! Removing again..")
        os.remove(local_folder)

    # Create link to network folder
    logger.info("Creating link to " + local_folder + " on homespace.")
    os.symlink(path_to_folder, local_folder)

    # Make sure link exists
    if os.path.islink(local_folder):
        logger.info("Link to "  + folder + " successfully created!")
    else:
        logger.warn("Could not create link to " + local_folder +". Attempting again.")
        os.symlink(path_to_folder, local_folder)
        # Check again. If link still doesn't exist then quit script
        if not os.path.islink(local_folder):
            logger.error("Unable to create link to " + path_to_folder + ". Quiting login")
            close_logger()
            sys.exit(1)


##### Begin main program ######

# Get school code. If return is invalid then exit with code 1.
if (get_school_code(NetUser) == "Unknown" or get_school_code(NetUser) == "" or get_school_code(NetUser)) is None:
    logger.error("Cannot redirect folders - most likely because of one of the following: \n1. " + NetUser + " is a local account.\n2. The logged in user does not have an associated school code.\n3. Active Directory is not reachable.\nQuitting folder redirection script.")
    close_logger()
    sys.exit(1)
else:
    # School code obtained. Continue
    logger.info(NetUser + " appears to be a valid AD account.")

# Get Homepath
home_path_="""dscl localhost -read "/Active Directory/ED/All Domains/Users/""" + NetUser + """" | grep 'SMBHome:' | awk '{print $2}'"""
home_path = subprocess.check_output(home_path_, shell=True).strip()
logger.info("Home path is : " + home_path)

# Set homepath tries to 1. Give it 5 attempts.
home_path_tries = 1

# If we don't have a homepath then try another few attempts
while home_path_tries < 6:
    if (home_path is None) or ("Error" in home_path) or (home_path == '') or (home_path == "Unknown"):
            logger.warn("Unable to obtain homepath. Trying again...")
            logger.info("Attempt to obtain home path : %d " % home_path_tries)
            home_path_="""dscl localhost -read "/Active Directory/ED/All Domains/Users/""" + NetUser + """" | grep 'SMBHome:' | awk '{print $2}'"""
            # If unable to get home path after 5 tries, quit the script as there is obviously an issue somewhere.
            if home_path_tries == 5:
                logger.error("Unable to obtain homepath after 5 attempts. Exiting script.")
                close_logger()
                sys.exit(1)
    else:
            logger.info("Found home path : " + home_path )
            break

    # Sleep for a second as it may be a timing issue
    time.sleep(1)
    home_path = subprocess.check_output(home_path_, shell=True).strip()
    # Add 1 to the attempts
    home_path_tries += 1

# Switch slashes to mac format
full_home_path = home_path.replace('\\', '/')
logger.info("Home path converted : " + full_home_path)
# Get server only
home_server = full_home_path.split('/')[2]
# Get mount point
#home_mount_point = full_home_path.split('/')[3]
# Get folder path after mount point
#home_folder_path = full_home_path.split('/',4)[4]

# Check to see if server is reachable
#response = subprocess.check_call(['ping', '-c', '1', home_server])
# If home_server is reachable
#if response == 0:
    #logger.info(home_server + " appears to be up!")
    # Get IP address of home server
    #ip_address = socket.gethostbyname(home_server)
    # Prepare netstat command
    #netstat_cmd = ['netstat -an | grep "ESTABLISHED" | grep {}'.format(ip_address)]
    # Get result of netstat
    #netstat_result = subprocess.check_output(netstat_cmd, shell=True).strip()
    # Display details for log
    #logger.info("The server IP Address is : " + ip_address)
    #logger.info("Result of NETSTAT : " + netstat_result)
#else:
    # Home server is not reachable at the moment. Attempting to coninue anyway
    #logger.warn("Can't ping " + home_server + "! Will keep trying to continue with folder redirection.")

# Check if home share is mounted
logger.info("Is home share mounted?")
# If homeshare is not currently mounted
if (check_mount(NetUser) == False):
    logger.warn("/Volumes/" + NetUser + " is not mounted. Is homeshare on datastore?")
    # Check if user is on datastore - as this particular server has been known to cause issues as it wasn't seen as a trusted server. This is now hopefully resolved but only commenting out the exit command in case it needs to be re-implemented
    if "datastore" in full_home_path:
        logger.warn("Home path is on datastore.")
        #close_logger()
        # sys.exit(1)
    else:
        # Home share not on datastore
        logger.info("Home share not on datastore. Attempting to mount.")

    # Set tries to 1
    mount_share_tries = 1
    # While the home space is not mounted and that the tries is less than 6
    while check_mount(NetUser) == False and mount_share_tries < 6:
        logger.info("Mount attempt : %d" % mount_share_tries)
        # Attempt another mount
        attempt_mount(NetUser, full_home_path)
        # Add one to tries
        mount_share_tries += 1

    # If after 5 attempts share is still not mounted, exit re-direction script with error code
    if check_mount(NetUser) == False:
        logger.error("Unable to mount network home. Exiting redirect script.")
        close_logger()
        sys.exit(1)
    else:
        logger.info("/Volumes/" + NetUser + " has mounted sucessfully.")
else:
    logger.info("/Volumes/" + NetUser + " already mounted.")

# Create links for all folders
# Desktop
create_link(NetUser, "Desktop")
# Documents
create_link(NetUser, "Documents")
# Movies
create_link(NetUser, "Movies")
# Music
create_link(NetUser, "Music")
# Pictures
create_link(NetUser, "Pictures")

logger.info("Attempting to set icons for Desktop and Documents folders.")
# Set Desktop folder icon
Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(Cocoa.NSImage.alloc().initWithContentsOfFile_("/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/DesktopFolderIcon.icns"), "/Users/${NetUser}/Desktop", 0)
# Set Documents folder icon
Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(Cocoa.NSImage.alloc().initWithContentsOfFile_("/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/DocumentsFolderIcon.icns"), "/Users/${NetUser}/Documents", 0)

# Restart Finder
logger.info("Restarting Finder.")
subprocess.call(['killall', 'Finder'])

# Sleep for a few seconds just to make sure policy has had time to run.
time.sleep(2)

# Kill any leftover jamf helper processes
kill_jh()

# Commit final message to log
logger.info("Folder redirection complete!")

# Close and remove the logging handlers
close_logger()

# Exit script
sys.exit(0)

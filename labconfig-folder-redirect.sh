#!/bin/bash

###################################################################
#
# Lab folder redirect script.
# 
# 
#
# Date: "Thu Sep 13 15:43:44 BST 2018"
# Version: 0.3
# Origin: https://github.com/UoE-macOS/lab.git
# Released by JSS User: dsavage
#
##################################################################


set -x

# Make sure preference doesn't ask for confirmation for an unknown server.
# Ideally this should be done within a config profile however some admins have problems with this
# https://www.jamf.com/jamf-nation/discussions/23565/you-are-attempting-to-connect-to-the-server-dialog-box-since-10-12-4
defaults write /Library/Preferences/com.apple.NetworkAuthorization AllowUnknownServers -bool YES

LDAP_SERVER="ldaps://authorise.is.ed.ac.uk"
LDAP_BASE="dc=authorise,dc=ed,dc=ac,dc=uk"
LDAP_COL="eduniCollegeCode"
LDAP_FULLNAME="cn"
LDAP_UIDNUM="uidNumber"

NetUser=`python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");'`

# Create log file
logFile="/Library/Logs/folder-redirect.log"

# Check to see if logfile exists. If so then delete as we only need log for the current user
if [ -f "$logFile" ]
then
    rm -f $logFile
fi

# Function for obtaining timestamp
timestamp() {
	while read -r line
	do
        timestamp=`date`
        echo "[$timestamp] $line"
	done
}

# Function for obtaining school code
get_school() {
  # Tweak to return the College rather than the School, we just want to make sure it's not a  local account and the dst test accounts don't have school codes...   
  uun=${1}
  school_code=$(ldapsearch -x -H "${LDAP_SERVER}" -b"${LDAP_BASE}" -s sub "(uid=${uun})" "${LDAP_COL}" | awk -F ': ' '/^'"${LDAP_COL}"'/ {print $2}')
        
  # Just return raw eduniSchoolCode for now - ideally we'd like the human-readable abbreviation
  [ -z "${school_code}" ] && school_code="Unknown"
  echo ${school_code}
}

# Function to attempt mounting share
attempt_mount() {
	# Generate the applescript command to mount the server
	# Use smb
    smb="smb://"
    # Grab full path to the share point
	fullName=`echo "${smb}${1}/${2}"`
	echo "Full path to mount : $fullName" | timestamp >> $logFile
	# Grab full command so that we can pass to apple script
	script_args="mount volume \"${fullName}\""	
	echo ${script_args} | timestamp >> $logFile
	# Mount share as logged in user
	sudo -u ${3} osascript -e "${script_args}"
	sleep 1s
}

# Function to return if share is mounted
check_mount() {
    if [ -d "/Volumes/$1" ] || [ -d /Volumes/${NetUser} ];
    then
    	# Share is mounted
    	retval=0
    else
    	# Share is not mounted
    	retval=1
    fi
    echo ${retval}  
}

# Log username
echo "Logged in user is ${NetUser}" | timestamp >> $logFile

# If the user does not exist or user is unknown
if [ -z "$(get_school ${NetUser})" ] || [ "$(get_school ${NetUser})" == "Unknown" ]
#  Then most likely not an AD account. Exit script as no redirection can be performed
then
	echo "Cannot redirect folders - most likely because of one of the following: " | timestamp >> $logFile
	echo "1. ${NetUser} is a local account." | timestamp >> $logFile
	echo "2. The logged in user does not have an associated school code." | timestamp >> $logFile
	echo "3. Active Directory is not reachable." | timestamp >> $logFile
	echo "Quitting folder redirection script." | timestamp >> $logFile
	exit 0;
# Else uun is valid
else
	echo "${NetUser} appears to be a valid AD account" | timestamp >> $logFile
fi

# Get homepath for uun and echo to log
homePath=`dscl localhost -read "/Active Directory/ED/All Domains/Users/${NetUser}" | grep 'SMBHome:' | awk '{print $2}'`
echo 'Do we have a homepath?' | timestamp >> $logFile # For debugging purposes
echo "${NetUser} home path is ${homePath}" | timestamp >> $logFile # For debugging purposes
sleep 1s
# If no homepath is returned then try again. Give it 5 attempts
if [ -z ${homePath} ]
then
    # Set inital attempts
    homePathTries=0
    # While homepath is null and less than 5
	while [ -z $homePath ] && [ ${homePathTries} -lt 5 ]
	do
		homePathTries=$((${homePathTries}+1))
		echo "Attempt to obtain home path : $homePathTries" | timestamp >> $logFile
        sleep 2s
		homePath=`dscl localhost -read "/Active Directory/ED/All Domains/Users/${NetUser}" | grep 'SMBHome:' | awk '{print $2}'`        
	done
	# If after 5 attempts we still cannot obtain the homepath, quit the script
	if [ -z ${homePath} ]
	then
		echo "Unable to obtain homepath after 5 attempts. Cannot redirect folders. Quiting script." | timestamp >> $logFile
		exit 0; 
	# Else homepath has been obtained successfully
	else
		echo "Successfully obtained homepath for ${NetUser} after ${homePathTries} attempt(s)." | timestamp >> $logFile
	fi
fi

echo "${NetUser} home path is ${homePath}" | timestamp >> $logFile

# Switch the slashes to make mac friendly and echo Home directory
#homeDirectory="`echo $homePath | tr '\\' '/'`"
homeDirectory="${homePath//\\//}"
echo "Home Directory is $homeDirectory" | timestamp >> $logFile

# Use awk to break down the home path to obtain servername
homeServer=`echo $homeDirectory | awk -F "/" '{print $3}'`
echo "Homeserver is $homeServer" | timestamp >> $logFile

# Get home share point (sg, etc..)
homeSharePoint=`echo $homeDirectory | awk -F "/" '{print $4}'` 
echo "Home sharepoint is $homeSharePoint" | timestamp >> $logFile

# Extract path after home sharepoint
tempHomePath=`echo $homeDirectory | awk -F "/" '{for(i=5;i<=NF;i++) print $i}'`
echo ${tempHomePath} | timestamp >> $logFile
homeSharePath=`echo $tempHomePath | tr ' ' '/'`
echo "Homeshare path is $homeSharePath" | timestamp >> $logFile

# Is the server connection there
PING_HOME=`ping -c 1 ${homeServer}`
SERVER_IP=`echo ${PING_HOME} | awk -F '[()]' '{print $2}'`
SERVER_CONNECTION=`netstat -an | grep "ESTABLISHED" | grep ${SERVER_IP}`

echo "The server IP is: ${SERVER_IP}" | timestamp >> $logFile
echo "Result of NETSTAT: ${SERVER_CONNECTION}" | timestamp >> $logFile

# Check to make sure Home share point is mounted.
echo "Is home share mounted?" | timestamp >> $logFile
if [ "$(check_mount ${homeSharePoint})" -eq 1 ] || [ -z "$(check_mount ${homeSharePoint})" ] 
then
    # 
    sleep 1s
	echo "/Volumes/$homeSharePoint not mounted. Is homeshare on datastore? " | timestamp >> $logFile
	# Before knowledge of the above defaults command, it was believed that if the original mount attempt on a datastore volume failed then it would ask for confirmation before attempting to reconnect, which we couldn't bypass.
	# The below "if" statement was used to check if the homepath was on datastore and if so to exit the script. Hopefully the above defaults command resolves this. Commented "exit 0;" for just now."
	if echo "$homePath" | grep -q "datastore"
    then
	    echo "Home path is on datastore." | timestamp >> $logFile
	    #exit 0;
    else
	    echo "Home share not on datastore. Attempting to mount." | timestamp >> $logFile
    fi
	# If share is not mounted and not on datastore then give it 5 attempts to mount
	tries=0
	while [ "$(check_mount ${homeSharePoint})" -eq 1 ] && [ ${tries} -lt 5 ];
	do
		tries=$((${tries}+1))
		echo "Mount attempt : $tries" | timestamp >> $logFile		
		$(attempt_mount ${homeServer} ${homeSharePoint} ${NetUser})
	done
	# If after 5 attempts share is stil not mounted, display user notification message and exit re-direction script
	if [ "$(check_mount ${homeSharePoint})" -eq 1 ];
	then
		echo "Unable to mount network home. Displaying notification message and exiting redirect script." | timestamp >> $logFile
		exit 0;
	# Else share has mounted successfully
	else
		echo "/Volumes/$homeSharePoint mounted successfully." | timestamp >> $logFile
	fi
# Else share already mounted
else
	echo "/Volumes/$homeSharePoint already mounted." | timestamp >> $logFile
fi


########## DESKTOP SECTION ##########

# Check to see if Desktop folder within homespace exists
echo "Checking to see if Desktop folder in homespace exists" | timestamp >> $logFile
if [ ! -d /Volumes/$homeSharePoint/$homeSharePath/Desktop ]
then
	echo "Desktop folder on homespace does not exist. Creating folder…" | timestamp >> $logFile
	mkdir /Volumes/$homeSharePoint/$homeSharePath/Desktop
	chown ${NetUser}:staff /Volumes/$homeSharePoint/$homeSharePath/Desktop
else
	echo "Desktop folder on server already exists. Moving on..." | timestamp >> $logFile
fi

# Check to see if a Desktop folder or alias exists. If so then delete
echo "Checking to see if local Desktop already exists..." | timestamp >> $logFile
if [ -d /Users/${NetUser}/Desktop ] || [ -L /Users/${NetUser}/Desktop ]
then
    if [ -L /Users/${NetUser}/Desktop ]
    then
        echo "Link already exists. Removing so we can recreate." | timestamp >> $logFile
        rm -vf /Users/${NetUser}/Desktop >> $logFile
    else
        echo "Local Desktop folder exists. Deleting…" | timestamp >> $logFile
        rm -vdfR /Users/${NetUser}/Desktop >> $logFile
    fi
else
   echo "Local Desktop folder does not exist." | timestamp >> $logFile 
fi

sleep 1s

# Create link to Desktop folder on Homespace
echo "Creating link to Desktop folder on homespace...." | timestamp >> $logFile
# Try removing the Desktop folder again in case it's re-appeared
rm -vdfR /Users/${NetUser}/Desktop >> $logFile
ln -sv /Volumes/$homeSharePoint/$homeSharePath/Desktop /Users/${NetUser}/Desktop >> $logFile
# Set the Desktop icon
python -c 'import Cocoa; Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(Cocoa.NSImage.alloc().initWithContentsOfFile_("/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/DesktopFolderIcon.icns"), "/Users/${NetUser}/Desktop", 0)'

# The following if statement was to check for nested Desktop links, however this may cause issues if for some reason the user has setup on purpose nested links (can't think why, but it's possible). We don't want to delete users data so commenting out just now.
: '
echo "Checking for nested duplicate symlink."
if [ -L /Users/${NetUser}/Desktop/Desktop ]
then
    echo "Found nested desktop symlink. Removing." | timestamp >> $logFile
    rm -fv /Users/${NetUser}/Desktop/Desktop >> $logFile
else
    echo "Not found."
fi
'

########## PICTURES SECTION ##########

# Check to see if Pictures folder within homespace exists
echo "Checking to see if Pictures folder in homespace exists" | timestamp >> $logFile
if [ ! -d /Volumes/$homeSharePoint/$homeSharePath/Pictures ]
then
	echo "Pictures folder on homespace does not exist. Creating folder…" | timestamp >> $logFile
	mkdir /Volumes/$homeSharePoint/$homeSharePath/Pictures
	chown ${NetUser}:staff /Volumes/$homeSharePoint/$homeSharePath/Pictures
else
	echo "Pictures folder on server already exists. Moving on..." | timestamp >> $logFile
fi

# Check to see if a Pictures folder or alias exists. If so then delete
echo "Checking to see if local Pictures already exists..." | timestamp >> $logFile
if [ -d /Users/${NetUser}/Pictures ] || [ -L /Users/${NetUser}/Pictures ]
then
    if [ -L /Users/${NetUser}/Pictures ]
    then
        echo "Link already exists. Removing so we can recreate." | timestamp >> $logFile
        rm -vf /Users/${NetUser}/Pictures >> $logFile
    else
        echo "Local Pictures folder exists. Deleting…" | timestamp >> $logFile
        rm -vdfR /Users/${NetUser}/Pictures >> $logFile
    fi
else
   echo "Local Pictures folder does not exist." | timestamp >> $logFile 
fi

sleep 1s

# Create link to Pictures folder on Homespace
echo "Creating link to Pictures folder on homespace...." | timestamp >> $logFile
ln -sv /Volumes/$homeSharePoint/$homeSharePath/Pictures /Users/${NetUser}/Pictures >> $logFile
# Set the Pictures icon
python -c 'import Cocoa; Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(Cocoa.NSImage.alloc().initWithContentsOfFile_("/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/PicturesFolderIcon.icns"), "/Users/${NetUser}/Pictures", 0)'

# The following if statement was to check for nested Pictures links, however this may cause issues if for some reason the user has setup on purpose nested links (can't think why, but it's possible). We don't want to delete users data so commenting out just now.
: '
echo "Checking for nested duplicate symlink."
if [ -L /Users/${NetUser}/Pictures/Pictures ]
then
    echo "Found nested Pictures symlink. Removing." | timestamp >> $logFile
    rm -fv /Users/${NetUser}/Pictures/Pictures >> $logFile
else
    echo "Not found."
fi
'


########## MUSIC SECTION ##########

# Check to see if Music folder within homespace exists
echo "Checking to see if Music folder in homespace exists" | timestamp >> $logFile
if [ ! -d /Volumes/$homeSharePoint/$homeSharePath/Music ]
then
	echo "Music folder on homespace does not exist. Creating folder…" | timestamp >> $logFile
	mkdir /Volumes/$homeSharePoint/$homeSharePath/Music
	chown ${NetUser}:staff /Volumes/$homeSharePoint/$homeSharePath/Music
else
	echo "Music folder on server already exists. Moving on..." | timestamp >> $logFile
fi

# Check to see if a Music folder or alias exists. If so then delete
echo "Checking to see if local Music already exists..." | timestamp >> $logFile
if [ -d /Users/${NetUser}/Music ] || [ -L /Users/${NetUser}/Music ]
then
    if [ -L /Users/${NetUser}/Music ]
    then
        echo "Link already exists. Removing so we can recreate." | timestamp >> $logFile
        rm -vf /Users/${NetUser}/Music >> $logFile
    else
        echo "Local Music folder exists. Deleting…" | timestamp >> $logFile
        rm -vdfR /Users/${NetUser}/Music >> $logFile
    fi
else
   echo "Local Music folder does not exist." | timestamp >> $logFile 
fi

sleep 1s

# Create link to Music folder on Homespace
echo "Creating link to Music folder on homespace...." | timestamp >> $logFile
ln -sv /Volumes/$homeSharePoint/$homeSharePath/Music /Users/${NetUser}/Music >> $logFile
# Set the Music icon
python -c 'import Cocoa; Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(Cocoa.NSImage.alloc().initWithContentsOfFile_("/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/MusicFolderIcon.icns"), "/Users/${NetUser}/Music", 0)'

# The following if statement was to check for nested Music links, however this may cause issues if for some reason the user has setup on purpose nested links (can't think why, but it's possible). We don't want to delete users data so commenting out just now.
: '
echo "Checking for nested duplicate symlink."
if [ -L /Users/${NetUser}/Music/Music ]
then
    echo "Found nested Music symlink. Removing." | timestamp >> $logFile
    rm -fv /Users/${NetUser}/Music/Music >> $logFile
else
    echo "Not found."
fi
'


########## MOVIES SECTION ##########

# Check to see if Movies folder within homespace exists
echo "Checking to see if Movies folder in homespace exists" | timestamp >> $logFile
if [ ! -d /Volumes/$homeSharePoint/$homeSharePath/Movies ]
then
	echo "Movies folder on homespace does not exist. Creating folder…" | timestamp >> $logFile
	mkdir /Volumes/$homeSharePoint/$homeSharePath/Movies
	chown ${NetUser}:staff /Volumes/$homeSharePoint/$homeSharePath/Movies
else
	echo "Movies folder on server already exists. Moving on..." | timestamp >> $logFile
fi

# Check to see if a Movies folder or alias exists. If so then delete
echo "Checking to see if local Movies already exists..." | timestamp >> $logFile
if [ -d /Users/${NetUser}/Movies ] || [ -L /Users/${NetUser}/Movies ]
then
    if [ -L /Users/${NetUser}/Movies ]
    then
        echo "Link already exists. Removing so we can recreate." | timestamp >> $logFile
        rm -vf /Users/${NetUser}/Movies >> $logFile
    else
        echo "Local Movies folder exists. Deleting…" | timestamp >> $logFile
        rm -vdfR /Users/${NetUser}/Movies >> $logFile
    fi
else
   echo "Local Movies folder does not exist." | timestamp >> $logFile 
fi

sleep 1s

# Create link to Movies folder on Homespace
echo "Creating link to Movies folder on homespace...." | timestamp >> $logFile
ln -sv /Volumes/$homeSharePoint/$homeSharePath/Movies /Users/${NetUser}/Movies >> $logFile
# Set the Movies icon
python -c 'import Cocoa; Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(Cocoa.NSImage.alloc().initWithContentsOfFile_("/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/MoviesFolderIcon.icns"), "/Users/${NetUser}/Movies", 0)'

# The following if statement was to check for nested Movies links, however this may cause issues if for some reason the user has setup on purpose nested links (can't think why, but it's possible). We don't want to delete users data so commenting out just now.
: '
echo "Checking for nested duplicate symlink."
if [ -L /Users/${NetUser}/Movies/Movies ]
then
    echo "Found nested Movies symlink. Removing." | timestamp >> $logFile
    rm -fv /Users/${NetUser}/Movies/Movies >> $logFile
else
    echo "Not found."
fi
'


########## DOCUMENTS SECTION ##########

# Check to see if Documents folder within homespace exists
echo "Checking to see if Documents folder in homespace exists" | timestamp >> $logFile
if [ ! -d /Volumes/$homeSharePoint/$homeSharePath/Documents ]
then
	echo "Documents folder on homespace does not exist. Creating folder…" | timestamp >> $logFile
	mkdir /Volumes/$homeSharePoint/$homeSharePath/Documents
	chown ${NetUser}:staff /Volumes/$homeSharePoint/$homeSharePath/Documents
else
	echo "Documents folder on server already exists. Moving on..." | timestamp >> $logFile
fi

# Check to see if a Documents folder or alias exists. If so then delete
echo "Checking to see if local Documents already exists..." | timestamp >> $logFile
if [ -d /Users/${NetUser}/Documents ] || [ -L /Users/${NetUser}/Documents ]
then
        echo "Local Documents folder or link exists. Deleting…" | timestamp >> $logFile
        rm -vfR /Users/${NetUser}/Documents >> $logFile
else
   echo "Local Documents folder does not exist." | timestamp >> $logFile 
fi

sleep 1s

# Create link to Documents folder on Homespace
echo "Creating link to Documents folder on homespace...." | timestamp >> $logFile
ln -sv /Volumes/$homeSharePoint/$homeSharePath/Documents /Users/${NetUser}/Documents >> $logFile
# Set the Documents icon
python -c 'import Cocoa; Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(Cocoa.NSImage.alloc().initWithContentsOfFile_("/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/DocumentsFolderIcon.icns"), "/Users/${NetUser}/Documents", 0)'


desktopMount="/Volumes/${homeSharePoint}/${homeSharePath}/Desktop"
echo "Full path to Desktop is $desktopMount" | timestamp >> $logFile
documentsMount="/Volumes/${homeSharePoint}/${homeSharePath}"
echo "Full path to Documents is $documentsMount" | timestamp >> $logFile

echo "Attempting to remove current local Desktop and local Documents sidebar entries..." | timestamp >> $logFile
# Remove current desktop and documents sidebar entries, along with network home folder if it exists.
#	python - <<EOF
#import sys
#sys.path.append('/usr/local/python')
#from FinderSidebarEditor import FinderSidebar                  # Import the module
#sidebar = FinderSidebar()                                      # Create a Finder sidebar instance to act on.
#sidebar.remove("Desktop")                                        # Remove Desktop favourite 
#sidebar.remove("Documents")									# Remove Documents favourite
#sidebar.remove("$NetUser")								# Remove shortcut to Network Home as it's recreated anyway
#EOF

killall Finder
sleep 1s

# Add the entry to the sidebar
add_FavoriteItems() {
echo "Add Documents sidebar entry." | timestamp >> $logFile
if [ -d /Volumes/${homeSharePoint} ]; then
    python - <<EOF
import sys
sys.path.append('/usr/local/python')
from FinderSidebarEditor import FinderSidebar                  # Import the module
sidebar = FinderSidebar()                                      # Create a Finder sidebar instance to act on.
sidebar.remove("Documents")									# Remove Documents favourite again just incase it re-appears
sidebar.add("/Users/$NetUser/Documents")          # Add redirected Documents favourite to sidebar
sidebar.move("$NetUser", "Desktop")
EOF
 else
 	echo "Documents sidebar shortcut failed." | timestamp >> $logFile
fi

echo "Add Desktop sidebar entry." | timestamp >> $logFile	
if [ -d /Volumes/${homeSharePoint} ]; then
    python - <<EOF
import sys
sys.path.append('/usr/local/python')
from FinderSidebarEditor import FinderSidebar                  # Import the module
sidebar = FinderSidebar()                                      # Create a Finder sidebar instance to act on.
sidebar.remove("Desktop")                                        # Remove Desktop favourite again just incase it re-appears
sidebar.add("$desktopMount")                                        # Add redirected 'Desktop' favourite to sidebar
sidebar.move("Desktop", "All My Files")
EOF
else
	echo "Desktop sidebar shortcut failed" | timestamp >> $logFile
fi

echo "Add home network folder sidebar entry." | timestamp >> $logFile
if [ -d /Volumes/${homeSharePoint} ]; then
    python - <<EOF
import sys
sys.path.append('/usr/local/python')
from FinderSidebarEditor import FinderSidebar                 # Import the module
sidebar = FinderSidebar()                                      # Create a Finder sidebar instance to act on.
sidebar.remove("$NetUser")
sidebar.add("/Volumes/$homeSharePoint/$homeSharePath")         # Add the UUN network home favourite to sidebar
EOF
else
	echo "Network Home sidebar shortcut failed" | timestamp >> $logFile
fi

}
echo "Adding homespace Desktop and homespace Documents sidebar entries..." | timestamp >> $logFile
add_FavoriteItems

echo "Restarting Finder.." | timestamp >> $logFile
killall Finder
sleep 2s
echo "Done." | timestamp >> $logFile

#Exit script
exit 0;

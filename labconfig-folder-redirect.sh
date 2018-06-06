#!/bin/bash
LDAP_SERVER="ldaps://authorise.is.ed.ac.uk"
LDAP_BASE="dc=authorise,dc=ed,dc=ac,dc=uk"
LDAP_SCHOOL="eduniSchoolCode"
LDAP_FULLNAME="cn"
LDAP_UIDNUM="uidNumber"

NetUser=`python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");'`

# Create log file
logFile="/Library/Logs/folder-redirect.log"

# Function if redirection fails
script_fail() {
osascript <<BRK
activate
beep
display dialog "There has been a problem with your login. Please \"Restart\" now if possible; if you wish to continue working, select \"Cancel\" but be aware your files may be at risk and any data should be saved to external media." buttons {"Restart", "Cancel"} default button 1
copy the result as list to {buttonpressed}
try
	if the buttonpressed is "Restart" then tell application "System Events" to restart
end try
BRK
exit 0;
}

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
  uun=${1}
  school_code=$(ldapsearch -x -H "${LDAP_SERVER}" -b"${LDAP_BASE}" -s sub "(uid=${uun})" "${LDAP_SCHOOL}" | awk -F ': ' '/^'"${LDAP_SCHOOL}"'/ {print $2}')
        
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
	sleep 5
}

# Function to return if share is mounted
check_mount() {
    if [ -d "/Volumes/$1" ];
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
echo "Logged in user is $NetUser" | timestamp >> $logFile

# If the user does not exist or user is unknown
if [ -z "$(get_school ${NetUser})" ] || [ "$(get_school ${NetUser})" == "Unknown" ]
#  Then most likely not an AD account. Exit script as no redirection can be performed
then
	echo "Cannot redirect folders - most likely because of one of the following: " | timestamp >> $logFile
	echo "1. $NetUser is a local account." | timestamp >> $logFile
	echo "2. The logged in user does not have an associated school code." | timestamp >> $logFile
	echo "3. Active Directory is not reachable." | timestamp >> $logFile
	echo "Quiting folder redirection script." | timestamp >> $logFile
	(script_fail)
# Else uun is valid
else
	echo "$NetUser appears to be a valid AD account" | timestamp >> $logFile
fi

# Get homepath for uun and echo to log
homePath=`dscl localhost -read "/Active Directory/ED/All Domains/Users/${NetUser}" | grep 'SMBHome:' | awk '{print $2}'`
echo "$NetUser home path is ${homePath}" | timestamp >> $logFile

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
homePath=`echo $homeDirectory | awk -F "/" '{for(i=5;i<=NF;i++) print $i}'` 
homeSharePath=`echo $homePath | tr ' ' '/'`
echo "Homeshare path is $homeSharePath" | timestamp >> $logFile

# Check to make sure Home share point is mounted.
echo "Is home share mounted?" | timestamp >> $logFile
if [ "$(check_mount ${homeSharePoint})" -eq 1 ] || [ -z "$(check_mount ${homeSharePoint})" ];
then
	echo "/Volumes/$homeSharePoint not mounted. Attempting to mount..." | timestamp >> $logFile
	# If share is not mounted then give it 5 attempts to mount
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
		(script_fail)
	# Else share has mounted successfully
	else
		echo "/Volumes/$homeSharePoint mounted successfully." | timestamp >> $logFile
	fi
# Else share already mounted
else
	echo "/Volumes/$homeSharePoint already mounted." | timestamp >> $logFile
fi

# Check to see if Desktop folder within homespace exists
echo "Checking to see if Desktop folder in homespace exists" | timestamp >> $logFile
if [ ! -d /Volumes/$homeSharePoint/$homeSharePath/Desktop ]
then
	echo "Desktop folder on homespace does not exist. Creating folder…" | timestamp >> $logFile
	mkdir /Volumes/$homeSharePoint/$homeSharePath/Desktop
	chown $NetUser:staff /Volumes/$homeSharePoint/$homeSharePath/Desktop
else
	echo "Desktop folder on server already exists. Moving on..." | timestamp >> $logFile
fi

# Check to see if a Desktop folder or alias exists. If so then delete
if test -d /Users/$NetUser/Desktop
then
    echo "Local Desktop folder or alias exists. Deleting…" | timestamp >> $logFile
    rm -vdfR /Users/$NetUser/Desktop
else
   echo "Local Desktop folder does not exist." | timestamp >> $logFile 
fi

# Create link to Desktop folder on Homespace
echo "Creating link to Desktop folder on homespace...." | timestamp >> $logFile
ln -s /Volumes/$homeSharePoint/$homeSharePath/Desktop /Users/$NetUser/Desktop

# Check to see if local Documents folder exists. If so then delete.
if test -d /Users/$NetUser/Documents
then
    echo "Local documents folder exists. Deleting…" | timestamp >> $logFile
    rm -vdfR /Users/$NetUser/Documents
    echo "Creating link to homespace..." | timestamp >> $logFile
else
    echo "Local Documents folder does not exist. Creating link..." | timestamp >> $logFile	
fi

rm -vdfR /Users/$NetUser/Documents
# Create link to root of the homespace, calling it "Documents". Has to be done using an alias so Finder shortcut can be placed in sidebar - so Applescript is used
osascript <<EOF
    set p to "/Volumes/$homeSharePoint/$homeSharePath" 
	set q to POSIX file p
	do shell script "echo " & q & " >> $logFile"
	tell application "Finder"
	make new alias file to q at home with properties {name:"Documents"}
	end tell
EOF

desktopMount="/Volumes/${homeSharePoint}/${homeSharePath}/Desktop"
echo "Full path to Desktop is $desktopMount" | timestamp >> $logFile
documentsMount="/Volumes/${homeSharePoint}/${homeSharePath}"
echo "Full path to Documents is $documentsMount" | timestamp >> $logFile

echo "Attempting to remove current local Desktop and local Documents sidebar entries..." | timestamp >> $logFile
# Remove current desktop and documents sidebar entries
python - <<EOF
import sys
sys.path.append('/usr/local/python')
from FinderSidebarEditor import FinderSidebar                  # Import the module
sidebar = FinderSidebar()                                      # Create a Finder sidebar instance to act on.
sidebar.remove("Desktop")                                        # Remove Desktop favourite 
sidebar.remove("Documents")									# Remove Documents favourite
EOF

killall Finder
sleep 2s

# Add the entry to the sidebar
add_FavoriteItems() { 
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
}
echo "Adding homespace Desktop and homespace Documents sidebar entries..." | timestamp >> $logFile
add_FavoriteItems

echo "Restarting Finder.." | timestamp >> $logFile
killall Finder
sleep 5s

#kill -9 $jamfHelperPID
#killall $jamfHelperPID

exit 0;

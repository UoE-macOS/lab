#!/bin/bash
LDAP_SERVER="ldaps://authorise.is.ed.ac.uk"
LDAP_BASE="dc=authorise,dc=ed,dc=ac,dc=uk"
LDAP_SCHOOL="eduniSchoolCode"
LDAP_FULLNAME="cn"
LDAP_UIDNUM="uidNumber"

NetUser=`python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");'`

# Create log file
logFile="/Library/Logs/folder-redirect.log"

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

# Log username
echo "Logged in user is $NetUser" | timestamp >> $logFile

# If the user does not exist or user is unknown
if [ -z "$(get_school ${NetUser})" ] || [ "$(get_school ${NetUser})" == "Unknown" ]
#  then most likely not an AD account. Exit script as no redirection can be performed
then
	echo "$NetUser appears to be a local account without AD" | timestamp >> $logFile
	exit 0;
# Else uun is valid
else
	echo "$NetUser is a Valid AD account" | timestamp >> $logFile
fi

# Get homepath for uun and echo to log
HomePath=`dscl localhost -read "/Active Directory/ED/All Domains/Users/${NetUser}" | grep 'SMBHome:' | awk '{print $2}'`
echo "$NetUSer Home Path is $HomePath" | timestamp >> $logFile

# Switch the slashes to make mac friendly and echo Home directory
#homeDirectory="`echo $HomePath | tr '\\' '/'`"
homeDirectory="${HomePath//\\//}"
echo "Home Directory is $homeDirectory" | timestamp >> $logFile

# Use awk to break down the home path to obtain servername and echo to log
homeServer=`echo $homeDirectory | awk -F "/" '{print $3}'`
echo "Homeserver is $homeServer" | timestamp >> $logFile

# Get home share point (sg, etc..) and echo to log
homeSharePoint=`echo $homeDirectory | awk -F "/" '{print $4}'` 
echo "Home sharepoint is $homeSharePoint" | timestamp >> $logFile

# Extract path after home sharepoint and echo to log
homePath=`echo $homeDirectory | awk -F "/" '{for(i=5;i<=NF;i++) print $i}'` 
homeSharePath=`echo $homePath | tr ' ' '/'`
echo "Homeshare path is $homeSharePath" | timestamp >> $logFile

# Check to make sure Home share point is mounted. If not then attempt to mount.
echo "Is home share mounted?" | timestamp >> $logFile
if [ ! -d /Volumes/$homeSharePoint ];
then
    echo "NO! Attempting to mount.." | timestamp >> $logFile
    
else
    echo "YES! Home share is mounted! Moving on...." | timestamp >> $logFile
fi
           


# Generate the applescript command to mount the server
: '
smb="smb://"
fullName=`echo "${smb}${homeServer}/${homeSharePoint}"`
echo $fullName
# script_args="mount volume \"${fullName}\""
echo ${script_args}
'

# If the home volume is unavailable take 5 attempts at remounting it
: '
tries=0
while ! [ -d /Volumes/$homeSharePoint/$homeSharePath ] && [ ${tries} -lt 5 ];
do
	echo "Try number $tries"
	tries=$((${tries}+1))
	echo "Attempting to mount ${script_args}"
	sudo -u ${NetUser} osascript -e "${script_args}"
	sleep 5
done
'
echo "Checking to see if Desktop folder in homespace exists" | timestamp >> $logFile

if [ ! -d /Volumes/$homeSharePoint/$homeSharePath/Desktop ]
then
	echo "Desktop folder on homespace does not exist. Creating folder…" | timestamp >> $logFile
	mkdir /Volumes/$homeSharePoint/$homeSharePath/Desktop
	chown $NetUser:staff /Volumes/$homeSharePoint/$homeSharePath/Desktop
else
	echo "Desktop folder on server already exists. Moving on..." | timestamp >> $logFile
fi

echo "Restarting Finder.." | timestamp >> $logFile

killall Finder

# Sleep to make sure Finder restarts...
sleep 5s

# Check to see if local Documents folder exists. If so then delete.
if test -d /Users/$NetUser/Documents
then
    echo "Local documents folder exists. Deleting…" | timestamp >> $logFile
    rm -vdfR /Users/$NetUser/Documents
    # Create link to root of the homespace, calling it "Documents". Has to be done using an alias so Finder shortcut can be placed in sidebar - so Applescript is used
    echo "Creating link to homespace..." | timestamp >> $logFile
osascript <<EOF
	    set p to "/Volumes/$homeSharePoint/$homeSharePath" 
	    set q to POSIX file p
	    do shell script "echo " & q & " | timestamp >> $logFile"
	    tell application "Finder"
	    make new alias file to q at home with properties {name:"Documents"}
	    end tell
EOF
else
    echo "Local Documents folder does not exist. Movin on..." | timestamp >> $logFile
osascript <<EOF
	    set p to "/Volumes/$homeSharePoint/$homeSharePath" 
	    set q to POSIX file p
	    do shell script "echo " & q & ">> $logFile"
	    tell application "Finder"
	    make new alias file to q at home with properties {name:"Documents"}
	    end tell
EOF
fi

if test -d /Users/$NetUser/Desktop
then
    echo "Local Desktop folder exists. Deleting…" | timestamp >> $logFile
    rm -vdfR /Users/$NetUser/Desktop
    echo "Creating link to Desktop folder on homespace...." | timestamp >> $logFile
    ln -s /Volumes/$homeSharePoint/$homeSharePath/Desktop /Users/$NetUser/Desktop
else
   echo "Local Desktop folder does not exist. Movin on..." | timestamp >> $logFile 
fi

shareMounted=`ls /Volumes | grep "${homeSharePoint}"`

: '
if ! [ -z $shareMounted ]
	then
	# (re)create symlink to Desktop and Documents on home server
	ln -s /Volumes/$homeSharePoint/$homeSharePath/Desktop /Users/$NetUser/Desktop
	echo "files redirected to Server"
else
	echo "login fail"
	
#execute an apple script with info that this is broken
osascript <<BRK
activate
beep
display dialog "There has been a problem with your login. Please \"Restart\" now if possible; if you wish to continue working, select \"Cancel\" but be aware your files may be at risk" buttons {"Restart", "Cancel"} default button 1
copy the result as list to {buttonpressed}
try
	if the buttonpressed is "Restart" then tell application "System Events" to restart
end try
BRK

fi
'

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
sidebar.remove("Desktop")                                        # Add 'Utilities' favorite to sidebar
sidebar.remove("Documents")
EOF

# Add the entry to the sidebar
add_FavoriteItems() {
if [ -d /Volumes/${homeSharePoint} ]; then
    python - <<EOF
import sys
sys.path.append('/usr/local/python')
from FinderSidebarEditor import FinderSidebar                  # Import the module
sidebar = FinderSidebar()                                      # Create a Finder sidebar instance to act on.
sidebar.add("$desktopMount")                                        # Add 'Utilities' favorite to sidebar
sidebar.move("Desktop", "All My Files")
EOF
else
	echo "Desktop sidebar shortcut not working!!!" >> $logFile
fi
 
if [ -d /Volumes/${homeSharePoint} ]; then
    python - <<EOF
import sys
sys.path.append('/usr/local/python')
from FinderSidebarEditor import FinderSidebar                  # Import the module
sidebar = FinderSidebar()                                      # Create a Finder sidebar instance to act on.
sidebar.add("/Users/$NetUser/Documents")                                        # Add 'Utilities' favorite to sidebar
sidebar.move("$NetUser", "Desktop")
EOF
 else
 	echo "Documents sidebar shortcut not working!!!" >> $logFile
fi

}
echo "Add homespace Desktop and homespace Documents sidebar entries" >> $logFile
add_FavoriteItems
#kill -9 $jamfHelperPID
#killall $jamfHelperPID
exit 0;
#!/bin/bash

######
#
# Date: Fri 14 Sep 2018 12:00:41 BST
# Version: 0.5
# Author: ganders1
#
######

# Set variables
LDAP_SERVER="ldaps://authorise.is.ed.ac.uk"
LDAP_BASE="dc=authorise,dc=ed,dc=ac,dc=uk"
LDAP_COL="eduniCollegeCode"
LDAP_FULLNAME="cn"
LDAP_UIDNUM="uidNumber"

# Create log file
logFile="/Library/Logs/master-login.log"

# Get logged in user
NetUser=`python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");'`

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

# Function to display JAMF Helper message
displayMessage() {
    # Get hostname and convert to upper case
	tempCompName=`hostname`
	compName=`echo "$tempCompName" | tr '[:lower:]' '[:upper:]'`
	# Call JAMF Helper window and show message
	"/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfhelper" \
	-windowType "fs" \
	-heading "Your Mac is being set up for use." \
	-description "$1
	
	Computer name : $compName
	" \
	-icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/com.apple.imac-aluminum-24.icns \
	-iconSize "256" \
	-alignDescription "center" \
	-alignHeading "center" &
}

echo "Current logged in user is $NetUser" | timestamp >> $logFile

# If the logged in user does not exist in AD or user is unknown
if [ -z "$(get_school ${NetUser})" ] || [ "$(get_school ${NetUser})" == "Unknown" ]
#  Then most likely not an AD account. Exit script as no redirection can be performed
then
	echo "Cannot run login policies. Most likely because of one of the following: " | timestamp >> $logFile
	echo "1. $NetUser is a local account." | timestamp >> $logFile
	echo "2. The logged in user does not have an associated school code." | timestamp >> $logFile
	echo "3. Active Directory is not reachable." | timestamp >> $logFile
	echo "Bypassing login policies and quiting master login script." | timestamp >> $logFile
	exit 0;
fi

echo "Locking screen." | timestamp >> $logFile
# We don't want the user to quit jamf helper, so initiate screen lock - I'm not sure if this is required - Some admins seem to indicate that JAMFHelper can be quit with cmd+Q
/System/Library/CoreServices/RemoteManagement/AppleVNCServer.bundle/Contents/Support/LockScreen.app/Contents/MacOS/LockScreen -session 256 &

# Display initial JAMF Helper message
echo "Displaying intial jamfHelper message.." | timestamp >> $logFile
description='This may take a minute, depending on your network speed.
Please call IS Helpline at 0131 651 5151 if you need assistance.'
(displayMessage "$description")
sleep 2s


# Set Acrobat Pro as the default PDF handler if it is installed

echo "Setting Acrobat to be default pdf handler." | timestamp >> $logFile

if [ -d /Applications/Adobe\ Acrobat\ DC/Adobe\ Acrobat.app ]; then
	# Doesn't seem to play well on 10.13 /usr/local/bin/duti -s com.adobe.Acrobat.Pro pdf all
    sudo -u ${NetUser} python -c 'from LaunchServices import LSSetDefaultRoleHandlerForContentType; LSSetDefaultRoleHandlerForContentType("com.adobe.pdf", 0x00000002, "com.adobe.Acrobat.Pro")'
fi


# Check for Adobe’s Creative Cloud app then close it and disable its LaunchAgent to stop it from automatically starting

if [ -d /Applications/Utilities/Adobe\ Creative\ Cloud/ACC/Creative\ Cloud.app ]; then

echo "Creative Cloud app is running. Stopping it and removing its LaunchAgent." | timestamp >> $logFile

rm -f /Library/LaunchAgents/com.adobe.AdobeCreativeCloud.plist
echo "Deleted Creative Cloud LaunchAgent." | timestamp >> $logFile

kill -9 $(ps -A | grep "Creative Cloud.app" | grep -v grep | awk -F " " '{print $1}')
echo "Killed Creative Cloud app process." | timestamp >> $logFile

launchctl unload -w /Library/LaunchAgents/com.adobe.AdobeCreativeCloud.plist
echo "Unloaded Creative Cloud LaunchAgent." | timestamp >> $logFile

fi


# Run custom triggers for browser defaults
# Chrome
echo "Setting Chrome defaults..." | timestamp >> $logFile
/usr/local/jamf/bin/jamf policy -event chromeDefaults
echo "Setting Firefox defaults..." | timestamp >> $logFile
# Firefox
/usr/local/jamf/bin/jamf policy -event firefoxDefaults
echo "Browser defaults set." | timestamp >> $logFile


# Kill this instance of JAMF Helper
kill jamfhelper

# Run LabMon policy - COMMENTED OUT UNTIL ML LAB IS READY (G.A.)
#echo "Running Labmon policy.." | timestamp >> $logFile
#desc3='LABMON will happen here! …'
#(displayMessage "$desc3")
#sleep 3s
/usr/local/jamf/bin/jamf policy -event Labmon-Login > /dev/null 2>&1
# Kill this instance of JAMF Helper
kill jamfhelper

# Run folder redirection policy
echo "Running folder redirection policy..." | timestamp >> $logFile
descFolderRedirect='Running folder redirection….'
(displayMessage "$descFolderRedirect")
# Run custom trigger for folder redirection
/usr/local/jamf/bin/jamf policy -event Redirect
sleep 2s

# Kill this instance of JAMF Helper
kill jamfhelper

# Run Desktop and Dock policy
echo "Running Desktop and Dock policy..." | timestamp >> $logFile
desc2='Configuring the Desktop and Dock….'
(displayMessage "$desc2")

# We need to rework the existing dockutil script, will add additional options later
echo "Running MacApps custom trigger." | timestamp >> $logFile
/usr/local/jamf/bin/jamf policy -event MacApps
echo "Running Dock custom trigger." | timestamp >> $logFile
/usr/local/jamf/bin/jamf policy -event OADock
# Run custom trigger for desktop image
echo "Running custom trigger for Desktop image." | timestamp >> $logFile
/usr/local/jamf/bin/jamf policy -event Desktop

echo "Setting save window expansion." | timestamp >> $logFile
# Expand the save window
su $NetUser -c "/usr/bin/defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true"
su $NetUser -c "/usr/bin/defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true"

# Check for App Store prefs' Automatic Update preference being enabled and disable it

AutoUpdateStatus=`defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticCheckEnabled`

if [ $AutoUpdateStatus == "1" ]; then
	echo "Automatic Update preference is enabled. Disabling it..."
	defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticCheckEnabled -bool FALSE

else 
	echo "Automatic Update preference is not enabled."
fi

sleep 2s

# Add everyone as an lpoperator so they can unpause print queues
/usr/sbin/dseditgroup -o edit -a everyone -t group _lpoperator


# Kill this instance of JAMF Helper
kill jamfhelper

echo "All custom login policies run." | timestamp >> $logFile
descLogin='Logging in….'
(displayMessage "$descLogin")

# Sleep for a few seconds
sleep 2s

# Open welcome page for OA Labs
/usr/local/jamf/bin/jamf policy -event welcomePage

echo "Killing all instances of LockScreen and jamfHelper..." | timestamp >> $logFile
# Kill the LockScreen and the JAMF helper once all login policies have completed
killall -9 LockScreen
killall -9 jamfhelper

# kick the login items
/usr/local/bin/jamf policy -event LoginItem

echo "Done" | timestamp >> $logFile

echo "Trying custom trigger for Desktop image again!" | timestamp >> $logFile
/usr/local/jamf/bin/jamf policy -event Desktop

exit 0;

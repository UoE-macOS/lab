#!/bin/bash

# Master login policy to run triggers associated with Python policies

# ----------- DECLARE VARIABLES -----------

# Create log file
logFile="/Library/Logs/login-master-py.log"

# Get logged in user
NetUser=`python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");'`

# Declare LDAP details
LDAP_SERVER="ldaps://authorise.is.ed.ac.uk"
LDAP_BASE="dc=authorise,dc=ed,dc=ac,dc=uk"
LDAP_COL="eduniCollegeCode"
LDAP_FULLNAME="cn"
LDAP_UIDNUM="uidNumber"


# ----------- DECLARE FUNCTIONS -----------

# --- Function for obtaining timestamp ---
timestamp() {
    while read -r line
    do
        timestamp=`date`
        echo "[$timestamp] $line"
    done
}

# --- Function for obtaining school code ---
get_school() {
  # Tweak to return the College rather than the School, we just want to make sure it's not a local account and the dst test accounts don't have school codes...
  uun=${1}
  school_code=$(ldapsearch -x -H "${LDAP_SERVER}" -b"${LDAP_BASE}" -s sub "(uid=${uun})" "${LDAP_COL}" | awk -F ': ' '/^'"${LDAP_COL}"'/ {print $2}')

  # Just return raw eduniSchoolCode for now - ideally we'd like the human-readable abbreviation
  [ -z "${school_code}" ] && school_code="Unknown"
  echo ${school_code}
}

# --- Function to kill Jamf Helper process ---
kill_jh(){
    jamfHelperPID=$( ps -A | grep "jamfHelper" | awk '{print $1}')
    echo "Jamf Helper PID $jamfHelperPID" | timestamp 2>&1 | tee -a $logFile
    echo "Killing process $jamfHelperPID" | timestamp 2>&1 | tee -a $logFile
    kill $jamfHelperPID
}


# --- Function to display JAMF Helper message ---
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
    -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/com.apple.imac-unibody-21.icns \
    -iconSize "256" \
    -alignDescription "center" \
    -alignHeading "center" &
}

# --- Function to display error message ---
displayErrorMessage() {
    kill_jh
    echo "Displaying error message." | timestamp 2>&1 | tee -a $logFile
    # Get hostname and convert to upper case
    tempCompName=`hostname`
    compName=`echo "$tempCompName" | tr '[:lower:]' '[:upper:]'`
    # Call JAMF Helper window and show message
    "/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfhelper" \
    -windowType "fs" \
    -heading "Login failure!
    Cause : $1" \
    -description "$2

    This computer will restart in 1 minute to ensure any partial network connections are safely closed.
    Contact the IS Helpline on (0131) 651 5151 for assistance if you get this error again on this computer (name: ${compName}), or on another computer." \
    -icon /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns \
    -iconSize "32" \
    -alignDescription "center" \
    -alignHeading "center" &
    # Send shutdown signal for 1 minute, send to background
    shutdown -r +1 &
    echo "Restart signal sent. Will perform restart in 1 minute." | timestamp 2>&1 | tee -a $logFile
    # sleep on the error page for 2 minutes to make sure that the error window stays on-screen for the duration of the shutdown period.
    echo "Sleeping for 2 minutes to make sure that error window displays until machiine restarts" | timestamp 2>&1 | tee -a $logFile
    sleep 120s
}


# ******* BEGIN MAIN PROGRAM *******

# Display logged in username
echo "Logged in user is ${NetUser}." | timestamp 2>&1 | tee -a $logFile

# We don't want the user to quit jamf helper, so initiate screen lock - I'm not sure if this is required - Some admins seem to indicate that jamf helper can be quit with cmd+Q
echo "Locking screen." | timestamp 2>&1 | tee -a $logFile
/System/Library/CoreServices/RemoteManagement/AppleVNCServer.bundle/Contents/Support/LockScreen.app/Contents/MacOS/LockScreen -session 256 &

# Start initial jamf Helper Window
echo "Starting initial jamf Helper screen..." | timestamp 2>&1 | tee -a $logFile
(displayMessage "Starting login policies...")

# Check to see if logfile exists. If so then delete as we only need log for the current user
if [ -f "$logFile" ]
then
    rm -f $logFile
fi

# If the logged in user does not exist / unreachable in AD or user is unknown
if [ -z "$(get_school ${NetUser})" ] || [ "$(get_school ${NetUser})" == "Unknown" ]
then
    echo "${NetUser} appears to be unreachable in AD or unknown. Checking to see if ${NetUser} is a local account..."| timestamp 2>&1 | tee -a $logFile
    # Find out if it's a local account. See if there is a dscl entry for the user. If so then it's a local account.
    account=`dscl . list /Users | grep ${NetUser}`
    # If the above command returned nothing then it's not a local account.
    if [ "$account" == "" ] || [ -z "$account" ]
        then
        echo "Not a local account or AD account. Cannot run login policies. Most likely because of one of the following: " | timestamp 2>&1 | tee -a $logFile
      echo "1. ${NetUser} does not have an associated school code." | timestamp 2>&1 | tee -a $logFile
      echo "2. Network accounts are unavailable." | timestamp 2>&1 | tee -a $logFile
      (displayErrorMessage "Cannot obtain network account." "Your university account $NetUser appears to be unreachable. This could be due to a network issue with this computer")
    # Else it's a local account.
    else
        echo "$NetUser appears to be a local account. Bypassing login policies as there is no need for them..." | timestamp 2>&1 | tee -a $logFile
        # Kill LockScreen
        killall LockScreen
        # Kill jamf Helper
        kill_jh
        # Call JAMF Helper window and show message
            (displayMessage "Logging in with local account ${NetUser}. Bypassing login policies.") &
      sleep 5s
      kill_jh
      echo "Done." | timestamp 2>&1 | tee -a $logFile
      exit 0;
    fi
fi

# Make sure preference doesn't ask for confirmation for an unknown server.
# Ideally this should be done within a config profile however some admins have problems with this
# https://www.jamf.com/jamf-nation/discussions/23565/you-are-attempting-to-connect-to-the-server-dialog-box-since-10-12-4
defaults write /Library/Preferences/com.apple.NetworkAuthorization AllowUnknownServers -bool YES

# Just incase there are any network drives mounted from previous users, unmount all network drives.
echo "Unmounting any network volumes" | timestamp 2>&1 | tee -a $logFile
# Force unmounts all currently mounted filesystems which are using smb, nfs or afp (hopefully this should cover all types of network server connections)
/sbin/umount -Afv -t nfs,smbfs,afp | timestamp 2>&1 | tee -a $logFile

# set acrobat pro as the default pdf handler if it is installed
echo "Setting Acrobat to be default pdf handler." | timestamp 2>&1 | tee -a $logFile
if [ -d /Applications/Adobe\ Acrobat\ DC/Adobe\ Acrobat.app ]; then
    duti -s com.adobe.Acrobat.Pro pdf all
fi

# Set lab screensaver time beyond the auto-logout time so that message can remain visible.
echo "Setting lab screensaver time..." | timestamp 2>&1 | tee -a $logFile
/usr/local/jamf/bin/jamf policy -event Set-Screensaver-Time

# Kill initial jamf helper screen.
kill_jh

# Folder redirect
echo "Running folder redirection policy." | timestamp 2>&1 | tee -a $logFile
(displayMessage "Running folder redirection...")
/usr/local/jamf/bin/jamf policy -event folder-redirect-py
if [ $? -ne 0 ]
then
    echo "Folder re-direct did not return a successful exit code. Displaying logout message to user." | timestamp 2>&1 | tee -a $logFile
    (displayErrorMessage "Could not re-direct folders." "The login process was unable to connect to your M: drive or obtain your network home location.")
else
    echo "Folder re-direct appears to have completed successfully" | timestamp 2>&1 | tee -a $logFile
fi
kill_jh

# Check quota
echo "Running quota check." | timestamp 2>&1 | tee -a $logFile
(displayMessage "Checking Quota...")
killall LockScreen
/usr/local/jamf/bin/jamf policy -event quota-check-py
if [ $? -ne 0 ]
then
    echo "Quota check did not return a successful exit code. Displaying logout message to user." | timestamp 2>&1 | tee -a $logFile
    (displayErrorMessage "Unable to check quota." "The login process was unable to check your user quota.")
else
    echo "Quota check appears to have completed successfully" | timestamp 2>&1 | tee -a $logFile
fi
kill_jh

# Run Desktop and Dock policy
echo "Running Desktop and Dock policy..." | timestamp 2>&1 | tee -a $logFile
(displayMessage "Configuring the Desktop and Dock...")

# We need to rework the existing dockutil script, will add additional options later
echo "Running MacApps custom trigger." | timestamp 2>&1 | tee -a $logFile
/usr/local/jamf/bin/jamf policy -event MacApps
echo "Running Dock custom trigger." | timestamp 2>&1 | tee -a $logFile
/usr/local/jamf/bin/jamf policy -event OADock
# Run custom trigger for desktop image
echo "Running custom trigger for Desktop image." | timestamp 2>&1 | tee -a $logFile
/usr/local/jamf/bin/jamf policy -event Desktop

echo "Setting save window expansion." | timestamp 2>&1 | tee -a $logFile
# Expand the save window
su $NetUser -c "/usr/bin/defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true"
su $NetUser -c "/usr/bin/defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true"

# Check for App Store prefs' Automatic Update preference being enabled and disable it
AutoUpdateStatus=`defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticCheckEnabled`
if [ $AutoUpdateStatus == "1" ]; then
    echo "Automatic Update preference is enabled. Disabling it..." | timestamp 2>&1 | tee -a $logFile
    defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticCheckEnabled -bool FALSE
else
    echo "Automatic Update preference is not enabled." | timestamp 2>&1 | tee -a $logFile
fi

# kill jamf helper
kill_jh

# Setting Chrome defaults
echo "Setting Chrome defaults..." | timestamp 2>&1 | tee -a $logFile
(displayMessage "Setting Chrome defaults...")
/usr/local/jamf/bin/jamf policy -event chromeDefaults
kill_jh

# Setting Firefox defaults
echo "Setting Firefox defaults..." | timestamp 2>&1 | tee -a $logFile
(displayMessage "Setting Firefox defaults...")
/usr/local/jamf/bin/jamf policy -event firefoxDefaults
kill_jh

# Add everyone as an lpoperator so they can unpause print queues
echo "Setting Printer configuration..." | timestamp 2>&1 | tee -a $logFile
/usr/sbin/dseditgroup -o edit -a everyone -t group _lpoperator

# Configuring Sidebar
echo "Configuring sidebar." | timestamp 2>&1 | tee -a $logFile
(displayMessage "Configuring sidebar...")
/usr/local/jamf/bin/jamf policy -event finder-sidebar-py
if [ $? -ne 0 ]
then
    echo "Configuring sidebar did not return a successful exit code. Displaying logout message to user." | timestamp 2>&1 | tee -a $logFile
    (displayErrorMessage "Cannot setup Finder Sidebar" "The login process was unable to setup your Finder Sidebar. This is most likley due to either a network issue with this computer of your M: drive")
else
    echo "Configuring sidebar appears to have completed successfully." | timestamp 2>&1 | tee -a $logFile
fi
kill_jh

# Running local custom login scripts
echo "Running local login scripts..." | timestamp 2>&1 | tee -a $logFile
descLocalScripts='Running local login scripts...'
(displayMessage "$descLocalScripts")
# Run custom trigger for local login scripts
/usr/local/jamf/bin/jamf policy -event CustomLogin
kill_jh

# Logging in
(displayMessage "Logging in....")

# Run login trigger for welcome page
echo "Running welcome page policy." | timestamp 2>&1 | tee -a $logFile
/usr/local/jamf/bin/jamf policy -event welcomePage

echo "Labs login master policy complete." | timestamp 2>&1 | tee -a $logFile

# Stop the screen lock
echo "Killing LockScreen." | timestamp 2>&1 | tee -a $logFile
killall LockScreen

# Kill jamf helper
echo "Killing last instance of jamf helper." | timestamp 2>&1 | tee -a $logFile
kill_jh

echo "Done." | timestamp 2>&1 | tee -a $logFile
exit 0;

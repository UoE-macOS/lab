#!/bin/bash

###################################################################
#
# Lab nightly reboot script and warning.
#
#
# Date: "25 July 2018 15:16:09 BST"
# Version: 0.3
# Origin: https://github.com/UoE-macOS/lab.git
# Released by JSS User: rcoleman
#
##################################################################

# Create logfile
logFile="/Library/Logs/nightly-reboot.log"

Today=`date | awk '{print $1" "$2" "$3}'`
RebootDone=`grep "$Today" $logFile`

if ! [ -z "$RebootDone" ]; then
	# Script has run today
    exit 0;
fi

# Check to see if log exists. If so then delete as we only require an up to date log
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

# Line below no longer required... I think! - Jamf Helper can be killed using it's name
# jamfHelperPID=""

# Function for displaying message and countdown to logged in user
Display_Countdown ()
{
# Set the desired number of minutes until reboot.
counter=15
echo "Counter set to 15" | timestamp >> $logFile

# While loop to show repeated message for set number of minutes, counting down til the reboot.
while ! [ "$counter" == 0 ]; do
# The body of the message that will be displayed, advising user of the need to reboot.
echo "Displaying message for $counter minute(s) to user" | timestamp >> $logFile
PROMPT_MESSAGE="This Mac will perform its nightly restart in $counter minute(s). 
Please save your work. 
 
"

# Line below no longer required... I think! - Jamf Helper can be killed using it's name
# jamfHelperPIDOld=$jamfHelperPID

# Bring up the prompt window advising user of need to restart and wait one minute.
"$jamfHelper" -windowType utility \
						-icon "$LOGO" \
						-heading "$PROMPT_TITLE" \
						-description "$PROMPT_MESSAGE" &

# Lines below no longer required... I think! - Jamf Helper can be killed using it's name
# jamfHelperPID=$( ps -A | grep "jamfHelper" | awk '{print $1}')
# sleep 0.5
# kill $jamfHelperPIDOld
# sleep 59.5

# Wait for 60 seconds
sleep 60s

# remove 1 from counter
let "counter = $counter -1"

# Kill all instances of Jamf Helper
killall jamfHelper 2> /dev/null
done

# Just incase there is still an instance of JamfHelper open, kill it.
killall -9 jamfHelper

# Display message to user that computer is restarting. Message will display for 5 seconds
"$jamfHelper" -windowType utility -icon "$LOGO" -heading "Restarting..." -description "This Mac will now restart.
 " -timeout 5
}
 
# Set the location for the jamfHelper utility that will create the prompt window.
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
	if [[ ! -x "$jamfHelper" ]]; then
		echo "******* jamfHelper not found. *******" | timestamp >> $logFile
		exit 1;
	else
		echo "JamfHelper found" | timestamp >> $logFile
	fi

# Set the University logo for the prompt window.
LOGO="/usr/local/jamf/UoELogo.png"
# Make sure Logo exists
if [[ ! -f "$LOGO" ]]
then
	echo "Cannot find logo at $LOGO" | timestamp >> $logFile
else
	echo "Logo found at $LOGO" | timestamp >> $logFile
fi

# The title of the message that will be displayed to the user.
PROMPT_TITLE="Nightly Mac Lab Restart"

# Set the button message for the prompt window.
BUTTON="Restart Now"
 
# Get username
username=`python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");'`

# Check there is a user present
echo "Is there a user currently logged in?" | timestamp >> $logFile

if ! [ -z "${username}" ]; then
	# Display the 15 min warning message.
	echo "$username is currently logged in. Displaying message." | timestamp >> $logFile
	Display_Countdown
else
	# No user is logged in
	echo "No user is logged in. Restarting machine." | timestamp >> $logFile
fi

# Again, make sure no instance of JamfHelper is running
killall jamfHelper 2> /dev/null

# Perform restart. Unfortunately cannot be a graceful restart as this gives the user the option to cancel.
echo "******* Performing reboot  in 1 minute *******" | timestamp >> $logFile
# Set shutdown time for 1 minute and shove process to the background so that the policy can complete
shutdown -r +1 &

echo "Done." | timestamp >> $logFile

exit 0;

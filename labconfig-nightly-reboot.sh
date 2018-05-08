#!/bin/bash

###################################################################
#
# Lab nightly reboot script and warning.
# 
# 
#
# Date: "Tue  8 May 2018 15:16:09 BST"
# Version: 0.1
# Origin: https://github.com/UoE-macOS/lab.git
# Released by JSS User: dsavage
#
##################################################################


Display_Countdown ()
{
# Set the location for the jamfHelper utility that will create the prompt window.
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
	if [[ ! -x "$jamfHelper" ]]; then
		echo "******* jamfHelper not found. *******"
		exit 1;
	fi

# Set the University logo for the prompt window.
LOGO="/usr/local/jamf/UoELogo.png"

# The title of the message that will be displayed to the user.
PROMPT_TITLE="Nightly Mac Lab Restart"

# Set the button message for the prompt window.
BUTTON="Restart Now"

# Set the desired number of minutes until reboot.
counter=15

jamfHelperPID=""

# While loop to show repeated message for set number of minutes, counting down til the reboot.
while ! [ "$counter" == 0 ]; do

# The body of the message that will be displayed, advising user of the need to reboot.
PROMPT_MESSAGE="This Mac will perform its nightly restart in $counter minute(s). 

Please save your work. 
 
"
jamfHelperPIDOld=$jamfHelperPID

# Bring up the prompt window advising user of need to restart and wait one minute.
"$jamfHelper" -windowType utility \
						-icon "$LOGO" \
						-heading "$PROMPT_TITLE" \
						-description "$PROMPT_MESSAGE" &
jamfHelperPID=$( ps -A | grep "jamfHelper" | awk '{print $1}')
sleep 0.5
kill $jamfHelperPIDOld
sleep 59.5
let "counter = $counter -1"

done

kill $jamfHelperPID
# Perform reboot. This cannot be a graceful reboot as that offers the user the option to cancel it.
"$jamfHelper" -windowType utility -icon "$LOGO" -heading "Restarting..." -description "This Mac will now restart.

 " -timeout 5
}
 
# Is there a user logged in
username=`python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");'`

# Check there is a user present
if ! [ -z "${username}" ]; then
	# Display the 15 min warning message.
	Display_Countdown
fi

echo "******* Performing reboot *******"
shutdown -r now
exit 0;

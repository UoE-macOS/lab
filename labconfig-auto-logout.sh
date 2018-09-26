#!/bin/bash

###################################################################
#
# Lab auto-logout script and warning for users idle over 10 minutes.
# As with the Windows desktop, it then gives them a 20-minute countdown before forcibly logging out.
#
# Date: "Wed 29 Aug 2018 13:04:09 BST"
# Version: 0.1
# Origin: https://github.com/UoE-macOS/lab.git
# Released by JSS User: ganders1
#
###################################################################

# Create logfile
logFile="/Library/Logs/auto-logout.log"

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

###### SETTINGS TO GENERATE LOGOUT MESSAGE IN JAMFHELPER ######

# Set the location for the jamfHelper utility that will create the logout message window.
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
    # If jamfhelper doesn't exist then there is obviously an issue. Exit this script.
	if [[ ! -x "$jamfHelper" ]]; then
		echo "******* jamfHelper not found. *******" | timestamp 2>&1 | tee -a $logFile
		exit 1;
	else
		echo "JamfHelper found" | timestamp 2>&1 | tee -a $logFile
	fi
	
# Set location of the University logo for the logout message and make sure it exists. If not it's not a deal breaker.
LOGO="/usr/local/jamf/UoELogo.png"
if [[ ! -f "$LOGO" ]]
then
	echo "Cannot find logo at $LOGO" | timestamp 2>&1 | tee -a $logFile
else
	echo "Logo found at $LOGO" | timestamp 2>&1 | tee -a $logFile
fi

# Set title of the logout message that will be displayed to the user.
PROMPT_TITLE="University Lab Mac - Auto-Logout"


############# FUNCTIONS #############

# Function to kill jamf helper
kill_jh(){
	jamfHelperPID=$( ps -A | grep "jamfHelper" | awk '{print $1}')
  	echo "Jamf Helper PID $jamfHelperPID. Killing process." | timestamp 2>&1 | tee -a $logFile
	kill $jamfHelperPID
}

# Function for displaying the logout message and countdown to the logged-in user
Display_Logout_Message () {

    # Set the desired number of minutes until logout after the Mac has been idle for 10 minutes.
    # Set to 20 after testing to mirror Windows desktop.
	counter=0
	dialogue=20
	
	# While loop to show repeated message for set number of minutes, counting down til the automatic logout.
    # Reset window every 15 seconds
	while [ "$idletimeMINS" -gt 10 ] && [ "$counter" -lt 20 ]; do
		# Get message to display
        # Set the body of the message that will be displayed, advising user they will be logged out.
PROMPT_MESSAGE="This Mac has been logged in and idle for over 10 minutes.

For security reasons, you will be automatically logged out in $dialogue minute(s) if the Mac remains idle.

ANY UNSAVED WORK WILL BE LOST.
 
"		# Display values
		echo "Counter value is $counter" | timestamp 2>&1 | tee -a $logFile
		echo "Idle time is $idletimeMINS minutes." | timestamp 2>&1 | tee -a $logFile
		# Bring up the prompt window advising user of the automatic idle logout.
		"$jamfHelper" -windowType utility -icon "$LOGO" -heading "$PROMPT_TITLE" -description "$PROMPT_MESSAGE" -timeout 15
        # Get idle time to see if user is around
		idletimeMINS=`/usr/sbin/ioreg -c IOHIDSystem | /usr/bin/awk '/HIDIdleTime/ {print int($NF/1000000000)/60; exit}' | awk -F "." '{print $1}'`
        # If idle time is 0 minutes then user is around
		if [ $idletimeMINS == 0 ]; then
			break
		fi
		# Bring up the prompt window advising user of the automatic idle logout.
		"$jamfHelper" -windowType utility -icon "$LOGO" -heading "$PROMPT_TITLE" -description "$PROMPT_MESSAGE" -timeout 15
        # Get idle time to see if user is around
		idletimeMINS=`/usr/sbin/ioreg -c IOHIDSystem | /usr/bin/awk '/HIDIdleTime/ {print int($NF/1000000000)/60; exit}' | awk -F "." '{print $1}'`
        # If idle time is 0 minutes then user is around
		if [ $idletimeMINS == 0 ]; then
			break
		fi
		# Bring up the prompt window advising user of the automatic idle logout.
		"$jamfHelper" -windowType utility -icon "$LOGO" -heading "$PROMPT_TITLE" -description "$PROMPT_MESSAGE" -timeout 15
        # Get idle time to see if user is around
		idletimeMINS=`/usr/sbin/ioreg -c IOHIDSystem | /usr/bin/awk '/HIDIdleTime/ {print int($NF/1000000000)/60; exit}' | awk -F "." '{print $1}'`
        # If idle time is 0 minutes then user is around
		if [ $idletimeMINS == 0 ]; then
			break
		fi
		# Bring up the prompt window advising user of the automatic idle logout.
		"$jamfHelper" -windowType utility -icon "$LOGO" -heading "$PROMPT_TITLE" -description "$PROMPT_MESSAGE" -timeout 15
        
        # Add to counter
		counter=$((counter+1))
        # Change dialogue count
		dialogue=$((20-counter))
        # Get idle time
		idletimeMINS=`/usr/sbin/ioreg -c IOHIDSystem | /usr/bin/awk '/HIDIdleTime/ {print int($NF/1000000000)/60; exit}' | awk -F "." '{print $1}'`
        # Echo to log
		echo "Idle time at end of loop $idletimeMINS" | timestamp 2>&1 | tee -a $logFile
	done
    # Set Counter to 20
	if [ $counter == 20 ]; then
		# kill all apps and restart.
		Force_Logout
	else
		echo "Computer not idle..." | timestamp 2>&1 | tee -a $logFile
    fi
}


# Function for forcing the logout of the Mac.
Force_Logout () { 
    echo "******* Starting auto-logout process. *******" | timestamp 2>&1 | tee -a $logFile
    # Again, make sure no instance of JamfHelper is running
    echo "******* Killing jamfHelper for the last time before auto-logout *******" | timestamp 2>&1 | tee -a $logFile
    kill_jh
    # Display message to user that computer is going to log out. Message will display for 5 seconds
    echo "Displaying message to auto logout" | timestamp 2>&1 | tee -a $logFile
    "$jamfHelper" -windowType utility -icon "$LOGO" -heading "Automatic logout after 30 minutes idle." -description "THIS MAC WILL NOW LOGOUT." -timeout 10
    # kill jamf helper again
    kill_jh
    # Close all open apps
    echo "Force quiting all open apps." | timestamp 2>&1 | tee -a $logFile
    osascript <<EOF
tell application "System Events"
	set listOfProcesses to (name of every process where background only is false)
end tell
repeat with processName in listOfProcesses
	do shell script "Killall " & quoted form of processName	
end repeat
EOF
    echo "All apps now closed" | timestamp 2>&1 | tee -a $logFile
    # Perform automatic logout. Unfortunately, cannot be a graceful logout as this allows apps to block it.
    echo "******* Performing automatic logout *******" | timestamp 2>&1 | tee -a $logFile
    # Logout
    osascript -e 'tell application "loginwindow" to  «event aevtrlgo»'
    echo "Done." | timestamp 2>&1 | tee -a $logFile
}


############ CHECK FOR USER AND DISPLAY LOGOUT MESSAGE ############

# Get username
username=`python -c 'from SystemConfiguration import SCDynamicStoreCopyConsoleUser; import sys; username = (SCDynamicStoreCopyConsoleUser(None, None, None) or [None])[0]; username = [username,""][username in [u"loginwindow", None, u""]]; sys.stdout.write(username + "\n");'`

# Check there is a user present, test their idle time and show message if it is 10 minutes or more.
if ! [ -z "${username}" ]; then
	echo "$username is logged in." | timestamp 2>&1 | tee -a $logFile
	# Work out how long the current user has been idle
	idletimeMINS=`/usr/sbin/ioreg -c IOHIDSystem | /usr/bin/awk '/HIDIdleTime/ {print int($NF/1000000000)/60; exit}' | awk -F "." '{print $1}'`
	echo "System has been idle for $idletimeMINS minutes" | timestamp 2>&1 | tee -a $logFile

	# If idletime is longer than 10 minutes then display message
	if [ "$idletimeMINS" > 10 ]; then
		Display_Logout_Message
    else
        echo "Idle time is only $idletimeMINS minutes." | timestamp 2>&1 | tee -a $logFile
	fi
	
else
	# No user is logged in
	echo "No user is logged in." | timestamp 2>&1 | tee -a $logFile
	exit 253; # 
fi

exit 0;

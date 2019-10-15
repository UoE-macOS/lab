#!/bin/bash

######
#
# This script reads in the app link configs and creates or deletes the app symlinks as required
#
#
# Date: Tue 15 Oct 2019 14:55:40 BST
# Version: 0.1.4
# Author: ganders1
#
######

# Set our folder paths
MacSD="/Library/MacSD"
ConfigDir="${MacSD}/MacAppsConf"
ACC="${MacSD}/Applications/Accessories"

if [ -d "${MacSD}/Applications" ]; then
  # Make sure the icon is set
  python -c 'import Cocoa; Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(Cocoa.NSImage.alloc().initWithContentsOfFile_("/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"), "/Library/MacSD/Applications", 0)'
else
  mkdir "${MacSD}/Applications"
  python -c 'import Cocoa; Cocoa.NSWorkspace.sharedWorkspace().setIcon_forFile_options_(Cocoa.NSImage.alloc().initWithContentsOfFile_("/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns"), "/Library/MacSD/Applications", 0)'
fi

# Check correct path to system applications is being used for 10.15+

OSVersion=`sw_vers | grep ProductVersion | awk -F "." '{print $2}'`

if [ $OSVersion -le 14 ]; then
PathToApps="/Applications"
else
PathToApps="/System/Applications"
fi

# Add the accessories, bit of a cheat since this would normally be in a policy that "adds" the app.
echo "$PathToApps/Calculator.app+${ACC}/Calculator.app" > "${ConfigDir}/LN~Accessories~Calculator.app"
echo "$PathToApps/Utilities/Grapher.app+${ACC}/Grapher.app" > "${ConfigDir}/LN~Accessories~Grapher.app"
echo "$PathToApps/Image Capture.app+${ACC}/Image Capture.app" > "${ConfigDir}/LN~Accessories~Image Capture.app"
echo "$PathToApps/Utilities/Screenshot.app+${ACC}/Screenshot.app" > "${ConfigDir}/LN~Accessories~Screenshot.app"
echo "$PathToApps/Utilities/Terminal.app+${ACC}/Terminal.app" > "${ConfigDir}/LN~Accessories~Terminal.app"

# Add each app
SAVEIFS=$IFS
IFS=$(echo -en "\n\b")
MacSD="/Library/MacSD"
ConfigDir="${MacSD}/MacAppsConf"
ConfFiles="$ConfigDir/*"
for f in $ConfFiles
do
  echo "Processing $f file..."
  Category=`echo ${f} | awk -F "~" '{print $2}'`
  ApplicationName=`echo ${f} | awk -F "~" '{print $3}'`
  CategoryPath="${MacSD}/Applications/$Category"
  echo "The path is: $CategoryPath"
  mkdir -p -v "${CategoryPath}"
  LinkPath="${MacSD}/Applications/$Category/$ApplicationName"
  AppPath=`cat "${f}" | awk -F "+" '{print $1}'`
  if [ -L "$LinkPath" ]; then
    echo "Delete and recreate symlink: ${AppPath} ${LinkPath}"
    rm -f "$LinkPath"
    # only make links to valid points, typos happen...
    if [ -d "${AppPath}" ]; then
    	ln -s "${AppPath}" "${LinkPath}"
    fi
  else
    if [ -d "${AppPath}" ]; then
    	echo "Create symlink: ${AppPath} ${LinkPath}"
        ln -s "${AppPath}" "${LinkPath}"
    fi
  fi
  # take action on each file. $f store current file name
  cat $f
done
IFS=$SAVEIFS

# Remove any extra links
ls ${MacSD}/Applications | grep -v "Icon" | grep -v ".DS_Store" > /tmp/CatList.txt
cat "/tmp/CatList.txt" | ( while read Category; 
  do
    SAVEIFS=$IFS
    IFS=$(echo -en "\n\b")
    echo "The Category is: ${Category}"
    AppLinks="${MacSD}/Applications/${Category}/*"
    for App in $AppLinks
      do
       echo "The link is ${App}"
        AppName=`basename "${App}"`
        Valid=`ls "${ConfigDir}" | grep "LN~${Category}~${AppName}"`
        if [ -z "${Valid}" ]; then
          rm -f "${App}"
        fi
      done
      IFS=$SAVEIFS
      if [ -z "$(ls -A "${MacSD}/Applications/${Category}" | grep -v ".DS_Store" | grep -v ".localized")" ]; then
           # Folder is empty
           rm -d "${MacSD}/Applications/${Category}"
      fi
done)

# Fix office firstrun
submit_diagnostic_data_to_microsoft=false


DisableOffice2016FirstRun(){

   # This function will disable the first run dialog windows for all Office 2016 apps.
   # It will also set the desired diagnostic info settings for Office application.

   /usr/bin/defaults write /Library/Preferences/com.microsoft."$app" kSubUIAppCompletedFirstRunSetup1507 -bool true
   /usr/bin/defaults write /Library/Preferences/com.microsoft."$app" SendAllTelemetryEnabled -bool "$submit_diagnostic_data_to_microsoft"

   # Outlook and OneNote require one additional first run setting to be disabled

   if [[ $app == "Outlook" ]] || [[ $app == "onenote.mac" ]]; then

     /usr/bin/defaults write /Library/Preferences/com.microsoft."$app" FirstRunExperienceCompletedO15 -bool true

   fi

}



# Run the DisableOffice2016FirstRun function for each detected Office 2016
# application to disable the first run dialogs for that Office 2016 application.

if [[ -e "/Applications/Microsoft Excel.app" ]]; then
	app=Excel
	DisableOffice2016FirstRun
fi

if [[ -e "/Applications/Microsoft OneNote.app" ]]; then
	app=onenote.mac
	DisableOffice2016FirstRun
fi

if [[ -e "/Applications/Microsoft Outlook.app" ]]; then
	app=Outlook
	DisableOffice2016FirstRun
fi

if [[ -e "/Applications/Microsoft PowerPoint.app" ]]; then
	app=Powerpoint
	DisableOffice2016FirstRun
fi

if [[ -e "/Applications/Microsoft Word.app" ]]; then
	app=Word
	DisableOffice2016FirstRun
fi


exit 0;

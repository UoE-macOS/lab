#!/bin/bash

######
#
# This script reads in the app link configs and creates or deletes the app synlinks as required
#
#
# Date: Wed 11 Jul 2018 14:51:00 BST
# Version: 0.1.2
# Author: dsavage
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

# Add the accesories, bit of a cheat since this would normally be in a policy that "adds" the app.
echo "/Applications/Calculator.app+${ACC}/Calculator.app" > "${ConfigDir}/LN~Accessories~Calculator.app"
echo "/Applications/Image Capture.app+${ACC}/Image Capture.app" > "${ConfigDir}/LN~Accessories~Image Capture.app"
echo "/Applications/Utilities/Grab.app+${ACC}/Grab.app" > "${ConfigDir}/LN~Accessories~Grab.app"
echo "/Applications/Utilities/Grapher.app+${ACC}/Grapher.app" > "${ConfigDir}/LN~Accessories~Grapher.app"
echo "/Applications/Utilities/Terminal.app+${ACC}/Terminal.app" > "${ConfigDir}/LN~Accessories~Terminal.app"

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
    ln -s "${AppPath}" "${LinkPath}"
  else
    echo "Create symlink: ${AppPath} ${LinkPath}"
    ln -s "${AppPath}" "${LinkPath}"
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

exit 0;

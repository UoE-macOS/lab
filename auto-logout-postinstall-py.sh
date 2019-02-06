#!/bin/bash

# Set permissions on daemon
chown root:wheel /Library/LaunchDaemons/ed.dst.labs-auto-logout-py.plist
chmod 644 /Library/LaunchDaemons/ed.dst.labs-auto-logout-py.plist

# Launch daemon
launchctl load -w /Library/LaunchDaemons/ed.dst.labs-auto-logout-py.plist
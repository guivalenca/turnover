# Sourced by burst.sh. $1 = screenshot folder.
# H: where does FIFinderSyncController.showExtensionManagementInterface() land? (setup checklist button)
#    No synthesized input. Quits System Settings afterwards only if it was not already running.
shots=$1
was_running=$(pgrep -x "System Settings" >/dev/null && echo yes || echo no)
open -g "turnover-spike://manage-extensions"
sleep 3
screencapture -x $shots/H1-extension-management.png
osascript -e 'tell application "System Events" to get name of every window of process "System Settings"' 2>&1 | sed 's/^/System Settings windows: /'
[[ $was_running == no ]] && pkill -x 'System Settings'
sleep 0.5

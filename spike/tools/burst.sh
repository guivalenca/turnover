#!/bin/zsh
# Run one short burst of synthesized input against the Finder test window, politely:
#   burst.sh <testFolder> <min-idle-seconds> <script.zsh> [args...]
# 1. waits until nobody has touched the keyboard or mouse for <min-idle-seconds>;
# 2. remembers the frontmost app and the cursor position;
# 3. brings the test folder's Finder window forward at a fixed frame (300,200 900x560);
# 4. sources <script.zsh>, which uses $ctl (spikectl) and $folder;
# 5. gives focus back to the remembered app and puts the cursor back.
set -uo pipefail
ctl=${0:A:h}/../build/spikectl
folder=$1; min=$2; script=$3; shift 3

while true; do
  idle=$(ioreg -c IOHIDSystem -d 4 | awk '/HIDIdleTime/ {printf "%d", $NF/1000000000; exit}')
  (( idle >= min )) && break
  sleep 3
done
echo "$(date +%T) idle ${idle}s, starting burst $script"

front=$($ctl front)
mouse=($($ctl mouse))
open "$folder"
sleep 1.5
$ctl window "${folder:t}" 300 200 900 560 >/dev/null || { echo "window not found"; $ctl activate $front; exit 4; }
sleep 0.7

source "$script" "$@"
rc=$?

$ctl activate $front
$ctl run "move:${mouse[1]},${mouse[2]}" >/dev/null
echo "$(date +%T) burst done rc=$rc"
exit $rc

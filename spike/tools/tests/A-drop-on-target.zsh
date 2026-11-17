# Sourced by burst.sh. $1 = screenshot folder.
# Survey the window, then test A: drag a.heic, press ⇧ mid-drag, hold still, then drop on the
# ring's target. Expect: drag detected, ring opens, drop accepted with the URL, file not moved.
shots=$1
win=${folder:t}
for n in a.heic b.heic c.png d.txt clip.mov dest; do echo "find $n: $($ctl find $n $win | tr '\n' ';')"; done
screencapture -x $shots/A0-survey.png
read ax ay _ <<< "$($ctl find a.heic $win | head -1)"
[[ -z "${ax:-}" ]] && { echo "a.heic not found"; $ctl dump $win 9 | head -80; return 5 }
# ⇧ is pressed at (850,560); the target sits 95 pt above it.
$ctl run "expect:$ax,$ay,a.heic" "move:$ax,$ay" "down:$ax,$ay" \
  "drag:$((ax+30)),$((ay+30)),6,120" "drag:850,560,12,300" "sleep:250" "shot:$shots/A1-dragging.png" \
  "shift:down" "sleep:400" "shot:$shots/A2-shift-no-move.png" \
  "drag:852,562,2,40" "sleep:250" "shot:$shots/A3-ring-open.png" \
  "drag:850,465,8,250" "sleep:300" "shot:$shots/A4-on-target.png" \
  "up" "sleep:300" "shift:up" || return $?
ls -1 $folder $folder/dest

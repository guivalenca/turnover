# Sourced by burst.sh. $1 = screenshot folder.
# Z: same as B (drop off-target over the "dest" row) but with a fully clear panel (fillAlpha 0) and
#    no glass. Does a 0-alpha window still own the drag everywhere, or does the drop fall through to
#    Finder underneath (a.heic would land in dest/)? Then a drop on the target must still be accepted.
shots=$1
win=${folder:t}
read ax ay _ <<< "$($ctl find a.heic $win | head -1)"
read dx dy _ <<< "$($ctl find dest $win | head -1)"
[[ -z "${ax:-}" || -z "${dx:-}" ]] && { echo "items not found"; return 5 }
defaults write com.guivalenca.turnover.spike fillAlpha -float 0
defaults write com.guivalenca.turnover.spike glass -bool false

$ctl run "expect:$dx,$dy,dest" "expect:$ax,$ay,a.heic" "move:$ax,$ay" "down:$ax,$ay" \
  "drag:$((ax+30)),$((ay+30)),6,120" "drag:850,560,12,300" "sleep:150" \
  "shift:down" "drag:852,562,2,40" "sleep:200" "drag:$dx,$dy,10,300" "sleep:250" "shot:$shots/Z1-clear-over-dest.png" \
  "up" "sleep:600" "shift:up" "sleep:300"
rc=$?
echo "after clear-panel drop over dest:"; ls -1 $folder $folder/dest
if (( rc == 0 )); then
  $ctl run "expect:$ax,$ay,a.heic" "move:$ax,$ay" "down:$ax,$ay" \
    "drag:$((ax+30)),$((ay+30)),6,120" "drag:850,560,12,300" "sleep:150" \
    "shift:down" "drag:852,562,2,40" "sleep:200" "drag:850,465,8,250" "sleep:300" "shot:$shots/Z2-clear-on-target.png" \
    "up" "sleep:300" "shift:up" "sleep:300"
  rc=$?
fi
defaults delete com.guivalenca.turnover.spike fillAlpha
defaults delete com.guivalenca.turnover.spike glass
return $rc

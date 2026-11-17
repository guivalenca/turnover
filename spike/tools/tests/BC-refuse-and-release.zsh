# Sourced by burst.sh. $1 = screenshot folder.
# B: ring open, drop off-target right over the "dest" folder icon (which is under the panel).
#    Expect: drop refused, a.heic stays put, dest stays empty (no fall-through to Finder).
# C: ring open, release ⇧ (panel hides), drop on "dest". Expect: a normal Finder move into dest.
shots=$1
win=${folder:t}
read ax ay _ <<< "$($ctl find a.heic $win | head -1)"
read dx dy _ <<< "$($ctl find dest $win | head -1)"
[[ -z "${ax:-}" || -z "${dx:-}" ]] && { echo "items not found"; return 5 }
echo "a.heic=$ax,$ay dest=$dx,$dy"

$ctl run "expect:$dx,$dy,dest" "expect:$ax,$ay,a.heic" "move:$ax,$ay" "down:$ax,$ay" \
  "drag:$((ax+30)),$((ay+30)),6,120" "drag:850,560,12,300" "sleep:150" \
  "shift:down" "drag:852,562,2,40" "sleep:200" \
  "drag:$dx,$dy,10,300" "sleep:250" "shot:$shots/B1-over-dest-ring-open.png" \
  "up" "sleep:600" "shift:up" "sleep:300" || return $?
echo "after B:"; ls -1 $folder $folder/dest

$ctl run "expect:$dx,$dy,dest" "expect:$ax,$ay,a.heic" "move:$ax,$ay" "down:$ax,$ay" \
  "drag:$((ax+30)),$((ay+30)),6,120" "drag:850,560,12,300" "sleep:150" \
  "shift:down" "drag:852,562,2,40" "sleep:250" "shot:$shots/C1-ring-open.png" \
  "shift:up" "sleep:250" "shot:$shots/C2-shift-released.png" \
  "drag:$dx,$dy,10,300" "sleep:200" "shot:$shots/C3-over-dest.png" "up" "sleep:600" || return $?
echo "after C:"; ls -1 $folder $folder/dest

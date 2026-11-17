# Sourced by burst.sh. $1 = screenshot folder.
# R: one ring run again (drop on target) to log the drag-image source and pasteboard access policy.
# F: with the spike running, ⇧-click, ⇧+↓ and ⇧ during a box-select still work in Finder (list view),
#    and none of them opens the ring. Rows are clicked in the Date column (x=800): a second click on
#    a selected file's *name* starts a rename, which would swallow the arrow keys.
shots=$1
win=${folder:t}
read ax ay _ <<< "$($ctl find a.heic $win | head -1)"
read cx cy _ <<< "$($ctl find c.png $win | head -1)"
[[ -z "${ax:-}" || -z "${cx:-}" ]] && { echo "items not found"; return 5 }
ex=1150; ey=720   # empty area under the rows
rx=800            # Date column

$ctl run "expect:$ax,$ay,a.heic" "move:$ax,$ay" "down:$ax,$ay" \
  "drag:$((ax+30)),$((ay+30)),6,120" "drag:850,560,12,300" "sleep:150" \
  "shift:down" "drag:852,562,2,40" "sleep:200" "drag:850,465,8,250" "sleep:300" "shot:$shots/R1-on-target.png" \
  "up" "sleep:300" "shift:up" "sleep:300" || return $?

$ctl run "expect:$ex,$ey,$win" "click:$ex,$ey" "sleep:300" "click:$rx,$ay" "sleep:600" \
  "shift:down" "click:$rx,$cy" "shift:up" "sleep:400" "shot:$shots/F1-shift-click.png" || return $?
echo "after click a.heic row, ⇧-click c.png row:"; $ctl selected $win

$ctl run "click:$ex,$ey" "sleep:300" "click:$rx,$ay" "sleep:600" \
  "shift:down" "key:down" "sleep:120" "key:down" "sleep:120" "shift:up" "sleep:300" "shot:$shots/F2-shift-arrow.png" || return $?
echo "after click a.heic row, ⇧↓ ⇧↓:"; $ctl selected $win

$ctl run "click:$ex,$ey" "sleep:300" "move:$ex,$ey" "down:$ex,$ey" "drag:$((ex-40)),$((ey-40)),5,100" \
  "shift:down" "drag:$rx,$((cy+5)),12,400" "sleep:300" "shot:$shots/F3-shift-box-select.png" \
  "up" "sleep:150" "shift:up" "sleep:300" || return $?
echo "after ⇧ box-select from the empty area up to the c.png row:"; $ctl selected $win
$ctl run "click:$ex,$ey" "sleep:200"

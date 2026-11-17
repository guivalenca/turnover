# Sourced by burst.sh. $1 = screenshot folder.
# D: ⇧ held before the drag starts -> no ring. Release and press ⇧ again mid-drag -> ring opens.
# E: Esc with the ring open -> the drag is cancelled and the ring closes. Nothing moves.
shots=$1
win=${folder:t}
read bx by _ <<< "$($ctl find b.heic $win | head -1)"
[[ -z "${bx:-}" ]] && { echo "b.heic not found"; return 5 }

$ctl run "expect:$bx,$by,b.heic" "move:$bx,$by" "shift:down" "sleep:150" "down:$bx,$by" \
  "drag:$((bx+30)),$((by+30)),6,120" "drag:850,560,12,300" "sleep:400" "shot:$shots/D1-shift-held-from-start.png" \
  "shift:up" "sleep:200" "shift:down" "drag:852,562,2,40" "sleep:300" "shot:$shots/D2-shift-repressed.png" \
  "key:esc" "sleep:400" "shot:$shots/E1-after-esc.png" \
  "up" "sleep:200" "shift:up" "sleep:300" || return $?
echo "after D/E:"; ls -1 $folder $folder/dest

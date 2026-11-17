# Sourced by burst.sh. $1 = screenshot folder.
# G1: right-click a.heic -> top-level "Turnover" submenu -> "PNG (1 image)".
#     Expect: app logs TRANSPORT received convert to=png files=[.../a.heic].
# G2: select a.heic…clip.mov (3 images + 1 video) -> Turnover -> "MP4 (1 video)".
#     Expect: the submenu lists PNG/JPEG (3 images) and MP4 (1 video); the app receives all 4 paths.
# G3: right-click d.txt: no "Turnover" item. Esc closes the menu.
shots=$1
win=${folder:t}
rx=800  # Date column: clicking there selects a row without starting a rename
read ax ay _ <<< "$($ctl find a.heic $win | head -1)"
read mx my _ <<< "$($ctl find clip.mov $win | head -1)"
read tx ty _ <<< "$($ctl find d.txt $win | head -1)"
[[ -z "${ax:-}" || -z "${mx:-}" || -z "${tx:-}" ]] && { echo "items not found"; return 5 }

item() {  # centre of the visible menu item titled exactly $1, or starting with $1 if $2 == prefix
  $ctl menus | grep -v "centre=0 1117" | awk -v t="$1" -v mode="${2:-exact}" '
    { q = index($0, "AXMenuItem \"" t); if (!q) next
      rest = substr($0, q + 12 + length(t), 1); if (mode == "exact" && rest != "\"") next
      for (i = 1; i <= NF; i++) if ($i ~ /^centre=/) { sub("centre=", "", $i); print $i, $(i+1); exit } }'
}

pick() {  # open Turnover submenu at the current context menu and click the item starting with $1
  local tx ty px py
  read tx ty <<< "$(item Turnover)"
  [[ -z "${tx:-}" ]] && { echo "no Turnover item"; $ctl run "key:esc"; return 6 }
  $ctl run "move:$tx,$ty,6,150" "sleep:700" || return $?
  $ctl menus | grep -v "centre=0 1117" | grep -A6 'AXMenuItem "Turnover"' | sed 's/^ *//' | sed 's/^/  submenu: /'
  read px py <<< "$(item "$1" prefix)"
  [[ -z "${px:-}" ]] && { echo "no $1 item"; $ctl run "key:esc" "key:esc"; return 7 }
  $ctl run "move:$px,$ty,6,150" "move:$px,$py,3,80" "sleep:300" "shot:$shots/G-$1.png" "click:$px,$py" "sleep:1200"
}

$ctl run "expect:$ax,$ay,a.heic" "click:$rx,$ay" "sleep:400" "rclick:$rx,$ay" "sleep:700" || return $?
pick PNG || return $?

$ctl run "click:$rx,$ay" "sleep:400" "shift:down" "click:$rx,$my" "shift:up" "sleep:300" "rclick:$rx,$my" "sleep:700" || return $?
pick MP4 || return $?

$ctl run "expect:$tx,$ty,d.txt" "click:$rx,$ty" "sleep:400" "rclick:$rx,$ty" "sleep:700" "shot:$shots/G3-txt-menu.png" || return $?
echo "exact Turnover items for d.txt: $(item Turnover | wc -l | tr -d ' ')"
$ctl run "key:esc" "sleep:200"

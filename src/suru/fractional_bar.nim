import strformat
import strutils
import ../suru
import ./format
import ./common_displays

proc barDisplay*(ssb: SingleSuruBar): string =
  if ssb.total > 0:
    ssb.barDisplay("█", " ", ["▏", "▎", "▍", "▌", "▋", "▊", "▉"])
  else:
    "░".repeat(ssb.length)

proc format*(ssb: SingleSuruBar): string {.gcsafe.} =
  &"{ssb.percentDisplay}|{ssb.barDisplay}| {ssb.progressDisplay} [{ssb.timeDisplay}, {ssb.speedDisplay}]"


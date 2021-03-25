import ../suru
import ./format
import strformat
import strutils

proc percentDisplay*(ssb: SingleSuruBar): string =
  if ssb.total > 0:
    &"{(ssb.percent*100).int:>3}%"
  else:
    " ??%"

proc barDisplay*(ssb: SingleSuruBar): string =
  if ssb.total > 0:
    ssb.barDisplay("=", " ", [">"])
  else:
    "#".repeat(ssb.length)

proc progressDisplay*(ssb: SingleSuruBar): string =
  if ssb.total > 0:
    let totalStr = $ssb.total
    &"{($ssb.progress).align(totalStr.len, ' ')}/{totalStr}"
  else:
    let progressStr = $ssb.progress
    &"{progressStr.align(progressStr.len, ' ')}/" & "?".repeat(progressStr.len)

proc timeDisplay*(ssb: SingleSuruBar): string =
  if ssb.total > 0:
    &"{ssb.elapsed.formatTime}<{ssb.eta.formatTime}"
  else:
    &"{ssb.elapsed.formatTime}"

proc speedDisplay*(ssb: SingleSuruBar): string =
  &"{ssb.perSecond.formatUnit}/sec"

proc format*(ssb: SingleSuruBar): string {.gcsafe.} =
  &"{ssb.percentDisplay}|{ssb.barDisplay}| {ssb.progressDisplay} [{ssb.timeDisplay}, {ssb.speedDisplay}]"


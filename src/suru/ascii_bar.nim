import std/[
  strformat,
  strutils,
]
import ../suru
import "."/[
  format,
  common_displays,
]

proc barDisplay*(ssb: SingleSuruBar): string =
  if ssb.total > 0:
    ssb.barDisplay("=", " ", [">"], alwaysShow = true)
  else:
    "#".repeat(ssb.length)

proc format*(ssb: SingleSuruBar): string {.gcsafe.} =
  &"{ssb.percentDisplay}|{ssb.barDisplay}| {ssb.progressDisplay} [{ssb.timeDisplay}, {ssb.speedDisplay}]"


import macros, std/monotimes, times, terminal, math, strutils
{.experimental: "forLoopMacros".}

type
  ExpMovingAverager = object
    timeAverage: int ## in milliseconds
    timeMeasure: int ## in milliseconds
    mean: float
  SuruBar* = object
    length: int
    progress: int
    total: int
    stat: ExpMovingAverager
    firstAccess: MonoTime
    lastAccess: MonoTime
    lastProgress: int

#

proc push(mv: var ExpMovingAverager, value: int) =
  let valFloat = value.float
  if mv.mean == 0:
    mv.mean = valFloat
  else:
    mv.mean = valFloat + exp(-mv.timeMeasure/mv.timeAverage) * (mv.mean - valFloat)

#

proc inc*(bar: var SuruBar) =
  ## Increments the bar progress
  inc bar.progress

proc formatTime(secs: SomeInteger): string =
  discard
  result = align($(secs div 60), 2, '0') & ":" & align($(secs mod 60), 2, '0')

let fractionals = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
proc `$`*(bar: SuruBar): string =
  let length: float = if bar.length == 0:
    25
  else:
    bar.length

  let
    percentage = bar.progress / bar.total
    shaded = floor(percentage * length).int
    fractional = floor(percentage * length * 8).int - (shaded * 8)
    perSec = bar.stat.mean * (1000/bar.stat.timeMeasure)
    timeElapsed = ((bar.lastAccess.ticks - bar.firstAccess.ticks) div 1_000_000_000).formatTime
    timeLeft = if perSec > 0: round((bar.total - bar.progress).float / perSec).int.formatTime else: "??:??"

  result = "|" & "█".repeat(shaded) & fractionals[fractional] &
    " ".repeat(length.int - shaded - (if fractional == 0: 0 else: 1)) & "| " &
    $bar.progress & "/" & $bar.total &
    " [" & timeElapsed & "<" & timeLeft & ", " &
    perSec.formatFloat(ffDecimal, 2) & "/sec]"

proc show*(bar: var SuruBar) =
  ## Shows the bar in a formatted style.
  ## Does not set lastAccess, use show(bar: var SuruBar, lastAccess: MonoTime) instead
  stdout.eraseLine
  stdout.write $bar
  stdout.flushFile
  stdout.setCursorXPos 0

proc show*(bar: var SuruBar, lastAccess: MonoTime) =
  ## Shows the bar in a formatted style.
  ## Sets lastAccess, use show(bar: var SuruBar) for the final printing
  bar.lastAccess = lastAccess
  stdout.eraseLine
  stdout.write $bar
  stdout.flushFile
  stdout.setCursorXPos 0

proc calculateMeanChange(bar: var SuruBar) =
  bar.stat.push bar.progress - bar.lastProgress
  bar.lastProgress = bar.progress

#

template len(x: typedesc[array]): int =
  system.len(x)

template len[N, T](x: array[N, T]): int =
  system.len(x)

template len(arg: untyped): int =
  0

macro suru*(x: ForLoopStmt): untyped =
  ## Wraps an iterable for printing a progress bar
  ## WARNING: Does not work for iterators
  expectKind x, nnkForStmt

  let
    bar = genSym(nskVar, "bar")
    toIterate = genSym(nskVar, "toIterate")
    a = x[^2][1]

  result = newStmtList()

  # first printing of the progress bar
  result.add quote do:
    var
      `bar`: SuruBar
      `toIterate` = `a`

    `bar`.total = len(`toIterate`)
    `bar`.firstAccess = getMonoTime()
    `bar`.lastAccess = `bar`.firstAccess
    `bar`.stat.timeAverage = 1000
    `bar`.stat.timeMeasure = 50
    `bar`.show(getMonoTime())
    `bar`.calculateMeanChange
    # echo `bar`.repr

  var body = x[^1]
  # makes body a statement list to be able to add statements
  if body.kind != nnkStmtList:
    body = newTree(nnkStmtList, body)

  # in-loop printing of the progress bar
  body.add quote do:
    inc `bar`
    let
      newTime = getMonoTime()
      difference = newTime.ticks - `bar`.lastAccess.ticks
    if difference > 50_000_000:
      `bar`.stat.timeMeasure = difference.int div 1_000_000.int
      `bar`.show(newTime)
      `bar`.calculateMeanChange

  # re-adds the variables into the new for statement
  var newFor = newTree(nnkForStmt)
  for i in 0..<x.len-2:
    newFor.add x[i]

  # transforms suru(...) to '...'
  newFor.add toIterate
  newFor.add body
  result.add newFor

  # wraps the whole macro in a block to create a new scope
  # also includes final print of the bar
  result = quote do:
    block:
      `result`
      `bar`.show()
      echo ""

when isMainModule:
  import os, sequtils, random
  randomize()

  for b in suru(toSeq(0..<1_000)):
    sleep((rand(99) + 1))
    discard

  for a, b in suru([1, 2, 3, 5]):
    sleep(1000)
    discard

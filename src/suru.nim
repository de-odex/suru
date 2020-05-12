import macros, std/monotimes, times, terminal, math, strutils
{.experimental: "forLoopMacros".}

type
  ExpMovingAverager = object
    mean: float
  SuruBar* = object
    length: int
    progress: int
    total: int
    progressStat: ExpMovingAverager
    timeStat: ExpMovingAverager
    firstAccess: MonoTime
    lastAccess: MonoTime
    lastProgress: int

#

proc push(mv: var ExpMovingAverager, value: int) =
  let valFloat = value.float
  if mv.mean == 0:
    mv.mean = valFloat
  else:
    mv.mean = valFloat + exp(-1/5) * (mv.mean - valFloat)

#

proc initSuruBar*(length: int = 25): SuruBar =
  ## Creates a SuruBar with a length
  ## Does not prime the bar for a loop, use initPreLoop for that
  SuruBar(
    length: length
  )

proc inc*(bar: var SuruBar) =
  ## Increments the bar progress
  inc bar.progress

proc formatTime(secs: SomeFloat): string =
  if secs < 0 or secs.classify notin {fcNormal, fcSubnormal, fcZero}:
    # if time is under 0 or abnormal, output ??
    "??s"
  elif secs <= 180:
    # under three minutes, just render as seconds
    secs.formatFloat(ffDecimal, 1) & "s"
  else:
    # use minute format
    let secs = round(secs).int
    align($(secs div 60), 2, '0') & ":" & align($(secs mod 60), 2, '0')

let fractionals = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
proc `$`*(bar: SuruBar): string =
  let
    percentage = bar.progress / bar.total
    shaded = floor(percentage * bar.length.float).int
    fractional = floor(percentage * bar.length.float * 8).int - (shaded * 8)
    unshaded = bar.length - shaded - (if fractional == 0: 0 else: 1)
    perSec = bar.progressStat.mean * (1000/bar.timeStat.mean)
    timeElapsed = ((bar.lastAccess.ticks - bar.firstAccess.ticks).float / 1_000_000_000).formatTime
    timeLeft = ((bar.total - bar.progress).float / perSec).formatTime

  result = (percentage*100).formatFloat(ffDecimal, 0).align(3) & "%|" &
    "█".repeat(shaded) & fractionals[fractional] & " ".repeat(unshaded) & "| " &
    $bar.progress & "/" & $bar.total & " [" & timeElapsed & "<" & timeLeft &
    ", " &
    (if perSec.classify notin {fcNormal, fcSubnormal, fcZero}: "??" else: perSec.formatFloat(ffDecimal, 2)) &
    "/sec]"

proc show*(bar: var SuruBar) =
  ## Shows the bar in a formatted style.
  stdout.eraseLine
  stdout.write $bar
  stdout.flushFile
  stdout.setCursorXPos 0

proc initPreLoop*(bar: var SuruBar, iterableLength: int) =
  bar.total = iterableLength
  bar.firstAccess = getMonoTime()

proc update*(bar: var SuruBar, time: MonoTime, difference: SomeInteger) =
  bar.lastAccess = time
  bar.timeStat.push difference.int div 1_000_000.int
  bar.progressStat.push bar.progress - bar.lastProgress
  bar.show()
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
      `bar`: SuruBar = initSuruBar()
      `toIterate` = `a`

    `bar`.initPreLoop(len(`toIterate`))
    `bar`.update(getMonoTime(), 0)

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
      `bar`.update(newTime, difference)

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
  import unittest, os, sequtils, random
  randomize()

  test "random time test":
    for a in suru(toSeq(0..<100)):
      sleep((rand(99) + 1))

  test "long time test":
    for a in suru([1, 2, 3, 5]):
      sleep(1000)

  test "constant time test":
    for a in suru(toSeq(0..<100)):
      sleep(25)

  test "v-shaped time test":
    for a in suru(toSeq(1..100) & toSeq(countdown(100, 1))):
      sleep(a)

  test "increasing time test":
    for a in suru(toSeq(1..100)):
      sleep(a)

  test "sinusoidal time test":
    for a in suru(toSeq(1..100)):
      sleep(int(sin(a.float / 5) * 50 + 50))

import macros, std/monotimes, times, terminal, math, strutils, sequtils
{.experimental: "forLoopMacros".}

type
  ExpMovingAverager = object
    mean: float
  SuruBar* = object
    length: seq[int]
    progress: seq[int]
    total: seq[int]
    progressStat: seq[ExpMovingAverager]
    timeStat: seq[ExpMovingAverager]
    startTime: seq[MonoTime]
    lastIncrement: seq[MonoTime]
    lastAccess: seq[MonoTime]
    lastProgress: seq[int]
    currentIndex: int # for usage in show(), tracks current index cursor is on relative to first progress bar

#

proc push(mv: var ExpMovingAverager, value: int) =
  let valFloat = value.float
  if mv.mean == 0:
    mv.mean = valFloat
  else:
    mv.mean = valFloat + exp(-1/5) * (mv.mean - valFloat)

#

proc initSuruBar*(lengths: varargs[int]): SuruBar =
  ## Creates a SuruBar with the given lengths
  ## Does not prime the bar for a loop, use initPreLoop for that
  let lengths = if lengths.len == 0:
    @[25]
  else:
    @lengths
  let
    zeroes = 0.repeat(lengths.len)
    averagers = ExpMovingAverager().repeat(lengths.len)
    monotimes = MonoTime().repeat(lengths.len)
  SuruBar(
    length: lengths,
    progress: zeroes,
    total: zeroes,
    progressStat: averagers,
    timeStat: averagers,
    startTime: monotimes,
    lastIncrement: monotimes,
    lastAccess: monotimes,
    lastProgress: zeroes,
  )

# proc initSuruBar*(length: int = 25): SuruBar =
#   initSuruBar(length)

proc len(bar: SuruBar): int =
  bar.length.len

iterator items(bar: SuruBar): int =
  for item in 0..<bar.length.len:
    yield item

proc inc*(bar: var SuruBar, index: int = 0) =
  ## Increments the bar progress
  inc bar.progress[index]
  let newTime = getMonoTime()
  bar.timeStat[index].push (newTime.ticks - bar.lastIncrement[index].ticks).int div 1_000_000
  bar.lastIncrement[index] = newTime
  bar.progressStat[index].push bar.progress[index] - bar.lastProgress[index]
  bar.lastProgress[index] = bar.progress[index]

proc formatTime(secs: SomeFloat): string =
  if secs.classify notin {fcNormal, fcSubnormal, fcZero}:
    # if time is abnormal, output ??
    "??s"
  elif secs < 0:
    # cheat bad float subtraction by clipping anything under 0 to 0
    "0.0s"
  elif secs <= 180:
    # under three minutes, just render as seconds
    secs.formatFloat(ffDecimal, 1) & "s"
  else:
    # use minute format
    let secs = round(secs).int
    align($(secs div 60), 2, '0') & ":" & align($(secs mod 60), 2, '0')

let fractionals = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
proc `$`*(bar: SuruBar, index: int = 0): string =
  let
    percentage = bar.progress[index] / bar.total[index]
    shaded = floor(percentage * bar.length[index].float).int
    fractional = floor(percentage * bar.length[index].float * 8).int - shaded * 8
    unshaded = bar.length[index] - shaded - (if fractional == 0: 0 else: 1)
    perSec = bar.progressStat[index].mean * (1000/bar.timeStat[index].mean)
    timeElapsed = (bar.lastAccess[index].ticks - bar.startTime[index].ticks).float / 1_000_000_000
    timeLeft = (bar.total[index] - bar.progress[index]).float / perSec -
      ((getMonoTime().ticks - bar.lastIncrement[index].ticks).float / 1_000_000_000)

  result = (percentage*100).formatFloat(ffDecimal, 0).align(3) & "%|" &
    "█".repeat(shaded) & fractionals[fractional] & " ".repeat(unshaded) & "| " &
    $bar.progress[index] & "/" & $bar.total[index] &
    " [" & timeElapsed.formatTime & "<" & timeLeft.formatTime & ", " &
    (if perSec.classify notin {fcNormal, fcSubnormal, fcZero}: "??" else: perSec.formatFloat(ffDecimal, 2)) &
    "/sec]"

proc show*(bar: var SuruBar, index: int = 0) =
  ## Shows the bar in a formatted style.
  let difference = index - bar.currentIndex
  if difference < 0:
    stdout.cursorUp(abs(difference))
  elif difference > 0:
    stdout.cursorDown(abs(difference))
  bar.currentIndex = index
  stdout.eraseLine
  stdout.write `$`(bar, index)
  stdout.flushFile
  stdout.setCursorXPos 0

proc start*(bar: var SuruBar, iterableLengths: varargs[int]) =
  doAssert iterableLengths.len == bar.len

  for index in 1..<iterableLengths.len:
    echo ""
  if iterableLengths.len > 1:
    stdout.cursorUp(iterableLengths.len - 1)

  bar.total = @iterableLengths
  bar.startTime = getMonoTime().repeat(iterableLengths.len)
  bar.lastAccess = bar.startTime
  bar.lastIncrement = bar.startTime
  for index in 0..<iterableLengths.len:
    bar.timeStat[index].push 0
    bar.progressStat[index].push 0
    bar.show(index)

proc update*(bar: var SuruBar, delay: int, index: int = 0) =
  let
    newTime = getMonoTime()
    difference = newTime.ticks - bar.lastAccess[index].ticks # in nanoseconds
  if difference > delay: # in nanoseconds
    bar.lastAccess[index] = newTime
    bar.show(index)

proc finish(bar: var SuruBar) =
  for index in bar:
    bar.show(index)
  echo ""

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

    `bar`.start(len(`toIterate`))

  var body = x[^1]
  # makes body a statement list to be able to add statements
  if body.kind != nnkStmtList:
    body = newTree(nnkStmtList, body)

  # in-loop printing of the progress bar
  body.add quote do:
    inc `bar`
    `bar`.update(50_000_000)

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
      `bar`.finish()

when isMainModule:
  import unittest, os, sequtils, random
  randomize()

  test "random time test":
    for a in suru(toSeq(0..<100)):
      sleep((rand(99) + 1))

  test "long time test":
    for a in suru([1, 2, 3, 5]):
      sleep(1000)

  test "alternate long time test":
    sleep 1000
    var bar: SuruBar = initSuruBar(25)

    bar.start(4)

    for a in toSeq(1..1000):
      sleep 4
      if a mod 250 == 0:
        inc bar
      bar.update(50_000_000)

    bar.finish()

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

  test "multi-bar test":
    echo "check if this line is removed by the bars"
    sleep 1000
    var bar: SuruBar = initSuruBar(25, 25)

    bar.start(1000, 40)

    for a in toSeq(1..1000):
      sleep 25
      inc bar
      if a mod 25 == 0:
        inc bar, 1
      bar.update(50_000_000)
      bar.update(50_000_000, 1)

    bar.finish()

    echo "check if this line is removed by the bars"

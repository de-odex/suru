import macros, std/monotimes, times, terminal, math, strutils, sequtils, unicode
{.experimental: "forLoopMacros".}

type
  ExpMovingAverager = distinct float
  SuruBar* = object
    length: seq[int]
    progress: seq[int]
    total: seq[int]
    barStr: seq[string]
    progressStat: seq[ExpMovingAverager]
    timeStat: seq[ExpMovingAverager]
    startTime: seq[MonoTime]
    lastIncrement: seq[MonoTime]
    currentAccess: seq[MonoTime]
    lastAccess: seq[MonoTime]
    lastProgress: seq[int]
    currentIndex: int # for usage in show(), tracks current index cursor is on relative to first progress bar

let
  fractionals = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
  prefixes = ["", "k", "M", "G", "T", "P", "E", "Z"] # Y is omitted, max is 1Y

proc incMagnitude(n: float, magnitude: int): (float, int) =
  if n > 1000:
    result = (n / 1000, magnitude + 1)
  else:
    result = (n, magnitude)

proc highestMagnitude(n: float): (float, int) =
  result = (n, 0)
  var new = incMagnitude(result[0], result[1])
  while result != new and new[1] <= prefixes.high:
    result = new
    new = incMagnitude(result[0], result[1])

proc formatUnit*(n: float): string =
  case n.classify
  of fcNan:
    return static: "??".align(6, ' ')
  of {fcNormal, fcSubnormal, fcZero, fcNegZero}:
    let (n, mag) = highestMagnitude(n)
    if n < 1_000:
      result = (n.formatFloat(ffDecimal, 2) & prefixes[mag]).align(6, ' ')
    else:
      result = static: ">1.00Y".align(6, ' ')
  of fcInf:
    result = static: ">1.00Y".align(6, ' ')
  of fcNegInf:
    result = static: "0.00".align(6, ' ')

proc formatTime(secs: SomeFloat): string =
  if secs.classify notin {fcNormal, fcSubnormal, fcZero}:
    # if time is abnormal, output ??
    result = "  ??s"
  elif secs < 0:
    # cheat bad float subtraction by clipping anything under 0 to 0
    result = " 0.0s"
  elif secs <= 100:
    # under a minute and 40 seconds, just render as seconds
    result = (secs.formatFloat(ffDecimal, 1) & "s").align(5, ' ')
  else:
    # use minute format
    let secs = secs.int
    result = ($(secs div 60)).align(2, '0') & ":" & ($(secs mod 60)).align(2, '0')

#

const alpha = exp(-1/5)

proc push(mv: var ExpMovingAverager, value: float) =
  if mv.float == 0:
    mv = value.ExpMovingAverager
  else:
    mv = (value + alpha * (mv.float - value)).ExpMovingAverager

proc push(mv: var ExpMovingAverager, value: int) =
  mv.push(value.float)

#

proc initSuruBar*(lengths: varargs[int]): SuruBar =
  ## Creates a SuruBar with the given lengths
  ## Does not prime the bar for a loop, use ``setup`` for that
  let lengths = if lengths.len == 0:
    @[25]
  else:
    @lengths
  let
    zeroes = 0.repeat(lengths.len)
    averagers = 0.ExpMovingAverager.repeat(lengths.len)
    monotimes = MonoTime().repeat(lengths.len)
  SuruBar(
    length: lengths,
    progress: zeroes,
    total: zeroes,
    barStr: lengths.mapIt(
      0.formatFloat(ffDecimal, 0).align(3, ' ') & "%|" & " ".repeat(it) & "| " & "0/0"
    ),
    progressStat: averagers,
    timeStat: averagers,
    startTime: monotimes,
    lastIncrement: monotimes,
    currentAccess: monotimes,
    lastAccess: monotimes,
    lastProgress: zeroes,
  )

proc initSuruBar*(lengthsAndAmounts: varargs[(int, int)]): SuruBar =
  initSuruBar((@lengthsAndAmounts).foldl(a & b[0].repeat(b[1]), newSeq[int]()))

proc len(bar: SuruBar): int =
  bar.length.len

iterator items(bar: SuruBar): int =
  for item in 0..<bar.length.len:
    yield item

proc inc*(bar: var SuruBar, index: int = 0) =
  ## Increments the bar progress
  inc bar.progress[index]
  let
    percentage = bar.progress[index] / bar.total[index]
    shaded = floor(percentage * bar.length[index].float).int
    fractional = (percentage * bar.length[index].float * 8).int mod 8
    unshaded = bar.length[index] - shaded - (if fractional == 0: 0 else: 1)
    totalStr = $bar.total[index]

  # TODO: improve the algorithm
  if shaded < bar.length[index]:
    bar.barStr[index] = "█".repeat(shaded) & fractionals[fractional] & " ".repeat(unshaded)
  elif shaded == bar.length[index]:
    bar.barStr[index] = "█".repeat(shaded)
  bar.barStr[index] = (percentage*100).formatFloat(ffDecimal, 0).align(3, ' ') & "%|" &
    bar.barStr[index] & "| " &
    ($bar.progress[index]).align(totalStr.len, ' ') & "/" & totalStr

  let newTime = getMonoTime()
  bar.timeStat[index].push (newTime.ticks - bar.lastIncrement[index].ticks).int div 1_000_000
  bar.lastIncrement[index] = newTime
  bar.progressStat[index].push bar.progress[index] - bar.lastProgress[index]
  bar.lastProgress[index] = bar.progress[index]

proc incAll*(bar: var SuruBar) =
  for index in bar:
    inc bar, index

proc `$`*(bar: SuruBar, index: int = 0): string =
  let
    perSec = bar.progressStat[index].float * (1000/bar.timeStat[index].float)
    timeElapsed = (bar.currentAccess[index].ticks - bar.startTime[index].ticks).float / 1_000_000_000
    timeLeft = (bar.total[index] - bar.progress[index]).float / perSec -
      ((getMonoTime().ticks - bar.lastIncrement[index].ticks).float / 1_000_000_000)

  result = bar.barStr[index] &
    " [" & timeElapsed.formatTime & "<" & timeLeft.formatTime & ", " & perSec.formatUnit & "/sec]"

  when defined(suruDebug):
    result &= " " & ((getMonoTime().ticks - bar.lastAccess[index].ticks).float/1_000_000).formatFloat(ffDecimal, 2) & "ms/frame"

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

proc reset*(bar: var SuruBar, index: int = 0, iterableLength: int) =
  ## Resets the bar to an empty bar, not including its length and total.
  let now = getMonoTime()
  bar.progress[index] = 0
  bar.total[index] = iterableLength
  bar.barStr[index] = 0.formatFloat(ffDecimal, 0).align(3, ' ') & "%|" &
    " ".repeat(bar.length[index]) & "| " & "0".align(($bar.total[index]).len, ' ') &
    "/" & ($bar.total[index])
  bar.progressStat[index] = 0.ExpMovingAverager
  bar.timeStat[index] = 0.ExpMovingAverager
  bar.startTime[index] = now
  bar.lastIncrement[index] = now
  bar.currentAccess[index] = now
  bar.lastAccess[index] = now
  bar.lastProgress[index] = 0

proc setup*(bar: var SuruBar, iterableLengths: varargs[int]) =

  # sets certain fields more properly now that the iterable length is known
  doAssert iterableLengths.len == bar.len

  for index in 1..<iterableLengths.len:
    echo ""
  if iterableLengths.len > 1:
    stdout.cursorUp(iterableLengths.len - 1)

  bar.total = @iterableLengths
  bar.barStr = zip(bar.length, bar.total).mapIt(
    0.formatFloat(ffDecimal, 0).align(3, ' ') & "%|" & " ".repeat(it[0]) & "| " &
    "0".align(($it[1]).len, ' ') & "/" & ($it[1])
  )
  bar.startTime = getMonoTime().repeat(iterableLengths.len)
  bar.currentAccess = bar.startTime
  bar.lastAccess = bar.startTime
  bar.lastIncrement = bar.startTime
  for index in 0..<iterableLengths.len:
    bar.timeStat[index].push 0
    bar.progressStat[index].push 0
    bar.show(index)

proc setup*(bar: var SuruBar, iterableLengthsAndAmounts: varargs[(int, int)]) =
  bar.setup((@iterableLengthsAndAmounts).foldl(a & b[0].repeat(b[1]), newSeq[int]()))

proc start*(bar: var SuruBar, iterableLengths: varargs[int]) {.deprecated: "Deprecated, use ``setup``".} =
  bar.setup(iterableLengths)

proc start*(bar: var SuruBar, iterableLengthsAndAmounts: varargs[(int, int)]) {.deprecated: "Deprecated, use ``setup``".} =
  bar.setup(iterableLengthsAndAmounts)

proc update*(bar: var SuruBar, delay: int, index: int = 0) =
  let
    newTime = getMonoTime()
    difference = newTime.ticks - bar.lastAccess[index].ticks # in nanoseconds
  if difference > delay: # in nanoseconds
    bar.currentAccess[index] = newTime
    bar.show(index)
    bar.lastAccess[index] = newTime

proc updateAll*(bar: var SuruBar, delay: int) =
  for index in bar:
    bar.update(delay, index)

proc finish*(bar: var SuruBar) =
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

    `bar`.setup(len(`toIterate`))

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
    for a in suru(0..<100):
      sleep((rand(99) + 1))

  test "long time test":
    for a in suru([1, 2, 3, 5]):
      sleep(1000)

  test "alternate long time test":
    var bar: SuruBar = initSuruBar(25)
    bar.setup(4)
    for a in 1..1000:
      sleep 5
      if a mod 250 == 0:
        inc bar
      bar.update(50_000_000)
    bar.finish()

  test "constant time test":
    for a in suru(0..<100):
      sleep(25)

  test "v-shaped time test":
    for a in suru(toSeq(1..100) & toSeq(countdown(100, 1))):
      sleep(a)

  test "increasing time test":
    for a in suru(1..100):
      sleep(a)

  test "sinusoidal time test":
    for a in suru(1..100):
      sleep(int(sin(a.float / 5) * 50 + 50))

  test "multi-bar test":
    echo "check if this line is removed by the bars"
    sleep 1000
    var bar: SuruBar = initSuruBar(25, 25)
    bar.setup(1000, 40)
    for a in 1..1000:
      sleep 25
      inc bar
      if a mod 25 == 0:
        inc bar, 1
      bar.update(50_000_000)
      bar.update(50_000_000, 1)
    bar.finish()
    echo "check if this line is removed by the bars"

  test "iterative bar test":
    var bar: SuruBar = initSuruBar(25, 25)
    bar.setup(10, 100)
    for a in 1..10:
      bar.reset(1, a*10)
      for b in 1..a*10:
        sleep 25
        inc bar, 1
        bar.update(50_000_000)
        bar.update(50_000_000, 1)
      inc bar
    bar.finish()

  test "frame time test": # use -d:suruDebug to see frame time
    var bar: SuruBar = initSuruBar(25)
    bar.setup(10_000_000)
    for a in 1..10_000_000:
      # sleep 1
      inc bar
      bar.update(1_000)
    bar.finish()

  test "multi-bar frame time test":
    var bar: SuruBar = initSuruBar((25, 30))
    bar.setup((10_000, 30))
    for a in 1..10_000:
      # sleep 1
      incAll bar
      bar.updateAll(1_000)
    bar.finish()

import std/[
  macros,
  math,
  monotimes,
  sequtils,
  strutils,
  terminal,
  times,
  unicode,
]
when compileOption("threads"):
  import std/os

{.experimental: "forLoopMacros".}

type
  ExpMovingAverager = distinct float
  SingleSuruBar* = object
    length*: int
    progress: int
    total*: int                     # total amount of progresses
    progressStat: ExpMovingAverager # moving average of increments to progresses
    timeStat: ExpMovingAverager     # moving average of time difference between progresses
    startTime: MonoTime             # start time of bar
    lastChange: MonoTime            # last time bar was changed, used for timeStat
    currentAccess: MonoTime
    lastAccess: MonoTime
    format: proc(ssb: SingleSuruBar): string {.gcsafe.}
  SuruBar* = object
    bars: seq[SingleSuruBar]
    currentIndex: int # for usage in show(), tracks current index cursor is on relative to first progress bar
when compileOption("threads"):
  type
    SuruBarController* = object # new object to still allow non-threaded SuruBars when threads:on
      bar: SuruBar
      finished: bool
      progressThread: Thread[ptr SuruBarController]

# exponential moving averager

const alpha = exp(-1/5)

proc push(mv: var ExpMovingAverager, value: SomeNumber) =
  let value = value.float
  if mv.float == 0:
    mv = value.ExpMovingAverager
  else:
    mv = (value + alpha * (mv.float - value)).ExpMovingAverager

# getters and format generators

proc progress*(ssb: SingleSuruBar): int = ssb.progress
proc perSecond*(ssb: SingleSuruBar): float =
  ssb.progressStat.float * (1_000_000_000 / ssb.timeStat.float)
proc elapsed*(ssb: SingleSuruBar): float =
  (ssb.currentAccess.ticks - ssb.startTime.ticks).float / 1_000_000_000
proc eta*(ssb: SingleSuruBar): float =
  (ssb.total - ssb.progress).float / ssb.perSecond - ((ssb.currentAccess.ticks - ssb.lastChange.ticks).float / 1_000_000_000)
proc percent*(ssb: SingleSuruBar): float = ssb.progress / ssb.total

proc `progress=`*(ssb: var SingleSuruBar, progress: int) =
  let lastProgress = ssb.progress
  ssb.progress = progress
  let newTime = getMonoTime()
  ssb.timeStat.push (newTime.ticks - ssb.lastChange.ticks).int
  ssb.lastChange = newTime
  ssb.progressStat.push ssb.progress - lastProgress

proc `format=`*(ssb: var SingleSuruBar, format: proc(ssb: SingleSuruBar): string {.gcsafe.}) =
  ssb.format = format

import ./suru/fractional_bar

# single suru bar

proc initSingleSuruBar*(length: int): SingleSuruBar =
  SingleSuruBar(
    length: length,
    format: format,
  )

proc inc*(ssb: var SingleSuruBar, y: Natural = 1) =
  ## Increments the bar progress
  ssb.`progress=`(ssb.progress + y)

proc `$`(ssb: SingleSuruBar): string =
  result = ssb.format(ssb)

proc show(ssb: var SingleSuruBar) =
  ## Shows the bar in a formatted style.
  when defined(windows):
    stdout.eraseLine()
    stdout.write($ssb)
  else:
    stdout.write("\e[2K", $ssb)
  stdout.flushFile()
  stdout.setCursorXPos(0)

proc reset*(ssb: var SingleSuruBar) =
  ## Resets the bar to an empty bar, not including its length and total.
  let now = getMonoTime()
  ssb.progress = 0
  ssb.progressStat = 0.ExpMovingAverager
  ssb.timeStat = 0.ExpMovingAverager
  ssb.startTime = now
  ssb.lastChange = now
  ssb.currentAccess = now
  ssb.lastAccess = now

# suru bar

iterator items*(sb: SuruBar): SingleSuruBar =
  for bar in sb.bars:
    yield bar

iterator mitems*(sb: var SuruBar): var SingleSuruBar =
  var index: int
  while index < sb.bars.len:
    yield sb.bars[index]
    inc(index)

iterator pairs*(sb: SuruBar): (int, SingleSuruBar) =
  var index: int
  while index < sb.bars.len:
    yield (index, sb.bars[index])
    inc(index)

iterator mpairs*(sb: var SuruBar): (int, var SingleSuruBar) =
  var index: int
  while index < sb.bars.len:
    yield (index, sb.bars[index])
    inc(index)

proc `[]`*(sb: SuruBar, index: Natural): SingleSuruBar =
  sb.bars[index]

proc `[]`*(sb: var SuruBar, index: Natural): var SingleSuruBar =
  sb.bars[index]

proc inc*(sb: var SuruBar, y: Natural = 1) =
  ## Increments the bar progress
  for bar in sb.mitems:
    inc bar, y

proc moveCursor(sb: var SuruBar, index: int = 0) =
  let difference = index - sb.currentIndex
  if difference < 0:
    stdout.cursorUp(abs(difference))
  elif difference > 0:
    stdout.cursorDown(abs(difference))
  sb.currentIndex = index

proc `format=`*(sb: var SuruBar, format: proc(ssb: SingleSuruBar): string {.gcsafe.}) =
  for bar in sb.mitems:
    bar.format = format

proc initSuruBar*(bars: int = 1): SuruBar =
  ## Creates a SuruBar with the given amount of bars
  ## Does not prime the bar for a loop, use ``setup`` for that
  SuruBar(
    bars: initSingleSuruBar(25).repeat(bars),
  )

proc setup*(sb: var SuruBar) =
  ## Sets up stdout and the time fields for running
  ## Call this immediately before your loop

  stdout.write("\n".repeat(sb.bars.high))
  if sb.bars.high > 0:
    stdout.cursorUp(sb.bars.high)

  for index, bar in sb.mpairs:
    bar.startTime = getMonoTime()
    bar.currentAccess = bar.startTime
    bar.lastAccess = bar.startTime
    bar.lastChange = bar.startTime
    sb.moveCursor(index)
    bar.show()

proc update*(sb: var SuruBar, delay: int = 8_000_000, index: int = -1) =
  template update {.dirty.} =
    let
      difference = newTime.ticks - sb[index].lastAccess.ticks # in nanoseconds
    if difference > max(delay, 1_000_000): # in nanoseconds
      sb[index].currentAccess = newTime
      sb.moveCursor(index)
      sb[index].show()
      sb[index].lastAccess = newTime
  let
    newTime = getMonoTime()
  if index < 0:
    for index, _ in sb:
      update()
  else:
    update()

proc finish*(sb: var SuruBar) =
  for index, _ in sb:
    sb.moveCursor(index)
    sb[index].show()
  echo ""

#

when compileOption("threads"):
  # TODO: fix code duplication
  iterator items*(sbc: ptr SuruBarController): SingleSuruBar =
    for bar in sbc[].bar.bars:
      yield bar

  iterator mitems*(sbc: ptr SuruBarController): var SingleSuruBar =
    var index: int
    while index < sbc[].bar.bars.len:
      yield sbc[].bar.bars[index]
      inc(index)

  iterator pairs*(sbc: ptr SuruBarController): (int, SingleSuruBar) =
    var index: int
    while index < sbc[].bar.bars.len:
      yield (index, sbc[].bar.bars[index])
      inc(index)

  proc `[]`*(sbc: ptr SuruBarController, index: Natural): var SingleSuruBar =
    sbc[].bar.bars[index]

  proc inc*(sbc: ptr SuruBarController, y: Natural = 1) =
    ## Increments the bar progress
    for bar in sbc[].bar.mitems:
      inc bar, y

  proc moveCursor(sbc: ptr SuruBarController, index: int = 0) =
    let difference = index - sbc[].bar.currentIndex
    if difference < 0:
      stdout.cursorUp(abs(difference))
    elif difference > 0:
      stdout.cursorDown(abs(difference))
    sbc[].bar.currentIndex = index

  proc `format=`*(sbc: ptr SuruBarController, format: proc(ssb: SingleSuruBar): string {.gcsafe.}) =
    for bar in sbc.mitems:
      bar.format = format

  proc initSuruBarThreaded*(bars: int = 1): ptr SuruBarController =
    ## Creates a SuruBar with the given amount of bars
    ## Does not prime the bar for a loop, use ``setup`` for that
    result = createShared(SuruBarController)
    result[] = SuruBarController(
      bar: SuruBar(bars: initSingleSuruBar(25).repeat(bars)),
    )

  proc setup*(sbc: ptr SuruBarController, iterableLengths: varargs[int]) =
    sbc[].bar.setup()

    proc progressThread(sbc: ptr SuruBarController) {.thread.} =
      while not sbc.finished:
        sleep 50
        sbc[].bar.update()
      # finished now
      sbc[].bar.finish()

    createThread(sbc[].progressThread, progressThread, sbc)

  template update*(sbc: ptr SuruBarController, delay: int = 0, index: int = 0) =
    discard

  proc finish*(sbc: ptr SuruBarController) =
    sbc[].finished = true
    joinThread(sbc[].progressThread)
    freeShared(sbc)
else:
  proc initSuruBarThreaded*(bars: int = 1): SuruBar =
    ## Creates a SuruBar with the given amount of bars
    ## Does not prime the bar for a loop, use ``setup`` for that
    {.hint: "threads is not on, using non-threaded version".}
    initSuruBar(bars)

#

template len(x: typedesc[array]): int =
  system.len(x)

template len[N, T](x: array[N, T]): int =
  system.len(x)

template len(arg: untyped): int =
  0

macro suru*(forLoop: ForLoopStmt): untyped =
  ## Wraps an iterable for printing a progress bar
  expectKind forLoop, nnkForStmt

  let
    toIterate = forLoop[^2][1] # the "x" in "for i in x"

  var
    preLoop = newStmtList()
    body = forLoop[^1]
    newFor = newTree(nnkForStmt)
    postLoop = newStmtList()

  var
    bar = genSym(nskVar, "bar")
    barSet: bool
    delayVal = quote do: 50_000_000
    threaded: bool
    formatVal: NimNode
    totalVal: NimNode

  # handle settings
  if forLoop[^2].len > 2:
    let settings = forLoop[^2][2..^1]
    for setting in settings:
      setting.expectKind(nnkExprEqExpr)
      setting[0].expectKind(nnkIdent)

      # threaded
      # ? format: not really needed if barIdent...
      # barIdent: for manual incrementing
      #   will not disable update call, only the increment call
      # delay
      # ? total: not needed if barIdent...

      if setting[0].eqIdent "threaded":
        setting[1].expectKind(nnkIdent)
        if setting[1].eqIdent "true":
          threaded = true
        elif setting[1].eqIdent "true":
          discard
        else:
          error("invalid value for setting value (bool expected): " & $setting[1], setting[1])
      elif setting[0].eqIdent "format":
        formatVal = setting[1]
      elif setting[0].eqIdent "total":
        totalVal = setting[1]
      elif setting[0].eqIdent "barIdent":
        setting[1].expectKind(nnkIdent)
        bar = setting[1]
      elif setting[0].eqIdent "delay":
        delayVal = setting[1]
      else:
        error("invalid value for setting: " & $setting[0], setting)

  # first printing of the progress bar
  if threaded:
    preLoop.add quote do:
      var
        `bar` = initSuruBarThreaded()
  else:
    preLoop.add quote do:
      var
        `bar` = initSuruBar()

  if not formatVal.isNil:
    preLoop.add quote do:
      `bar`.format = `formatVal`

  if not totalVal.isNil:
    preLoop.add quote do:
      `bar`[0].total = `totalVal`
  else:
    preLoop.add quote do:
      when compiles(len(`toIterate`)):
        `bar`[0].total = `toIterate`.len
      else:
        `bar`[0].total = 0
  preLoop.add quote do:
    `bar`.setup()

  # makes body a statement list to be able to add statements
  if body.kind != nnkStmtList:
    body = newTree(nnkStmtList, body)

  # in-loop printing of the progress bar
  body.add quote do:
    inc `bar`
    `bar`.update(`delayVal`)

  # re-adds the variables into the new for statement
  for i in 0..<forLoop.len-2:
    newFor.add forLoop[i]

  # transforms suru(...) to '...'
  newFor.add toIterate
  newFor.add body

  postLoop.add quote do:
    `bar`.finish()

  # wraps the whole macro in a block to create a new scope
  # also includes final print of the bar
  result = quote do:
    block:
      `preLoop`
      `newFor`
      `postLoop`


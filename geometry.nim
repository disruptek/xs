import nre
import asyncdispatch
import asyncfutures
import strformat
import options
import strutils
import logging

import cligen
import i3ipc

type
  Geometry* = tuple[w: int; h: int; x: Option[int]; y: Option[int]]

proc parseGeometry(geometry: string): Option[Geometry] =
  ## parse a geometry string like 640x480+20-30
  let geo = geometry.match(re"(\d+)x(\d+)(?:([\+\-])?(\d+)?)(?:([\+\-])?(\d+)?)")
  if not geo.isSome:
    return
  let
    cap = geo.get.captures.toSeq
    width = cap[0].get.parseInt
    height = cap[1].get.parseInt
  var x, y: Option[int]
  if cap[3].isSome:
    x = some(cap[3].get.parseInt)
    if cap[2].get == "-": x = some(x.get * -1)
  if cap[5].isSome:
    y = some(cap[5].get.parseInt)
    if cap[4].get == "-": y = some(y.get * -1)

  result = some((w: width, h: height, x: x, y: y))

proc positionWindowsMatching*(geo: Geometry; regexps: seq[Regex]):
  Option[RunCommandReply] =
  let
    compositor = waitfor newCompositor()
    receipt = compositor.invoke(GetTree)

  for regexp in regexps:
    for window in everyClient(receipt.tree):
      if window.`type` != "floating_con":
        continue
      if not window.name.contains(regexp):
        continue
      var command = &"[con_id={window.id}] " &
        &"resize set width {geo.w} px height {geo.h} px"
      if geo.x.isSome:
        command &= &", move absolute position {geo.x.get} px {geo.y.get(0)} px"
      var reply = compositor.invoke(RunCommand, command)
      for n in reply.ran:
        if not n.success:
          return some(n)

proc geometry(geometry: string; patterns: seq[string]) =
  ## position to given geometry any windows whose names match regexp patterns
  let parsed = geometry.parseGeometry
  if not parsed.isSome:
    quit "unable to parse geometry; try eg. 640x480+20-50"
  let
    geo = parsed.get

  var regexps: seq[Regex]
  for pattern in patterns:
    regexps.add re(pattern)

  let response = positionWindowsMatching(geo, regexps)
  if response.isSome:
    echo response.get.error
    echo response.get.parse_error
    quit(1)

when isMainModule:
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  dispatch geometry

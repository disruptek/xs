#? replace(sub = "\t", by = " ")
##
##
## a thing that monitors when windows are focussed and
## sets their opacity accordingly
##
##
import os
import json
import strutils
import cligen
import strformat
import logging

import i3ipc
import jsonconvert

type
  Pid = int
  ProcessDetails = tuple[exe: string, ppid: Pid]

proc findProcessDetails(pid: Pid): ProcessDetails =
  ## given a pid, get the process name and parent pid
  try:
    let
      str = readFile("/proc" / $pid / "stat")
      pids = str.split(' ')
      mom = pids[3].parseInt
      exe = pids[1][1..^2]
    return (exe: exe, ppid: mom)
  except IOError as e:
    warn repr(e)
  except OSError as e:
    warn repr(e)
  result = (exe: "", ppid: 0)

proc isChildOf(pid: Pid; parent: Pid): bool =
  ## finally, a suitable answer to the age-old question,
  ## "is this pid a child process of that parent pid?"
  if pid == parent:
    return true
  if pid <= 1:
    return false
  let cap = pid.findProcessDetails
  result = cap.ppid.isChildOf(parent)

proc findParentNamed(child: Pid; name: string): Pid =
  ## discover latest ancestor given a child pid and
  ## parent process name; 0 in the absence of same
  if child <= 1:
    return 0
  let cap = child.findProcessDetails
  if cap.exe == name:
    return child
  result = cap.ppid.findParentNamed(name)

proc setOpacity(comp: Compositor; app: int; to=1.0) =
  ## send a new opacity value to the compositor
  if app == 0:
    return
  discard waitFor RunCommand.send(comp, &"[con_id={app}] opacity {to:1.2f}")
  #discard waitFor RunCommand.send(comp, &"opacity {to:1.2f}")

proc findActiveWindowId(js: JsonNode): int {.deprecated.} =
  ## given an event, try to get active window id
  while true:
    if "change" notin js:
      break
    if js["change"].getStr != "focus":
      break
    if "container" notin js:
      break
    let c = js["container"]
    if "id" notin c:
      break
    return c["id"].getInt
  return 0

iterator windowChanges(compositor: Compositor): WindowEvent =
  ## yield window events
  discard waitFor Subscribe.send(compositor, "[\"window\"]")

  while true:
    let receipt = waitFor compositor.recv()
    if receipt.kind != EventReceipt:
      continue
    if receipt.event.kind != Window:
      continue
    yield receipt.event.window

iterator floatingWindows(js: JsonNode): JsonNode {.deprecated.} =
  if "floating_nodes" in js:
    var floaters = js["floating_nodes"]
    assert floaters.kind == JArray
    for j in floaters.elems:
      yield j

proc hasFloatingWindows(js: JsonNode): bool {.deprecated.} =
  result = false
  for j in js.floatingWindows:
    return true

iterator walkWindows(js: JsonNode): JsonNode {.deprecated.} =
  if js != nil:
    if js.hasFloatingWindows:
      for floater in js.floatingWindows:
        yield floater
    else:
      yield js

iterator walkWindows(container: TreeResult): TreeResult =
  if container != nil:
    if container.floatingNodes.len > 0:
      for floater in container.floatingNodes:
        yield floater
    else:
      yield container

proc isTerminal(js: JsonNode): bool {.deprecated.} =
  const terminals = ["kitty", "Alacritty"]
  for window in js.walkWindows:
    if window.get("app_id", "") in terminals:
      return true

proc isTerminal(container: TreeResult): bool =
  const terminals = ["kitty", "Alacritty"]
  for window in container.walkWindows:
    if window.appId in terminals:
      return true

proc isIrc(js: JsonNode): bool {.deprecated.} =
  for window in js.walkWindows:
    if window.get("name", "") == "irc":
      return true

proc isIrc(container: TreeResult): bool =
  for window in container.walkWindows:
    if window.name == "irc":
      return true

proc autoOpacity(active=1.0; inactive=0.75, fgcolor="", bgcolor="") =
  ## set opacity on active|inactive windows

  var
    now, was = 0
    compositor = waitFor newCompositor()

  for event in compositor.windowChanges():
    if event.change != "focus":
      continue
    now = event.container.id
    if now == 0:
      continue
    if now == was:
      continue
    compositor.setOpacity(now, active)
    compositor.setOpacity(was, inactive)
    if event.container.isIrc:
      was = 0
    elif event.container.isTerminal:
      was = now
    else:
      was = 0

when isMainModule:
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  dispatch autoOpacity

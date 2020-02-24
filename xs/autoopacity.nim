##
##
## a thing that monitors when windows are focussed and
## sets their opacity accordingly
##
##
import os
import strutils
import cligen
import strformat
import logging

import swayipc

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

proc isTerminal(container: TreeReply): bool =
  const terminals = ["kitty", "Alacritty"]
  for window in container.clientWalk:
    if window.appId in terminals:
      return true

proc isIrc(container: TreeReply): bool =
  for window in container.clientWalk:
    result = window.app_id == "irc"
    if result:
      break

proc isFloating(container: TreeReply): bool =
  for window in container.clientWalk:
    result = window.`type` == "floating_con"
    if result:
      break

proc autoOpacity(active=1.0; inactive=0.75; floating=0.30;
                 fgcolor=""; bgcolor="") =
  ## set opacity on active|inactive windows

  var
    now, was = 0
    wasfloats = false
    nowfloats = false
    compositor = waitFor newCompositor()

  for event in compositor.windowChanges():
    if event.change != "focus":
      continue
    nowfloats = event.container.isFloating
    now = event.container.id
    if now == 0:
      continue
    if now == was:
      continue
    compositor.setOpacity(now, active)
    if wasfloats and not event.container.isIrc:
      compositor.setOpacity(was, floating)
    else:
      compositor.setOpacity(was, inactive)
    if event.container.isIrc:
      was = now
    elif event.container.isTerminal:
      was = now
    elif nowfloats:
      was = now
    else:
      was = 0
    wasfloats = nowfloats

when isMainModule:
  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  dispatch autoOpacity

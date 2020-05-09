import std/strutils
import std/os
import std/strformat
import std/asyncdispatch
import std/logging

import swayipc
import pulseauto except `()`
import cutelog

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

when isMainModule:
  let
    logger = newCuteConsoleLogger()
  addHandler(logger)
  let
    compositor = waitfor newCompositor()
    reply = waitfor compositor.invoke(GetTree, @[])

  for client in reply.tree.everyClient:
    if client.focused:
      debug "focus: ", client.name
      debug "pid: ", client.pid
      let
        details = findProcessDetails(client.pid)
      debug "exe: ", details.exe
      pulseauto("25%", client = &"^{details.exe}$",
                property = "application\\.process\\.binary")

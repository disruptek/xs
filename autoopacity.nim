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

proc findActiveWindowId(js: JsonNode): int =
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
		#[
		let wp = c{"window_properties"}
		if wp == nil:
			break
		if wp["class"].getStr.endsWith("chromium"):
			if not c["sticky"].getBool(false):
				return 0
			if not wp["title"].getStr.startsWith("Watch Live PD"):
				return 0
		]#
		return c["id"].getInt
	return 0

iterator windowChanges(compositor: Compositor): Receipt =
	let
		payload = "[\"window\"]"
	var
		receipt: Receipt

	discard waitFor Subscribe.send(compositor, payload)

	while true:
		receipt = waitFor compositor.recv()
		if receipt.kind != EventReceipt:
			continue
		if receipt.ekind != Window:
			yield receipt
			break
		case receipt.kind:
		of MessageReceipt:
			if not receipt.toJson["success"].getBool:
				yield receipt
				break
		of EventReceipt:
			yield receipt

iterator floatingWindows(js: JsonNode): JsonNode =
	if "floating_nodes" in js:
		var floaters = js["floating_nodes"]
		assert floaters.kind == JArray
		for j in floaters.elems:
			yield j

proc hasFloatingWindows(js: JsonNode): bool =
	result = false
	for j in js.floatingWindows:
		return true

proc isKitty(js: JsonNode): bool =
	result = false
	if js.hasFloatingWindows:
		for floater in js.floatingWindows:
			if floater.isKitty:
				return true
	else:
		result = js["app_id"].getStr == "kitty"

proc autoOpacity(active=1.0; inactive=0.5, fgcolor="", bgcolor="") =
	## set opacity on active|inactive windows

	var
		now, was = 0
		compositor = waitFor newCompositor()

	for js in compositor.windowChanges():
		now = js.findActiveWindowId()
		if now == 0:
			continue
		if now == was:
			continue
		if "container" notin js:
			continue
		compositor.setOpacity(now, active)
		compositor.setOpacity(was, inactive)
		if js["container"].isKitty:
			was = now
		else:
			was = 0

if isMainModule:
	when defined(release):
		let level = lvlWarn
	else:
		let level = lvlAll
	let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
	addHandler(logger)

	dispatch autoOpacity

#? replace(sub = "\t", by = " ")
##
##
## a thing that monitors when kitty windows are focussed and
## sets the background opacity accordingly
##
##
## pass i3 or sway compositor event monitor output on stdin thusly:
##
## $ swaymsg --type SUBSCRIBE --monitor '["window"]' | <this tool> 0.95 0.4
##
## ...to set opacity to 95% when active and 40% when inactive.
##
##
import os
import osproc
import streams
import json
import strutils
import net
import cligen
import colors

type
	Pid = int
	ProcessDetails = tuple[exe: string, ppid: Pid]
	State = enum None, Active, Inactive
	Form = enum Many="N", One="1"

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
		echo repr(e)
	except OSError as e:
		echo repr(e)
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

proc findSocketAddress(pid: Pid): string =
	## discover unix socket path where given kitty pid is listening
	try:
		let
			str = readFile("/proc" / $pid / "cmdline")
			args = str.split('\0')
		for i, a in args.pairs:
			if a == "--listen-on":
				return args[i+1]["unix:".len..^1]
	except IOError as e:
		echo repr(e)
	except OSError as e:
		echo repr(e)
	result = ""

proc runKittyToSetOpacityAtAddress(addy: string; to=1.0): int =
	## run kitty to pass remote control commands?  silly.
	let
		# too lazy to lookup the actual source binary
		exe = "/usr/bin/kitty"
		arguments = @["@", "--to", "unix:" & addy, "set-background-opacity", $to]
	var process = exe.startProcess(args=arguments)
	result = process.waitForExit()

proc runKittyToSetColorAtAddress(addy: string; to: string): int =
	## run kitty to pass remote control commands?  silly.
	let
		# too lazy to lookup the actual source binary
		exe = "/usr/bin/kitty"
		arguments = @["@", "--to", "unix:" & addy, "set-colors", "background=" & $to]
	var process = exe.startProcess(args=arguments)
	result = process.waitForExit()

converter toJSON(c: Color): JsonNode =
	return newJInt(cast[int](c))

proc sendCommandToKitty(addy: string; js: JsonNode) =
	## send a remote control command to kitty
	let data = "\x1bP@kitty-cmd" & $js & "\x1b\\"
	var sock = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
	sock.connectUnix(addy)
	sock.send(data)
	sock.close()

proc setColorAtAddress(addy: string; to=""; opacity=1.0) =
	## send a new background value to the given address.
	## (does not currently apply opacity argument)
	if to == "":
		return

	let
		js = %* {
			"cmd": "set-colors",
			"version": [0, 14, 2],
			"no_response": true,
			"payload": {
				"title": "background=" & to,
				"match_window": nil,
				"match_tab": nil,
				"all": false,
				"configured": false,
				"reset": false,
				"cursor_text_color": false,
				"colors": {
					"background": to.parseColor,
				},
			},
		}
	try:
		addy.sendCommandToKitty(js)
	except OSError:  # zoom! we're racing, baby!
		echo runKittyToSetColorAtAddress(addy, to=to)

proc setOpacityAtAddress(addy: string; to=1.0) =
	## send a new opacity value to the given address.
	let js = %* {
		"cmd": "set-background-opacity",
		"version": [0, 14, 2],
		"no_response": true,
		"payload": {
			"match_window": nil,
			"all": false,
			"opacity": to.newJFloat,
		},
	}
	try:
		addy.sendCommandToKitty(js)
	except OSError:  # zoom! we're racing, baby!
		echo runKittyToSetOpacityAtAddress(addy, to=to)

proc findActiveWindow(js: JsonNode; kitties=false): Pid =
	## given an event, try to get active window pid;
	## kitties=true if you only want kitty processes
	while true:
		if "change" notin js:
			break
		if "container" notin js:
			break
		let c = js["container"]
		if "app_id" notin c:
			break
		if "pid" notin c:
			break
		if js["change"].getStr != "focus":
			break
		if kitties and c["app_id"].getStr != "kitty":
			break
		return c["pid"].getInt
	return 0

template eventsFromStream(stream: FileStream; js: JsonNode; code: untyped) =
	## yield event messages from the stream as json objects
	var
		line, msg: string
		dirty = true

	while true:
		try:
			line = stream.readLine()
		except:
			break
		msg &= line
		try:
			js = msg.parseJson()
			msg = ""
			code
		except JsonParsingError as e:
			echo repr(e)
			continue
		if stream.atEnd():
			break

iterator activePids(stream: FileStream): Pid =
	## yields the pid of currently active window when it changes
	var js: JsonNode
	stream.eventsFromStream(js):
		var pid = js.findActiveWindow(kitties=false)
		if pid == 0:
			continue
		yield pid

proc readEventType(js: JsonNode): State =
	## given a json object, try to determine window state
	let
		pid = getCurrentProcessId()
		active = js.findActiveWindow(kitties=true)
	if active == 0:
		return None
	return if pid.isChildOf(active):
		Active
	else:
		Inactive

iterator stateChanges(stream: FileStream): State =
	## yield state changes (and only changes) as they occur
	var
		js: JsonNode
		dirty = true
	stream.eventsFromStream(js):
		case js.readEventType():
			of None:
				discard
			of Inactive:
				if dirty:
					dirty = false
					yield Inactive
			of Active:
				dirty = true
				yield Active

proc setOpacity(kitty: Pid; to=1.0; color="") =
	if kitty == 0:
		return

	let cap = kitty.findProcessDetails()
	if cap.exe != "kitty":
		return

	let addy = kitty.findSocketAddress()
	if addy == "":
		return

	setOpacityAtAddress(addy, to=to)

proc setColor(kitty: Pid; color: string; opacity=1.0) =
	if kitty == 0:
		return

	let cap = kitty.findProcessDetails()
	if cap.exe != "kitty":
		return

	let addy = kitty.findSocketAddress()
	if addy == "":
		return

	setColorAtAddress(addy, to=color, opacity=opacity)

proc autoBackground(form: Form; active=1.0; inactive=0.8, fgcolor="", bgcolor="") =
	## set background opacity on active|inactive kitty windows
	var stream = newFileStream(stdin)

	case form:
		of One:
			var was = 0
			for now in stream.activePids():
				if now == was:
					continue
				was.setColor(bgcolor, opacity=inactive)
				was.setOpacity(inactive)
				now.setColor(fgcolor, opacity=active)
				now.setOpacity(active)
				was = now
		of Many:
			let
				pid = getCurrentProcessId()
				kitty = pid.findParentNamed("kitty")
				addy = kitty.findSocketAddress()
			if 0 == kitty:
				echo "no kitty parent"
				quit(1)

			if "" == addy:
				echo "not listening on a socket"
				quit(1)

			var
				alpha: float
				color: string
			for change in stream.stateChanges():
				(alpha, color) = case change:
					of Active: (active, fgcolor)
					of Inactive: (inactive, bgcolor)
					else: raise newException(Defect, "how very inappropriate!")
				setColorAtAddress(addy, to=color, opacity=alpha)
				setOpacityAtAddress(addy, to=alpha)

if isMainModule:
	dispatch autoBackground

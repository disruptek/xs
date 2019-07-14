#? replace(sub = "\t", by = " ")
import os
import irc
import cligen
import asyncdispatch
import asyncfutures
import times
import notify
import dbus
import tables
import strformat
import logging

const DEFAULT_NICK = "disruptek"
const DEFAULT_NAME = "Andy Davidoff"
const DEFAULT_HOST = "irc.chat.twitch.tv"
const DEFAULT_PORT = 6667
#const DEFAULT_CHAN = @["#" & DEFAULT_NICK]
const DEFAULT_CHAN = @[]

type
	Replaces = uint32
	NotifyIcon = enum NoIcon = "",
		ChatIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f5e8.png", # 🗨️
		EjectIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23cf.png", # ⏏️ 
		PlayIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u25b6.png", # ▶️
		StopIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23f9.png", # ⏹️
		ShuffleIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f500.png", # 🔀
		RepeatIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f501.png", # 🔁
		RecordIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23fa.png", # ⏺️
		JoinedIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23fa.png", # ⏺️
		PauseIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23f8.png", # ⏸️
		PartedIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u23f8.png", # ⏸️
		QuitIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u26d4.png", # ⛔
		OtherIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u2753.png", # ❓
		QuestionIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u2754.png", # ❔
		StatementIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f4ac.png", # 💬
		ThoughtIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f4ad.png", # 💭
		AngerIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f5ef.png", # 🗯️
		SpeechIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f4ac.png", # 💬
		LoudIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f4e2.png", # 📢
		TalkIcon = "/usr/share/icons/noto-emoji/128x128/emotes/emoji_u1f5e3.png", # 🗣️
	NotifyProc = proc (mtype: IrcMType; nick: string; text: string; channel: string; icon: NotifyIcon = OtherIcon): Replaces

#[

INT32 org.freedesktop.Notifications.Notify (	app_name,	 
 	replaces_id,	 
 	app_icon,	 
 	summary,	 
 	body,	 
 	actions,	 
 	hints,	 
 	expire_timeout);	 
STRING app_name;
UINT32 replaces_id;
STRING app_icon;
STRING summary;
STRING body;
ARRAY actions;
DICT hints;
INT32 expire_timeout;

]#

proc sendNotify[T](app_name: string; replaces_id: Replaces=0; app_icon=""; summary=""; body=""; actions: seq[string]= @[]; hints: Table[string, Variant[T]]; expire_timeout: int32 = 0): Replaces =
	## send a dbus message for notification purposes
	
	# this is straight outta solitudesf's example in dbus
	let bus = getBus(DBUS_BUS_SESSION)
	var msg = makeCall("org.freedesktop.Notifications",
		ObjectPath("/org/freedesktop/Notifications"),
		"org.freedesktop.Notifications",
		"Notify")

	msg.append(app_name)
	msg.append(replaces_id)
	msg.append(app_icon)
	msg.append(summary)
	msg.append(body)
	msg.append(actions)
	msg.append(hints)
	msg.append(expire_timeout)

	let
		pending = bus.sendMessageWithReply(msg)
		reply = pending.waitForReply()
	var
		iter = reply.iterate()
		value = iter.unpackCurrent(DbusValue)
	result = value.asNative(Replaces)
	#[
	try:
		iter.advanceIter
	except:
		break
	]#

proc processEvent(irc: AsyncIrc; event: IrcEvent; notice: NotifyProc) {.async.} =
	## the client runs this callback whenever an event comes in;
	## eg. a chat event, a server event, a channel event, etc.
	var
		chan, text: string
	case event.typ:
		of EvDisconnected:
			warn "disconnected; reconnecting..."
			discard irc.reconnect()
		of EvMsg:
			case event.cmd:
				of MPrivMsg:
					(chan, text) = (event.params[0], event.params[1])
					discard event.cmd.notice(event.nick, text, chan, icon=ChatIcon)
					info event.nick, "@", chan, ": ", text
				of MQuit:
					discard event.cmd.notice(event.nick, "«quit»", "", icon=QuitIcon)
					info event.nick, " quit"
				of MPart:
					chan = event.params[0]
					discard event.cmd.notice(event.nick, event.nick & "«part» " & chan, chan, icon=PartedIcon)
					info event.nick, " left " & chan
				of MJoin:
					chan = event.params[0]
					discard event.cmd.notice(event.nick, "«join» " & chan, chan, icon=JoinedIcon)
					info event.nick, " joined " & chan
				of MPong:
					#debug "pong"
					discard
				of MPing:
					#debug "ping"
					discard
				else:
					text = event.params[0]
					if event.nick != "":
						discard event.cmd.notice(event.nick, &"«{event.cmd}» " & text, text)
						debug event
		of EvConnected:
			warn "connected."
			discard
		else:
			debug event
			discard

proc bot(nick=DEFAULT_NICK;
	host=DEFAULT_HOST;
	port=DEFAULT_PORT;
	name=DEFAULT_NAME;
	pass="";
	notify="twitch";
	channels: seq[string]=DEFAULT_CHAN) =
	## this exists to define the cli arg parser;
	## it also runs our main irc loop

	let
		pass = os.getEnv("BOT_OAUTH", "")
		pno = Port(port)

	var irc: AsyncIrc

	if pass == "" and host == DEFAULT_HOST:
		error "need a password or BOT_OAUTH variable in your env"
		quit(1)

	var
		replace: Replaces = 0
		body: string
		who: string
		cmd: IrcMType

	proc notice(mtype: IrcMType; nick: string; text: string; channel: string; icon=OtherIcon): Replaces =
		let hints = {"urgency": newVariant(1'u8)}.toTable
		if nick == who and nick != "" and cmd == mtype:
			#body = was & "⏎\n" & text
			body &= "\n" & text
		else:
			body = text
			replace = 0
			cmd = mtype
			who = nick

		replace = sendNotify(notify, replaces_id=replace, app_icon= $icon,
			summary=nick, body=body, actions= @[], hints=hints,
			expire_timeout=300_000)
		result = replace

	proc eventHandler(irc: AsyncIrc; event: IrcEvent) {.async.} =
		waitfor processEvent(irc, event, notice)

	irc = newAsyncIrc(address=host, port=pno, nick=nick, user=nick,
		realname=name, serverPass=pass, joinChans=channels,
		callback=eventHandler)
	waitfor irc.run()

if isMainModule:
	let logger = newConsoleLogger(useStderr=true)
	addHandler(logger)

	dispatch bot

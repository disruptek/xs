import os
import streams
import sequtils
import osproc
import options
import httpclient
import httpcore
import base64
import strutils
import strformat
import uri

import cligen
import bump
import cutelog

const
  logLevel =
    when defined(debug):
      lvlDebug
    elif defined(release):
      lvlNotice
    elif defined(danger):
      lvlNotice
    else:
      lvlInfo

template crash(why: string) =
  ## a good way to exit ix()
  error why
  return 1

proc addIx*(data: var MultipartData;
           n: int; f = ""; id = ""; name = ""; filename = "";
           ext = ""; read = 0; remove = false) =
  ## add data for a paste to the payload we'll send via http
  if filename != "":
    data.addFiles {
      &"f:{n}": filename,
    }
  elif f != "":
    data.add &"f:{n}", f
  else:
    raise newException(ValueError, "filename/content missing")
  if ext != "":
    if not ext.startsWith(ExtSep):
      data.add &"ext:{n}", "{ExtSep}{ext}"
    else:
      data.add &"ext:{n}", ext
  if name != "":
    data.add &"name:{n}", name
  if id != "":
    data.add &"id:{n}", id
  if read != 0:
    data.add &"read:{n}", $read
  if remove:
    data.add &"rm", id

proc issueXclip*(output: string): bool =
  ## true if we seem to've successfully used xclip
  let
    xclip = findExe("xclip")
  if xclip == "":
    return false
  let
    process = startProcess(xclip, args = @["-in"],
                           options = {poUsePath})
  process.inputStream.write(output)
  process.inputStream.close()
  result = process.waitForExit == 0

proc paste*(name = "stdin"; xclip = true; extension = "nim"; reads = 0;
            get = ""; put = ""; delete = "";
            username = ""; password = "", log_level = logLevel,
            filenames: seq[string]): int =
  ## paste to ix
  var
    n: int
    data = newMultipartData()
    client = newHttpClient()
    user, pass: string

  # try to guess the username if it wasn't provided
  if username != "":
    user = username
  else:
    user = os.getEnv "IX_USER"
    if user == "":
      user = os.getEnv "USER"

  # try to guess the password if it wasn't provided
  if password != "":
    pass = password
  else:
    pass = os.getEnv "IX_PASS"

  # why would anyone want to submit more than one such command?
  if @[put, delete, get].count("") < 2:
    crash &"ambiguous.  use just one of put, delete, or get"

  # identify the id of the paste to work on an set the http method
  var
    id: string
    meth: HttpMethod
  if delete != "":
    meth = HttpDelete
    id = delete
  elif put != "":
    meth = HttpPut
    id = put
  elif get != "":
    meth = HttpGet
    id = get
  else:
    meth = HttpPost

  # some methods require authentication
  if meth in {HttpPut, HttpDelete}:
    if pass == "" or user == "":
      crash &"provide a password and username; $USER `{user}` by default"

  # we're going to record the apparent file extensions so we can use them
  # to build urls which will load the pastes with syntax highlighting
  var
    exts: seq[string]

  # build the multipart data for a submission
  if meth in {HttpPost, HttpPut}:
    # if no filenames were provided, we'll use stdin
    if filenames.len == 0:
      data.addIx(n, f = stdin.readAll, name = name.addFileExt(extension),
                 ext = extension, read = reads)
      exts.add extension.replace(".")
      n.inc
    # otherwise, add each file to the payload
    for fn in filenames.items:
      let
        splat = fn.splitFile
      exts.add splat.ext.replace(".")
      data.addIx(n, filename = fn, id = id, read = reads)
      n.inc

  # make a query of ix using all the info we've collected thus far
  var
    response: string
    url = "http://ix.io/" & id
  # set authentication credentials if available
  if user != "" and pass != "":
    client.headers["Authorization"] = @["Basic " & encode(&"{user}:{pass}")]
  # issue the request and store the response, a string, upon receipt
  case meth:
  of HttpGet:
    response = client.getContent(url)
  of HttpPut:
    response = client.putContent(url, multipart = data)
  of HttpPost:
    response = client.postContent(url, multipart = data)
  of HttpDelete:
    response = client.deleteContent(url)
  else:
    crash &"{meth} not supported; use Get, Put, Post, or Delete"

  # output the urls with the stashed extensions
  var
    output: string
  if meth in {HttpPost, HttpPut}:
    n = 0
    for link in response.splitLines:
      if link.startsWith("user") or link.strip == "":
        continue
      let
        uri = link.strip.parseUri
      if output != "":
        output &= "\n"
      # tweak the output url to add the appropriate syntax highlighter
      output &= $(uri / exts[n])
      n.inc
  else:
    # if we aren't getting pastes back, just dump whatever we get
    output = response

  # dump the output without any emojis
  fatal output

  # if xclip was requested, copy the output to our clipboard
  if xclip:
    if not issueXclip(output):
      notice "xclip fail"


when isMainModule:
  let
    console = newConsoleLogger(levelThreshold = logLevel,
                               useStderr = true, fmtStr = "")
    logger = newCuteLogger(console)
  addHandler(logger)

  let
    version = projectVersion()
  if version.isSome:
    clCfg.version = $version.get
  else:
    clCfg.version = "(unknown version)"

  dispatchCf paste, cmdName = "ix", cf = clCfg,
    doc = "get, put, post, delete pastes at ix.org",
    help = {
      "get": "retrieve a paste by id",
      "password": "password for authentication",
      "username": "username for authentication",
      "name": "default name of the input stream",
      "put": "update an existing paste identifier",
      "extension": "filename extension for content",
      "delete": "remove the given paste immediately",
      "reads": "remove after N reads; 0 to disable",
      "log-level": "specify Nim logging level",
      "xclip": "stuff output urls into clipboard",
      "filenames": "files to paste to ix",
    }

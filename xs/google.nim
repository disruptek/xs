import os
import json
import httpclient
import uri
import httpcore
import strformat
import tables
import logging
import uri
import sequtils
import asyncdispatch

import cligen

import rest
export rest

type
  ResultPage* = JsonNode

type
  Url = string
  GoogleClient* = object of RestClient
  GoogleError* = object of CatchableError        ## base for errors
  ParseError* = object of GoogleError            ## misc parse failure
    parsed*: ResultPage
    text*: string
  ErrorResponse* = object of ParseError          ## unwrap error response
    ShortMessage*: string
    LongMessage*: string
    ErrorCode*: string
    ErrorParameters*: ResultPage
  GoogleCall* = ref object of RestCall
  Keywords* = seq[string]
  ColorType* {.pure.} = enum Any = "", Mono = "mono", Gray = "gray", Color = "color"
  RightsType* {.pure.} = enum
    Any = "",
    PublicDomain = "cc_publicdomain",
    Attribute = "cc_attribute",
    Sharealike = "cc_sharealike",
    NonCommercial = "cc_noncommercial",
    NonDerived = "cc_nonderived"
  RightsSet = set[RightsType]
  DominantColor* {.pure.} = enum
    None = "",
    Red = "red",
    Orange = "orange",
    Yellow = "yellow",
    Green = "green",
    Teal = "teal",
    Blue = "blue",
    Purple = "purple",
    Pink = "pink",
    White = "white",
    Gray = "gray",
    Black = "black",
    Brown = "brown"
  ImageSize* {.pure.} = enum
    Any = "",
    Icon = "icon",
    Small = "small",
    Medium = "medium",
    Large = "large",
    XLarge = "xlarge",
    XXLarge = "xxlarge",
    Huge = "huge"
  ImageType* {.pure.} = enum
    Any = "",
    ClipArt = "clipart",
    Face = "face",
    LineArt = "lineart",
    News = "news"
    Stock = "stock"
    Animated = "animated"
    Photo = "photo"
  SearchType* {.pure.} = enum Any = "", WebPages = "web", Images = "image"
  RequestType* = Table[string, string]

  ListRequest* = ref RequestType
    #[
    q: string
    cx: string

    c2coff: string
    cr: string
    dateRestrict: string
    exactTerms: string
    excludeTerms: string
    fileType: string
    filter: string
    gl: string
    highRange: string
    hl: string
    hq: string
    imgColorType: string
    imgDominantColor: string
    imgSize: string
    imgType: string
    lowRange: string
    linkSite: string
    lr: string
    num: uint
    orTerms: string
    relatedSite: string
    rights: string
    safe: string
    searchType: SearchType
    siteSearch: string
    sort: string
    start: uint
    ]#

  ResponseType* = object of RootObj
    js: JsonNode

  ListResponse* = object of ResponseType

let Search* = GoogleCall()

proc `$`*(e: ref GoogleError): string
  {.raises: [].}=
  result = $typeof(e) & " " & e.msg

proc `$`*(e: ref ParseError): string
  {.raises: [].}=
  result = $typeof(e) & " " & e.msg & "\n" & $e.text

proc `$`*(e: ref ErrorResponse): string
  {.raises: [].} =
  result = $typeof(e) & " " & e.msg & "\n" & $e.parsed

method `$`(call: GoogleCall): string
  {.raises: [].} =
  ## turn a call into its name
  result = $call

method `$`*(response: ResponseType): string {.base.} =
  result = $response.js

proc defaultEndpoint*(name: Url=""): string =
  let key = cast[string](os.getEnv("GOOGLE_SEARCH_API"))
  if name == "":
    result = &"https://www.googleapis.com/customsearch/v1?key={key}"
  else:
    result = name & "?key=" & key

proc findSearchContext*(): string =
  result = cast[string](os.getEnv("GOOGLE_SEARCH_ENGINE"))
  assert result.len != 0, "define GOOGLE_SEARCH_ENGINE in env"

method recall*(call: GoogleCall; input: ListRequest): Recallable
  {.base, raises: [Exception].} =
  ## issue a retryable Search
  let
    base = defaultEndpoint()
  var url = base
  assert "cx" in input, "need cx (search engine id) in list request"
  assert "q" in input, "need q (keywords) in list request"
  for key, value in input.pairs:
    url &= "&" & key & "=" & value.encodeUrl(usePlus=true)

  result = call.newRecallable(url.parseUri, {
    "Content-Type": "application/json;charset=UTF-8",
  }, "")
  result.meth = HttpGet

converter toListResponse*(js: JsonNode): ListResponse =
  result = ListResponse(js: js)

converter toListResponse*(s: string): ListResponse =
  let js = s.parseJson()
  result = js.toListResponse()

proc googleSearch(fields="items";
  searchType=SearchType.Any;
  imgDominantColor=DominantColor.None;
  imgSize=ImageSize.Any;
  imgType=ImageType.Photo;
  imgColorType=ColorType.Any;
  fileType=""; num: uint = 0; sort="";
  rights: RightsSet = {};
  keywords: seq[string]) =
  var
    response: AsyncResponse
    rec: Recallable
    text: string
    query = ListRequest()

  query["cx"] = findSearchContext()
  query["q"] = keywords.join(" ")
  if num != 0:
    query["num"] = $num
  if fileType.len != 0:
    query["filetype"] = fileType
  if imgSize != ImageSize.Any:
    query["imgSize"] = $imgSize
  if imgType != ImageType.Any:
    query["imgType"] = $imgType
  if imgColorType != ColorType.Any:
    query["imgColorType"] = $imgColorType
  if imgDominantColor != DominantColor.None:
    query["imgDominantColor"] = $imgDominantColor
  if rights != {}:
    query["rights"] = toSeq(rights).join(",")
  if sort != "":
    query["sort"] = sort
  if searchType != SearchType.Any:
    query["searchType"] = $searchType

  query["fields"] = fields

  rec = Search.recall(query)
  try:
    response = rec.retried()
    text = waitfor response.body
    var lr: ListResponse = text.toListResponse
    echo $lr.js
  except RestError as e:
    debug "rest error:", e

when isMainModule:
  let logger = newConsoleLogger(useStderr=true)
  addHandler(logger)

  dispatch googleSearch


log       = (args...) -> console.log.apply console, args
fs        = require 'fs-plus'
path      = require 'path'
util      = require 'util'
crypto    = require 'crypto'
gitParser = require 'gitignore-parser'

class HelperProcess
  constructor: ->
    @filesByPath  = {}
    @filesByIndex = []
    @wordTrie     = {}
    
    process.on 'message', (msg) => @[msg.cmd] msg
    process.on 'disconnect',    => @destroy()
    
  send: (msg) -> process.send msg
  
  init: (@opts) ->
    # dataPath = path.join @opts.dataPath, '.find-all-files.data'
    # try
    #   file = fs.openSync dataPath, 'r'
    # catch e
    #   if e.code isnt 'ENOENT'
    #     log msg = ['data file open error at', dataPath, 'Code:', e.code].join ' '
    #     @send {cmd: 'FATAL', msg}
    #     setTimeout (-> process.exit 1), 1000
    #     return
    #   log 'warning: missing data file, creating new file at', dataPath
      
    ###
      packed format (53 bits)
         5 suffix
        16 filePath
        32 char offset
    ###
    log '@opts', @opts
    @checkAllProjects()
    
  updateOpts: (@opts) -> @checkAllProjects()
  
  checkAllProjects: ->
    for optPath in @opts.paths
      if @checkOneProject optPath then continue
      for projPath in fs.listSync optPath
        @checkOneProject projPath
      
  checkOneProject: (projPath) ->
    try
      giPath = path.join projPath, '.gitignore'
      # log 'giPath', fs.readFileSync giPath, 'utf8'
      gitignore = gitParser.compile fs.readFileSync giPath, 'utf8'
    catch e
      return no
    onDir = (dirPath) => 
      dir = path.basename dirPath
      if dir is '.git' then return false
      # if gitignore.accepts dir then log 'onDir', dir
      (not @opts.gitignore or gitignore.accepts dir)
    onFile = (filePath) =>
      filePath = filePath.toLowerCase()
      base = path.basename filePath
      sfx  = path.extname  filePath
      if ((sfx is  '' and @opts.suffixes.empty) or
          (sfx is '.' and @opts.suffixes.dot) or @opts.suffixes[sfx]) and 
         (not @opts.gitignore or gitignore.accepts base)
        @checkOneFile filePath
    fs.traverseTreeSync projPath, onFile, onDir
    yes
  
  checkOneFile: (filePath) ->
    log 'checkOneFile', filePath
    try
      stats = fs.statSync filePath
    catch e
      log 'ERROR on file stat, skipping', filePath, e.message
      return
    if not stats.isFile() then return
    fileTime = stats.mtime.getTime()
    if (oldFile = @filesByPath[filePath]) and 
        fileTime is oldFile.time
      return
      
    try
      text = fs.readFileSync filePath
    catch e
      log 'ERROR reading file, skipping', filePath, e.message
      return
    words = {}
    if not @regexStr
      try
        wordRegex = new RegExp @opts.wordRegex, 'g'
        @regexStr = @opts.wordRegex
      catch e
        log 'ERROR parsing word regex, using "[^\d]\\w*"', regexStr, e.message
        @regexStr = "\\w+"
    wordRegex = new RegExp @regexStr, 'g'
    while (parts = wordRegex.exec text)
      if parts[0] not in words then words[parts[0]] = yes
    wordList = Object.keys(words).sort()
    @checkWords filePath, fileTime, oldFile, wordList

  checkWords: (filePath, fileTime, oldFile, wordList) ->
    fileIndex = oldFile?.index ? @filesByIndex.length
    fileMd5 = crypto.createHash('md5').update(wordList.join ';').digest "hex"
    @filesByPath[filePath] = @filesByIndex[fileIndex] =
      {path:filePath, index:fileIndex, time:fileTime, md5:fileMd5}
    if fileMd5 is oldFile?.md5 then return
    
    if oldFile
      @traverseTrie (word, fileIndexes) =>
        
        fileIndexes.length isnt 0
      
  traverseTrie: ->  
    visitNode = (node, word) ->
      haveChild = no
      for letter, childNode of node
        if letter is 'fi'
          if not onFileIndexes word, childNode
            delete node.fi
          else haveChild = yes
        else 
          if not visitNode childNode, word+letter
            delete node[letter]
          else haveChild = yes
      haveChild
    visitNode @wordTrie, ''
  
    
    
    
  destroy: -> 
new HelperProcess

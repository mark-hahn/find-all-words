
log       = (args...) -> console.log.apply console, args
fs        = require 'fs-plus'
path      = require 'path'
util      = require 'util'
net       = require 'net'
crypto    = require 'crypto'
gitParser = require 'gitignore-parser'

FILE_IDX_INC = 1
pipePath = 
  if (process.platform is 'win32') 
    '\\\\.\\pipe\\atomfindallwords.sock'
  else '/tmp/atomfindallwords.sock'

class HelperProcess
  constructor: ->
    @connections = []
    @server = net.createServer()
      
    @server.listen pipePath, (args...) =>
      log 'server listen', args
      
    @server.on 'connection', (socket) =>
      socket.connectionIdx = connectionIdx = @connections.length
      @connections.push socket
      log 'received connection', connectionIdx
      
      destroy = ->
        delete @connections[connectionIdx]
        socket.destroy() 
        socket = null
        
      socket.on 'error', (err) ->
        log 'socket error on connection', connectionIdx, err.message
        destroy()
        
      socket.on 'data', (buf) => 
        msg = JSON.parse buf.toString()
        log 'recvd cmd', connectionIdx, msg.cmd
        @[msg.cmd] connectionIdx, msg
    
      socket.on 'end', ->
        log 'socket ended', connectionIdx
        destroy()
        
  send: (connectionIdx, msg) -> 
    if (socket = @connections[connectionIdx])
      socket.write JSON.stringify msg
  
  init: (connectionIdx, @opts) ->
    log 'init', @opts.newProcess
    if @opts.newProcess then @loadAllData()
    @scanAll connectionIdx
    
  updateOpts: (connectionIdx, @opts) -> 
    @scanAll connectionIdx
  
  getFilesForWord: (connectionIdx, msg) ->
    {word, caseSensitive, exactWord, assign, none} = msg
    filePaths = {}
    onFileIndexes = (indexes) =>
      for idx in indexes when idx
        filePaths[@filesByIndex[idx].path] = yes
    # if word is 'asdf'
      # log 'getFilesForWord', word, assign, none
    if assign and none
      @traverseWordTrie word, caseSensitive, exactWord, 'all', onFileIndexes
    else
      if assign
        @traverseWordTrie word, caseSensitive, exactWord, 'assign', onFileIndexes
      if none
        @traverseWordTrie word, caseSensitive, exactWord, 'none', onFileIndexes
    @send {
      cmd:  'filesForWord'
      files: Object.keys filePaths
      word, caseSensitive, exactWord, assign, none
    }

  scanAll: (connectionIdx) ->
    @filesChecked = 
      @filesAdded = @filesRemoved = @indexesAdded = 
      @timeMismatchCount = @md5MismatchCount =
      @changeCount = 0
    @setAllFileRemoveMarkers()
    for optPath in @opts.paths
      log 'scanning', optPath
      if @scanProject optPath then continue
      for projPath in fs.listSync optPath
        if fs.isDirectorySync projPath
          @scanProject projPath
    @removeMarkedFiles()
    @saveAllData() if @changeCount
    @send {connectionIdx, \
             cmd: 'scanned',
             @indexesAdded, @filesChecked,
             @filesAdded, @filesRemoved,
             @timeMismatchCount, @md5MismatchCount, 
             @changeCount }

################## PRIVATE ##################

  scanProject: (projPath) ->
    if @opts.gitignore and
       not fs.isDirectorySync path.join projPath, '.git'
      return no
    gitignore = @opts.gitignore and
      try
        giPath = path.join projPath, '.gitignore'
        gitignoreTxt = fs.readFileSync giPath, 'utf8'
        gitParser.compile gitignoreTxt + '\n.git\n'
      catch e
        null
    onDir = (dirPath) => 
      (not gitignore or gitignore.accepts path.basename dirPath)
    onFile = (filePath) =>
      sfx  = path.extname(filePath).toLowerCase()
      if ((sfx is  '' and @opts.suffixes.empty) or
          (sfx is '.' and @opts.suffixes.dot)   or 
                          @opts.suffixes[sfx] ) and 
         (not gitignore or gitignore.accepts path.basename filePath)
        @checkFile filePath
    fs.traverseTreeSync projPath, onFile, onDir
    yes
  
  checkFile: (filePath) ->
    @filesChecked++
    try
      stats = fs.statSync filePath
    catch e
      log 'ERROR on file stat, skipping', filePath, e.message
      return
    if not stats.isFile() then return
    
    # log 'oldFile', filePath, stats.mtime, Object.keys(@filesByPath).length
    
    if (oldFile = @filesByPath[filePath])
      delete oldFile.remove
    else
      @filesAdded++ 
      
    fileTime = stats.mtime.getTime()
    if fileTime is oldFile?.time then return
    
    @timeMismatchCount++ 
    
    try
      text = fs.readFileSync filePath
    catch e
      log 'ERROR reading file, skipping', filePath, e.message
      return
    wordsAssign = {}
    wordsNone   = {}
    wordRegex = new RegExp @opts.wordRegexStr, 'g'
    while (parts = wordRegex.exec text)
      word = parts[0]
      if word not of wordsAssign
        idx    = wordRegex.lastIndex
        before = text[0...idx-word.length]
        after  = text[idx...]
        if /^\s*=/.test(after)                            or
           /function\s+$/.test(before)                    or
           /for\s+(\w+,)?\s*$/.test(before) and 
             /^\s+(in|of)\s/.test(after)                  or
           /\{([^,}]*,)*([^,:}]+:)?\s*$/.test(before) and 
             /^\s*(,[^,}]* )*\}\s*=/.test(after)          or
           /\[([^,\]]*,)*\s*$/.test(before) and 
             /^\s*(,[^,\]]*)*\]\s*=/.test(after) 
          wordsAssign[word] = yes
          delete wordsNone[word]
        else
          wordsNone[word] = yes
    wordsAssignList = Object.keys(wordsAssign).sort()
    wordsNoneList   = Object.keys(wordsNone  ).sort()
    
    allWords = wordsAssignList.join(';') + ';;' +
               wordsNoneList  .join(';')
    fileMd5 = crypto.createHash('md5').update(allWords).digest "hex"
    
    if not (fileIndex = oldFile?.index)
      for file, idx in @filesByIndex when not file
        break
      fileIndex = idx
      
    @filesByPath[filePath] = @filesByIndex[fileIndex] =
      {path:filePath, index:fileIndex, time:fileTime, md5:fileMd5}
    if fileMd5 is oldFile?.md5 then return
    
    @md5MismatchCount++
    @changeCount++
    
    if oldFile then @removeFileIndexFromTrie oldFile.index
    for word in wordsAssignList
      @addWordFileIndexToTrie word, fileIndex, 'as'
    for word in wordsNoneList
      @addWordFileIndexToTrie word, fileIndex, 'no'

  setAllFileRemoveMarkers: ->
    for file in @filesByIndex when file
      file.remove = yes

  removeMarkedFiles: ->
    for file in @filesByIndex when file?.remove
      @filesRemoved++
      @changeCount++
      @removeFileIndexFromTrie file.index
      delete @filesByPath[file.path]
      delete @filesByIndex[file.index]
      
  removeFileIndexFromTrie: (fileIndex) ->
    @traverseWordTrie '', no, no, 'all', (fileIndexes) ->
      for fileIdx, idx in fileIndexes when fileIdx is fileIndex
        fileIndexes[idx] = 0
        return
  
  addWordFileIndexToTrie: (word, fileIndex, type) ->
    # if word is 'asdf'
      # log 'addWordFileIndexToTrie', word, fileIndex, type
    @indexesAdded++
    node = @getAddWordNodeFromTrie word
    fileIndexes = node[type] ?= new Int16Array FILE_IDX_INC
    for fileIdx, idx in fileIndexes when fileIdx is 0
      fileIndexes[idx] = fileIndex
      return
    oldLen = fileIndexes.length
    newLen = oldLen + FILE_IDX_INC
    newFileIndexes = new Int16Array newLen
    newFileIndexes[FILE_IDX_INC-1] = fileIndex
    newFileIndexes.set fileIndexes, FILE_IDX_INC
    node[type] = newFileIndexes
  
  getAddWordNodeFromTrie: (word) ->
    node = @wordTrie
    for letter in word
      lastNode = node
      if not (node = node[letter])
        node = lastNode[letter] = {}
    node
  
  traverseWordTrie: (wordIn, caseSensitive, exactWord, type, onFileIndexes) -> 
    # if wordIn is 'asdf'
      # log 'traverseWordTrie', type
    visitNode = (node, wordLeft, wordForNode) ->
      if not wordLeft
        if node.as and type in ['all', 'assign']
          onFileIndexes node.as, wordForNode, 'as'
        if node.no and type in ['all', 'none']
          onFileIndexes node.no, wordForNode, 'no'
        if exactWord then return
      for letter, childNode of node when letter.length is 1
        if not wordLeft or letter is wordLeft[0] or
           not caseSensitive and 
             letter.toLowerCase() is wordLeft[0].toLowerCase()
          visitNode childNode, wordLeft[1...], wordForNode + letter
    visitNode @wordTrie, wordIn, ''
  
  saveAllData: ->
    log 'saving to', @opts.dataPath
    tmpPath = @opts.dataPath + '.tmp'
    fd = fs.openSync tmpPath, 'w'
    writeJson = (obj) ->
      json    = JSON.stringify obj
      jsonLen = Buffer.byteLength json
      buf     = new Buffer 4 + jsonLen
      buf.writeInt32BE jsonLen, 0
      buf.write json, 4
      fs.writeSync fd, buf, 0, buf.length
    writeJson @filesByIndex
    @traverseWordTrie '', no, no, 'all', (fileIndexes, word, type) ->
      hdr    = word + ';' + type
      hdrLen = Buffer.byteLength hdr
      buf    = new Buffer 4 + hdrLen
      buf.writeInt32BE hdrLen, 0
      buf.write hdr, 4
      fs.writeSync fd, buf, 0, buf.length
      bufIdx = new Buffer fileIndexes.buffer
      buf = new Buffer 4
      buf.writeInt32BE bufIdx.length, 0
      fs.writeSync fd, buf, 0, buf.length
      fs.writeSync fd, bufIdx, 0, bufIdx.length
    fs.closeSync fd
    fs.removeSync @opts.dataPath
    fs.moveSync tmpPath, @opts.dataPath
    log 'saved'
    
  loadAllData: ->
    log 'loading from', @opts.dataPath
    @filesByIndex = []
    @filesByPath  = {}
    @wordTrie     = {}
    try
      fd = fs.openSync @opts.dataPath, 'r'
    catch e
      log 'Warning: data file missing:', @opts.dataPath
      return
    readLen = ->
      buf = new Buffer 4
      bytesRead = fs.readSync fd, buf, 0, 4
      if not bytesRead then 0
      else buf.readInt32BE 0
    jsonLen = readLen()
    buf = new Buffer jsonLen
    fs.readSync fd, buf, 0, jsonLen
    @filesByIndex = JSON.parse buf.toString()
    for file in @filesByIndex when file
      @filesByPath[file.path] = file
    while (hdrLen = readLen())
      buf = new Buffer hdrLen
      fs.readSync fd, buf, 0, hdrLen
      hdr = buf.toString()
      [word,type] = hdr.split ';'
      idxLen = readLen()
      buf = new Buffer idxLen
      fs.readSync fd, buf, 0, idxLen
      fileIndexes = new Int16Array idxLen/4
      for i in [0...idxLen/4]
        fileIndexes[i] = buf.readInt16BE i*4, true
      @addWordFileIndexToTrie word, fileIndexes, type
      
    log 'loaded', @filesByIndex.length, Object.keys(@wordTrie).length
      
  destroy: -> 
    
new HelperProcess

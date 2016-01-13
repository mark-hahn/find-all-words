
fs        = require 'fs-plus'
net       = require 'net'
path      = require 'path'
util      = require 'util'
crypto    = require 'crypto'
moment    = require 'moment'
gitParser = require 'gitignore-parser'

FILE_IDX_INC = 2

debug = process.argv[2]
logPath = path.join process.cwd(), 'find-all-words_process.log'
fs.removeSync logPath
log = (args...) -> 
  time = moment().format 'MM-DD HH:mm:ss'
  fs.appendFileSync logPath, time + ' ' + args.join(' ') + '\n'
log '-- starting helper process --'
log '-- node version', process.version
dbg = (if debug then log else ->)
dbg '-- debug mode'

pipePath = 
  if (process.platform is 'win32') 
    '\\\\.\\pipe\\atomfindallwords.sock'
  else '/tmp/atomfindallwords.sock'

process.on 'uncaughtException', (err) ->
  log '-- uncaughtException --'
  log util.inspect err, depth:null
  process.exit 1

class HelperProcess
  constructor: ->
    lastConnection = Date.now()
    @connections = []
    server = net.createServer()
      
    fs.removeSync pipePath
    server.listen pipePath, =>
      log 'server listening on', process.pid
      
    server.on 'error', (err) ->
      log 'server error', err.message
        
    server.on 'connection', (socket) =>
      connIdx = @connections.length
      @connections[connIdx] = socket
      log 'connection opened', connIdx
      
      destroy = =>
        log 'connection ended', connIdx
        delete @connections[connIdx]
        socket.destroy() 
        socket = null
        
      socket.on 'data', (buf) => 
        msg = JSON.parse buf.toString()
        dbg 'recvd cmd', connIdx, msg.cmd
        @[msg.cmd] connIdx, msg
        
      socket.on 'error', (err) ->
        log 'socket error', err.message
        destroy()
        
      socket.on 'end', destroy
        
    setInterval =>
      log 'setInterval', '\n', (new Date(lastConnection)).toString(), '\n', (new Date).toString()
      for connection in @connections when connection
        log 'lastConnection = Date.now()'
        lastConnection = Date.now()
        break
      if Date.now() > lastConnection + 200e3
        log '-- terminating idle process'
        server.close ->
          fs.removeSync pipePath
          log '-- terminated'
          process.exit 0
    , 60e3
        
  send: (connIdx, cmd, msg) -> 
    if (socket = @connections[connIdx])
      msg.cmd = cmd
      socket.write JSON.stringify msg
  
  broadcast: (cmd, msg) ->
    msg.cmd = cmd
    for socket in @connections when socket
      socket.write JSON.stringify msg

  init: (connIdx, @opts) ->
    log 'init', @opts.newProcess
    if @opts.newProcess then @loadAllData()
    @scanAll connIdx
    
  updateOpts: (connIdx, @opts) -> 
    @scanAll connIdx
  
  getFilesForWord: (connIdx, msg) ->
    {word, caseSensitive, exactWord, assign, none} = msg
    filePaths = {}
    onFileIndexes = (indexes) =>
      for idx in indexes when idx
        filePaths[@filesByIndex[idx].path] = yes
    if assign and none
      @traverseWordTrie word, caseSensitive, exactWord, 'all', onFileIndexes
    else
      if assign
        @traverseWordTrie word, caseSensitive, exactWord, 'assign', onFileIndexes
      if none
        @traverseWordTrie word, caseSensitive, exactWord, 'none', onFileIndexes
    @send connIdx, 'filesForWord', {
      files: Object.keys filePaths
      word, caseSensitive, exactWord, assign, none
    }

  scanAll: (connIdx) ->
    @filesChecked = 
      @filesAdded = @filesRemoved = @indexesAdded = 
      @timeMismatchCount = @md5MismatchCount =
      @changeCount = 0
    @setAllFileRemoveMarkers()
    for optPath in @opts.paths
      dbg 'scanning', optPath
      if @scanProject optPath then continue
      for projPath in fs.listSync optPath
        if fs.isDirectorySync projPath
          @scanProject projPath
    @removeMarkedFiles()
    @saveAllData() if @changeCount
    @broadcast 'scanned', {
      @indexesAdded, @filesChecked,
      @filesAdded, @filesRemoved,
      @timeMismatchCount, @md5MismatchCount, 
      @changeCount 
    }

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
        
  setFileIndexesInTrie: (word, fileIndexes, type) ->
    @indexesAdded += fileIndexes.length
    node = @getAddWordNodeFromTrie word
    node[type] = fileIndexes
  
  addWordFileIndexToTrie: (word, fileIndex, type) ->
    @indexesAdded++
    node = @getAddWordNodeFromTrie word
    fileIndexes = node[type] ?= new Int32Array FILE_IDX_INC
    for fileIdx, idx in fileIndexes when fileIdx is 0
      fileIndexes[idx] = fileIndex
      if word is 'asdf'
        log 'addWordFileIndexToTrie empty', 
             util.inspect {node, fileIdx, idx, fileIndex, fileIndexes}
      return
    oldLen = fileIndexes.length
    newLen = oldLen + FILE_IDX_INC
    newFileIndexes = new Int32Array newLen
    newFileIndexes[FILE_IDX_INC-1] = fileIndex
    newFileIndexes.set fileIndexes, FILE_IDX_INC
    node[type] = newFileIndexes
    if word is 'asdf'
      log 'addWordFileIndexToTrie non-empty', 
           util.inspect {node, fileIndex, newFileIndexes}
  
  getAddWordNodeFromTrie: (word) ->
    node = @wordTrie
    for letter in word
      lastNode = node
      if not (node = node[letter])
        node = lastNode[letter] = {}
    node
  
  traverseWordTrie: (wordIn, caseSensitive, exactWord, type, onFileIndexes) -> 
    if (asdf = wordIn is 'asdf')
      log 'traverseWordTrie', util.inspect {wordIn, caseSensitive, exactWord, type}
    visitNode = (node, wordLeft, wordForNode) ->
      if not wordLeft
        if node.as and type in ['all', 'assign']
          if asdf then log 'as', util.inspect(node.as), wordForNode
          onFileIndexes node.as, wordForNode, 'as'
        if node.no and type in ['all', 'none']
          if asdf then log 'no', util.inspect(node.no), wordForNode
          onFileIndexes node.no, wordForNode, 'no'
        if exactWord then return
      for letter, childNode of node when letter.length is 1
        if not wordLeft or letter is wordLeft[0] or
           not caseSensitive and 
             letter.toLowerCase() is wordLeft[0].toLowerCase()
          visitNode childNode, wordLeft[1...], wordForNode + letter
    visitNode @wordTrie, wordIn, ''
  
  saveAllData: ->
    dbg 'saving to', @opts.dataPath
    tmpPath = @opts.dataPath + '.tmp'
    fd      = fs.openSync tmpPath, 'w'
    
    json = JSON.stringify @filesByIndex
    while ((jsonLen = Buffer.byteLength json) % 4) then json += ' '
    jsonBuf = new Buffer 4 + jsonLen
    jsonBuf.writeInt32BE jsonLen, 0
    jsonBuf.write json, 4
    fs.writeSync fd, jsonBuf, 0, jsonBuf.length
    
    @traverseWordTrie '', no, no, 'all', (fileIndexes, word, type) ->
      hdr    = word + ';' + type
      while (hdr.length % 4) then hdr += ' '
      hdrLen = Buffer.byteLength hdr
      bufHdr = new Buffer 4 + hdrLen
      bufHdr.writeInt32BE hdrLen, 0
      bufHdr.write hdr, 4
      fs.writeSync fd, bufHdr, 0, bufHdr.length
      
      bufIdxLen = fileIndexes.length * 4
      bufIdx = new Buffer 4 + bufIdxLen
      bufIdx.writeInt32BE bufIdxLen, 0
      for i in [0...fileIndexes.length]
        bufIdx.writeInt32BE fileIndexes[i], 4 + i*4
      if word is 'asdf'
        log 'bufIdx', bufIdx.length, util.inspect {fileIndexes, word, type, bufIdx, fileIndexes}
      fs.writeSync fd, bufIdx, 0, bufIdx.length
      
    fs.closeSync fd
    fs.removeSync @opts.dataPath
    fs.moveSync tmpPath, @opts.dataPath
    dbg 'saved'
    
  loadAllData: ->
    log 'loading from', @opts.dataPath
    @filesByIndex = []
    @filesByPath  = {}
    @wordTrie     = {}
    try
      fd = fs.openSync @opts.dataPath, 'r'
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
        type = type[0..1]
        idxLen = readLen()
        buf = new Buffer idxLen
        fs.readSync fd, buf, 0, idxLen
        fileIndexes = new Int16Array idxLen/4
        for i in [0...idxLen/4]
          fileIndexes[i] = buf.readInt32BE i*4, true
        @setFileIndexesInTrie word, fileIndexes, type
      log 'loaded', @filesByIndex.length, Object.keys(@wordTrie).length
    catch e
      @filesByIndex = []
      @filesByPath  = {}
      @wordTrie     = {}
      log 'Warning: data file read err', util.inspect e
      
  destroy: -> 
    
new HelperProcess

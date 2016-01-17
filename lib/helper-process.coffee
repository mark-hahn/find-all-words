
fs        = require 'fs-plus'
net       = require 'net'
path      = require 'path'
util      = require 'util'
utils     = require './helper-utils'
crypto    = require 'crypto'
gitParser = require 'gitignore-parser'
Lexer     = require('coffee-script/lib/coffee-script/lexer').Lexer

FILE_IDX_INC = 2
ASSIGN_MASK  = 0xC0000000
CALL_MASK    = 0x30000000
ARG_MASK     = 0x0C000000
PARAM_MASK   = 0x03000000
VAR_MASK     = 0x00C00000
INDEX_MASK   = 0x000FFFFF

log = utils.log
dbg = utils.dbg

log '-- starting helper process --'
log '-- faw, node versions:', utils.version, process.version

process.on 'uncaughtException', (err) ->
  log '-- uncaughtException --'
  log util.inspect err, depth:null
  process.exit 1
  
class HelperProcess
  constructor: ->
    lastConnection = Date.now()
    @connections = []
    server = net.createServer()
      
    fs.removeSync utils.pipePath
    server.listen utils.pipePath, =>
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
          fs.removeSync utils.pipePath
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
    if (isCS = (path.extname(filePath).toLowerCase() is '.coffee'))
      source = fs.readFileSync filePath, 'utf8'
      tokens = []
      try
        rawTokens = new Lexer().__proto__.tokenize source
      catch e
        if e.toString().indexOf('SyntaxError') is -1
          log 'tokenizing error:', filePath, util.inspect e
        else 
          @parseError filePath, e
        return
      for tokenArr in rawTokens
        tokens.push @parseToken tokenArr
      if not @debug
        log filePath, util.inspect tokens
        @debug = yes
    return

    #   x=1
    #   
    # @filesChecked++
    # try
    #   stats = fs.statSync filePath
    # catch e
    #   log 'ERROR on file stat, skipping', filePath, e.message
    #   return
    # if not stats.isFile() then return
    # 
    # # dbg 'oldFile', filePath, stats.mtime, Object.keys(@filesByPath).length
    # 
    # if (oldFile = @filesByPath[filePath])
    #   delete oldFile.remove
    # else
    #   @filesAdded++ 
    #   
    # fileTime = stats.mtime.getTime()
    # if fileTime is oldFile?.time then return
    # 
    # @timeMismatchCount++ 
    # 
    # try
    #   text = fs.readFileSync filePath, 'utf8'
    # catch e
    #   log 'ERROR reading file, skipping', filePath, e.message
    #   return
    # words = {}
    # 
    # text.replace /([]+)(\s|$)/g, (match, subStr, __, ofs) ->
    #   ###
    #     CALL_MASK    = 0x10000000
    #     ARG_MASK     = 0x08000000
    #     PARAM_MASK   = 0x04000000
    #     INDEX_MASK   = 0x02000000
    #   ###
    #   checkWordAttrs = (word, isVar) ->
    #     if /\s*/.test word then return
    #     before = text[0...ofs]
    #     after  = text[ofs+word.length...]
    #     code = 0
    #     if isVar 
    #       code |= VAR_MASK
    #       if not isCS
    #         if /function\s+$/.test before then code |= FUNC_MASK
    #         if /^\s*\(/.test after        then code |= CALL_MASK
    #         if /^\s*=/ .test after        then code |= ASSIGN_MASK
    #       else
    #         # if /function\s+$/.test before then code |= FUNC_MASK
    # 
    #         
    #         
    #         
    #         if /\s+[^=]+?(\n|$)/.test after then code |= CALL_MASK
    #         
    #         if /^\s*=/.test(after)                            or
    #           /for\s+(\w+,)?\s*$/.test(before)           and 
    #           /^\s+(in|of)\s/.test(after)                  or
    #           /\{([^,}]*,)*([^,:}]+:)?\s*$/.test(before) and 
    #           /^\s*(,[^,}]* )*\}\s*=/.test(after)          or
    #           /\[([^,\]]*,)*\s*$/.test(before) 
    #           and /^\s*(,[^,\]]*)*\]\s*=/.test(after) then code |= ASSIGN_MASK
    #         
    #     
    #         
    #       
    #     words[word] = code  
    #   
    #   text.replace /\b[a-z_$][\W\$]*\b/i.match subStr
    #   checkWordAttrs(aVar, yes) for aVar in vars
    #   if vars[0] isnt word then checkSubStr[word, no]
    #   match
    #   
    # wordList = Object.keys(words).sort()
    # fileMd5 = crypto.createHash('md5').update(wordList.join ' ').digest "hex"
    # 
    # if not (fileIndex = oldFile?.index)
    #   for file, idx in @filesByIndex when not file
    #     break
    #   fileIndex = idx
    #   
    # @filesByPath[filePath] = @filesByIndex[fileIndex] =
    #   {path:filePath, index:fileIndex, time:fileTime, md5:fileMd5}
    # if fileMd5 is oldFile?.md5 then return
    # 
    # @md5MismatchCount++
    # @changeCount++
    # 
    # if oldFile then @removeFileFromTrie oldFile
    # for word in wordList
    #   @addWordFileToTrie word, file

  setAllFileRemoveMarkers: ->
    for file in @filesByIndex when file
      file.remove = yes

  removeMarkedFiles: ->
    for file in @filesByIndex when file?.remove
      @filesRemoved++
      @changeCount++
      @removeFileFromTrie file
      delete @filesByPath[file.path]
      delete @filesByIndex[file.index]
      
  removeFileFromTrie: (file) ->
    @traverseWordTrie '', no, no, 'all', (fileIndexes) ->
      for fileIndex, idx in fileIndexes when fileIndex is file.index
        fileIndexes[idx] = 0
        return
        
  setFileIndexesInTrie: (word, fileIndexes, type) ->
    @indexesAdded += fileIndexes.length
    node = @getAddWordNodeFromTrie word
    node[type] = fileIndexes
  
  addWordFileToTrie: (word, file) ->
    @indexesAdded++
    node = @getAddWordNodeFromTrie word
    fileIndexes = node[type] ?= new Int32Array FILE_IDX_INC
    for fileIndex, idx in fileIndexes when fileIndex is 0
      fileIndexes[idx] = file.index
      return
    oldLen = fileIndexes.length
    newLen = oldLen + FILE_IDX_INC
    newFileIndexes = new Int32Array newLen
    newFileIndexes[FILE_IDX_INC-1] = file.index
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
  
  parseError: (filePath, e) ->
    log 'parse err', filePath, util.inspect e, depth: null
    msg = 'Coffeescript Error\nfile skipped:' + filePath + '\n' + e.toString() + 
         ' at row:col ' + e.location.first_line + ':' + e.location.first_column + ' (to ' +
                          e.location.last_line  + ':' + e.location.last_column  + ')'
    @broadcast 'syntaxError', {msg}
    
  parseToken: (tokenArr) ->
    for tokenProp, val of tokenArr
      switch tokenProp
        when '0' then token = type: val
        when '1' then token.text = val
        when '2'
          {first_line:   token.row1, last_line:   token.row2,  \
           first_column: token.col1, last_column: token.col2} = val
        else token[tokenProp] = val
    token.col2 += 1
    if token.origin
      for prop, val of token.origin
        switch prop
          when '0' then token.originText = val
          when '1' then token.originType = val
          when '2'
            if val then \
              {first_line:   token.originRow1, \
               last_line:   token.originRow2
               first_column: token.originCol1
               last_column: token.originCol2} = val
            token.originCol2 += 1
      delete token.origin
    token
    
  destroy: -> 
    
new HelperProcess

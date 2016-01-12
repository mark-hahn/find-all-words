
log       = (args...) -> console.log.apply console, args
fs        = require 'fs-plus'
path      = require 'path'
util      = require 'util'
crypto    = require 'crypto'
gitParser = require 'gitignore-parser'

FILE_IDX_INC = 8

class HelperProcess
  constructor: ->
    process.on 'message', (msg) => @[msg.cmd] msg
    process.on 'disconnect',    => @destroy()
    
  send: (msg) -> process.send msg
  
  init: (@opts) ->
    @filesByPath  = {}
    @filesByIndex = []
    @wordTrie     = {}
    
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
      
    # log '@opts', @opts
    @scanAll()
    
  updateOpts: (@opts) -> 
    @regexStr = null
    @scanAll()
  
  scanAll: ->
    @fileCount = 0
    @wordCount = 0
    @setAllFileRemoveMarkers()
    for optPath in @opts.paths
      if @checkOneProject optPath then continue
      for projPath in fs.listSync optPath
        if fs.isDirectorySync projPath
          @checkOneProject projPath
    @removeMarkedFiles()
    @send {cmd: 'scanned', @fileCount, @wordCount}

  getFilesForWord: (msg) ->
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

  checkOneProject: (projPath) ->
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
        @checkOneFile filePath
    fs.traverseTreeSync projPath, onFile, onDir
    yes
  
  checkOneFile: (filePath) ->
    @fileCount++
    try
      stats = fs.statSync filePath
    catch e
      log 'ERROR on file stat, skipping', filePath, e.message
      return
    if not stats.isFile() then return
    
    if (oldFile = @filesByPath[filePath])
      delete oldFile.remove
      
    fileTime = stats.mtime.getTime()
    if fileTime is oldFile?.time then return

    try
      text = fs.readFileSync filePath
    catch e
      log 'ERROR reading file, skipping', filePath, e.message
      return
    if not @regexStr
      try
        new RegExp @opts.wordRegex
        @regexStr = @opts.wordRegex
      catch e
        log 'ERROR parsing word regex, using "[a-zA-Z_\\$]\\w*"', regexStr, e.message
        @regexStr = "[a-zA-Z_\\$]\\w*"
    wordsAssign = {}
    wordsNone   = {}
    wordRegex = new RegExp @regexStr, 'g'
    while (parts = wordRegex.exec text)
      word = parts[0]
      if word not of wordsAssign
        idx    = wordRegex.lastIndex
        before = text[0...idx-word.length]
        after  = text[idx...]
        if /^\s*=/.test(after)                            or
           /function\s+$/.test(before)                    or
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
      @removeFileIndexFromTrie file.index
      delete @filesByPath[file.path]
      delete @filesByIndex[file.index]
      
  removeFileIndexFromTrie: (fileIndex) ->
    @traverseWordTrie '', no, no, 'all', (fileIndexes) ->
      for fileIdx, idx in fileIndexes when fileIdx is fileIndex
        fileIndexes[idx] = 0
        return
  
  addWordFileIndexToTrie: (word, fileIndex, type) ->
    if word is 'asdf'
      log 'addWordFileIndexToTrie', word, fileIndex, type
    @wordCount++
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
  
  traverseWordTrie: (word, caseSensitive, exactWord, type, onFileIndexes) -> 
    # if word is 'asdf'
      # log 'traverseWordTrie', type
    visitNode = (node, word) ->
      if not word
        if node.as and type in ['all', 'assign']
          onFileIndexes node.as
        if node.no and type in ['all', 'none']
          onFileIndexes node.no
        if exactWord then return
      for letter, childNode of node when letter.length is 1
        if not word or letter is word[0] or
           not caseSensitive and 
             letter.toLowerCase() is word[0].toLowerCase()
          visitNode childNode, word[1...]
    visitNode @wordTrie, word
    
  destroy: -> 
    
new HelperProcess

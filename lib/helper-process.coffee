
log       = (args...) -> console.log.apply console, args
fs        = require 'fs-plus'
path      = require 'path'
util      = require 'util'
crypto    = require 'crypto'
gitParser = require 'gitignore-parser'

FILE_IDX_INC = 32

class HelperProcess
  constructor: ->
    process.on 'message', (msg) => @[msg.cmd] msg
    process.on 'disconnect',    => @destroy()
    
  send: (msg) -> process.send msg
  
  init: (@opts) ->
    @fileCount = 0
    @wordCount = 0
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
    @checkAllProjects()
    
  updateOpts: (@opts) -> @checkAllProjects()
  
  getFilesForWord: (msg) ->
    {word} = msg
    if not (node = @getAddWordNodeFromTrie word) or not node.fi
      node = fi: []
    @send
      cmd:  'filesForWord'
      word:  word
      files: (@filesByIndex[idx].path for idx in node.fi when idx)
  
  checkAllProjects: ->
    @setAllFileRemoveMarkers()
    
    for optPath in @opts.paths
      if @checkOneProject optPath then continue
      for projPath in fs.listSync optPath
        @checkOneProject projPath
    @removeMarkedFiles()
    # log {@fileCount, @wordCount}
    # log {@filesByIndex, @wordTrie}
      
  checkOneProject: (projPath) ->
    try
      giPath = path.join projPath, '.gitignore'
      gitignore = gitParser.compile fs.readFileSync giPath, 'utf8'
    catch e
      return no

    onDir = (dirPath) => 
      dir = path.basename dirPath
      (dir isnt '.git' and
        (not @opts.gitignore or gitignore.accepts dir))

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

    fileIndex = oldFile?.index ? @filesByIndex.length
    fileMd5 = crypto.createHash('md5').update(wordList.join ';').digest "hex"
    @filesByPath[filePath] = @filesByIndex[fileIndex] =
      {path:filePath, index:fileIndex, time:fileTime, md5:fileMd5}
    if fileMd5 is oldFile?.md5 then return
    
    if oldFile then @removeFileIndexFromTrie oldFile.index
    for word in wordList
      @addWordFileIndexToTrie word, fileIndex
    @normalizeTrie()

  setAllFileRemoveMarkers: ->
    for file in @filesByIndex when file
      file.remove = yes

  removeMarkedFiles: ->
    for file in @filesByIndex when file?.remove
      @removeFileIndexFromTrie file.index
      delete @filesByPath[file.path]
      delete @filesByIndex[file.index]
      
  addWordFileIndexToTrie: (word, fileIndex) ->
    @wordCount++
    node = @getAddWordNodeFromTrie word, yes
    fileIndexes = node.fi ?= new Int16Array FILE_IDX_INC
    for fileIdx, idx in fileIndexes when fileIdx is 0
      fileIndexes[idx] = fileIndex
      return
    oldLen = fileIndexes.length
    newLen = oldLen + FILE_IDX_INC
    newFileIndexes = new Int16Array newLen
    newFileIndexes.fill 0, 0, FILE_IDX_INC-1
    newFileIndexes[FILE_IDX_INC-1] = fileIndex
    newFileIndexes.set fileIndexes, FILE_IDX_INC
    node.fi = newFileIndexes
  
  getAddWordNodeFromTrie: (word, add) ->
    node = @wordTrie
    for letter in word
      lastNode = node
      if not (node = node[letter])
        if not add then return null
        node = lastNode[letter] = {}
    node
    
  removeFileIndexFromTrie: (fileIndex) ->
    @traverseWordTrie (fileIndexes) ->
      for fileIdx, idx in fileIndexes when fileIdx is fileIndex
        fileIndexes[idx] = 0
        return
  
  traverseWordTrie: (onFileIndexes) ->  
    visitNode = (node, word) ->
      haveChild = no
      for letter, childNode of node
        if letter is 'fi'
          if onFileIndexes(childNode) is false
            delete node.fi
          else haveChild = yes
        else 
          if not visitNode childNode, word+letter
            delete node[letter]
          else haveChild = yes
      haveChild
    visitNode @wordTrie, ''
    
  normalizeTrie: ->
    @traverseWordTrie (fileIndexes) =>
      Array.prototype.sort.call fileIndexes
    
  destroy: -> 
    
new HelperProcess


log       = (args...) -> console.log.apply console, args
path      = require 'path'
util      = require 'util'
fs        = require 'fs-plus'
gitParser = require 'gitignore-parser'

class HelperProcess
  constructor: ->
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
      
  checkOneFile: (filePath) ->
    log 'checkOneFile', filePath
  
  checkOneProject: (projPath) ->
    try
      giPath = path.join projPath, '.gitignore'
      # log 'giPath', fs.readFileSync giPath, 'utf8'
      gitignore = gitParser.compile fs.readFileSync giPath, 'utf8'
    catch e
      return no
      
    # log 'checkOneProject', projPath
    
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
  
  checkAllProjects: ->
    for optPath in @opts.paths
      if @checkOneProject optPath then continue
      for projPath in fs.listSync optPath
        @checkOneProject projPath
      
  destroy: -> 

new HelperProcess

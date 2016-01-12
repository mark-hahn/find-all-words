
log          = require('./utils') 'hlpr'
procLog      = require('./utils') 'proc'
childProcess = require 'child_process'

helperPath = process.cwd() + '/js/helper-process.js' 
  
module.exports =
class Helper
  
  constructor: (initOpts) ->
    @child = childProcess.fork helperPath, silent:yes
    @child.on 'message',          (msg) => @[msg.cmd] msg
    @child.on 'error',            (err) => @error err
    @child.on 'close',           (code) => log 'process exited with code', code
    @child.stdout.on 'data',     (data) -> 
      for line in data.toString().split '\n' when line then procLog line
    @child.stderr.on 'data',     (data) ->
      procLog 'STDERR ...\n', data.toString()
      
    log 'loading words 2'
    @send 'init', initOpts

  send: (cmd, data) -> @child.send Object.assign {cmd}, data
  
  # for asdf in y
  
  scanned: (msg) ->
    log 'scanned', msg
    @send 'getFilesForWord', 
      word:         'asdf'
      caseSensitive: yes
      exactWord:     yes
      assign:        yes
      none:          no
    
  filesForWord: (msg) ->
    log 'filesForWord', msg

  error: (err) ->
    log 'error:', err.message
    @child = null

  destory: ->
    @child?.kill()
    @child = null
  

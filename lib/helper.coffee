
log     = require('./utils') 'hlpr'
procLog = require('./utils') 'proc'
  
childProcess = require 'child_process'

helperPath = process.cwd() + '/js/helper-process.js' 
  
module.exports =
class Helper
  
  constructor: ->
    log 'constructor'
    
    @child = childProcess.fork helperPath, silent:yes
    @child.on 'message',          (msg) => @recv msg
    @child.on 'error',            (err) => @error err
    @child.on 'close',           (code) => log 'process exited with code', code
    @child.stdout.on 'data',     (data) -> 
      for line in data.toString().split '\n' when line then procLog line
    @child.stderr.on 'data',     (data) ->
      procLog 'STDERR ...\n', data.toString()

    @send 'hello'

  error: (err) ->
    log 'error:', err.message
    @child = null
    
  send: (msg) -> 
    @child.send msg
    
  recv: (msg) ->
    log 'recv', msg
    
  destory: ->
    @child?.kill()
    @child = null
  

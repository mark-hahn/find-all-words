
log          = require('./utils') 'hlpr'
procLog      = require('./utils') 'proc'
childProcess = require 'child_process'

helperPath = process.cwd() + '/js/helper-process.js' 
  
module.exports =
class Helper
  
  constructor: (initOpts) ->
    @child = childProcess.fork helperPath, silent:yes
    @child.on 'message',          (msg) => @recv msg
    @child.on 'error',            (err) => @error err
    @child.on 'close',           (code) => log 'process exited with code', code
    @child.stdout.on 'data',     (data) -> 
      for line in data.toString().split '\n' when line then procLog line
    @child.stderr.on 'data',     (data) ->
      procLog 'STDERR ...\n', data.toString()
    @send 'init', initOpts

  send: (cmd, data) -> @child.send Object.assign {cmd}, data
    
  recv: (msg) ->
    log 'recv', msg
    
  error: (err) ->
    log 'error:', err.message
    @child = null
      
  destory: ->
    @child?.kill()
    @child = null
  

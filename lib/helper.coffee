
log = require('./utils') 'hlpr'

childProcess = require 'child_process'

module.exports =
class Helper
  
  constructor: ->
    log 'constructor'
    
    @child = childProcess.fork '/root/.atom/packages/find-all-words/lib/helper-process'
    @child.on 'connected', (@connected) => @init()
    @child.on 'message',          (msg) => @recv msg
    @child.on 'error',            (err) -> @error err
    @child.on 'exit',    (code, signal) -> log 'process exit:', {code, signal}

  init: ->
    log 'connected:', @connected
    @readyCB?()
    
  ready: (@readyCB) ->
    if @connected 
      setImmediate => @readyCB()
      @readyCB = null
      
  error: (err) ->
    @readyCB? 'error:' + err.message
    @readyCB = null
    @child = null
    
  send: (msg) -> 
    if @connected
      log 'send', msg
      @child.send msg
  
  recv: (msg) ->
    log 'recv', msg
    
  destory: ->
    @child.kill()
    @child = null




console.log 'proc entering'

log = require('./utils') 'proc'

helperProcess = 
  
  init: ->
    log 'init'
    process.on 'message', @recv
    
  send: (msg) -> process.send msg
  
  recv: (msg) ->
    log 'received', msg


helperProcess.init()

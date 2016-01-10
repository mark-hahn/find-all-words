
log = (args...) -> console.log.apply console, args

class HelperProcess
  constructor: ->
    process.on 'message', (msg) => @recv msg
    process.on 'disconnect',    => @destroy()
    
  send: (msg) -> process.send msg
  
  recv: (msg) ->  
    log 'received', msg 
    
  destroy: -> 

new HelperProcess

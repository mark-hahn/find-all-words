
log = (args...) -> console.log.apply console, args

class HelperProcess
  constructor: ->
    process.on 'message', (msg) => @[msg.cmd] msg
    process.on 'disconnect',    => @destroy()
    
  send: (msg) -> process.send msg

  init: (opts) ->
    log 'init', opts
    @words = []
    
  updateOpts: (opts) ->  
    log 'updateOpts (not supported yet)', opts
    
  destroy: -> 

new HelperProcess

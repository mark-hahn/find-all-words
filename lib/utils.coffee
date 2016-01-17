moment =require 'moment'

logWithTime = (args...) -> 
  time = moment().format 'MM-DD HH:mm:ss'
  console.log time, args...

module.exports = (modName) ->
  
  (args...) -> 
    logWithTime 'find-all-words',  modName.toUpperCase()+':', args...
    args

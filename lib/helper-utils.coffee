
exports.version = version = '1'

fs     = require 'fs-plus'
path   = require 'path'
moment = require 'moment'

logPath = path.join process.cwd(), 'process.log'
fs.removeSync logPath

exports.logRaw = logRaw = (args...) ->
  fs.appendFileSync logPath, args.join(' ') + '\n'
  
exports.log = log = (args...) -> 
  time = moment().format 'MM-DD HH:mm:ss'
  logRaw time, args...

exports.debug = debug = process.argv[2]  
exports.dbg = dbg = (if debug then log else ->)
dbg '-- debug mode'

exports.pipePath = 
  if (process.platform is 'win32') 
    "\\\\.\\pipe\\atomFaw#{version}.sock"
  else "/tmp/atomFaw#{version}.sock"


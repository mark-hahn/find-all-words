
log          = require('./utils') 'hlpr'
fs           = require 'fs-plus'
net          = require 'net'
util         = require 'util'
path         = require 'path'
procLog      = require('./utils') 'proc'
childProcess = require 'child_process'

helperPath = process.cwd() + '/js/helper-process.js' 
pipePath = 
  if (process.platform is 'win32') 
    '\\\\.\\pipe\\atomfindallwords.sock'
  else '/tmp/atomfindallwords.sock'

module.exports =
class Helper
  
  constructor: (@initOpts) ->
    @debug = 
      if atom.project.getPaths()[0] is '/root/.atom/packages/find-all-words' then 'debug'
      else ''
    if @debug
      log 'Warning: killing helper process, this should only happen when debugging'
      childProcess.execSync \
        'kill $(pgrep -f "find-all-words/js/helper-process.js")' +
         ' 2> /dev/null' 
      fs.removeSync pipePath
    @createdServer = no
    @connectToPipeServer()
    
  connectToPipeServer: ->
    @pipe = net.createConnection path: pipePath, =>
      log 'connected to helper process'
      @pipe.setNoDelay()
      @pipe.unref()
      @initOpts.newProcess = @createdServer
      @send 'init', @initOpts
        
    @pipe.on 'data', (buf) => 
      msg = JSON.parse buf.toString()
      log 'recvd cmd', msg.cmd
      @[msg.cmd] msg
      
    @pipe.on 'error', (e) => 
      @pipe.destroy()
      @pipe = null
      if not @createdServer and e.code is 'ENOENT'
        @forkPipeServer()
        return
      log 'pipe error:', e.code, pipePath
      
  forkPipeServer: ->
    @child = childProcess.spawn 'node', [helperPath, @debug],
      {detached:yes, stdio: ['ignore', 'ignore', 'ignore']}
    log 'helper process spawned on pid', @child.pid
    setImmediate =>
      @createdServer = yes
      @connectToPipeServer()
  
  send: (cmd, msg) -> 
    msg.cmd = cmd
    @pipe.write JSON.stringify msg
    
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

  destroy: ->
    @child = null
    @pipe.destroy()
    @pipe = null

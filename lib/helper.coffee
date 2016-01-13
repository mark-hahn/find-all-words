
log          = require('./utils') 'hlpr'
fs           = require 'fs-plus'
net          = require 'net'
util         = require 'util'
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
    if atom.project.getPaths()[0] is '/root/.atom/packages/find-all-words'
      log 'Error: killing process, this should only happen in debug'
      childProcess.execSync \
        'kill $(pgrep -f "find-all-words/js/helper-process.js")' +
         ' 2> /dev/null' 
      fs.removeSync pipePath
    @connectToPipeServer()
    
  connectToPipeServer: ->
    @pipe = net.createConnection path: pipePath, (args...) =>
      log 'pipe connected', args
      @pipe.setNoDelay()
      @pipe.unref()
      @send Object.assign \
        {cmd:'init', newProcess:@createdServer}, @initOpts
        
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
    log 'forking helper-process'
    @child = childProcess.fork helperPath, silent:yes, detached:yes
    @child.stdout.on 'data',     (data) -> 
      for line in data.toString().split '\n' when line then procLog line
    @child.stderr.on 'data',     (data) ->
      procLog 'STDERR ...\n', data.toString()
    setImmediate =>
      @createdServer = yes
      @connectToPipeServer()
  
  send: (msg) -> @pipe.write JSON.stringify msg
    
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

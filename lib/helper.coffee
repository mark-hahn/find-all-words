
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
  
  constructor: (initOpts) ->
    log atom.project.getPaths()[0]
    if atom.project.getPaths()[0] is '/root/.atom/packages/find-all-words'
      log 'Error: killing process, this should only happen in debug'
      childProcess.execSync \
        'kill $(pgrep -f "find-all-words/js/helper-process.js") 2> /dev/null' 
      fs.removeSync pipePath
    @connectToPipeServer()
    
  connectToPipeServer: ->
    @pipe = net.createConnection path: pipePath, (args...) =>
      log 'pipe connected', args
      @pipe.unref()
      @pipe.setNoDelay()
      # @pipe.setTimeout 2000, (args...) ->
      #   log 'pipe timeout', args
        
    @pipe.on 'data', (args...) ->
      log 'pipe recv data', args
      
    @pipe.on 'error', (e) => 
      @pipe.destroy()
      @pipe = null
      if not @createdServer and e.code is 'ENOENT'
        @forkPipeServer()
        return
      log 'pipe error:', e.code, pipePath
  
  forkPipeServer: ->
    log 'forking pipe server'
    @child = childProcess.fork helperPath, silent:yes, detached:yes
    @child.stdout.on 'data',     (data) -> 
      for line in data.toString().split '\n' when line then procLog line
    @child.stderr.on 'data',     (data) ->
      procLog 'STDERR ...\n', data.toString()
    setImmediate =>
      @createdServer = yes
      @connectToPipeServer()
    
  #   @child = childProcess.fork helperPath, silent:yes, detached:yes
  #   
  #   @child.on 'message',          (msg) => @[msg.cmd] msg
  #   @child.on 'error',            (err) => @error err
  #   @child.on 'close',           (code) => log 'process exited with code', code
  #   @child.stdout.on 'data',     (data) -> 
  #     for line in data.toString().split '\n' when line then procLog line
  #   @child.stderr.on 'data',     (data) ->
  #     procLog 'STDERR ...\n', data.toString()
  #   @send 'init', initOpts
  # 
  # send: (cmd, data) -> @child.send Object.assign {cmd}, data
  # 
  # # for asdf in y
  # 
  # scanned: (msg) ->
  #   log 'scanned', msg
  #   @send 'getFilesForWord', 
  #     word:         'asdf'
  #     caseSensitive: yes
  #     exactWord:     yes
  #     assign:        yes
  #     none:          no
  #   
  # filesForWord: (msg) ->
  #   log 'filesForWord', msg
  # 
  # error: (err) ->
  #   log 'error:', err.message
  #   @child = null
  # 
  # destory: ->
  #   @child?.kill()
  #   @child = null
  # 

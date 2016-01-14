
fs           = require 'fs-plus'
net          = require 'net'
log          = require('./utils') 'hlpr'
hlprUtils    = require './helper-utils'
util         = require 'util'
path         = require 'path'
childProcess = require 'child_process'
helperPath   = process.cwd() + '/js/helper-process.js' 

module.exports =
class Helper
  
  constructor: (@initOpts) ->
    log 'faw/node version', hlprUtils.version, process.version
    @pipeErrorCount = 0
    @debug = 
      if atom.project.getPaths()[0] is '/root/.atom/packages/find-all-words' then 'debug'
      else ''
    if @debug
      log 'Warning: killing helper process (only when debugging)'
      childProcess.execSync \
        'kill $(pgrep -f "find-all-words/js/helper-process.js")' +
         ' 2> /dev/null' 
    @spawnedProcess = no
    @connectToPipeServer()
    
  connectToPipeServer: ->
    @pipe = net.createConnection path: hlprUtils.pipePath, =>
      log 'connected to helper process with pipe', hlprUtils.pipePath
      @pipe.setNoDelay()
      @pipe.unref()
      @initOpts.newProcess = @spawnedProcess
      @send 'init', @initOpts
        
    @pipe.on 'data', (buf) => 
      msg = JSON.parse buf.toString()
      log 'recvd cmd', msg.cmd
      @[msg.cmd] msg
      
    @pipe.on 'error', (e) => 
      @pipe.destroy()
      @pipe = null
      if not @spawnedProcess and e.code in ['ENOENT', 'ECONNREFUSED']
        log 'unable to connect to existing helper process:', e.code
        @spawnHelperProcess()
        return
      log 'pipe error:', @spawnedProcess, @pipeErrorCount, e.code, hlprUtils.pipePath
      if ++@pipeErrorCount < 5
        setTimeout (=> @connectToPipeServer()), 1000
  
  spawnHelperProcess: ->
    @child = childProcess.spawn 'node', [helperPath, @debug],
      {detached:yes, stdio: ['ignore', 'ignore', 'ignore']}
    log 'helper process spawned on pid', @child.pid, 'with pipe', hlprUtils.pipePath
    @spawnedProcess = yes
    setImmediate =>
      @connectToPipeServer()

  send: (cmd, msg) -> 
    msg.cmd = cmd
    @pipe.write JSON.stringify msg
    
  # asdf
  
  scanned: (msg) ->
    log 'scanned', msg
    @send 'getFilesForWord',  
      word:         'asdf'
      caseSensitive: yes
      exactWord:     yes
      assign:        yes
      none:          yes
    
  filesForWord: (msg) ->
    log 'filesForWord', msg

  destroy: ->
    @child = null
    @pipe.destroy()
    @pipe = null

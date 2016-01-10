
log = require('./utils') 'main'

fs      = require 'fs'
util    = require 'util'
SubAtom = require 'sub-atom'
Helper  = require './helper'

module.exports =
  config:
    dataPath:
      title: 'Data Directory'
      description: 'Path to directory to hold .find-all-files.data'
      type: 'string'
      default: '~/.atom'
      
    paths:
      title: 'Project & Parents'
      description: 'Paths of projects and/or directories containing projects ' +
                   '(separate with commas)'
      type: 'string'
      default: '~/.atom/projects'
      
    wordRegex:
      title: 'Word Regex'
      description: 'Regular expression to match words'
      type: 'string'
      default: '[a-zA-Z_\\$]\\w*'
      
    suffixes:
      title: 'File Suffixes'
      description: 'Search only in files with these suffixes (separate with commas)'
      type: 'string'
      default: 'coffee,js'
      
    gitignore:
      title: 'Ignore files in .gitignore'
      type: 'boolean'
      default: yes
      
  activate: ->
    @helper = new Helper @getConfig()
    atom.config.onDidChange 'find-all-words.dataPath',  => @updateConfig()
    atom.config.onDidChange 'find-all-words.paths',     => @updateConfig()
    atom.config.onDidChange 'find-all-words.suffixes',  => @updateConfig()
    atom.config.onDidChange 'find-all-words.wordRegex', => @updateConfig()
    atom.config.onDidChange 'find-all-words.gitignore', => @updateConfig()
    
  updateConfig: ->
    @helper.send 'updateOpts', @getConfig()
    
  getConfig: ->
    pathsStr = atom.config.get 'find-all-words.paths'
    paths = (path for path in pathsStr.split(/\s|,/g) when path)
      
    suffixes = {}
    suffixesStr = atom.config.get 'find-all-words.suffixes'
    if /,\s*,/.test suffixesStr then suffixes.empty = yes
    for suffix in suffixesStr.split(/\s|,/g) when suffix
      if suffix is '.' then suffixes.dot = yes
      else suffixes['.' + suffix.toLowerCase()] = yes

    return {    
      wordRegex: atom.config.get 'find-all-words.wordRegex'
      dataPath:  atom.config.get 'find-all-words.dataPath'
      gitignore: atom.config.get 'find-all-words.gitignore' 
      paths, suffixes
    }
    
    # @helper.ready (err) ->
    #   if err then log 'helper ready err', err; return
    #   log 'ready'
    #   @helper.send cmd: 'hello'
    
    # @subs = new SubAtom
  #   @subs.add atom.commands.add 'atom-workspace', 'find-all-words:open': => @open()
  #   @subs.add atom.commands.add 'atom-workspace', 'core:confirm':  => @submit()
  #   @subs.add atom.commands.add 'atom-workspace', 'core:cancel':   => @close()
  # 
  # open: ->
  #   if @panel then @close()
  # 
  #   if not (@editor = atom.workspace.getActiveTextEditor())
  #     console.log 'find-all-words: Active Pane Is Not A Text Editor'
  #     return
  #     
  #   dialog = document.createElement "div"
  #   dialog.setAttribute 'style', 'width:100%'
  #   dialog.innerHTML = """
  #     <div style="position:relative; display:inline-block; margin-right:10px;">
  #         <label  for="find-all-words-clipin">
  #           <input id="find-all-words-clipin" type="checkbox">
  #           Clipboard
  #         </label>
  #       <br>
  #         <label  for="find-all-words-selin">
  #           <input id="find-all-words-selin" type="checkbox" checked>
  #           Selection
  #         </label>
  #     </div>
  #     
  #     <div style="position:relative; top:-12px; display:inline-block; ">
  #       <div style="position:relative; top:2px; display:inline-block; margin-right:10px; 
  #                   font-size:14px; font-weight:bold"> 
  #         =&gt 
  #       </div>
  #       
  #       <input id="find-all-words-cmd" class="native-key-bindings" 
  #              placeholder="Enter shell command" 
  #              style="width:240px; font-size:14px; display:inline-block">
  #       
  #       <div style="position:relative; margin-left:10px; display:inline-block; 
  #                   font-size:14px; font-weight:bold"> 
  #         =&gt
  #       </div>
  #     </div>
  #     
  #     <div style="position:relative; display:inline-block; margin-left:10px;'>
  #         <label  for="find-all-words-clipout">
  #           <input id="find-all-words-clipout" type="checkbox">
  #           Clipboard
  #         </label>
  #       <br>
  #         <label  for="find-all-words-selout">
  #         <input id="find-all-words-selout" type="checkbox" checked>
  #         Selection
  #         </label>
  #     </div>
  #   """
  #   @panel = atom.workspace.addModalPanel item: dialog
  #   @input = document.getElementById 'find-all-words-cmd'
  #   @input.focus()
  #   @newlineSub = new SubAtom
  #   @newlineSub.add @input, 'keypress', (e) =>
  #     if e.which is 13 then @submit(); return false
  # 
  # submit: ->
  #   if @panel
  #     editorPath = @editor.getPath()
  #     for projPath in atom.project.getPaths()
  #       break if editorPath[0...projPath.length] is projPath
  #     stdin = ''
  #     if document.getElementById('find-all-words-clipin').checked
  #       stdin += atom.clipboard.read()
  #     if document.getElementById('find-all-words-selin').checked
  #       stdin += @editor.getSelectedText()
  #     selout  = document.getElementById('find-all-words-selout' ).checked
  #     clipout = document.getElementById('find-all-words-clipout').checked
  #     @process projPath, @input.value, stdin, selout, clipout
  #     @close()
  # 
  #   
  # process: (cwd, cmd, stdin, selout, clipout) ->
  #   try
  #     stdout = exec cmd, {cwd, input: stdin, timeout: 5e3}
  #     stdout = stdout.toString()
  #   catch e
  #     atom.confirm
  #       message: 'Exception:'
  #       detailedMessage:  e.stderr.toString()
  #       buttons: Close: => @close()
  #     return
  #   if selout
  #     range = @editor.getSelectedBufferRange()
  #     @editor.setTextInBufferRange range, stdout
  #   if clipout
  #     atom.clipboard.write stdout
  #   
  # close: ->
  #   if @panel
  #     @panel.destroy()
  #     @newlineSub.dispose()
  #     atom.views.getView(@editor).focus()
  #   @panel = null
  
  deactivate: ->
    # @close()
    # @subs.dispose()

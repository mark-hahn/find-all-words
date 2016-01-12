
log = require('./utils') 'main'

fs      = require 'fs'
util    = require 'util'
SubAtom = require 'sub-atom'
Helper  = require './helper'
config  = require './config'

module.exports =
  config: config.config
      
  activate: ->
    @subs = new SubAtom
    @helper = new Helper config.get()
    config.onChange @subs, => @helper.send 'updateOpts', config.get()
    
  #   
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

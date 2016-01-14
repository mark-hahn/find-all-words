
log  = require('./utils') 'conf'
path = require 'path'

module.exports =
  config:
    dataPath:
      title: 'Data Directory'
      description: 'Path to directory to hold .find-all-files.data'
      type: 'string'
      default: '~/.atom'
      
    paths:
      title: 'Project & Parents'
      description: 'Paths to projects and/or directories containing projects ' +
                   '(separate with commas)'
      type: 'string'
      default: '~/.atom/projects'
      
    suffixes:
      title: 'File Suffixes'
      description: 'Search only in files with these suffixes (separate with commas)'
      type: 'string'
      default: 'coffee, js'
      
    gitignore:
      title: 'Use git'
      description: 'All projects have .git folder and ignore files in .gitignore'
      type: 'boolean'
      default: yes
          
  onChange: (subs, cb) ->
    subs.add atom.config.onDidChange 'find-all-words.dataPath',  cb
    subs.add atom.config.onDidChange 'find-all-words.paths',     cb
    subs.add atom.config.onDidChange 'find-all-words.suffixes',  cb
    subs.add atom.config.onDidChange 'find-all-words.gitignore', cb

  get: ->
    pathsStr = atom.config.get 'find-all-words.paths'
    paths = (projPath for projPath in pathsStr.split(/\s|,/g) when projPath)
    
    suffixes = {}
    suffixesStr = atom.config.get 'find-all-words.suffixes'
    if /,\s*,/.test suffixesStr then suffixes.empty = yes
    for suffix in suffixesStr.split(/\s|,/g) when suffix
      if suffix is '.' then suffixes.dot = yes
      else 
        suffixes['.' + suffix.toLowerCase().replace /\./g, ''] = yes
        
    dataPathStr = atom.config.get 'find-all-words.dataPath'
    dataPath = path.join dataPathStr, '.find-all-files.data'
    
    return {    
      gitignore: atom.config.get 'find-all-words.gitignore' 
      dataPath, paths, suffixes
    }

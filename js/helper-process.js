// Generated by CoffeeScript 1.9.3
(function() {
  var FILE_IDX_INC, HelperProcess, crypto, fs, gitParser, log, path, util,
    slice = [].slice;

  log = function() {
    var args;
    args = 1 <= arguments.length ? slice.call(arguments, 0) : [];
    return console.log.apply(console, args);
  };

  fs = require('fs-plus');

  path = require('path');

  util = require('util');

  crypto = require('crypto');

  gitParser = require('gitignore-parser');

  FILE_IDX_INC = 32;

  HelperProcess = (function() {
    function HelperProcess() {
      process.on('message', (function(_this) {
        return function(msg) {
          return _this[msg.cmd](msg);
        };
      })(this));
      process.on('disconnect', (function(_this) {
        return function() {
          return _this.destroy();
        };
      })(this));
    }

    HelperProcess.prototype.send = function(msg) {
      return process.send(msg);
    };

    HelperProcess.prototype.init = function(opts) {
      this.opts = opts;
      this.fileCount = 0;
      this.wordCount = 0;
      this.filesByPath = {};
      this.filesByIndex = [];
      this.wordTrie = {};
      return this.checkAllProjects();
    };

    HelperProcess.prototype.updateOpts = function(opts) {
      this.opts = opts;
      this.regexStr = null;
      return this.checkAllProjects();
    };

    HelperProcess.prototype.getFilesForWord = function(msg) {
      var filePaths, i, idx, len, node, onFileIndexes, ref, ref1, ref2, whole, word;
      word = msg.word, whole = msg.whole;
      filePaths = {};
      node = (ref = this.getAddWordNodeFromTrie(word)) != null ? ref : {
        fi: []
      };
      ref2 = (ref1 = node.fi) != null ? ref1 : [];
      for (i = 0, len = ref2.length; i < len; i++) {
        idx = ref2[i];
        if (idx) {
          filePaths[this.filesByIndex[idx].path] = true;
        }
      }
      if (!whole) {
        onFileIndexes = (function(_this) {
          return function(indexes) {
            var j, len1, results;
            results = [];
            for (j = 0, len1 = indexes.length; j < len1; j++) {
              idx = indexes[j];
              if (idx) {
                results.push(filePaths[_this.filesByIndex[idx].path] = true);
              }
            }
            return results;
          };
        })(this);
        this.traverseWordTrie(node, onFileIndexes);
      }
      return this.send({
        cmd: 'filesForWord',
        word: word,
        files: Object.keys(filePaths)
      });
    };

    HelperProcess.prototype.checkAllProjects = function() {
      var i, j, len, len1, optPath, projPath, ref, ref1;
      this.setAllFileRemoveMarkers();
      ref = this.opts.paths;
      for (i = 0, len = ref.length; i < len; i++) {
        optPath = ref[i];
        if (this.checkOneProject(optPath)) {
          continue;
        }
        ref1 = fs.listSync(optPath);
        for (j = 0, len1 = ref1.length; j < len1; j++) {
          projPath = ref1[j];
          if (fs.isDirectorySync(projPath)) {
            this.checkOneProject(projPath);
          }
        }
      }
      this.removeMarkedFiles();
      return this.send({
        cmd: 'ready',
        fileCount: this.fileCount,
        wordCount: this.wordCount
      });
    };

    HelperProcess.prototype.checkOneProject = function(projPath) {
      var e, giPath, gitignore, onDir, onFile;
      if (this.opts.gitignore && !fs.isDirectorySync(path.join(projPath, '.git'))) {
        return false;
      }
      gitignore = this.opts.gitignore && (function() {
        try {
          giPath = path.join(projPath, '.gitignore');
          return gitParser.compile(fs.readFileSync(giPath, 'utf8'));
        } catch (_error) {
          e = _error;
          return null;
        }
      })();
      log('gitignore', projPath, gitignore);
      onDir = (function(_this) {
        return function(dirPath) {
          var dir;
          dir = path.basename(dirPath);
          return dir !== '.git' && (!gitignore || gitignore.accepts(dir));
        };
      })(this);
      onFile = (function(_this) {
        return function(filePath) {
          var base, sfx;
          filePath = filePath.toLowerCase();
          base = path.basename(filePath);
          sfx = path.extname(filePath);
          if (((sfx === '' && _this.opts.suffixes.empty) || (sfx === '.' && _this.opts.suffixes.dot) || _this.opts.suffixes[sfx]) && (!gitignore || gitignore.accepts(base))) {
            return _this.checkOneFile(filePath);
          }
        };
      })(this);
      fs.traverseTreeSync(projPath, onFile, onDir);
      return true;
    };

    HelperProcess.prototype.checkOneFile = function(filePath) {
      var e, fileIndex, fileMd5, fileTime, i, len, oldFile, parts, ref, stats, text, word, wordList, wordRegex, words;
      this.fileCount++;
      try {
        stats = fs.statSync(filePath);
      } catch (_error) {
        e = _error;
        log('ERROR on file stat, skipping', filePath, e.message);
        return;
      }
      if (!stats.isFile()) {
        return;
      }
      if ((oldFile = this.filesByPath[filePath])) {
        delete oldFile.remove;
      }
      fileTime = stats.mtime.getTime();
      if (fileTime === (oldFile != null ? oldFile.time : void 0)) {
        return;
      }
      try {
        text = fs.readFileSync(filePath);
      } catch (_error) {
        e = _error;
        log('ERROR reading file, skipping', filePath, e.message);
        return;
      }
      if (!this.regexStr) {
        try {
          new RegExp(this.opts.wordRegex);
          this.regexStr = this.opts.wordRegex;
        } catch (_error) {
          e = _error;
          log('ERROR parsing word regex, using "[a-zA-Z_\\$]\\w*"', regexStr, e.message);
          this.regexStr = "[a-zA-Z_\\$]\\w*";
        }
      }
      words = {};
      wordRegex = new RegExp(this.regexStr, 'g');
      while ((parts = wordRegex.exec(text))) {
        words[parts[0]] = true;
      }
      wordList = Object.keys(words).sort();
      fileIndex = (ref = oldFile != null ? oldFile.index : void 0) != null ? ref : this.filesByIndex.length;
      fileMd5 = crypto.createHash('md5').update(wordList.join(';')).digest("hex");
      this.filesByPath[filePath] = this.filesByIndex[fileIndex] = {
        path: filePath,
        index: fileIndex,
        time: fileTime,
        md5: fileMd5
      };
      if (fileMd5 === (oldFile != null ? oldFile.md5 : void 0)) {
        return;
      }
      if (oldFile) {
        this.removeFileIndexFromTrie(oldFile.index);
      }
      for (i = 0, len = wordList.length; i < len; i++) {
        word = wordList[i];
        this.addWordFileIndexToTrie(word, fileIndex);
      }
      return this.normalizeTrie();
    };

    HelperProcess.prototype.setAllFileRemoveMarkers = function() {
      var file, i, len, ref, results;
      ref = this.filesByIndex;
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        file = ref[i];
        if (file) {
          results.push(file.remove = true);
        }
      }
      return results;
    };

    HelperProcess.prototype.removeMarkedFiles = function() {
      var file, i, len, ref, results;
      ref = this.filesByIndex;
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        file = ref[i];
        if (!(file != null ? file.remove : void 0)) {
          continue;
        }
        this.removeFileIndexFromTrie(file.index);
        delete this.filesByPath[file.path];
        results.push(delete this.filesByIndex[file.index]);
      }
      return results;
    };

    HelperProcess.prototype.addWordFileIndexToTrie = function(word, fileIndex) {
      var fileIdx, fileIndexes, i, idx, len, newFileIndexes, newLen, node, oldLen;
      this.wordCount++;
      node = this.getAddWordNodeFromTrie(word, true);
      fileIndexes = node.fi != null ? node.fi : node.fi = new Int16Array(FILE_IDX_INC);
      for (idx = i = 0, len = fileIndexes.length; i < len; idx = ++i) {
        fileIdx = fileIndexes[idx];
        if (!(fileIdx === 0)) {
          continue;
        }
        fileIndexes[idx] = fileIndex;
        return;
      }
      oldLen = fileIndexes.length;
      newLen = oldLen + FILE_IDX_INC;
      newFileIndexes = new Int16Array(newLen);
      newFileIndexes.fill(0, 0, FILE_IDX_INC - 1);
      newFileIndexes[FILE_IDX_INC - 1] = fileIndex;
      newFileIndexes.set(fileIndexes, FILE_IDX_INC);
      return node.fi = newFileIndexes;
    };

    HelperProcess.prototype.getAddWordNodeFromTrie = function(word, add) {
      var i, lastNode, len, letter, node;
      node = this.wordTrie;
      for (i = 0, len = word.length; i < len; i++) {
        letter = word[i];
        lastNode = node;
        if (!(node = node[letter])) {
          if (!add) {
            return null;
          }
          node = lastNode[letter] = {};
        }
      }
      return node;
    };

    HelperProcess.prototype.removeFileIndexFromTrie = function(fileIndex) {
      return this.traverseWordTrie(function(fileIndexes) {
        var fileIdx, i, idx, len;
        for (idx = i = 0, len = fileIndexes.length; i < len; idx = ++i) {
          fileIdx = fileIndexes[idx];
          if (!(fileIdx === fileIndex)) {
            continue;
          }
          fileIndexes[idx] = 0;
          return;
        }
      });
    };

    HelperProcess.prototype.traverseWordTrie = function(root, onFileIndexes) {
      var visitNode;
      if (!onFileIndexes) {
        onFileIndexes = root;
        root = this.wordTrie;
      }
      visitNode = function(node, word) {
        var childNode, haveChild, letter;
        haveChild = false;
        for (letter in node) {
          childNode = node[letter];
          if (letter === 'fi') {
            if (onFileIndexes(childNode) === false) {
              delete node.fi;
            } else {
              haveChild = true;
            }
          } else {
            if (!visitNode(childNode, word + letter)) {
              delete node[letter];
            } else {
              haveChild = true;
            }
          }
        }
        return haveChild;
      };
      return visitNode(root, '');
    };

    HelperProcess.prototype.normalizeTrie = function() {
      return this.traverseWordTrie((function(_this) {
        return function(fileIndexes) {
          return Array.prototype.sort.call(fileIndexes);
        };
      })(this));
    };

    HelperProcess.prototype.destroy = function() {};

    return HelperProcess;

  })();

  new HelperProcess;

}).call(this);

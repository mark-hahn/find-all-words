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

  FILE_IDX_INC = 1;

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
      this.filesByPath = {};
      this.filesByIndex = [];
      this.wordTrie = {};
      return this.scanAll();
    };

    HelperProcess.prototype.updateOpts = function(opts) {
      this.opts = opts;
      this.regexStr = null;
      return this.scanAll();
    };

    HelperProcess.prototype.scanAll = function() {
      var i, j, len, len1, optPath, projPath, ref, ref1;
      this.fileCount = 0;
      this.wordCount = 0;
      this.setAllFileRemoveMarkers();
      ref = this.opts.paths;
      for (i = 0, len = ref.length; i < len; i++) {
        optPath = ref[i];
        log('optPath', optPath);
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
      this.saveAllData();
      return this.send({
        cmd: 'scanned',
        fileCount: this.fileCount,
        wordCount: this.wordCount
      });
    };

    HelperProcess.prototype.getFilesForWord = function(msg) {
      var assign, caseSensitive, exactWord, filePaths, none, onFileIndexes, word;
      word = msg.word, caseSensitive = msg.caseSensitive, exactWord = msg.exactWord, assign = msg.assign, none = msg.none;
      filePaths = {};
      onFileIndexes = (function(_this) {
        return function(indexes) {
          var i, idx, len, results;
          results = [];
          for (i = 0, len = indexes.length; i < len; i++) {
            idx = indexes[i];
            if (idx) {
              results.push(filePaths[_this.filesByIndex[idx].path] = true);
            }
          }
          return results;
        };
      })(this);
      if (assign && none) {
        this.traverseWordTrie(word, caseSensitive, exactWord, 'all', onFileIndexes);
      } else {
        if (assign) {
          this.traverseWordTrie(word, caseSensitive, exactWord, 'assign', onFileIndexes);
        }
        if (none) {
          this.traverseWordTrie(word, caseSensitive, exactWord, 'none', onFileIndexes);
        }
      }
      return this.send({
        cmd: 'filesForWord',
        files: Object.keys(filePaths),
        word: word,
        caseSensitive: caseSensitive,
        exactWord: exactWord,
        assign: assign,
        none: none
      });
    };

    HelperProcess.prototype.checkOneProject = function(projPath) {
      var e, giPath, gitignore, gitignoreTxt, onDir, onFile;
      if (this.opts.gitignore && !fs.isDirectorySync(path.join(projPath, '.git'))) {
        return false;
      }
      gitignore = this.opts.gitignore && (function() {
        try {
          giPath = path.join(projPath, '.gitignore');
          gitignoreTxt = fs.readFileSync(giPath, 'utf8');
          return gitParser.compile(gitignoreTxt + '\n.git\n');
        } catch (_error) {
          e = _error;
          return null;
        }
      })();
      onDir = (function(_this) {
        return function(dirPath) {
          return !gitignore || gitignore.accepts(path.basename(dirPath));
        };
      })(this);
      onFile = (function(_this) {
        return function(filePath) {
          var sfx;
          sfx = path.extname(filePath).toLowerCase();
          if (((sfx === '' && _this.opts.suffixes.empty) || (sfx === '.' && _this.opts.suffixes.dot) || _this.opts.suffixes[sfx]) && (!gitignore || gitignore.accepts(path.basename(filePath)))) {
            return _this.checkOneFile(filePath);
          }
        };
      })(this);
      fs.traverseTreeSync(projPath, onFile, onDir);
      return true;
    };

    HelperProcess.prototype.checkOneFile = function(filePath) {
      var after, allWords, before, e, file, fileIndex, fileMd5, fileTime, i, idx, j, k, len, len1, len2, oldFile, parts, ref, results, stats, text, word, wordRegex, wordsAssign, wordsAssignList, wordsNone, wordsNoneList;
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
      wordsAssign = {};
      wordsNone = {};
      wordRegex = new RegExp(this.opts.wordRegexStr, 'g');
      while ((parts = wordRegex.exec(text))) {
        word = parts[0];
        if (!(word in wordsAssign)) {
          idx = wordRegex.lastIndex;
          before = text.slice(0, idx - word.length);
          after = text.slice(idx);
          if (/^\s*=/.test(after) || /function\s+$/.test(before) || /for\s+(\w+,)?\s*$/.test(before) && /^\s+(in|of)\s/.test(after) || /\{([^,}]*,)*([^,:}]+:)?\s*$/.test(before) && /^\s*(,[^,}]* )*\}\s*=/.test(after) || /\[([^,\]]*,)*\s*$/.test(before) && /^\s*(,[^,\]]*)*\]\s*=/.test(after)) {
            wordsAssign[word] = true;
            delete wordsNone[word];
          } else {
            wordsNone[word] = true;
          }
        }
      }
      wordsAssignList = Object.keys(wordsAssign).sort();
      wordsNoneList = Object.keys(wordsNone).sort();
      allWords = wordsAssignList.join(';') + ';;' + wordsNoneList.join(';');
      fileMd5 = crypto.createHash('md5').update(allWords).digest("hex");
      if (!(fileIndex = oldFile != null ? oldFile.index : void 0)) {
        ref = this.filesByIndex;
        for (idx = i = 0, len = ref.length; i < len; idx = ++i) {
          file = ref[idx];
          if (!file) {
            break;
          }
        }
        fileIndex = idx;
      }
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
      for (j = 0, len1 = wordsAssignList.length; j < len1; j++) {
        word = wordsAssignList[j];
        this.addWordFileIndexToTrie(word, fileIndex, 'as');
      }
      results = [];
      for (k = 0, len2 = wordsNoneList.length; k < len2; k++) {
        word = wordsNoneList[k];
        results.push(this.addWordFileIndexToTrie(word, fileIndex, 'no'));
      }
      return results;
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

    HelperProcess.prototype.removeFileIndexFromTrie = function(fileIndex) {
      return this.traverseWordTrie('', false, false, 'all', function(fileIndexes) {
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

    HelperProcess.prototype.addWordFileIndexToTrie = function(word, fileIndex, type) {
      var fileIdx, fileIndexes, i, idx, len, newFileIndexes, newLen, node, oldLen;
      this.wordCount++;
      node = this.getAddWordNodeFromTrie(word);
      fileIndexes = node[type] != null ? node[type] : node[type] = new Int16Array(FILE_IDX_INC);
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
      newFileIndexes[FILE_IDX_INC - 1] = fileIndex;
      newFileIndexes.set(fileIndexes, FILE_IDX_INC);
      return node[type] = newFileIndexes;
    };

    HelperProcess.prototype.getAddWordNodeFromTrie = function(word) {
      var i, lastNode, len, letter, node;
      node = this.wordTrie;
      for (i = 0, len = word.length; i < len; i++) {
        letter = word[i];
        lastNode = node;
        if (!(node = node[letter])) {
          node = lastNode[letter] = {};
        }
      }
      return node;
    };

    HelperProcess.prototype.traverseWordTrie = function(wordIn, caseSensitive, exactWord, type, onFileIndexes) {
      var visitNode;
      visitNode = function(node, wordLeft, wordForNode) {
        var childNode, letter, results;
        if (!wordLeft) {
          if (node.as && (type === 'all' || type === 'assign')) {
            onFileIndexes(node.as, wordForNode, 'as');
          }
          if (node.no && (type === 'all' || type === 'none')) {
            onFileIndexes(node.no, wordForNode, 'no');
          }
          if (exactWord) {
            return;
          }
        }
        results = [];
        for (letter in node) {
          childNode = node[letter];
          if (letter.length === 1) {
            if (!wordLeft || letter === wordLeft[0] || !caseSensitive && letter.toLowerCase() === wordLeft[0].toLowerCase()) {
              results.push(visitNode(childNode, wordLeft.slice(1), wordForNode + letter));
            } else {
              results.push(void 0);
            }
          }
        }
        return results;
      };
      return visitNode(this.wordTrie, wordIn, '');
    };

    HelperProcess.prototype.saveAllData = function() {
      var fd, tmpPath, writeJson;
      log('saveAllData start');
      tmpPath = this.opts.dataPath + '.tmp';
      fd = fs.openSync(tmpPath, 'w');
      writeJson = function(obj) {
        var buf, json, jsonLen;
        json = JSON.stringify(obj);
        jsonLen = Buffer.byteLength(json);
        buf = new Buffer(4 + jsonLen);
        buf.writeInt32BE(jsonLen, 0);
        buf.write(json, 4);
        return fs.writeSync(fd, buf, 0, buf.length);
      };
      writeJson(this.opts);
      writeJson(this.filesByIndex);
      this.traverseWordTrie('', false, false, 'all', function(fileIndexes, word, type) {
        var buf, bufIdx, hdr, hdrLen;
        hdr = word + ';' + type;
        hdrLen = Buffer.byteLength(hdr);
        buf = new Buffer(4 + hdrLen);
        buf.writeInt32BE(hdrLen, 0);
        buf.write(hdr, 4);
        fs.writeSync(fd, buf, 0, buf.length);
        bufIdx = new Buffer(fileIndexes.buffer);
        buf = new Buffer(4);
        buf.writeInt32BE(bufIdx.length, 0);
        fs.writeSync(fd, buf, 0, buf.length);
        return fs.writeSync(fd, bufIdx, 0, bufIdx.length);
      });
      fs.closeSync(fd);
      fs.removeSync(this.opts.dataPath);
      return fs.moveSync(tmpPath, this.opts.dataPath);
    };

    HelperProcess.prototype.loadAllData = function() {};

    HelperProcess.prototype.destroy = function() {};

    return HelperProcess;

  })();

  new HelperProcess;

}).call(this);

// Generated by CoffeeScript 1.9.3
(function() {
  var dbg, debug, fs, log, logPath, logRaw, moment, path, version,
    slice = [].slice;

  exports.version = version = '1';

  fs = require('fs-plus');

  path = require('path');

  moment = require('moment');

  logPath = path.join(process.cwd(), 'process.log');

  fs.removeSync(logPath);

  exports.logRaw = logRaw = function() {
    var args;
    args = 1 <= arguments.length ? slice.call(arguments, 0) : [];
    return fs.appendFileSync(logPath, args.join(' ') + '\n');
  };

  exports.log = log = function() {
    var args, time;
    args = 1 <= arguments.length ? slice.call(arguments, 0) : [];
    time = moment().format('MM-DD HH:mm:ss');
    return logRaw.apply(null, [time].concat(slice.call(args)));
  };

  exports.debug = debug = process.argv[2];

  exports.dbg = dbg = (debug ? log : function() {});

  dbg('-- debug mode');

  exports.pipePath = process.platform === 'win32' ? "\\\\.\\pipe\\atomFaw" + version + ".sock" : "/tmp/atomFaw" + version + ".sock";

}).call(this);

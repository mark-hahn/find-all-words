// Generated by CoffeeScript 1.9.3
(function() {
  var logWithTime, moment,
    slice = [].slice;

  moment = require('moment');

  logWithTime = function() {
    var args, time;
    args = 1 <= arguments.length ? slice.call(arguments, 0) : [];
    time = moment().format('MM-DD HH:mm:ss');
    return console.log.apply(console, [time].concat(slice.call(args)));
  };

  module.exports = function(modName) {
    return function() {
      var args;
      args = 1 <= arguments.length ? slice.call(arguments, 0) : [];
      return logWithTime.apply(null, ['find-all-words', modName.toLowerCase() + ':'].concat(slice.call(args)));
    };
  };

}).call(this);

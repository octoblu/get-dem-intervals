_           = require 'lodash'
async       = require 'async'
commander   = require 'commander'
colors      = require 'colors'
redis       = require 'redis'
packageJSON = require './package.json'

INTERVAL_TYPES = ['operation:interval', 'operation:schedule', 'operation:throttle', 'operation:debounce']

class Command
  constructor: ->

  parseOptions: =>
    commander
      .version packageJSON.version
      .option '-r, --redis <redis://localhost:6379>', 'Redis server to hit (env: MRP_REDIS_URL)'
      .parse process.argv

    redisUrl = commander.redis ? process.env.MRP_REDIS_URL || 'redis://localhost:6379'
    @client = redis.createClient redisUrl

  panic: (error) =>
    console.error colors.red error.message
    console.error error.stack
    process.exit 1

  run: =>
    @parseOptions()

    @flowKeys (error, keys) =>
      return @panic error if error?

      async.mapSeries keys, @getIntervalConfigs, (error, groupedIntervalConfigs) =>
        return @panic error if error?
        intervalConfigs = _.flatten groupedIntervalConfigs
        console.log JSON.stringify(intervalConfigs, null, 2)
        process.exit 0


  flowKeys: (callback) =>
    @client.keys '*', (error, keys) =>
      return callback error if error?
      callback null, @filterAllButFlows(keys)

  filterAllButFlows: (keys) =>
    regex = new RegExp /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
    _.filter keys, (key) =>
      regex.test key

  filterAllButConfigs: (keys) =>
    regex = new RegExp /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\/config$/
    _.filter keys, (key) =>
      regex.test key

  getConfigKeys: (key, callback) =>
    @client.hkeys key, (error, subKeys) =>
      return callback error if error?
      callback null, @filterAllButConfigs subKeys

  getIntervalConfigs: (flowKey, callback) =>
    process.stderr.write(".");
    @getConfigKeys flowKey, (error, configKeys) =>
      return callback error if error?

      @getConfigs flowKey, configKeys, (error, configs) =>
        return callback error if error?

        intervalConfigs = _.filter configs, (config) => _.includes INTERVAL_TYPES, config.type
        callback null, _.map intervalConfigs, (config) =>
          sendTo: flowKey
          nodeId: config.id
          intervalTime: @multipler(config.timeoutUnits) * (config.repeat ? config.timeout)
          cronString: config.crontab
          nonce: config.nanocyte.nonce

  getConfigs: (flowKey, configKeys, callback) =>
    async.map configKeys, (configKey, cb) =>
      @client.hget flowKey, configKey, (error, config) =>
        return cb error if error?
        return cb null, JSON.parse(config)
    , callback

  multipler: (units) =>
    return 1000 if units == 'seconds'
    return 1000*60 if units == 'minutes'
    return 1000*60*60 if units == 'hours'
    return 1


command = new Command
command.run()

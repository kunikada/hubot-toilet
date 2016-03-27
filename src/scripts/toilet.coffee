# Description:
#   Interact with IoT device through MQTT server
#
# Dependencies:
#   mqtt: *
#
# Configuration:
#   HUBOT_ESP_MAC
#   HUBOT_CHATWORK_INTERVAL_SEC
#   HUBOT_MQTT_URL
#   HUBOT_MQTT_AUTH
#
#   Auth format is "username:password".
#
# Commands:
#   hubot get <param> - get param's value
#   hubot set <param> <value> - set value in param 
#   空いてますか？ - check whether the restroom is empty, and reply 
#
# Notes:
#   None
#
# Author:
#   kunikada

mqtt = require 'mqtt'

class EspHelper
  wait: []

  constructor: ->
    mac = process.env.HUBOT_ESP_MAC
    @mqtt = new MqttHelper mac

  isDead: ->
    now = Date.now() / 1000 | 0
    sleepmin = @mqtt.get('sleepmin_oncheck') or 10
    resetTime = parseInt @mqtt.get('resetTime'), 10
    now > resetTime + sleepmin * 60 * 2

  isEmpty: ->
    @mqtt.get('status') is '2'

  isntEmpty: -> not @isEmpty()

  isntWaiting: ->
    @wait.length is 0

  pushWait: (envelope) ->
    for human in @wait
      if human.envelope.room is envelope.room and
        human.envelope.user is envelope.user
          return

    now = Date.now() / 1000 | 0
    human =
      envelope: envelope
      createTime: now
    @wait.push human

  countWait: ->
    @wait.length

  calcWaitMinutes: ->
    waitTime = @mqtt.waitTime
    sum = 0
    for time in waitTime
      sum += time
    Math.floor sum / waitTime.length / 60

  listen: (robot) ->
    interval = process.env.HUBOT_CHATWORK_INTERVAL_SEC or 5
    setInterval =>
      return if @isntWaiting() or @isntEmpty()

      now = Date.now() / 1000 | 0
      human = @wait[0]
      if human.noticeTime? 
        @wait.shift() if now - human.noticeTime > @calcWaitMinutes() * 60 
        return

      human.noticeTime = now
      robot.reply human.envelope, '空きました！'
    , interval * 1000    

class MqttHelper
  data: []
  waitTime: [300]

  constructor: (@mac) ->
    auth = process.env.HUBOT_MQTT_AUTH.split ':'
    url = process.env.HUBOT_MQTT_URL
    options =
      username: auth[0]
      password: auth[1]
    @client = mqtt.connect url, options

    @client.subscribe "reset/#{@mac}"
    @client.subscribe "#{@mac}/#"

    @client.on 'message', (topic, payload) =>
      message = payload.toString()
      if topic is "#{@mac}/result" and
        @get('status') is '1' and
          message.split(' ')[1] is '2'
            @waitTime.unshift (message.split(' ')[0] - @get('resultTime'))
            @waitTime = @waitTime.slice 0, 9

      @data[topic] = message

  get: (param) ->
    @data["#{@mac}/result"] ?= ''
    switch param
      when 'resetTime'
        @data["reset/#{@mac}"]
      when 'resultTime'
        @data["#{@mac}/result"].split(' ')[0]
      when 'status'
        @data["#{@mac}/result"].split(' ')[1]
      when 'lux'
        @data["#{@mac}/result"].split(' ')[2]
      else
        @data["#{@mac}/settings/#{param}"]

  set: (param, value) ->
    options = 
      retain: true
    @client.publish "#{@mac}/settings/#{param}", value, options

module.exports = (robot) ->
  espHelper = new EspHelper

  robot.hear /(こんこん|コンコン|(空|あ)いて(る|ますか?)[?？])/, (res) ->
    if espHelper.isDead()
      res.reply "へんじがない。\nただのしかばねのようだ。"
      return

    if espHelper.isntWaiting() and espHelper.isEmpty()
      res.reply '安心してください、空いてますよ！'
      return

    espHelper.pushWait res.envelope
    num = espHelper.countWait()
    min = espHelper.calcWaitMinutes() * num
    res.reply "只今の待ち時間は#{min}分です。\n現在あなたを含めて#{num}人待っています。"

  robot.respond /(get|set)\s+(\S+)\s*(\S*)/i, (res) ->
    method = res.match[1]
    param = res.match[2]
    value = res.match[3]
    
    switch method
      when 'get'
        res.send espHelper.mqtt.get param
      when 'set'
        espHelper.mqtt.set param, value

  espHelper.listen robot

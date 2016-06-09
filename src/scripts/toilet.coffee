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

class Time
  @now: ->
    Date.now() / 1000 | 0

  @untilNow: (from) ->
    @now() - from

class EspHelper
  wait: []

  constructor: ->
    mac = process.env.HUBOT_ESP_MAC
    @mqtt = new MqttHelper mac

  isDead: ->
    Time.untilNow(@mqtt.get 'resultTime') > 24 * 60 * 60

  isEmpty: ->
    @mqtt.get('status') is '2'

  isntEmpty: -> not @isEmpty()

  isLeftLighting: ->
    @isntEmpty() and Time.untilNow(@mqtt.get 'resultTime') > 15 * 60

  isntWaiting: ->
    @wait.length is 0

  pushWait: (envelope) ->
    for record, i in @wait
      if record.room is envelope.room and
        record.user is envelope.user
          return i + 1

    @wait.push envelope
    @wait.length

  listen: (robot) ->
    interval = process.env.HUBOT_CHATWORK_INTERVAL_SEC or 5
    setInterval =>
      return if @isntWaiting() or @isntEmpty()

      for envelope in @wait
        message = '空きました!'
        if @wait.length > 1
          message += "\nけど、他にも待っていた人がいたようです。"
        robot.reply envelope, message

      @wait = []
    , interval * 1000    

class MqttHelper
  data: []

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
      @data[topic] = payload.toString()

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

    if espHelper.isLeftLighting()
      res.reply 'もしかして: 電気の消し忘れ'
      return

    if espHelper.isEmpty()
      res.reply '安心してください、空いてますよ！'
      return

    num = espHelper.pushWait res.envelope
    message = '入ってます。'
    if num > 1
      message += "\nあなたで#{num}人目ですよ。"
    res.reply message

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

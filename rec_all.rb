#!/usr/bin/env ruby
Dir.chdir __dir__
require 'pp'
require 'yaml'
require 'bundler/setup'
require 'open-uri'
require 'json'

def api(url)
  json = open(url, 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/48.0.2564.82 Safari/537.36', 'Origin' => 'http://hibiki-radio.jp', 'Referer' => 'http://hibiki-radio.jp/', 'X-Requested-With' => 'XMLHttpRequest', &:read)
  JSON.parse(json)
end

programs = []

page = 1
loop do
  res = api("https://vcms-api.hibiki-radio.jp/api/v1//programs?limit=8&page=#{page}")
  break if res.size != 8

  res.each do |x|
    programs << x['access_id']
  end
  page += 1
end

p programs
puts "----"

programs.each do |program|
  puts "$ ./rec.rb #{program} #{program}"
  p(system("./rec.rb", program, program))

  sleep 1
end


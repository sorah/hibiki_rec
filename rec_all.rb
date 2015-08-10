#!/usr/bin/env ruby
Dir.chdir __dir__
require 'pp'
require 'yaml'
require 'bundler/setup'
require 'open-uri'
require 'nokogiri'

mokuji = Nokogiri::HTML(open('http://hibiki-radio.jp/mokuji', &:read))

programs = mokuji.search('.hbkMokujiTable .hbkMokujiLink2 > a').map {|_| [_.inner_text, _['href']] }

worked_memo = {} # remove repeats

programs.each do |(program_title, program_url)|
  program_html = Nokogiri::HTML(open(program_url, &:read))
  listen_btn_href = program_html.at('a#hbkListenBtn')['href']
  m = listen_btn_href.match(/[?&;]radio_id=(.+?)(?:\z|[&;])/)
  raise unless m

  program_id = m[1]
  if worked_memo[program_id]
    puts "# skipping #{program_url} #{program_title} (#{program_id})"
    next
  end

  program_name = program_url.sub(/\A.*\/description\//, '').gsub(/\//,'_')

  worked_memo[program_id] = true

  puts "$ ./rec.rb #{program_name} #{program_id}"
  p(system("./rec.rb", program_name, program_id))

  sleep 1
end


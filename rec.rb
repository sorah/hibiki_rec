#!/usr/bin/env ruby
Dir.chdir __dir__
require 'pp'
require 'yaml'
require 'time'
require 'bundler/setup'
require 'uri'
require 'open-uri'
require 'nokogiri'

class Radio
  def initialize(radio_id)
    html = open("http://hibiki-radio.jp/?radio_id=#{radio_id}", &:read)
    m = html.match(/channelID:"(.+?)",contentsID:"(.+?)"/)
    raise RuntimeError, 'no channel_id contents_id' unless m

    @channel_id = m[1]
    @contents_id = m[2]
  end

  attr_reader :channel_id, :contents_id

  def description
    @description ||= Description.new(channel_id)
  end

  def content
    @content ||= Content.new(channel_id, contents_id)
  end

  class Description
    def initialize(channel_id)
      url = "http://image.hibiki-radio.jp/uploads/data/channel/#{channel_id}/description.xml"
      @xml = Nokogiri::XML(open(url, &:read))
    end

    def casts
      @xml.search('data cast name').map(&:inner_text)
    end

    def title
      @xml.at('data title').inner_text
    end

    def outline
      @xml.at('data outline').inner_text
    end

    def link
      @xml.at('data link').inner_text
    end
  end

  class Content
    def initialize(channel_id, contents_id)
      url = "http://image.hibiki-radio.jp/uploads/data/channel/#{channel_id}/#{contents_id}.xml"
      @xml = Nokogiri::XML(open(url, &:read))
    end

    def flv
      @xml.at('flv').inner_text.split(/\?/,2)
    end

    def dir
      @xml.at('dir').inner_text
    end

    def protocol
      @xml.at('protocol').inner_text
    end

    def domain
      @xml.at('domain').inner_text
    end

    def playpath
      flv[0]
    end

    def query
      flv[1]
    end

    def app
      "#{dir}?#{query}"
    end

    def rtmp
      "#{protocol}://#{domain}"
    end
  end
end

config_path = "#{__dir__}/config.yml"
if File.exists?(config_path)
  config = YAML.load_file(config_path)
else
  config = {}
end
SAVE_DIR = config['save_dir'] || "#{__dir__}/saved"
HTTP_BASE = config['http_base'] || "http://localhost"

if ARGV.size < 2
  abort "usage: #{$0} name id"
end

name, radio_id = *ARGV

target_dir = File.join(SAVE_DIR,name)
Dir.mkdir(target_dir) unless File.exists?(target_dir)

rss_path = File.join(target_dir, 'index.xml')

radio = Radio.new(radio_id)
content = radio.content
description = radio.description

flv_path = File.join(target_dir,"#{radio.channel_id}-#{radio.contents_id}.flv")
mp3_path = flv_path.sub(/\.flv$/, '.mp3')

exit if File.exist?(flv_path) && File.exist?(mp3_path)

cmd = [
  'rtmpdump',
  '-o', flv_path,
  '--rtmp', content.rtmp,
  '--app', content.app,
  '--playpath', content.playpath,
].map(&:to_s)

puts "==> #{cmd.join(' ')}"
status = nil
out = ""

IO.popen([*cmd, err: [:child, :out]], 'r') do |io|
  th = Thread.new {
    begin
      buf = ""
      until io.eof?
        str =  io.read(10)
        buf << str; out << str
        lines = buf.split(/\r|\n/)
        if 1 < lines.size
          buf = lines.pop
          lines.each do |line|
            puts line
          end
        end
      end
    rescue Exception => e
      p e
      puts e.backtrace
    end
  }

  pid, status = Process.waitpid(io.pid)

  th.kill if th && th.alive?
end

if status && !status.success?
  puts "  * May be fail"
elsif /^Download may be incomplete/ === out
  puts "  * Download may be incomplete"
else
  puts "  * Done!"
end




cmd = ["ffmpeg", "-i", flv_path, "-b:a", "96k", mp3_path]
puts "==> #{cmd.join(' ')}"

status = system(*cmd)
if status
  puts "  * Done!"
  mp3_path
else
  puts "  * Failed ;("
  nil
end

puts "==> Generating RSS"

oldxml = Nokogiri::XML(File.read(rss_path)) if File.exists?(rss_path)
pubdate = Time.now
builder = Nokogiri::XML::Builder.new do |xml|
  xml.rss('xmlns:itunes' => "http://www.itunes.com/dtds/podcast-1.0.dtd", version: '2.0') {
    xml.channel {
      casts = radio.description.casts.join(', ')

      xml.title radio.description.title.gsub(/<.+?>/, ' ')
      xml.description radio.description.outline.gsub(/<.+?>/,'')
      xml.link radio.description.link
      xml['itunes'].author casts

      xml.lastBuildDate Time.now.rfc2822
      xml.language 'ja'

      xml.item {
        xml.title "#{pubdate.strftime("%Y/%m/%d %H:%M")} #{radio.description.title} - #{casts}"
        xml.description radio.description.outline.gsub(/<.+?>/,'')
        link = "#{HTTP_BASE}/#{name}/#{File.basename(mp3_path)}"
        xml.link link
        xml.guid link
        xml.author casts
        xml.pubDate pubdate.rfc2822
        xml.enclosure(url: link, length: File.stat(mp3_path).size, type: 'audio/mpeg')
      }

      if oldxml
        oldxml.search('rss channel item').each do |olditem|
          xml.item {
            xml.title olditem.at('title').text
            xml.description olditem.at('description').text
            xml.link olditem.at('link').text
            xml.guid olditem.at('guid').text
            xml.author olditem.at('author').text
            xml.pubDate olditem.at('pubDate').text
            xml.enclosure(
              url: olditem.at('enclosure')['url'],
              length: olditem.at('enclosure')['length'],
              type: olditem.at('enclosure')['type'],
            )
          }
        end
      end
    }
  }
end

File.write rss_path, builder.to_xml

#!/usr/bin/env ruby
Dir.chdir __dir__
require 'pp'
require 'digest/sha1'
require 'yaml'
require 'time'
require 'bundler/setup'
require 'uri'
require 'open-uri'
require 'nokogiri'
require 'json'

def api(url)
  json = open(url, 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/48.0.2564.82 Safari/537.36', 'Origin' => 'http://hibiki-radio.jp', 'Referer' => 'http://hibiki-radio.jp/', 'X-Requested-With' => 'XMLHttpRequest', &:read)
  JSON.parse(json)
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

program = api("https://vcms-api.hibiki-radio.jp/api/v1/programs/#{radio_id}")
episode = program['episode']

if episode['video']['live_flg'] != false
  $stderr.puts "live_flg is not false"
  exit 1
end

description = program['description']

mp4_path =  File.join(target_dir,"#{radio_id}-v2-#{episode['id']}.mp4")
mp3_path =  File.join(target_dir,"#{radio_id}-v2-#{episode['id']}.mp3")

exit if File.exist?(mp4_path) && File.exist?(mp3_path)

m3u8 = api("https://vcms-api.hibiki-radio.jp/api/v1/videos/play_check?video_id=#{episode['video']['id']}")['playlist_url']

cmd = [
  'ffmpeg',
  '-y',
  '-i', m3u8,
  *%w(-vcodec copy -acodec copy -bsf:a aac_adtstoasc) ,
  mp4_path,
].map(&:to_s)

status = system(*cmd)
if status
  puts "  * Done!"
  mp3_path
else
  puts "  * Failed ;("
  nil
end



puts "==> #{cmd.join(' ')}"
status = nil
out = ""

cmd = ["ffmpeg", "-i", mp4_path, "-vcodec", "none", "-b:a", "96k", mp3_path]
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
      casts = program['cast']

      xml.title program['name'].gsub(/<.+?>/, ' ')
      xml.description program['description'].gsub(/<.+?>/,'')
      xml.link "http://hibiki-radio.jp/description/#{radio_id}"
      xml['itunes'].author casts

      xml.lastBuildDate Time.now.rfc2822
      xml.language 'ja'

      xml.item {
        xml.title "#{pubdate.strftime("%Y/%m/%d %H:%M")} #{program['name']} - #{casts}"
        xml.description program['description'].gsub(/<.+?>/,'')
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

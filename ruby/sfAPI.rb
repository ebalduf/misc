require 'net/http'
require 'uri'
require 'json'
require 'openssl'
 
class SfRPC
  def initialize(service_url)
    @uri = URI.parse(service_url)
  end
 
  def method_missing(name, *args)
    post_body = { 'method' => name, 'params' => Hash[*args.flatten], 'id' => 'jsonrpc' }.to_json
    resp = JSON.parse( http_post_request(post_body) )
    raise JSONRPCError, resp['error'] if resp['error']
    resp['result']
  end
 
  def http_post_request(post_body)
    http = Net::HTTP.new(@uri.host, @uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    request = Net::HTTP::Post.new(@uri.request_uri)
    request.basic_auth(@uri.user, @uri.password)
    request.content_type = 'application/json'
    request.body = post_body
    http.request(request).body
  end
 
  class JSONRPCError < RuntimeError; end
end
 
  sfrpc = SfRPC.new('https://admin:solidfire@10.10.1.84/json-rpc/7.0')
 
# Examples:
 
# Show all drive ids
#sfrpc.ListDrives['drives'].each { |drive| puts drive['serial'] }
puts "accounts"
sfrpc.ListAccounts['accounts'].each { |acct| puts acct['username'] }
puts "add account"
account = sfrpc.AddAccount( "username", "test" )
puts "accounts"
sfrpc.ListAccounts['accounts'].each { |acct| puts acct['username'] }

puts "- create volume"
vol = sfrpc.CreateVolume("name", "test2", "accountID", account['accountID'], "totalSize",1000000000, "enable512e",true, "qos",{ "minIOPS" => 1600, "maxIOPS" => 15000, "burstIOPS" => 15000} )

puts "volumeID ->", vol['volumeID']

puts " - delete volume"
sfrpc.DeleteVolume( "volumeID", vol['volumeID'] )
sfrpc.PurgeDeletedVolume( "volumeID", vol['volumeID'] )

puts "remove account"
sfrpc.RemoveAccount( "accountID", account['accountID'])
puts "accounts"
sfrpc.ListAccounts['accounts'].each { |acct| puts acct['username'] }


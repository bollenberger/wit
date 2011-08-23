require 'webgui.rb'
require 'sslweb.rb'
require 'calendar/calendar.rb'
require 'tab.rb'

#Thread.abort_on_exception = true

server = SSLWebServer.new('cert_localhost.pem', 'localhost_keypair.pem', 8080)

server.handler = WebApp.new('Title') do |window|
    s = Select.new(window)
    o1 = Option.new(s, 'Option 1')
    o2 = Option.new(s, 'Option 2')
end
server.listen
